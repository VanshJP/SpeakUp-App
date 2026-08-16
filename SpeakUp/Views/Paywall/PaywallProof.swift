import Foundation
import SwiftData

/// What the user's own library says, projected into plain values.
///
/// Read on a background context because it decodes `Recording.analysis`, which
/// must never happen on the main thread inside a scrolling view.
nonisolated struct PaywallProof: Sendable {
    var takes = 0
    /// Takes that actually carry a score. Distinct from `takes`, which counts
    /// unscored recordings too, and it is the span `gain` is measured across.
    var scoredTakes = 0
    var best = 0
    var streak = 0
    var firstScore: Int?
    var gain: Int?
    /// Oldest to newest, capped — a sparkline 200 points wide is a smear.
    var recentScores: [Int] = []
    var deferred = 0
    /// Where the missing points are, from the same recent window.
    var headroom: PaywallHeadroom?

    var hasScores: Bool { !recentScores.isEmpty }

    /// Points gained per take, from the user's own first-to-last movement.
    /// Nil below three takes or when the trend is flat or down — a pace claim
    /// built on two points, or on a decline, is not a claim worth making.
    ///
    /// Divided by `scoredTakes`, not `recentScores.count`: `gain` spans the
    /// whole history, while `recentScores` is capped at 14 for the sparkline.
    /// Mixing the two overstated the rate by the ratio between them — roughly
    /// 7x for a hundred-take user — and that rate is what
    /// `monthsToCloseOnFreeTier` puts on the paywall as a claim.
    var pointsPerTake: Double? {
        guard scoredTakes >= 3, let gain, gain > 0 else { return nil }
        return Double(gain) / Double(scoredTakes - 1)
    }

    /// How long the free tier takes to close the remaining gap, at the rate
    /// this user is actually improving. Nil when either input is missing.
    var monthsToCloseOnFreeTier: Int? {
        guard let headroom, let rate = pointsPerTake else { return nil }
        return Self.monthsToClose(
            points: headroom.points,
            pointsPerTake: rate,
            takesPerMonth: Double(FreeTierPolicy.expired.monthlyAnalyses)
        )
    }

    // MARK: - Pure math

    /// Months of practice needed to close `points`, capped at three years so a
    /// near-flat rate reads as "a long time" rather than a nonsense number.
    static func monthsToClose(points: Int, pointsPerTake: Double, takesPerMonth: Double) -> Int? {
        guard points > 0, pointsPerTake > 0, takesPerMonth > 0 else { return nil }
        let takesNeeded = Double(points) / pointsPerTake
        let months = (takesNeeded / takesPerMonth).rounded(.up)
        return min(36, max(1, Int(months)))
    }

    // MARK: - Load

    static func load(container: ModelContainer) async -> PaywallProof {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            let recordings = (try? context.fetch(descriptor)) ?? []
            let analyses = recordings.compactMap(\.analysis)
            let scores = analyses.map(\.speechScore.overall)

            var proof = PaywallProof()
            proof.takes = recordings.count
            proof.scoredTakes = scores.count
            proof.best = scores.max() ?? 0
            proof.streak = Date.calculateStreak(from: recordings.map(\.date))
            proof.recentScores = Array(scores.suffix(14))
            proof.deferred = recordings.filter(\.analysisBlockedByAllowance).count
            proof.firstScore = scores.first
            if let first = scores.first, let last = scores.last, scores.count >= 2 {
                proof.gain = last - first
            }
            proof.headroom = PaywallHeadroom.make(
                subscores: analyses.suffix(5).map(\.speechScore.subscores),
                recentOverall: Array(scores.suffix(5))
            )
            return proof
        }.value
    }
}

// MARK: - Headroom

/// One dimension the user has not maxed out, and what closing it is worth.
nonisolated struct SubscoreGap: Sendable, Equatable, Identifiable {
    let name: String
    let value: Int
    /// Overall-score points this dimension is still holding back.
    let worth: Int
    /// Index into `AppColors.subscoreTone`, so the paywall and the weight
    /// editor tint the same dimension the same way.
    let toneIndex: Int

    var id: String { name }
}

/// The "how much is left" half of the offer, computed from the user's own
/// recent sessions rather than from any claim about other people.
nonisolated struct PaywallHeadroom: Sendable, Equatable {
    /// Average overall score over the recent window — the number the user has
    /// been seeing on their own results.
    let current: Int
    /// Points between `current` and a perfect 100.
    let points: Int
    /// Weakest first, capped to the three worth showing.
    let gaps: [SubscoreGap]

    /// Averages each dimension over the window, then ranks by what a perfect
    /// score in that dimension would add to the overall — a weak dimension with
    /// a small weight is not the one to practise first.
    ///
    /// ponytail: uses `ScoreWeights.defaults` rather than the user's tuned
    /// weights. Fetching `UserSettings` here would put a second query on the
    /// paywall load for a number that moves by a point or two.
    static func make(subscores: [SpeechSubscores], recentOverall: [Int]) -> PaywallHeadroom? {
        guard !subscores.isEmpty, !recentOverall.isEmpty else { return nil }

        let weights = ScoreWeights.defaults
        let dimensions: [(name: String, values: [Int], weight: Double, tone: Int)] = [
            ("Clarity", subscores.map(\.clarity), weights.clarity, 0),
            ("Pace", subscores.map(\.pace), weights.pace, 1),
            ("Filler control", subscores.map(\.fillerUsage), weights.filler, 2),
            ("Pauses", subscores.map(\.pauseQuality), weights.pause, 3),
            ("Vocal variety", subscores.compactMap(\.vocalVariety), weights.vocalVariety, 4),
            ("Delivery", subscores.compactMap(\.delivery), weights.delivery, 5),
            ("Vocabulary", subscores.compactMap(\.vocabulary), weights.vocabulary, 6),
            ("Structure", subscores.compactMap(\.structure), weights.structure, 7),
            ("Relevance", subscores.compactMap(\.relevance), weights.relevance, 8)
        ]

        let available = dimensions.filter { !$0.values.isEmpty }
        let totalWeight = available.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let gaps: [SubscoreGap] = available.compactMap { dimension in
            let average = Int((Double(dimension.values.reduce(0, +)) / Double(dimension.values.count)).rounded())
            let worth = Int(((dimension.weight / totalWeight) * Double(100 - average)).rounded())
            // A dimension already at the ceiling is not headroom, and a rounded
            // zero is not a reason to practise anything.
            guard worth > 0 else { return nil }
            return SubscoreGap(name: dimension.name, value: average, worth: worth, toneIndex: dimension.tone)
        }
        .sorted { $0.worth > $1.worth }

        let current = Int((Double(recentOverall.reduce(0, +)) / Double(recentOverall.count)).rounded())
        let points = max(0, 100 - current)
        guard points > 0, !gaps.isEmpty else { return nil }

        return PaywallHeadroom(current: current, points: points, gaps: Array(gaps.prefix(3)))
    }
}
