import Foundation

/// Modular blocks on the Today home screen. Users reorder and hide these the
/// way Bevel-style health dashboards do — session stays pinned because it is
/// the one action the screen exists to start.
nonisolated enum TodayHomeModule: String, CaseIterable, Identifiable, Sendable, Codable {
    case rings
    case weeklyRecap
    case focus
    case session
    case tools
    case learn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rings: return "Weekly rings"
        case .weeklyRecap: return "Weekly recap"
        case .focus: return "Coach focus"
        case .session: return "Today's session"
        case .tools: return "Prep tools"
        case .learn: return "Learning path"
        }
    }

    var subtitle: String {
        switch self {
        case .rings: return "Sessions, score, and improvement at a glance"
        case .weeklyRecap: return "What changed since last week (when there is news)"
        case .focus: return "The one thing to work on before you speak"
        case .session: return "Prompt, word workout, and start buttons — always on"
        case .tools: return "Warm-up, drills, calm, and the prompt wheel"
        case .learn: return "Jump into this week's curriculum lesson"
        }
    }

    var icon: String {
        switch self {
        case .rings: return "circle.circle"
        case .weeklyRecap: return "chart.line.uptrend.xyaxis"
        case .focus: return "scope"
        case .session: return "mic.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .learn: return "map.fill"
        }
    }

    /// Cannot be hidden or pushed out of the layout — the home screen's job.
    var isPinned: Bool { self == .session }

    /// Factory default order and visibility. Learn is off until the user opts in
    /// so Today stays a practice surface, not a second Learning Path tab.
    static let defaultVisible: [TodayHomeModule] = [
        .rings, .weeklyRecap, .focus, .session, .tools
    ]
}

/// Resolves the persisted Today layout. Empty storage means "never customized"
/// and returns the factory default — not an empty home.
nonisolated enum TodayHomeLayout {
    static func resolve(_ raw: [String]) -> [TodayHomeModule] {
        guard !raw.isEmpty else { return TodayHomeModule.defaultVisible }

        var seen = Set<TodayHomeModule>()
        var ordered: [TodayHomeModule] = []
        for value in raw {
            guard let module = TodayHomeModule(rawValue: value), !seen.contains(module) else { continue }
            seen.insert(module)
            ordered.append(module)
        }

        // Session is required. If a stale or hand-edited payload dropped it,
        // put it back after focus (or at the front if focus is also missing).
        if !ordered.contains(.session) {
            if let focusIndex = ordered.firstIndex(of: .focus) {
                ordered.insert(.session, at: focusIndex + 1)
            } else {
                ordered.insert(.session, at: min(ordered.count, 2))
            }
        }

        return ordered
    }

    /// Full catalog for the customize editor: visible modules first (in order),
    /// then every hidden module in CaseIterable order.
    static func editorRows(visibleRaw: [String]) -> [TodayHomeModule] {
        let visible = resolve(visibleRaw)
        let hidden = TodayHomeModule.allCases.filter { !visible.contains($0) }
        return visible + hidden
    }

    static func encode(_ modules: [TodayHomeModule]) -> [String] {
        modules.map(\.rawValue)
    }
}
