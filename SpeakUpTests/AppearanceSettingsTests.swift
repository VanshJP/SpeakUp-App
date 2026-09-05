import Testing
@testable import SpeakUp

/// Raw values are the SwiftData payload for `UserSettings.appCanvas` /
/// `UserSettings.glassAppearance`. Reordering cases would silently remap
/// stored preferences.
struct AppearanceSettingsTests {

    @Test func appCanvasRawValuesAreStable() {
        #expect(AppCanvas.classic.rawValue == 0)
        #expect(AppCanvas.midnight.rawValue == 1)
        #expect(AppCanvas.mist.rawValue == 2)
        #expect(AppCanvas.aurora.rawValue == 3)
        #expect(AppCanvas.ember.rawValue == 4)
        #expect(AppCanvas.horizon.rawValue == 5)
        #expect(AppCanvas.prism.rawValue == 6)
        #expect(AppCanvas.depth.rawValue == 7)
    }

    @Test func appCanvasFallsBackToClassic() {
        #expect(AppCanvas(rawValue: 99) == nil)
        #expect((AppCanvas(rawValue: 99) ?? .classic) == .classic)
    }

    @Test func appCanvasNamesAreUnique() {
        let names = AppCanvas.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test func glassAppearanceRawValuesAreStable() {
        #expect(GlassAppearance.light.rawValue == 0)
        #expect(GlassAppearance.dark.rawValue == 1)
    }

    @Test func glassAppearanceFallsBackToLight() {
        #expect(GlassAppearance(rawValue: 9) == nil)
        #expect((GlassAppearance(rawValue: 9) ?? .light) == .light)
    }

    @Test func darkGlassIsQuieterThanLight() {
        // Opacity is the lift amount — dark must lift less so plates sink.
        #expect(GlassAppearance.dark.rimOpacities.0 < GlassAppearance.light.rimOpacities.0)
    }

    @Test func reviewToolCatalogIsComplete() {
        #expect(ReviewToolKind.allCases.map(\.title) == [
            "Compare", "Listen back", "Goals", "Journal"
        ])
    }
}
