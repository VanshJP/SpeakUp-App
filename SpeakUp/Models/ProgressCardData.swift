import Foundation

/// Everything the Then-vs-Now share card is allowed to show.
///
/// A value type rather than two `Recording`s on purpose: the card physically
/// cannot leak a transcript, a prompt, a story title, or an audio URL, because
/// none of them exist on this struct. Dates, counts, and scores only.
nonisolated struct ProgressCardData: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let label: String
        let before: Int
        let after: Int
        /// Whether a lower number is the better one (filler count).
        let lowerIsBetter: Bool

        var improved: Bool {
            lowerIsBetter ? after < before : after > before
        }

        var changed: Bool { after != before }
    }

    let firstDate: Date
    let latestDate: Date
    let firstScore: Int
    let latestScore: Int
    let sessionCount: Int
    let rows: [Row]

    var delta: Int { latestScore - firstScore }

    var daysBetween: Int {
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: latestDate).day ?? 0
        return max(days, 0)
    }

    /// The one line the card leads with. Progress is stated plainly and a
    /// flat or negative delta is not dressed up as a win — a share card that
    /// lies is worth less than no share card.
    var headline: String {
        if delta > 0 { return "+\(delta) points" }
        if delta == 0 { return "Holding steady" }
        return "\(sessionCount) sessions in"
    }

    var subheadline: String {
        let sessions = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        guard daysBetween > 0 else { return sessions }
        let days = daysBetween == 1 ? "1 day" : "\(daysBetween) days"
        return "\(sessions) over \(days)"
    }
}

extension ProgressCardData {
    /// Builds the card from the two analyses the comparison screens already
    /// hold. Returns nil when either side is unscored.
    static func make(
        first: SpeechAnalysis?,
        firstDate: Date,
        latest: SpeechAnalysis?,
        latestDate: Date,
        sessionCount: Int
    ) -> ProgressCardData? {
        guard let first, let latest else { return nil }

        return ProgressCardData(
            firstDate: firstDate,
            latestDate: latestDate,
            firstScore: first.speechScore.overall,
            latestScore: latest.speechScore.overall,
            sessionCount: sessionCount,
            rows: [
                Row(
                    label: "Clarity",
                    before: first.speechScore.subscores.clarity,
                    after: latest.speechScore.subscores.clarity,
                    lowerIsBetter: false
                ),
                Row(
                    label: "Pace",
                    before: first.speechScore.subscores.pace,
                    after: latest.speechScore.subscores.pace,
                    lowerIsBetter: false
                ),
                Row(
                    label: "Pauses",
                    before: first.speechScore.subscores.pauseQuality,
                    after: latest.speechScore.subscores.pauseQuality,
                    lowerIsBetter: false
                ),
                Row(
                    label: "Fillers",
                    before: first.totalFillerCount,
                    after: latest.totalFillerCount,
                    lowerIsBetter: true
                )
            ]
        )
    }
}
