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

    // MARK: - Catalogue linkage
    //
    // Both menus paint through the one `CanvasLook` catalogue. These pin the
    // link: a look renamed on one screen and not the other is the exact drift
    // the shared catalogue exists to prevent.

    @Test func sharedNamesResolveToTheSameLook() {
        #expect(RecordingBackdrop.aurora.look == AppCanvas.aurora.look)
        #expect(RecordingBackdrop.ember.look == AppCanvas.ember.look)
    }

    @Test func sharedNamesShareTheirDescription() {
        #expect(RecordingBackdrop.aurora.subtitle == AppCanvas.aurora.subtitle)
        #expect(RecordingBackdrop.ember.subtitle == AppCanvas.ember.subtitle)
    }

    @Test func baseIsClassicAndNeverAnimates() {
        #expect(RecordingBackdrop.base.look == .classic)
        #expect(!RecordingBackdrop.base.look.isAnimated)
    }

    @Test func everyOtherBackdropAnimates() {
        for backdrop in RecordingBackdrop.allCases where backdrop != .base {
            #expect(backdrop.look.isAnimated, "\(backdrop.displayName) should move")
        }
    }

    @Test func everyMenuEntryMapsToItsOwnLook() {
        let looks = RecordingBackdrop.allCases.filter { $0 != .base }.map(\.look)
        #expect(Set(looks).count == looks.count)
        let appLooks = AppCanvas.allCases.map(\.look)
        #expect(Set(appLooks).count == appLooks.count)
    }

    @Test func everyLookHasASummary() {
        for look in CanvasLook.allCases {
            #expect(!look.summary.isEmpty)
        }
    }
}
