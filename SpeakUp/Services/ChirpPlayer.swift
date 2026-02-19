import AVFoundation

/// Synthesizes and plays short audio tones to cue exercise phase transitions.
/// Uses AVAudioPlayer with in-memory WAV data for maximum reliability.
final class ChirpPlayer {
    static let shared = ChirpPlayer()

    var isEnabled: Bool = true

    private let sampleRate: Double = 44100
    private var player: AVAudioPlayer?

    private init() {}

    enum Chirp {
        case inhale    // high tone — breathe in
        case hold      // quiet mid tone — hold breath
        case exhale    // lower tone — breathe out
        case tick      // quick neutral cue — step advance or drill event

        var frequency: Float {
            switch self {
            case .inhale:  return 880
            case .hold:    return 528
            case .exhale:  return 330
            case .tick:    return 660
            }
        }

        var duration: Double {
            switch self {
            case .inhale, .exhale: return 0.15
            case .hold:            return 0.10
            case .tick:            return 0.08
            }
        }

        var volume: Float {
            switch self {
            case .hold:    return 0.15
            case .tick:    return 0.25
            default:       return 0.35
            }
        }
    }

    func play(_ chirp: Chirp) {
        guard isEnabled else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback && session.category != .playAndRecord {
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
            }

            let data = generateWAV(frequency: chirp.frequency, duration: chirp.duration, volume: chirp.volume)
            player = try AVAudioPlayer(data: data)
            player?.play()
        } catch {
            // Silently fail — chirps are non-critical
        }
    }

    private func generateWAV(frequency: Float, duration: Double, volume: Float) -> Data {
        let frameCount = Int(sampleRate * duration)
        let dataSize = frameCount * 2 // 16-bit samples

        var data = Data()

        // WAV header (44 bytes)
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32(&data, UInt32(36 + dataSize))          // file size - 8
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendUInt32(&data, 16)                             // chunk size
        appendUInt16(&data, 1)                              // PCM format
        appendUInt16(&data, 1)                              // mono
        appendUInt32(&data, UInt32(sampleRate))             // sample rate
        appendUInt32(&data, UInt32(sampleRate) * 2)         // byte rate
        appendUInt16(&data, 2)                              // block align
        appendUInt16(&data, 16)                             // bits per sample
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32(&data, UInt32(dataSize))               // data size

        // Generate samples
        for i in 0..<frameCount {
            let t = Float(i) / Float(sampleRate)
            let envelope = sin(Float.pi * Float(i) / Float(frameCount))
            let sample = sin(2 * .pi * frequency * t) * volume * envelope
            let intSample = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            appendInt16(&data, intSample)
        }

        return data
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private func appendInt16(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }
}
