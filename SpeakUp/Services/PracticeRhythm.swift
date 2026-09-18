import Foundation

/// Learns the time of day a user actually practises and turns it into the hour
/// the daily reminder should land.
///
/// The shape is borrowed from what Duolingo has published about their practice
/// reminder: rather than firing at a time the product picked, it converges on
/// the time that person already shows up, and arrives shortly *before* it. A
/// nudge at the moment someone was going to open the app anyway is the one that
/// gets acted on; a nudge six hours off is the one that gets the app muted.
///
/// Recording timestamps are the signal. They are the only honest record of when
/// this user practises, and they cost nothing extra to collect.
///
/// Pure and `nonisolated` so the whole rule set is testable without a
/// `ModelContext`, a notification centre, or a clock.
nonisolated enum PracticeRhythm {
    /// How far ahead of the usual time the reminder lands. Long enough to be a
    /// prompt rather than an echo, short enough that the intent survives it.
    static let leadMinutes = 30

    /// Below this many sessions there is no rhythm to speak of, so any signal
    /// beats the 9:00 default and the spread test is skipped. At or above it,
    /// a scattered history has to clear `minimumConcentration` before it is
    /// allowed to move the reminder.
    static let minimumSessions = 4

    /// Mean resultant length (0 = times spread evenly around the clock, 1 = all
    /// identical). 0.55 is roughly "most sessions inside a three-hour window".
    /// Below it the user has no settled time and moving the reminder daily
    /// would be churn dressed up as personalization.
    static let minimumConcentration = 0.55

    /// Sessions older than this contribute almost nothing. Someone who moved
    /// their practice from morning to evening should be followed within a
    /// couple of weeks, not averaged against a habit they no longer have.
    static let halfLifeDays = 14.0

    /// How many of the most recent sessions to weigh at all.
    static let sampleLimit = 40

    private static let minutesPerDay = 1440.0

    // MARK: - Suggestion

    struct Suggestion: Equatable {
        /// When the reminder should fire - `typical` minus the lead.
        var hour: Int
        var minute: Int
        /// The learned practice time itself, for copy that has to explain the
        /// reminder ("you usually practise around 7:40 PM").
        var typicalHour: Int
        var typicalMinute: Int
        /// Mean resultant length of the sample. Reported so a caller can say
        /// how settled the rhythm is without recomputing it.
        var concentration: Double
    }

    /// The reminder time this user's history argues for, or `nil` when the
    /// history has nothing to say and the currently stored time should stand.
    ///
    /// - Parameters:
    /// - practiceDates: session timestamps, any order.
    /// - now: reference point for recency weighting.
    static func suggestion(
        from practiceDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Suggestion? {
        let sample = practiceDates.sorted(by: >).prefix(sampleLimit)
        guard !sample.isEmpty else { return nil }

        // Times of day live on a circle: 23:50 and 00:10 are twenty minutes
        // apart, and an arithmetic mean of the two lands at noon. Averaging the
        // unit vectors instead is what makes a late-night practitioner get a
        // late-night reminder.
        var x = 0.0
        var y = 0.0
        var totalWeight = 0.0

        for date in sample {
            guard let minutes = minutesIntoDay(date, calendar: calendar) else { continue }
            let ageDays = max(0, now.timeIntervalSince(date)) / 86_400
            let weight = pow(0.5, ageDays / halfLifeDays)
            let angle = 2 * Double.pi * Double(minutes) / minutesPerDay
            x += weight * cos(angle)
            y += weight * sin(angle)
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }

        let concentration = (x * x + y * y).squareRoot() / totalWeight
        // A tight cluster is what earns the right to move someone's reminder.
        // Under `minimumSessions` we are seeding rather than learning, and a
        // seed from one real session still beats a default nobody chose.
        if sample.count >= minimumSessions, concentration < minimumConcentration {
            return nil
        }

        var meanAngle = atan2(y, x)
        if meanAngle < 0 { meanAngle += 2 * Double.pi }

        let typical = Int((meanAngle / (2 * Double.pi) * minutesPerDay).rounded())
            % Int(minutesPerDay)
        let reminder = (typical - leadMinutes + Int(minutesPerDay)) % Int(minutesPerDay)

        return Suggestion(
            hour: reminder / 60,
            minute: reminder % 60,
            typicalHour: typical / 60,
            typicalMinute: typical % 60,
            concentration: concentration
        )
    }

    // MARK: - Helpers

    private static func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }
}
