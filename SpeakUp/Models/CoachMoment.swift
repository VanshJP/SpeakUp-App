import Foundation

// MARK: - Signal

/// Practice facts that earn a rare coach note — never a form, never transcript
/// mining. Scores and dates only.
nonisolated enum CoachMomentSignal: String, CaseIterable, Sendable, Identifiable {
    case returnFromLapse
    case firstAxisClear
    case practiceAnniversary
    case softLanding

    var id: String { rawValue }

    /// Celebrations spend the weekly rarity budget. Soft return and soft landing
    /// are ordinary care and never do.
    var isCelebration: Bool {
        switch self {
        case .returnFromLapse, .softLanding: return false
        case .firstAxisClear, .practiceAnniversary: return true
        }
    }

    /// Higher wins when several signals fire at once.
    var priority: Int {
        switch self {
        case .softLanding: return 100
        case .returnFromLapse: return 90
        case .practiceAnniversary: return 80
        case .firstAxisClear: return 60
        }
    }
}

// MARK: - Action / surface

nonisolated enum CoachMomentAction: Sendable, Equatable {
    case openConfidence
    case practiceAgain
    case close
}

nonisolated enum CoachMomentSurface: String, Sendable {
    /// Inline card on Today (FriendChallenge-style).
    case today
    /// Inline card on the session results screen.
    case detail
    /// Full-screen celebration.
    case overlay
}

// MARK: - Moment

/// One coach note — short copy, one optional action, rarity class.
nonisolated struct CoachMoment: Sendable, Identifiable, Equatable {
    let id: String
    let signal: CoachMomentSignal
    let title: String
    let body: String
    let actionTitle: String
    let action: CoachMomentAction
    let surface: CoachMomentSurface
    /// Optional dimension slug for analytics (bucketed).
    let detailSlug: String?

    var isCelebration: Bool { signal.isCelebration }
}

// MARK: - Snapshot / budget

/// Everything the engine needs. Built by the service from SwiftData; the
/// engine itself never touches a ModelContext. No transcript text.
nonisolated struct CoachMomentSnapshot: Sendable {
    var now: Date = .now
    var practicedToday: Bool = false
    /// Nil when the user has never completed a scored take.
    var daysSinceLastPractice: Int? = nil
    /// Stable key for one absence episode. Welcome-back delivery is tied to
    /// this date, not today's date, so it cannot nag every day while away.
    var lastPracticeDate: Date? = nil
    var firstPracticeDate: Date? = nil
    /// Includes the current result. Detail notes start on session two so the
    /// first score gets room to be understood without another intervention.
    var scoredSessionCount: Int = 0
    var latestOverall: Int? = nil
    var latestTotalWords: Int? = nil
    /// Dimensions that cleared mastery on *this* take and were never cleared
    /// before.
    var newlyClearedDimensions: [CoachDimension] = []
    var userName: String = ""
}

nonisolated struct CoachMomentBudget: Sendable, Equatable {
    var weekKey: String
    var celebrationsUsed: Int
    /// Moment ids already delivered (day-keyed ids are capped when persisting).
    var deliveredIDs: [String]

    static let weeklyCelebrationCap = 1

    var remainingCelebrations: Int {
        max(0, Self.weeklyCelebrationCap - celebrationsUsed)
    }

    func rolling(now: Date, calendar: Calendar = .current) -> CoachMomentBudget {
        let key = CoachMomentEngine.weekKey(for: now, calendar: calendar)
        if key == weekKey { return self }
        return CoachMomentBudget(weekKey: key, celebrationsUsed: 0, deliveredIDs: deliveredIDs)
    }

    /// Records either acceptance or dismissal. Seeing the celebration spends
    /// its weekly slot either way; dismissing it must not unlock another one.
    func recordingDelivery(
        of moment: CoachMoment,
        now: Date,
        calendar: Calendar = .current
    ) -> CoachMomentBudget {
        var next = rolling(now: now, calendar: calendar)
        let isNewDelivery = !next.deliveredIDs.contains(moment.id)
        if isNewDelivery, moment.isCelebration {
            next.celebrationsUsed = min(
                Self.weeklyCelebrationCap,
                next.celebrationsUsed + 1
            )
        }
        next.deliveredIDs = CoachMomentEngine.cappedDeliveredIDs(
            next.deliveredIDs,
            adding: moment.id
        )
        return next
    }
}

// MARK: - Engine

/// Rare coach notes: detect a signal, pick one note, respect the weekly cap.
nonisolated enum CoachMomentEngine {

    /// Quiet days before a welcome-back note. Higher than a single missed day
    /// so the card does not nag after a busy weekend.
    static let lapseThresholdDays = 5
    /// Soft-landing overall ceiling — below this, offer a gentle retry first.
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
        _ snap: CoachMomentSnapshot,
        calendar: Calendar = .current
    ) -> [CoachMomentSignal] {
        var signals: [CoachMomentSignal] = []

        if let days = snap.daysSinceLastPractice,
           days >= lapseThresholdDays,
           !snap.practicedToday {
            signals.append(.returnFromLapse)
        }

        let hasBaseline = snap.scoredSessionCount >= 2

        if hasBaseline, !snap.newlyClearedDimensions.isEmpty {
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

        if hasBaseline,
           let overall = snap.latestOverall,
           let words = snap.latestTotalWords,
           words > 0,
           overall > 0,
           overall < softLandingOverallCeiling {
            signals.append(.softLanding)
        }

        return signals.sorted { $0.priority > $1.priority }
    }

    // MARK: Propose

    /// Picks at most one note. Celebrations require budget; care notes do not.
    /// When `surface` is set, only notes for that surface are considered.
    static func propose(
        snapshot: CoachMomentSnapshot,
        budget: CoachMomentBudget,
        surface: CoachMomentSurface? = nil,
        calendar: Calendar = .current
    ) -> CoachMoment? {
        let rolled = budget.rolling(now: snapshot.now, calendar: calendar)
        let signals = detectSignals(snapshot, calendar: calendar)
        let delivered = Set(rolled.deliveredIDs)
        let day = dayKey(for: snapshot.now, calendar: calendar)

        for signal in signals {
            if signal.isCelebration, rolled.remainingCelebrations <= 0 { continue }
            guard let moment = moment(
                for: signal,
                snapshot: snapshot,
                dayKey: day,
                calendar: calendar
            ) else { continue }
            if let surface, moment.surface != surface { continue }
            if delivered.contains(moment.id) { continue }
            return moment
        }
        return nil
    }

    // MARK: Moment builders

    private static func moment(
        for signal: CoachMomentSignal,
        snapshot: CoachMomentSnapshot,
        dayKey: String,
        calendar: Calendar
    ) -> CoachMoment? {
        let name = snapshot.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greet = name.isEmpty ? nil : name

        switch signal {
        case .returnFromLapse:
            // No day-count — counting absences reads as surveillance.
            guard let lastPracticeDate = snapshot.lastPracticeDate else { return nil }
            return CoachMoment(
                id: "return-since-\(CoachMomentEngine.dayKey(for: lastPracticeDate, calendar: calendar))",
                signal: .returnFromLapse,
                title: greet.map { "Welcome back, \($0)" } ?? "Welcome back",
                body: "No catch-up quiz. A short calm reset, then today's prompt when you're ready.",
                actionTitle: "Ease back in",
                action: .openConfidence,
                surface: .today,
                detailSlug: "lapse"
            )

        case .firstAxisClear:
            guard let dimension = snapshot.newlyClearedDimensions.first else { return nil }
            return CoachMoment(
                id: "axis-\(dimension.rawValue)",
                signal: .firstAxisClear,
                title: "\(dimension.title) reached target",
                body: "This take cleared the mark. One more rep while it is warm.",
                actionTitle: "One more rep",
                action: .practiceAgain,
                surface: .detail,
                detailSlug: dimension.analyticsSlug
            )

        case .practiceAnniversary:
            guard let first = snapshot.firstPracticeDate else { return nil }
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: first),
                to: calendar.startOfDay(for: snapshot.now)
            ).day ?? 0
            return CoachMoment(
                id: "anniversary-\(days)",
                signal: .practiceAnniversary,
                title: days == 365 ? "One year of practice" : "\(days) days in",
                body: greet.map {
                    "\($0), every practice session added something. This milestone is yours."
                } ?? "Every practice session added something. This milestone is yours.",
                actionTitle: "Nice",
                action: .close,
                surface: .overlay,
                detailSlug: "days_\(days)"
            )

        case .softLanding:
            return CoachMoment(
                id: "soft-\(dayKey)",
                signal: .softLanding,
                title: "One take, not a verdict",
                body: "Want another go? Same prompt, no pressure.",
                actionTitle: "Try again",
                action: .practiceAgain,
                surface: .detail,
                detailSlug: "soft"
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

        // Anniversary and axis ids are lifetime milestones. Return ids only
        // need to outlive their absence episode, so keep the latest ten.
        let permanentMilestones = next.filter { id in
            id.hasPrefix("anniversary-")
                || id.hasPrefix("axis-")
        }
        let returnEpisodes = next.filter { $0.hasPrefix("return-since-") }
        let dayKeyed = next.filter { id in
            !id.hasPrefix("anniversary-")
                && !id.hasPrefix("axis-")
                && !id.hasPrefix("return-since-")
        }
        return permanentMilestones
            + Array(returnEpisodes.suffix(10))
            + Array(dayKeyed.suffix(limit))
    }
}
