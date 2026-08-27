import Testing
@testable import SpeakUp

@Suite("Today home layout")
struct TodayHomeLayoutTests {

    @Test("Empty storage resolves to factory default")
    func emptyMeansDefault() {
        #expect(TodayHomeLayout.resolve([]) == TodayHomeModule.defaultVisible)
    }

    @Test("Session is forced back when a payload drops it")
    func sessionAlwaysPinned() {
        let raw = ["rings", "tools", "learn"]
        let resolved = TodayHomeLayout.resolve(raw)
        #expect(resolved.contains(.session))
        #expect(resolved.first == .rings)
        #expect(resolved.contains(.tools))
        #expect(resolved.contains(.learn))
    }

    @Test("Unknown raw values are skipped and order is preserved")
    func skipsUnknownPreservesOrder() {
        let raw = ["focus", "not-a-module", "session", "tools"]
        #expect(TodayHomeLayout.resolve(raw) == [.focus, .session, .tools])
    }

    @Test("Duplicates collapse to first occurrence")
    func dedupes() {
        let raw = ["session", "rings", "session", "tools"]
        #expect(TodayHomeLayout.resolve(raw) == [.session, .rings, .tools])
    }

    @Test("Encode round-trips through resolve")
    func encodeRoundTrip() {
        let modules: [TodayHomeModule] = [.tools, .session, .rings]
        let encoded = TodayHomeLayout.encode(modules)
        #expect(TodayHomeLayout.resolve(encoded) == modules)
    }

    @Test("Default visible keeps session and hides learn")
    func defaultHidesLearn() {
        #expect(TodayHomeModule.defaultVisible.contains(.session))
        #expect(!TodayHomeModule.defaultVisible.contains(.learn))
        #expect(TodayHomeModule.session.isPinned)
    }
}

@Suite("Practice tool catalog")
struct PracticeToolKindTests {

    @Test("Coach routes map to the owning tool")
    func recommendedFromRoute() {
        #expect(PracticeToolKind.recommended(for: .warmUp) == .warmUp)
        #expect(PracticeToolKind.recommended(for: .readAloud) == .readAloud)
        #expect(PracticeToolKind.recommended(for: .drill("fillerElimination")) == .drills)
        #expect(PracticeToolKind.recommended(for: nil) == nil)
    }

    @Test("Today strip stays at four prep tools")
    func todayStripCount() {
        #expect(PracticeToolKind.todayStripDefaults.count == 4)
        #expect(PracticeToolKind.todayStripDefaults.contains(.warmUp))
        #expect(PracticeToolKind.todayStripDefaults.contains(.drills))
        #expect(PracticeToolKind.todayStripDefaults.contains(.calm))
        // Read Aloud took the Wheel's slot: the Wheel lives in Library →
        // Prompts, where you pick what to say, not in the prep strip.
        #expect(PracticeToolKind.todayStripDefaults.contains(.readAloud))
        #expect(!PracticeToolKind.todayStripDefaults.contains(.learn))
    }
}
