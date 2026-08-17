import Testing
@testable import SpeakUp

/// Raw values are the SwiftData payload for `UserSettings.countdownBackdrop`.
/// Reordering cases would silently remap existing users onto the wrong sky.
struct RecordingBackdropTests {
    @Test func rawValuesStayStable() {
        #expect(RecordingBackdrop.base.rawValue == 0)
        #expect(RecordingBackdrop.aurora.rawValue == 1)
        #expect(RecordingBackdrop.hyperspace.rawValue == 2)
        #expect(RecordingBackdrop.nebula.rawValue == 3)
        #expect(RecordingBackdrop.ember.rawValue == 4)
        #expect(RecordingBackdrop.void.rawValue == 5)
    }

    @Test func unknownRawValueFallsBackToBase() {
        #expect(RecordingBackdrop(rawValue: 99) == nil)
        #expect((RecordingBackdrop(rawValue: 99) ?? .base) == .base)
    }

    @Test func everyCaseHasAUniqueName() {
        let names = RecordingBackdrop.allCases.map(\.displayName)
        #expect(names.count == Set(names).count)
        for name in names {
            #expect(!name.isEmpty)
        }
    }
}
