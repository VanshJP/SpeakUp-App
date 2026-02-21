import Foundation
import AVFoundation
import Observation

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
    var isPlaying = false
    var playbackProgress: Double = 0
    var playbackDuration: TimeInterval = 0

    // Permission
    var hasPermission = false

    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    // Completion handler for recording finish
    private var recordingCompletion: ((Bool) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Session Setup
    
    private func setupSession() {
        recordingSession = AVAudioSession.sharedInstance()
    }
    
    func requestPermission() async -> Bool {
        do {
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try recordingSession?.setActive(true)
            
            if #available(iOS 17.0, *) {
                hasPermission = await AVAudioApplication.requestRecordPermission()
            } else {
                hasPermission = await withCheckedContinuation { continuation in
                    recordingSession?.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
            
            return hasPermission
        } catch {
            print("Failed to set up audio session: \(error)")
            return false
        }
    }
    
    // MARK: - Recording
    
    func startRecording() async throws -> URL {
        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw AudioServiceError.noPermission
            }
        }
        
        // Generate file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try recordingSession?.setActive(true)

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

        let duration = recorder.currentTime

        // Wait for the recorder to properly finalize the file
        let success = await withCheckedContinuation { continuation in
            recordingCompletion = { success in
                continuation.resume(returning: success)
            }
            recorder.stop()
        }

        isRecording = false
        recordingDuration = duration

        // Give the file system a moment to finalize
        try? await Task.sleep(for: .milliseconds(100))

        guard success else {
            return nil
        }

        // Capture URL and clear it so cleanup() won't delete the file
        let url = recordingURL
        recordingURL = nil
        audioRecorder = nil

        return url
    }
    
    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Clear any pending completion handler
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
        return audioRecorder?.averagePower(forChannel: 0) ?? -160
    }
    
    // MARK: - Playback
    
    func play(url: URL) async throws {
        do {
            try recordingSession?.setCategory(.playback, mode: .default)
            try recordingSession?.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            playbackDuration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            
            isPlaying = true
            
            // Start progress timer
            await MainActor.run {
                playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self, let player = self.audioPlayer else { return }
                    self.playbackProgress = player.currentTime / player.duration
                }
            }
        } catch {
            throw AudioServiceError.playbackFailed(error)
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playbackTimer?.invalidate()
            self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }
    
    func stop() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
    }
    
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = progress * player.duration
        playbackProgress = progress
    }
    
    // MARK: - File Management
    
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
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
            playbackTimer?.invalidate()
            playbackTimer = nil
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

