import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import SpeakUp

// MonoPCM.decode feeds pitch scoring, isolation preprocessing, and speaker
// labeling — a wrong frame count or sample rate silently skews every
// downstream acoustic number. Files are synthesized per test in a temporary
// directory so the decoder sees real containers, not mocks.

nonisolated struct MonoPCMDecodeTests {
    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoPCMDecodeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a float32 CAF with deterministic sine content and lets the file
    /// close (flush its header) before returning, so decode reads finished data.
    private func writeAudio(channels: Int, frames: Int, sampleRate: Double, at url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard frames > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else {
            throw CocoaError(.coderInvalidValue)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            let dst = buffer.floatChannelData![channel]
            for frame in 0..<frames {
                dst[frame] = sin(Float(frame) * 0.05 + Float(channel)) * 0.5
            }
        }
        try file.write(from: buffer)
    }

    @Test func monoFloat32RoundTripsSampleCountAndRate() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("mono.caf")
        try writeAudio(channels: 1, frames: 4_800, sampleRate: 22_050, at: url)

        let decoded = MonoPCM.decode(url: url)
        #expect(decoded?.samples.count == 4_800)
        #expect(decoded?.sampleRate == 22_050)
        #expect(decoded?.samples.allSatisfy(\.isFinite) == true)
    }

    @Test func stereoDownmixProducesFiniteSamplesAtFullFrameCount() throws {
        // Pitch analysis assumes mono; the converter path must hand it one
        // finite sample per source frame at the same rate.
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("stereo.caf")
        try writeAudio(channels: 2, frames: 9_600, sampleRate: 44_100, at: url)

        let decoded = MonoPCM.decode(url: url)
        #expect(decoded?.samples.count == 9_600)
        #expect(decoded?.sampleRate == 44_100)
        #expect(decoded?.samples.allSatisfy(\.isFinite) == true)
    }

    @Test func zeroFrameFileDecodesToNil() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("empty.caf")
        try writeAudio(channels: 1, frames: 0, sampleRate: 44_100, at: url)

        #expect(MonoPCM.decode(url: url) == nil)
    }

    @Test func garbageBytesWithWavExtensionReturnNil() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("garbage.wav")
        // Fixed junk prefix keeps this deterministic; random tail covers
        // container-parser edge paths without ever forming a RIFF header.
        var garbage = Data("this is not audio data".utf8)
        garbage.append(contentsOf: (0..<512).map { _ in UInt8.random(in: 0...255) })
        try garbage.write(to: url)

        #expect(MonoPCM.decode(url: url) == nil)
    }
}
