import AVFoundation
import Foundation
import Speech

/// Speech-to-text for finished takes, on Apple's `SpeechAnalyzer`.
///
/// The model runs in a system process on the Neural Engine, and the framework
/// has no server path: audio never leaves the device. It replaced WhisperKit,
/// which ran inside the app - a ~150 MB Hugging Face download, a Core ML build
/// that fought the local LLM for memory, and a filler-biased prompt that made
/// the decoder drop whole 30 s windows (the back half of most one-minute
/// takes) after retrying each one up to six times. That retry loop is what
/// held the analyzing screen.
///
/// `SpeechTranscriber` keeps hesitations ("um", and "uh" as "ah") with no
/// prompting. It needs a 16-core Neural Engine (iPhone 12 and later). Older
/// phones get `DictationTranscriber`, which strips hesitations, so they count
/// only word fillers ("like", "you know").
///
/// Call off the main actor: transcription converts the whole take.
nonisolated enum OnDeviceTranscriber {
    enum Backend: String, Sendable {
        case speechTranscriber = "speech_transcriber"
        case dictationTranscriber = "dictation_transcriber"
    }

    struct Transcript: Sendable {
        /// In spoken order. Ranges tile each phrase edge to edge - see
        /// `WordTimingRefiner` for getting the pauses back.
        let words: [RawWordTiming]
        let backend: Backend
    }

    /// One piece of the transcriber's attributed text: usually a single word
    /// with its leading space and trailing punctuation (" day,").
    struct TimedRun: Sendable {
        let text: String
        let start: TimeInterval?
        let end: TimeInterval?
        let confidence: Double?
    }

    static let locale = Locale(identifier: "en-US")

    // MARK: - Model

    /// Downloads the on-device model if the system does not have it yet. A
    /// no-op once installed; the system keeps one copy for every app.
    static func prepareModel() async throws {
        try await install(makeEngine())
    }

    /// True when `prepareModel()` would download.
    static func needsDownload() async -> Bool {
        guard let engine = try? await makeEngine() else { return false }
        let status = await AssetInventory.status(forModules: [engine.module])
        return status == .supported || status == .downloading
    }

    // MARK: - Transcription

    /// Transcribes an already-decoded take, so one decode serves the
    /// transcriber and every acoustic pass after it.
    static func transcribe(_ pcm: MonoPCM, contextualStrings: [String] = []) async throws -> Transcript {
        let engine = try await makeEngine()
        try await install(engine)

        // The analyzer takes one format per module and rejects the rest -
        // its own file reader included ("Audio format is not supported") -
        // so the conversion is ours.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [engine.module]),
              let buffer = convert(pcm, to: format) else {
            throw OnDeviceTranscriberError.unsupported
        }

        let seconds = Double(pcm.samples.count) / pcm.sampleRate
        // Measured at 60-85x real time; the budget only exists so a wedged
        // speech daemon fails the take instead of holding it.
        let texts = try await withDeadline(seconds: 30 + seconds / 2) {
            try await analyze(buffer, with: engine, contextualStrings: contextualStrings)
        }
        return Transcript(words: words(from: texts), backend: engine.backend)
    }

    /// The whole take in `format`. Mono float in, whatever the analyzer
    /// wants out (16 kHz, 16-bit on current devices).
    static func convert(_ pcm: MonoPCM, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !pcm.samples.isEmpty,
              let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: pcm.sampleRate,
                channels: 1,
                interleaved: false
              ),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(pcm.samples.count)),
              let converter = AVAudioConverter(from: sourceFormat, to: format) else { return nil }

        source.frameLength = source.frameCapacity
        pcm.samples.withUnsafeBufferPointer { samples in
            source.floatChannelData![0].update(from: samples.baseAddress!, count: samples.count)
        }

        let capacity = AVAudioFrameCount((Double(pcm.samples.count) * format.sampleRate / pcm.sampleRate).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var handedOver = false
        let status = converter.convert(to: output, error: nil) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .endOfStream
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return source
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }

    /// Words out of the transcriber's attributed text.
    static func words(from texts: [AttributedString]) -> [RawWordTiming] {
        var runs: [TimedRun] = []
        for text in texts {
            for run in text.runs {
                let range = run.audioTimeRange
                runs.append(TimedRun(
                    text: String(text[run.range].characters),
                    start: range?.start.seconds,
                    end: range?.end.seconds,
                    confidence: run.transcriptionConfidence
                ))
            }
        }
        return words(from: runs)
    }

    /// Splits runs into words. `DictationTranscriber` also emits multi-word
    /// runs ("a lot of "), which share the run's time by length, and bare
    /// punctuation (", "), which joins the word before it.
    static func words(from runs: [TimedRun]) -> [RawWordTiming] {
        var words: [RawWordTiming] = []
        var clock: TimeInterval = 0

        for run in runs {
            let start = max(clock, run.start ?? clock)
            let end = max(start, run.end ?? start)
            clock = end

            let tokens = run.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let spokenLength = tokens.filter(isSpoken).reduce(0) { $0 + $1.count }
            var cursor = start

            for token in tokens {
                guard isSpoken(token) else {
                    if let last = words.popLast() {
                        words.append(RawWordTiming(
                            word: last.word + token,
                            start: last.start,
                            end: last.end,
                            confidence: last.confidence
                        ))
                    }
                    continue
                }
                let tokenEnd = cursor + (end - start) * Double(token.count) / Double(spokenLength)
                words.append(RawWordTiming(
                    word: token,
                    start: cursor,
                    end: tokenEnd,
                    confidence: run.confidence ?? 1
                ))
                cursor = tokenEnd
            }
        }
        return words
    }

    private static func isSpoken(_ token: String) -> Bool {
        token.contains { $0.isLetter || $0.isNumber }
    }

    // MARK: - Engine

    private enum Engine {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .speech(let module): module
            case .dictation(let module): module
            }
        }

        var backend: Backend {
            switch self {
            case .speech: .speechTranscriber
            case .dictation: .dictationTranscriber
            }
        }
    }

    private static func makeEngine() async throws -> Engine {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            ))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(DictationTranscriber(
                locale: supported,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            ))
        }
        throw OnDeviceTranscriberError.unsupported
    }

    private static func install(_ engine: Engine) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [engine.module]) {
            try await request.downloadAndInstall()
        }
    }

    private static func analyze(
        _ audio: AVAudioPCMBuffer,
        with engine: Engine,
        contextualStrings: [String]
    ) async throws -> [AttributedString] {
        let analyzer = SpeechAnalyzer(modules: [engine.module])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            // Vocabulary is a hint; a transcriber that ignores it still works.
            try? await analyzer.setContext(context)
        }

        let results: Task<[AttributedString], Error>
        switch engine {
        case .speech(let module):
            results = Task { try await module.results.reduce(into: [AttributedString]()) { if $1.isFinal { $0.append($1.text) } } }
        case .dictation(let module):
            results = Task { try await module.results.reduce(into: [AttributedString]()) { if $1.isFinal { $0.append($1.text) } } }
        }

        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        feed.yield(AnalyzerInput(buffer: audio))
        feed.finish()

        do {
            try await withTaskCancellationHandler {
                if let end = try await analyzer.analyzeSequence(input) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            results.cancel()
            throw error
        }
        return try await results.value
    }

    // MARK: - Deadline

    /// Runs `operation`, and gives up after `seconds` without waiting for it
    /// to notice. A task group cannot do this: it waits for every child before
    /// it rethrows, so a timeout could never fire past a wedged call.
    private static func withDeadline<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = Race<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                race.adopt(Task {
                    do {
                        race.finish(.success(try await operation()))
                    } catch {
                        race.finish(.failure(error))
                    }
                })
                race.adopt(Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    race.finish(.failure(OnDeviceTranscriberError.timedOut))
                })
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }

    /// Resumes a continuation with the first racer to finish and cancels the
    /// rest. Locks stay in sync methods (NSLock is unavailable in async
    /// contexts under Swift 6).
    private final class Race<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var outcome: Result<T, Error>?
        private var racers: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            guard let outcome else {
                self.continuation = continuation
                lock.unlock()
                return
            }
            lock.unlock()
            continuation.resume(with: outcome)
        }

        func adopt(_ racer: Task<Void, Never>) {
            lock.lock()
            let isOver = outcome != nil
            if !isOver { racers.append(racer) }
            lock.unlock()
            if isOver { racer.cancel() }
        }

        func finish(_ result: Result<T, Error>) {
            lock.lock()
            guard outcome == nil else {
                lock.unlock()
                return
            }
            outcome = result
            let waiting = continuation
            continuation = nil
            let losers = racers
            racers = []
            lock.unlock()
            losers.forEach { $0.cancel() }
            waiting?.resume(with: result)
        }
    }
}

nonisolated enum OnDeviceTranscriberError: LocalizedError {
    case unsupported
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "On-device English transcription isn't available on this device."
        case .timedOut:
            return "Transcription took too long. Your recording is saved - try again."
        }
    }
}
