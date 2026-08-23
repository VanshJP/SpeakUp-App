import Foundation
import AVFoundation
import Observation
import QuartzCore
import UIKit

@Observable
class AudioService: NSObject {
    // Recording
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    var isRecording = false
    var recordingURL: URL?
    var recordingDuration: TimeInterval = 0

    // Playback
    private var audioPlayer: AVAudioPlayer?
    /// File the current `audioPlayer` was loaded from. Taps on coaching
    /// surfaces re-request the same URL constantly; this is what lets `play`
    /// tell "seek the live player" apart from "load a different take".
    private var playerURL: URL?
    var isPlaying = false
    var playbackProgress: Double = 0
    var playbackDuration: TimeInterval = 0
    var currentPlaybackTime: TimeInterval = 0

    // Permission
    var hasPermission = false

    /// True while the mic is actually picking something up.
    ///
    /// The recording and drill screens used to derive this from the
    /// instantaneous level (`audioLevel > -40`), which flipped on every gap
    /// between words — a strobe in the corner of a screen whose whole job is
    /// "talk now". This holds a decaying peak instead, so ordinary pauses keep
    /// it lit and only real silence puts it out.
    private(set) var isHearingInput = true

    /// Tuning knobs for `isHearingInput`. `getAudioLevel()` runs at 10 Hz, so
    /// the peak sheds 15 dB/s: a normal speaking peak survives ~2.5 s of quiet
    /// before the indicator drops. Raise the decay to react faster; lower the
    /// floor if a quiet room reads as silence.
    private static let peakDecayPerSample: Float = 1.5
    private static let hearingFloor: Float = -40
    private var inputPeak: Float = 0

    private var recordingTimer: Timer?
    private var displayLink: CADisplayLink?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // Completion handler for recording finish
    private var recordingCompletion: ((Bool) -> Void)?

    override init() {
        super.init()
        setupSession()
        registerLifecycleObservers()
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Session Setup
    
    private func setupSession() {
        recordingSession = AVAudioSession.sharedInstance()
    }

    func requestPermission() async -> Bool {
        do {
            try configureRecordingSession()
            hasPermission = await AVAudioApplication.requestRecordPermission()
            return hasPermission
        } catch {
            print("Failed to set up audio session: \(error)")
            return false
        }
    }

    /// Shared session config for capture. Matches recorder sample rate to the
    /// hardware IO rate — a hardcoded 44.1 kHz under `.voiceChat` / HFP (often
    /// 8–16 kHz) was producing silent or time-stretched m4a files.
    private func configureRecordingSession() throws {
        let session = recordingSession ?? AVAudioSession.sharedInstance()
        recordingSession = session
        // `.bluetoothHighQualityRecording` (iOS 26+) prefers AirPods HQ capture
        // when available; HFP remains for classic BT headsets.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .bluetoothHighQualityRecording]
        )
        // Prefer a speech-friendly rate; hardware may still negotiate lower on HFP.
        try? session.setPreferredSampleRate(44_100)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func recorderSettings(matching session: AVAudioSession) -> [String: Any] {
        let hardwareRate = session.sampleRate
        // Fall back only when the session has not published a rate yet.
        let sampleRate = hardwareRate > 0 ? hardwareRate : 44_100
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
    
    // MARK: - Recording
    
    func startRecording() async throws -> URL {
        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw AudioServiceError.noPermission
            }
        }
        
        // Always capture to local Documents. iCloud promotion happens after stop.
        let storageDir = ICloudStorageService.shared.recordingsDirectory
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let audioFilename = storageDir.appendingPathComponent("\(UUID().uuidString).m4a")
        
        do {
            try configureRecordingSession()
            let session = recordingSession ?? AVAudioSession.sharedInstance()
            let settings = recorderSettings(matching: session)

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            let started = audioRecorder?.record() ?? false
            guard started else {
                throw AudioServiceError.recordingFailed(NSError(domain: "AudioService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"]))
            }

            isRecording = true
            recordingURL = audioFilename
            recordingDuration = 0

            // Full grace window at the top of a take, so the indicator doesn't
            // cry "no sound" in the second before the speaker starts.
            inputPeak = 0
            isHearingInput = true

            // Start duration timer
            await MainActor.run {
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    self?.recordingDuration = self?.audioRecorder?.currentTime ?? 0
                }
            }

            return audioFilename
        } catch {
            throw AudioServiceError.recordingFailed(error)
        }
    }
    
    func stopRecording() async -> URL? {
        recordingTimer?.invalidate()
        recordingTimer = nil

        guard let recorder = audioRecorder else {
            isRecording = false
            return nil
        }

        // A stop is already in flight — overwriting recordingCompletion would
        // leak its continuation and hang the first caller forever.
        guard recordingCompletion == nil else { return nil }

        // Wait for the recorder to properly finalize the file
        let success = await withCheckedContinuation { continuation in
            recordingCompletion = { success in
                continuation.resume(returning: success)
            }
            recorder.stop()
        }

        isRecording = false
        try? await Task.sleep(for: .milliseconds(100))

        let localURL = recordingURL
        recordingURL = nil
        audioRecorder = nil

        guard success else {
            if let localURL {
                try? FileManager.default.removeItem(at: localURL)
            }
            recordingDuration = 0
            return nil
        }

        // Promote to iCloud only after the file is fully finalized locally.
        let url = localURL.map { ICloudStorageService.shared.promoteToICloudIfNeeded(localURL: $0) }

        // Duration comes from the finalized file, not recorder.currentTime —
        // the latter drifts under audio-session interruptions and sample-rate
        // mismatches (e.g. .voiceChat + HFP), occasionally by 60× or more.
        recordingDuration = url.flatMap { getAudioDuration(at: $0) } ?? 0

        return url
    }
    
    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        // A pending stopRecording() continuation is parked on this closure.
        // Dropping it leaked the continuation and hung that caller forever —
        // resolve it as cancelled instead. Nilling afterwards means the
        // delegate's callback for recorder.stop() below cannot double-resume.
        recordingCompletion?(false)
        recordingCompletion = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Delete the file if it exists (user cancelled recording)
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordingURL = nil
        recordingDuration = 0
    }
    
    func getAudioLevel() -> Float {
        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160

        // Decaying peak, not the raw reading: a gap between two words is not a
        // dead mic. Written only when it flips, so observers don't re-render at
        // the sampling rate.
        inputPeak = max(level, inputPeak - Self.peakDecayPerSample)
        let hearing = inputPeak > Self.hearingFloor
        if hearing != isHearingInput {
            isHearingInput = hearing
        }

        return level
    }
    
    // MARK: - Playback
    
    /// - Parameter startingAt: seconds to begin from. Set before `play()` so the
    ///   audio never audibly starts at zero and jump-cuts — the coaching screen
    ///   plays from a timestamp far more often than from the top.
    func play(url: URL, startingAt startTime: TimeInterval = 0) async throws {
        do {
            try recordingSession?.setCategory(.playback, mode: .default)
            try recordingSession?.setActive(true)

            // The same file is already loaded (playing or paused)? Seek the
            // live player instead of rebuilding it. Creating a new
            // AVAudioPlayer tears down and re-primes the decoder, which lands
            // on the ear as a jump-cut restart — exactly what tapping a word
            // mid-playback used to feel like.
            if let player = audioPlayer, playerURL == url {
                playbackDuration = player.duration
                seekPlayer(to: startTime)
                player.play()

                isPlaying = true

                await MainActor.run {
                    self.startDisplayLink()
                }
                return
            }

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            playerURL = url
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            playbackDuration = audioPlayer?.duration ?? 0
            seekPlayer(to: startTime)
            audioPlayer?.play()
            
            isPlaying = true

            await MainActor.run {
                self.startDisplayLink()
            }
        } catch {
            throw AudioServiceError.playbackFailed(error)
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        displayLink?.isPaused = true
    }

    func stop() {
        stopDisplayLink()

        audioPlayer?.stop()
        audioPlayer = nil
        playerURL = nil
        isPlaying = false
        playbackProgress = 0
        currentPlaybackTime = 0
    }

    /// Fraction-based seek for the drawer scrubber (0…1 of the duration).
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let clamped = max(0, min(1, progress))
        player.currentTime = clamped * player.duration
        playbackProgress = clamped
        currentPlaybackTime = player.currentTime
    }

    /// Absolute-time seek in seconds — what word taps and coaching stamps
    /// arrive as. Clamps into the playable range; a request past the end
    /// lands just short of it rather than falling off.
    func seek(toTime time: TimeInterval) {
        seekPlayer(to: time)
    }

    /// Shared seek core. The final tenth of a second is unusable — seeking
    /// there plays nothing and reports finished immediately.
    private func seekPlayer(to time: TimeInterval) {
        guard let player = audioPlayer, player.duration > 0 else { return }
        let clamped = min(max(0, time), max(0, player.duration - 0.1))
        player.currentTime = clamped
        currentPlaybackTime = clamped
        playbackProgress = clamped / player.duration
    }

    // MARK: - Playback clock

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        guard let player = audioPlayer, player.isPlaying else { return }
        let duration = player.duration
        let time = player.currentTime
        currentPlaybackTime = time
        playbackProgress = duration > 0 ? max(0, min(1, time / duration)) : 0
    }

    // MARK: - App lifecycle

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        let resign = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.displayLink?.isPaused = true
        }
        let active = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let player = self.audioPlayer {
                self.currentPlaybackTime = player.currentTime
                if player.duration > 0 {
                    self.playbackProgress = max(0, min(1, player.currentTime / player.duration))
                }
            }
            if self.isPlaying {
                self.displayLink?.isPaused = false
            }
        }
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSessionInterruption(notification)
        }
        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        lifecycleObservers = [resign, active, interruption, routeChange]
    }

    /// Phone calls / Siri yank the session. Playback pauses here.
    /// Recording has no pause UX — `RecordingViewModel` finalizes the take
    /// on interruption so the timer and UI never lie about still capturing.
    private func handleSessionInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue),
            type == .began,
            isPlaying
        else { return }

        audioPlayer?.pause()
        isPlaying = false
        displayLink?.isPaused = true
    }

    /// Unplugged headphones mid-take: keep recording on the built-in mic.
    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            reason == .oldDeviceUnavailable,
            isRecording
        else { return }
        // Recorder keeps writing after route change; re-assert category so
        // `.defaultToSpeaker` wins over a dead BT/HFP path.
        try? configureRecordingSession()
        if audioRecorder?.isRecording == false {
            _ = audioRecorder?.record()
        }
    }
    
    // MARK: - File Management
    
    func getAudioDuration(at url: URL) -> TimeInterval? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return nil
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stop()
        cancelRecording()
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
        recordingCompletion?(flag)
        recordingCompletion = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            print("Recording encode error: \(error)")
        }
        recordingCompletion?(false)
        recordingCompletion = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            playbackProgress = 0
            currentPlaybackTime = 0
            stopDisplayLink()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error {
            print("Playback decode error: \(error)")
        }
    }
}

// MARK: - Errors

enum AudioServiceError: LocalizedError {
    case noPermission
    case recordingFailed(Error)
    case playbackFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone permission is required to record audio."
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .playbackFailed(let error):
            return "Playback failed: \(error.localizedDescription)"
        }
    }
}

