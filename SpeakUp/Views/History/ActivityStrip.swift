import SwiftUI

/// About four months of practice as a dot grid, with a switchable metric.
///
/// One grid, two lenses: *did I show up* (session count) and *was it any good*
/// (average score). Reading both off the same geometry is what makes the
/// distinction visible — a dense green wall with mediocre scores is a different
/// problem from a sparse wall with great ones.
///
/// Derived entirely from the `RecordingSummary` array History already holds, so
/// it costs no extra fetch and never touches a `Recording` blob.
struct ActivityStrip: View {
    let summaries: [RecordingSummary]

    @State private var metric: ActivityMetric = .sessions

    private static let weeksShown = 17
    private static let spacing: CGFloat = 3

    var body: some View {
        // Built once per render and passed down — reading a computed
        // `buckets` inside the cell loop would rebuild the dictionary for
        // every one of the 119 cells.
        let buckets = Self.buckets(from: summaries)

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                header

                // Cells are flexible squares so the grid always spans the full
                // card width — no scrolling, no dead space on either side.
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Self.spacing) {
                            ForEach(week, id: \.self) { day in
                                cellView(for: day, bucket: buckets[day])
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                footer(buckets)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            SectionPicker(
                sections: ActivityMetric.allCases,
                selection: $metric,
                label: { $0.shortLabel },
                style: .compact,
                layout: .scrollable
            )
            .fixedSize()
        }
    }

    private func footer(_ buckets: [Date: DayBucket]) -> some View {
        HStack(spacing: 8) {
            Text(metric.caption(for: buckets))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // Fixed-size so the caption is the side that truncates on narrow
            // screens rather than the legend collapsing.
            HStack(spacing: 3) {
                Text(metric.legendLow)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(metric.color(intensity: intensity))
                        .frame(width: 8, height: 8)
                }

                Text(metric.legendHigh)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func cellView(for day: Date, bucket: DayBucket?) -> some View {
        let isFuture = day > Date()

        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isFuture ? Color.clear : metric.color(intensity: metric.intensity(for: bucket)))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if Calendar.current.isDateInToday(day) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                }
            }
            .accessibilityLabel(accessibilityLabel(for: day, bucket: bucket))
    }

    private func accessibilityLabel(for day: Date, bucket: DayBucket?) -> String {
        let dateText = day.formatted(.dateTime.month().day())
        guard let bucket, bucket.count > 0 else { return "\(dateText), no sessions" }
        switch metric {
        case .sessions:
            return "\(dateText), \(bucket.count) session\(bucket.count == 1 ? "" : "s")"
        case .score:
            guard let average = bucket.averageScore else { return "\(dateText), no score" }
            return "\(dateText), average score \(average)"
        }
    }

    // MARK: - Derived Data

    /// Per-day totals keyed by start-of-day.
    private static func buckets(from summaries: [RecordingSummary]) -> [Date: DayBucket] {
        var result: [Date: DayBucket] = [:]
        let calendar = Calendar.current

        for summary in summaries {
            let day = calendar.startOfDay(for: summary.date)
            var bucket = result[day] ?? DayBucket()
            bucket.count += 1
            if let score = summary.overallScore {
                bucket.scoreTotal += score
                bucket.scoredCount += 1
            }
            result[day] = bucket
        }

        return result
    }

    /// `weeksShown` columns of seven days, oldest first, ending on the current week.
    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return []
        }

        return (0..<Self.weeksShown).reversed().compactMap { weekOffset -> [Date]? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: thisWeekStart) else {
                return nil
            }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        }
    }
}

// MARK: - Day Bucket

struct DayBucket {
    var count: Int = 0
    var scoreTotal: Int = 0
    var scoredCount: Int = 0

    var averageScore: Int? {
        guard scoredCount > 0 else { return nil }
        return Int((Double(scoreTotal) / Double(scoredCount)).rounded())
    }
}

// MARK: - Metric

enum ActivityMetric: String, CaseIterable, Identifiable {
    case sessions
    case score

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .sessions: return "Sessions"
        case .score: return "Score"
        }
    }

    var title: String {
        switch self {
        case .sessions: return "Practice activity"
        case .score: return "Score by day"
        }
    }

    /// Legend endpoints — the ramp means volume for sessions and quality for
    /// score, so the wording has to follow the metric.
    var legendLow: String {
        switch self {
        case .sessions: return "Less"
        case .score: return "Low"
        }
    }

    var legendHigh: String {
        switch self {
        case .sessions: return "More"
        case .score: return "High"
        }
    }

    /// Sessions saturate at 3/day — beyond that the color stops carrying
    /// information and the grid just looks uniformly loud.
    func intensity(for bucket: DayBucket?) -> Double {
        guard let bucket, bucket.count > 0 else { return 0 }
        switch self {
        case .sessions:
            return min(1.0, Double(bucket.count) / 3.0)
        case .score:
            guard let average = bucket.averageScore else { return 0 }
            return min(1.0, Double(average) / 100.0)
        }
    }

    func color(intensity: Double) -> Color {
        switch self {
        case .sessions:
            return AppColors.contributionColor(intensity: intensity)
        case .score:
            guard intensity > 0 else { return Color.white.opacity(0.06) }
            return AppColors.scoreColor(for: Int(intensity * 100)).opacity(0.35 + intensity * 0.65)
        }
    }

    func caption(for buckets: [Date: DayBucket]) -> String {
        let active = buckets.values.filter { $0.count > 0 }
        switch self {
        case .sessions:
            let total = active.reduce(0) { $0 + $1.count }
            return "\(total) session\(total == 1 ? "" : "s") · \(active.count) active day\(active.count == 1 ? "" : "s")"
        case .score:
            let scored = active.compactMap(\.averageScore)
            guard !scored.isEmpty else { return "No scored sessions yet" }
            let average = Int((Double(scored.reduce(0, +)) / Double(scored.count)).rounded())
            return "\(average) avg across \(scored.count) day\(scored.count == 1 ? "" : "s")"
        }
    }
}

#Preview {
    ZStack {
        AppBackground()
        ActivityStrip(summaries: (0..<40).map { index in
            RecordingSummary(
                id: UUID(),
                date: Date().addingTimeInterval(-Double(index) * 43200),
                actualDuration: 60,
                displayTitle: "Session \(index)",
                isFavorite: false,
                isProcessing: false,
                storyId: nil,
                promptCategory: "Storytelling",
                overallScore: 50 + (index % 45),
                wpm: 130,
                fillerCount: 3,
                searchableText: ""
            )
        })
        .padding()
    }
}
