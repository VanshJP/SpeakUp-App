import Foundation

/// How well the speaker recalled a word. There is no rating UI — saying the
/// word in a recording *is* the review, so the grade is inferred from how many
/// times it showed up that day.
nonisolated enum VocabGrade: Int, Sendable {
    case again = 1
    case good = 3
    case easy = 4
}

/// FSRS memory state for one vocabulary word.
///
/// Lives in `UserDefaults` next to the day cache rather than in SwiftData: it
/// is a handful of doubles per word, it has to be readable off the main actor
/// while picking, and it carries no user content worth syncing.
nonisolated struct VocabReviewState: Codable, Sendable, Equatable {
    var stability: Double
    var difficulty: Double
    var lastReview: Date
    var due: Date
    var reps: Int
    var lapses: Int
    /// Days missed in a row. Optional so state written before backoff existed
    /// still decodes. Reset by any successful review.
    var consecutiveLapses: Int?
    /// Day stamp of the last grade. A day counts once no matter how many times
    /// Today or a finished recording re-evaluates the same words.
    var lastGradedDay: String
}

/// FSRS-4.5 scheduler. Decides when a word should come back so it moves into
/// active vocabulary instead of being spotlighted once and forgotten.
nonisolated enum VocabScheduler {
    /// Published FSRS-4.5 default weights. Not optimized per user — 1–3 reviews
    /// a day is nowhere near enough of a review log to train on.
    private static let w: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474,
        0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755
    ]
    private static let decay = -0.5
    private static let factor = 19.0 / 81.0
    /// ponytail: retention and the interval ceiling are constants, not settings.
    /// 0.9 is the FSRS default; the 90-day cap keeps a well-known word in
    /// rotation instead of retiring it for a year. Expose them only if someone
    /// asks to tune them.
    private static let desiredRetention = 0.9
    private static let maxIntervalDays = 90.0
    /// D₀ for an easy first review — FSRS reverts difficulty toward this.
    private static let reversionTarget = initialDifficulty(4)

    /// Probability the speaker still has the word available, 0…1.
    static func retrievability(_ state: VocabReviewState, on date: Date) -> Double {
        let elapsedDays = max(0, date.timeIntervalSince(state.lastReview) / 86_400)
        return pow(1 + factor * elapsedDays / max(state.stability, 0.1), decay)
    }

    static func review(
        _ state: VocabReviewState?,
        grade: VocabGrade,
        on date: Date,
        calendar: Calendar = .current
    ) -> VocabReviewState {
        let stamp = VocabChallengeService.dayStamp(date, calendar: calendar)

        guard let state else {
            let stability = max(0.1, w[grade.rawValue - 1])
            return VocabReviewState(
                stability: stability,
                difficulty: initialDifficulty(Double(grade.rawValue)),
                lastReview: date,
                due: dueDate(stability: stability, from: date, calendar: calendar),
                reps: 1,
                lapses: grade == .again ? 1 : 0,
                consecutiveLapses: grade == .again ? 1 : 0,
                lastGradedDay: stamp
            )
        }

        let g = Double(grade.rawValue)
        let r = retrievability(state, on: date)
        let drifted = state.difficulty - w[6] * (g - 3)
        let difficulty = clamp(w[7] * reversionTarget + (1 - w[7]) * drifted, 1, 10)

        let stability: Double
        if grade == .again {
            let forgotten = w[11]
                * pow(difficulty, -w[12])
                * (pow(state.stability + 1, w[13]) - 1)
                * exp(w[14] * (1 - r))
            // Forgetting must never look like progress.
            stability = max(0.1, min(forgotten, state.stability))
        } else {
            let easyBonus = grade == .easy ? w[16] : 1.0
            let growth = exp(w[8])
                * (11 - difficulty)
                * pow(state.stability, -w[9])
                * (exp(w[10] * (1 - r)) - 1)
                * easyBonus
            stability = max(0.1, state.stability * (1 + growth))
        }

        return VocabReviewState(
            stability: stability,
            difficulty: difficulty,
            lastReview: date,
            due: dueDate(stability: stability, from: date, calendar: calendar),
            reps: state.reps + 1,
            lapses: state.lapses + (grade == .again ? 1 : 0),
            consecutiveLapses: grade == .again ? (state.consecutiveLapses ?? 0) + 1 : 0,
            lastGradedDay: stamp
        )
    }

    // MARK: - Helpers

    private static func initialDifficulty(_ grade: Double) -> Double {
        clamp(w[4] - (grade - 3) * w[5], 1, 10)
    }

    private static func dueDate(stability: Double, from date: Date, calendar: Calendar) -> Date {
        let raw = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        let days = Int(min(maxIntervalDays, max(1, raw.rounded())))
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start) ?? date
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}
