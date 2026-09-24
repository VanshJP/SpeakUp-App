import Foundation
import os.log
import AVFoundation
import Observation
import QuartzCore
import UIKit

@Observable
class AudioService: NSObject {
    private let logger = Logger.app("Audio")
    // Recording
    private var audioRecorder: AVAudioRecorder?
    /// Reserved before any await so a double tap cannot start two recorders.
    private var isStartingRecording = false
    var isRecording = false
    var recordingURL: URL?
    var recordingDuration: TimeInterval = 0

    // Playback
    private var audioPlayer: AVAudioPlayer?
    /// Lets `play` seek the live player instead of reloading the same file.
    private var playerURL: URL?
    var isPlaying = false
    var playbackProgress: Double = 0
    var playbackDuration: TimeInterval = 0
    var currentPlaybackTime: TimeInterval = 0

    // Permission
    var hasPermission = false

    /// "Is this mic working", not "is sound arriving right now": the first
    /// real reading latches it on for the rest of the take, so pauses never
    /// flash a no-sound warning. A dead mic never latches.
    private(set) var isHearingInput = true

    /// Latched once a real reading clears `hearingFloor` during this take.
    private var hasConfirmedInput = false

    /// Pre-latch tuning. At 10 Hz sampling the peak sheds 15 dB/s, so priming
    /// it to 0 buys ~2.5 s of grace at the top of a take.
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
        registerLifecycleObservers()
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Session Setup

    func requestPermission() async -> Bool {
        do {
            try await configureRecordingSession()
            hasPermission = await AVAudioApplication.requestRecordPermission()
            return hasPermission
        } catch {
            logger.error("Failed to set up audio session: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return false
        }
    }

    /// Session activation blocks on the audio server, so it never runs on main.
    private func configureRecordingSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.activateRecordingSession()
        }.value
    }

    private nonisolated static func activateRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
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

    private nonisolated static func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    /// Activates the session and starts a recorder at the hardware rate.
    /// Off main: `record()` re-activates the session and blocks like
    /// `setActive`. A hardcoded 44.1 kHz under HFP (8-16 kHz) produced silent
    /// or time-stretched files.
    private nonisolated static func startRecorder(url: URL) throws -> AVAudioRecorder {
        try activateRecordingSession()
        let hardwareRate = AVAudioSession.sharedInstance().sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: hardwareRate > 0 ? hardwareRate : 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "AudioService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }
        return recorder
    }

    // MARK: - Recording

    /// True while `stopRecording` is waiting on the recorder delegate.
    /// Callers must not `cancelRecording` / `cleanup` in this window - that
    /// resumes the stop continuation as failure and deletes the m4a.
    var isFinalizingRecording: Bool { recordingCompletion != nil }

    func startRecording() async throws -> URL {
        // `recordingURL` still points at the finalizing file.
        guard recordingCompletion == nil else {
            throw AudioServiceError.recordingFailed(NSError(
                domain: "AudioService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Recording is still finalizing"]
            ))
        }
        guard !isRecording, !isStartingRecording, audioRecorder == nil else {
            if isRecording, let recordingURL {
                return recordingURL
            }
            throw AudioServiceError.recordingFailed(NSError(
                domain: "AudioService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recording already in progress"]
            ))
        }
        isStartingRecording = true
        defer { isStartingRecording = false }

        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw AudioServiceError.noPermission
            }
        }

        // Another start/stop may have won during the permission await.
        guard recordingCompletion == nil, !isRecording, audioRecorder == nil else {
            throw AudioServiceError.recordingFailed(NSError(
                domain: "AudioService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recording already in progress"]
            ))
        }

        // Capture locally; iCloud promotion happens after stop.
        let storageDir = ICloudStorageService.shared.recordingsDirectory
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let audioFilename = storageDir.appendingPathComponent("\(UUID().uuidString).m4a")

        do {
            let recorder = try await Task.detached(priority: .userInitiated) {
                RecorderBox(try Self.startRecorder(url: audioFilename))
            }.value.recorder
            recorder.delegate = self
            audioRecorder = recorder

            isRecording = true
            recordingURL = audioFilename
            recordingDuration = 0

            resetInputConfidence()

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration = self?.audioRecorder?.currentTime ?? 0
            }

            return audioFilename
        } catch {
            audioRecorder = nil
            isRecording = false
            recordingURL = nil
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

        // Overwriting an in-flight completion would hang the first caller.
        guard recordingCompletion == nil else { return nil }

        let success = await withCheckedContinuation { continuation in
            recordingCompletion = { success in
                continuation.resume(returning: success)
            }
            recorder.stop()
        }

        isRecording = false
        resetInputConfidence()
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

        guard let localURL else {
            recordingDuration = 0
            return nil
        }

        // From the finalized file: `currentTime` drifts under interruptions
        // and HFP rate mismatches. Read locally, before the move, off main.
        recordingDuration = await Task.detached(priority: .userInitiated) {
            AudioService.fileDuration(at: localURL)
        }.value ?? 0

        // Stays local. The iCloud move waits on the daemon for seconds, and
        // every screen after a take was waiting on it. The analysis job
        // promotes the file once it is done reading it; launch migration
        // sweeps anything else.
        return localURL
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Cancelling mid-stop would delete the file being finalized.
        guard recordingCompletion == nil else { return }

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordingURL = nil
        recordingDuration = 0
        resetInputConfidence()
    }

    func getAudioLevel() -> Float {
        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160

        inputPeak = max(level, inputPeak - Self.peakDecayPerSample)

        // Latch on `level`, not `inputPeak`: the primed peak starts above the floor.
        if !hasConfirmedInput, level > Self.hearingFloor {
            hasConfirmedInput = true
        }

        let hearing = hasConfirmedInput || inputPeak > Self.hearingFloor
        if hearing != isHearingInput {
            isHearingInput = hearing
        }

        return level
    }

    /// Per take, so a latch never leaks across sessions.
    private func resetInputConfidence() {
        inputPeak = 0
        hasConfirmedInput = false
        isHearingInput = true
    }

    // MARK: - Playback

    /// Seeks before `play()` so a mid-file start never jump-cuts from zero.
    func play(url: URL, startingAt startTime: TimeInterval = 0) async throws {
        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.activatePlaybackSession()
            }.value

            // Same file loaded: seek it. A new player re-primes the decoder
            // and restarts audibly.
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

    /// Absolute-time seek (word taps, coaching stamps). Clamped to the playable range.
    func seek(toTime time: TimeInterval) {
        seekPlayer(to: time)
    }

    /// The last 0.1 s is unusable: seeking there reports finished immediately.
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

    /// Calls/Siri: pause playback. `RecordingViewModel` finalizes an
    /// interrupted take itself.
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
        // Re-assert the category so `.defaultToSpeaker` wins over a dead
        // BT/HFP path, then resume the recorder if the route change paused it.
        guard let recorder = audioRecorder else { return }
        let box = RecorderBox(recorder)
        Task.detached(priority: .userInitiated) {
            try? Self.activateRecordingSession()
            if !box.recorder.isRecording {
                _ = box.recorder.record()
            }
        }
    }

    // MARK: - File Management

    /// Opens the file; call off the main actor.
    nonisolated static func fileDuration(at url: URL) -> TimeInterval? {
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
        // Cancel would delete a take that is still finalizing.
        guard !isFinalizingRecording else { return }
        cancelRecording()
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            logger.error("Recording finished unsuccessfully")
        }
        recordingCompletion?(flag)
        recordingCompletion = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            logger.error("Recording encode error: \(error.localizedDescription, privacy: .private(mask: .hash))")
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
            logger.error("Playback decode error: \(error.localizedDescription, privacy: .private(mask: .hash))")
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

/// Carries a non-Sendable recorder across the off-main start and route repair.
nonisolated private final class RecorderBox: @unchecked Sendable {
    let recorder: AVAudioRecorder
    init(_ recorder: AVAudioRecorder) { self.recorder = recorder }
}
