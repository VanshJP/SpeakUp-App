import Testing
@testable import SpeakUp

/// Raw values are the SwiftData payload for `UserSettings.countdownBackdrop`.
/// Reordering cases would silently remap existing users onto the wrong sky.
struct CountdownBackdropTests {
    @Test func rawValuesStayStable() {
        #expect(CountdownBackdrop.base.rawValue == 0)
        #expect(CountdownBackdrop.aurora.rawValue == 1)
        #expect(CountdownBackdrop.hyperspace.rawValue == 2)
        #expect(CountdownBackdrop.nebula.rawValue == 3)
        #expect(CountdownBackdrop.ember.rawValue == 4)
        #expect(CountdownBackdrop.void.rawValue == 5)
    }

    @Test func unknownRawValueFallsBackToBase() {
        #expect(CountdownBackdrop(rawValue: 99) == nil)
        #expect((CountdownBackdrop(rawValue: 99) ?? .base) == .base)
    }

    @Test func everyCaseHasAUniqueName() {
        let names = CountdownBackdrop.allCases.map(\.displayName)
        #expect(names.count == Set(names).count)
        for name in names {
            #expect(!name.isEmpty)
        }
    }
}
