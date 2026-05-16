import AVFoundation

/// Centralized reward sound effects. Buffers are synthesized once on first
/// use and replayed through a shared `AVAudioPlayerNode` so each call is
/// allocation-free and stays tight to the haptic that fires alongside it.
///
/// Distinct from `ChirpPlayer` — that service cues exercise phase
/// transitions (inhale / hold / exhale / tick); this one is for the
/// dopamine ding when the user completes something rewarding.
enum SoundEffects {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let sampleRate: Double = 44_100
    private static var configured = false
    private static var successChimeBuffer: AVAudioPCMBuffer?

    /// Pre-warm the audio engine. Safe to call repeatedly.
    static func prepare() {
        configure()
    }

    /// Bright two-note bell for completion / success moments.
    static func successChime() {
        configure()
        guard let buffer = successChimeBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    // MARK: - Setup

    private static func configure() {
        guard !configured else { return }
        configured = true

        // Playback (not ambient) so the chime still fires when the ringer
        // switch is off — completing practice is a deliberate user moment
        // and should be heard. mixWithOthers keeps any music or podcast
        // playing through. Skip the category switch if AudioService already
        // owns a record/playback session — we don't want to disrupt an
        // active recording.
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, options: [.mixWithOthers])
            try? session.setActive(true)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()

        successChimeBuffer = renderSuccessChime(format: format)
    }

    // MARK: - Synthesis

    /// Renders a short two-note bell: an E6 mallet attack with a B6 overtone
    /// joining ~80 ms later, both decaying exponentially. Adds a faint sub-
    /// octave for body. Total length ~0.55 s.
    private static func renderSuccessChime(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration: Double = 0.55
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        let note1: Double = 1318.51   // E6
        let note2: Double = 1975.53   // B6
        let crossover: Double = 0.08
        let attack: Double = 0.005

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let attackEnv = t < attack ? t / attack : 1.0
            let env1 = attackEnv * exp(-3.0 * t)

            var sample = sin(2.0 * .pi * note1 * t) * env1 * 0.45
            sample += sin(2.0 * .pi * (note1 / 2.0) * t) * env1 * 0.12

            if t >= crossover {
                let t2 = t - crossover
                let env2 = exp(-3.5 * t2)
                sample += sin(2.0 * .pi * note2 * t2) * env2 * 0.4
            }

            channel[frame] = Float(sample * 0.7)
        }
        return buffer
    }
}
