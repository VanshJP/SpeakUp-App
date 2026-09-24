import SwiftUI
import Testing
@testable import SpeakUp

struct TakeWaveformTests {

    @Test("Resampling fills any bar count without repeating, and keeps peaks")
    func resampling() {
        let levels: [CGFloat] = [0.1, 0.9, 0.2, 0.3]
        #expect(TakeWaveform.resampled(levels, to: 4) == levels)
        #expect(TakeWaveform.resampled(levels, to: 2) == [0.9, 0.3])
        #expect(TakeWaveform.resampled(levels, to: 8) == [0.1, 0.1, 0.9, 0.9, 0.2, 0.2, 0.3, 0.3])
        #expect(TakeWaveform.resampled(levels, to: 3).count == 3)
        #expect(TakeWaveform.resampled([], to: 5).isEmpty)
    }

    @Test("Estimated progress eases toward 90% and never passes it")
    func estimate() {
        #expect(TakeWaveform.fraction(elapsed: 0, expected: 10) == 0)
        #expect(TakeWaveform.fraction(elapsed: 10, expected: 10) < 0.9)
        #expect(TakeWaveform.fraction(elapsed: 1000, expected: 10) <= 0.9)
        #expect(TakeWaveform.fraction(elapsed: 5, expected: 0) == 0)
    }

    @Test("Decibel samples map into 0...1 with a floor for silence")
    func decibels() {
        let levels = TakeWaveform.levels(fromDecibels: Array(repeating: -160, count: 100) + Array(repeating: 0, count: 100))
        #expect(!levels.isEmpty)
        #expect(levels.allSatisfy { $0 >= 0.1 && $0 <= 1 })
        #expect(levels.first! < levels.last!)
        #expect(TakeWaveform.levels(fromDecibels: [1, 2]).isEmpty)
    }
}
