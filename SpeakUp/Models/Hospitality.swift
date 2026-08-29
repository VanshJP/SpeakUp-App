import Foundation

// MARK: - Signal

/// Unstated needs the app can notice without a form — Guidara's "ghosts".
///
/// Detection is pure and on-device. These are facts about practice history and
/// the latest take, not vibes inferred from a chat model.
nonisolated enum HospitalitySignal: String, CaseIterable, Sendable, Identifiable {
    case returnFromLapse
    case streakMilestone
    case firstAxisClear
    case practiceAnniversary
    case softLanding
    case fillerBreakthrough
    case lifeContextPrep

    var id: String { rawValue }

    /// Whether fulfilling this signal spends the weekly legend budget.
    /// Soft return and dignity care are baseline hospitality (the 95%); legends
    /// are the rare 5%.
    var isLegend: Bool {
        switch self {
        case .returnFromLapse, .softLanding: return false
        case .streakMilestone, .firstAxisClear, .practiceAnniversary,
             .fillerBreakthrough, .lifeContextPrep: return true
        }
    }

    /// Higher wins when several ghosts fire at once.
    var priority: Int {
        switch self {
        case .softLanding: return 100
        case .returnFromLapse: return 90
        case .practiceAnniversary: return 80
        case .streakMilestone: return 70
        case .firstAxisClear: return 60
        case .fillerBreakthrough: return 50
        case .lifeContextPrep: return 40
        }
    }
}

// MARK: - Life context

/// Lightweight transcript ghosts — keywords that hint at a real-world stake.
nonisolated enum HospitalityLifeContext: String, Sendable, CaseIterable {
    case interview
    case presentation
    case wedding
    case standup
    case pitch

    var title: String {
        switch self {
        case .interview: return "Interview"
        case .presentation: return "Presentation"
        case .wedding: return "Toast"
        case .standup: return "Stand-up"
        case .pitch: return "Pitch"
        }
    }

    var coachingLine: String {
        switch self {
        case .interview:
            return "Lead with the answer in sentence one, then support it. Interviews reward clarity over warming up."
        case .presentation:
            return "One idea per breath. Land the point, pause two beats, then move — the room needs the gap more than you do."
        case .wedding:
            return "Pick one story and one feeling. A toast that tries to cover everything covers nothing."
        case .standup:
            return "Thirty seconds of signal: what shipped, what's blocked, what you need. Cut the throat-clearing."
        case .pitch:
            return "Problem, stakes, ask — in that order. The ask belongs in the last ten seconds, not buried mid-flow."
        }
    }

    /// Case-insensitive token/phrase hits. Deliberately narrow so a casual
    /// mention of "pitch" in sports talk does not invent a fundraising brief.
    static func detect(in transcript: String) -> HospitalityLifeContext? {
        let lower = transcript.lowercased()
        let checks: [(HospitalityLifeContext, [String])] = [
            (.interview, ["interview", "hiring manager", "job offer"]),
            (.wedding, ["wedding", "maid of honor", "best man", "toast to"]),
            (.standup, ["stand-up", "standup", "daily scrum", "scrum today"]),
            (.pitch, ["pitch deck", "investor", "fundraising", "seed round"]),
            (.presentation, ["presentation", "keynote", "all-hands", "slide deck"]),
        ]
        for (context, needles) in checks {
            if needles.contains(where: { lower.contains($0) }) {
                return context
            }
        }
        return nil
    }
}

// MARK: - Gesture / action / surface

nonisolated enum HospitalityGesture: String, Sendable, CaseIterable {
    case softReturn
    case victoryMontage
    case axisToast
    case anniversaryToast
    case dignityRetry
    case contextualBrief
}

nonisolated enum HospitalityAction: Sendable, Equatable {
    case openConfidence
    case openWarmUp
    case openDrill(String)
    case openReadAloud
    case practiceAgain
    case dismissOnly
}

nonisolated enum HospitalitySurface: String, Sendable {
    /// Inline card on Today (FriendChallenge-style).
    case today
    /// Inline card on the session results screen.
    case detail
    /// Full-screen overlay celebration.
    case overlay
}

// MARK: - Moment

/// One delivered hospitality gesture — copy + action + budget class.
nonisolated struct HospitalityMoment: Sendable, Identifiable, Equatable {
    let id: String
    let signal: HospitalitySignal
    let gesture: HospitalityGesture
    let title: String
    let body: String
    let actionTitle: String
    let action: HospitalityAction
    let surface: HospitalitySurface
    /// Optional dimension / life-context slug for analytics (bucketed).
    let detailSlug: String?

    var isLegend: Bool { signal.isLegend }
}

// MARK: - Snapshot / budget

/// Everything the engine needs. Built by the service from SwiftData; the
/// engine itself never touches a ModelContext.
nonisolated struct HospitalitySnapshot: Sendable {
    var now: Date = .now
    var currentStreak: Int = 0
    var practicedToday: Bool = false
    /// Nil when the user has never completed a scored take.
    var daysSinceLastPractice: Int? = nil
    var firstPracticeDate: Date? = nil
    var latestOverall: Int? = nil
    var latestFillerCount: Int? = nil
    var latestTotalWords: Int? = nil
    var latestTranscript: String? = nil
    /// Dimensions that cleared mastery on *this* take and were never cleared
    /// before — the "first axis win" ghost.
    var newlyClearedDimensions: [CoachDimension] = []
    var userName: String = ""
    var lifeContext: HospitalityLifeContext? = nil
}

nonisolated struct HospitalityBudgetState: Sendable, Equatable {
    var weekKey: String
    var legendsUsed: Int
    /// Moment ids already delivered (capped by the engine when persisting).
    var deliveredIDs: [String]

    static let weeklyLegendCap = 1

    var remainingLegends: Int {
        max(0, Self.weeklyLegendCap - legendsUsed)
    }

    func rolling(now: Date, calendar: Calendar = .current) -> HospitalityBudgetState {
        let key = HospitalityEngine.weekKey(for: now, calendar: calendar)
        if key == weekKey { return self }
        return HospitalityBudgetState(weekKey: key, legendsUsed: 0, deliveredIDs: deliveredIDs)
    }
}

// MARK: - Engine

/// Pure 95/5 hospitality: detect ghosts, pick one gesture, respect the budget.
nonisolated enum HospitalityEngine {

    /// Days away before a return is treated as a lapse worth hosting.
    static let lapseThresholdDays = 3
    /// Soft-landing overall ceiling — below this, protect dignity first.
    static let softLandingOverallCeiling = 45
    /// Anniversary milestones (days since first practice).
    static let anniversaryDays: [Int] = [30, 100, 365]

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? calendar.component(.year, from: date)
        let week = comps.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        calendar.startOfDay(for: date).ISO8601Format()
    }

    // MARK: Detect

    static func detectSignals(
        _ snap: HospitalitySnapshot,
        calendar: Calendar = .current
    ) -> [HospitalitySignal] {
        var signals: [HospitalitySignal] = []

        if let days = snap.daysSinceLastPractice,
           days >= lapseThresholdDays,
           !snap.practicedToday {
            signals.append(.returnFromLapse)
        }

        if snap.currentStreak >= 7, snap.currentStreak % 7 == 0, snap.practicedToday {
            signals.append(.streakMilestone)
        }

        if !snap.newlyClearedDimensions.isEmpty {
            signals.append(.firstAxisClear)
        }

        if let first = snap.firstPracticeDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: first),
                to: calendar.startOfDay(for: snap.now)
            ).day ?? 0
            if anniversaryDays.contains(days) {
                signals.append(.practiceAnniversary)
            }
        }

        if let overall = snap.latestOverall,
           let words = snap.latestTotalWords,
           words > 0,
           overall > 0,
           overall < softLandingOverallCeiling {
            signals.append(.softLanding)
        }

        if let fillers = snap.latestFillerCount,
           let words = snap.latestTotalWords,
           words >= 40,
           fillers == 0 {
            signals.append(.fillerBreakthrough)
        }

        if snap.lifeContext != nil || HospitalityLifeContext.detect(in: snap.latestTranscript ?? "") != nil {
            signals.append(.lifeContextPrep)
        }

        return signals.sorted { $0.priority > $1.priority }
    }

    // MARK: Propose

    /// Picks at most one moment. Legends require budget; care gestures do not.
    /// When `surface` is set, only moments for that surface are considered —
    /// so Today care cannot starve an overlay legend on the same visit.
    static func propose(
        snapshot: HospitalitySnapshot,
        budget: HospitalityBudgetState,
        surface: HospitalitySurface? = nil,
        calendar: Calendar = .current
    ) -> HospitalityMoment? {
        let rolled = budget.rolling(now: snapshot.now, calendar: calendar)
        let signals = detectSignals(snapshot, calendar: calendar)
        let delivered = Set(rolled.deliveredIDs)
        let day = dayKey(for: snapshot.now, calendar: calendar)

        for signal in signals {
            if signal.isLegend, rolled.remainingLegends <= 0 { continue }
            guard let moment = moment(
                for: signal,
                snapshot: snapshot,
                dayKey: day
            ) else { continue }
            if let surface, moment.surface != surface { continue }
            if delivered.contains(moment.id) { continue }
            return moment
        }
        return nil
    }

    // MARK: Moment builders

    private static func moment(
        for signal: HospitalitySignal,
        snapshot: HospitalitySnapshot,
        dayKey: String
    ) -> HospitalityMoment? {
        let name = snapshot.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greet = name.isEmpty ? nil : name

        switch signal {
        case .returnFromLapse:
            let days = snapshot.daysSinceLastPractice ?? lapseThresholdDays
            return HospitalityMoment(
                id: "return-\(dayKey)",
                signal: .returnFromLapse,
                gesture: .softReturn,
                title: greet.map { "Welcome back, \($0)" } ?? "Welcome back",
                body: "It's been \(days) days. No lecture — a sixty-second calm reset, then today's prompt when you're ready.",
                actionTitle: "Ease back in",
                action: .openConfidence,
                surface: .today,
                detailSlug: "lapse_\(min(days, 30))"
            )

        case .streakMilestone:
            let streak = snapshot.currentStreak
            return HospitalityMoment(
                id: "streak-\(streak)",
                signal: .streakMilestone,
                gesture: .victoryMontage,
                title: "Day \(streak)",
                body: "Seven-day blocks are how voices change. You showed up again — that is the whole trick.",
                actionTitle: "Keep the streak warm",
                action: .openWarmUp,
                surface: .overlay,
                detailSlug: "streak_\(streak)"
            )

        case .firstAxisClear:
            guard let dimension = snapshot.newlyClearedDimensions.first else { return nil }
            return HospitalityMoment(
                id: "axis-\(dimension.rawValue)",
                signal: .firstAxisClear,
                gesture: .axisToast,
                title: "\(dimension.title) cleared",
                body: "First time hitting the bar on \(dimension.title.lowercased()). That habit is yours now — bank another rep while it is warm.",
                actionTitle: "One more rep",
                action: .practiceAgain,
                surface: .detail,
                detailSlug: dimension.analyticsSlug
            )

        case .practiceAnniversary:
            guard let first = snapshot.firstPracticeDate else { return nil }
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: first),
                to: Calendar.current.startOfDay(for: snapshot.now)
            ).day ?? 0
            return HospitalityMoment(
                id: "anniversary-\(days)",
                signal: .practiceAnniversary,
                gesture: .anniversaryToast,
                title: days == 365 ? "One year of practice" : "\(days) days in",
                body: greet.map {
                    "\($0), you started this quietly and kept going. That is unreasonable hospitality to your future self."
                } ?? "You started this quietly and kept going. That is unreasonable hospitality to your future self.",
                actionTitle: "Practice today",
                action: .practiceAgain,
                surface: .overlay,
                detailSlug: "days_\(days)"
            )

        case .softLanding:
            return HospitalityMoment(
                id: "soft-\(dayKey)",
                signal: .softLanding,
                gesture: .dignityRetry,
                title: "Rough take — still yours",
                body: "Scores can wait. Trash the pressure, keep the dignity, and try the same prompt once more when you're ready.",
                actionTitle: "Try again, gently",
                action: .practiceAgain,
                surface: .detail,
                detailSlug: "soft"
            )

        case .fillerBreakthrough:
            return HospitalityMoment(
                id: "filler-zero-\(dayKey)",
                signal: .fillerBreakthrough,
                gesture: .victoryMontage,
                title: "Zero fillers",
                body: "A full take without a crutch word. That silence you held instead — that is control.",
                actionTitle: "Lock it in",
                action: .openDrill("fillerElimination"),
                surface: .detail,
                detailSlug: "zero_filler"
            )

        case .lifeContextPrep:
            let context = snapshot.lifeContext
                ?? HospitalityLifeContext.detect(in: snapshot.latestTranscript ?? "")
            guard let context else { return nil }
            let action: HospitalityAction = {
                switch context {
                case .interview, .standup, .pitch: return .openDrill("impromptuSprint")
                case .presentation, .wedding: return .openWarmUp
                }
            }()
            return HospitalityMoment(
                id: "life-\(context.rawValue)-\(dayKey)",
                signal: .lifeContextPrep,
                gesture: .contextualBrief,
                title: "\(context.title) mode",
                body: context.coachingLine,
                actionTitle: "Train for it",
                action: action,
                surface: .today,
                detailSlug: context.rawValue
            )
        }
    }

    /// Dimensions that hit mastery on this take and were never cleared before.
    static func newlyCleared(
        current: SpeechSubscores,
        previouslyCleared: Set<String>,
        masteryTarget: Int = CoachPlanService.masteryTarget
    ) -> [CoachDimension] {
        CoachDimension.allCases.filter { dimension in
            guard !previouslyCleared.contains(dimension.rawValue) else { return false }
            guard let score = dimension.subscore(in: current) else { return false }
            return score >= masteryTarget
        }
    }

    /// Cap delivered-id history so UserSettings does not grow forever.
    static func cappedDeliveredIDs(_ ids: [String], adding newID: String, limit: Int = 40) -> [String] {
        var next = ids.filter { $0 != newID }
        next.append(newID)
        if next.count > limit {
            next = Array(next.suffix(limit))
        }
        return next
    }
}
