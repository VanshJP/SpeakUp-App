import WidgetKit
import SwiftUI

struct StatsRingEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let sessions: Int
    let sessionsGoal: Int
    let score: Int
    let improvement: Int
}

struct StatsRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsRingEntry {
        StatsRingEntry(date: .now, streak: 5, sessions: 3, sessionsGoal: 5, score: 72, improvement: 12)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsRingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsRingEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func currentEntry() -> StatsRingEntry {
        StatsRingEntry(
            date: .now,
            streak: WidgetDataProvider.currentStreak,
            sessions: WidgetDataProvider.weeklySessionCount,
            sessionsGoal: WidgetDataProvider.weeklyGoalSessions,
            score: WidgetDataProvider.weeklyAverageScore,
            improvement: WidgetDataProvider.weeklyImprovementRate
        )
    }
}

// MARK: - Widget View

struct StatsRingWidgetView: View {
    let entry: StatsRingEntry
    @Environment(\.widgetFamily) private var family

    /// Same 7-day horizon the app uses for a streak ring.
    private let streakTarget = 7

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLayout
            case .accessoryRectangular:
                rectangularLayout
            case .systemSmall:
                smallLayout
            default:
                mediumLayout
            }
        }
        .widgetURL(URL(string: "speakup://record"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Small
    //
    // The rings carry no labels of their own, so the legend below is what makes
    // them readable. Keep the two together.

    private var smallLayout: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            rings(diameter: 74, lineWidth: 7, centerFont: WidgetType.value)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                legendItem(icon: "flame.fill", value: "\(entry.streak)", tint: WidgetPalette.ember)
                legendItem(icon: "mic.fill", value: "\(entry.sessions)/\(entry.sessionsGoal)", tint: WidgetPalette.brandBright)
                legendItem(icon: improvementIcon, value: improvementText, tint: improvementTint)
            }
        }
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            rings(diameter: 96, lineWidth: 9, centerFont: WidgetType.numeralMedium)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(icon: "chart.bar.fill", title: "Your Stats")

                metricRow(
                    icon: "flame.fill",
                    label: "Streak",
                    value: entry.streak == 1 ? "1 day" : "\(entry.streak) days",
                    tint: WidgetPalette.ember
                )
                metricRow(
                    icon: "mic.fill",
                    label: "Sessions",
                    value: "\(entry.sessions)/\(entry.sessionsGoal)",
                    tint: WidgetPalette.brandBright
                )
                metricRow(
                    icon: improvementIcon,
                    label: "Progress",
                    value: improvementText,
                    tint: improvementTint
                )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Lock Screen

    private var circularLayout: some View {
        Gauge(value: Double(min(max(entry.score, 0), 100)), in: 0...100) {
            Image(systemName: "waveform")
        } currentValueLabel: {
            Text(entry.score > 0 ? "\(entry.score)" : "—")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Big Talk")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
            }
            .widgetAccentable()

            Text(entry.score > 0 ? "Avg \(entry.score) · \(improvementText)" : "No scores yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(entry.streak)d streak · \(entry.sessions)/\(entry.sessionsGoal) sessions")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rings

    private func rings(diameter: CGFloat, lineWidth: CGFloat, centerFont: Font) -> some View {
        let gap = lineWidth * 2.3

        return ZStack {
            WidgetRing(
                progress: Double(min(entry.streak, streakTarget)) / Double(streakTarget),
                tint: WidgetPalette.ember,
                lineWidth: lineWidth
            )
            .frame(width: diameter, height: diameter)

            WidgetRing(
                progress: Double(entry.sessions) / Double(max(entry.sessionsGoal, 1)),
                tint: WidgetPalette.brandBright,
                lineWidth: lineWidth
            )
            .frame(width: diameter - gap, height: diameter - gap)

            WidgetRing(
                progress: Double(entry.score) / 100,
                tint: scoreTint,
                lineWidth: lineWidth
            )
            .frame(width: diameter - (gap * 2), height: diameter - (gap * 2))

            Text(entry.score > 0 ? "\(entry.score)" : "—")
                .font(centerFont)
                .foregroundStyle(scoreTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Pieces

    private func legendItem(icon: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)

            Text(value)
                .font(WidgetType.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)

            Text(label)
                .font(WidgetType.label)
                .foregroundStyle(WidgetPalette.textTertiary)

            Spacer(minLength: 4)

            Text(value)
                .font(WidgetType.value)
                .foregroundStyle(WidgetPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Helpers

    private var scoreTint: Color {
        entry.score > 0 ? WidgetPalette.score(for: entry.score) : WidgetPalette.textTertiary
    }

    private var improvementTint: Color {
        WidgetPalette.trend(for: entry.improvement)
    }

    private var improvementIcon: String {
        if entry.improvement > 1 { return "arrow.up.right" }
        if entry.improvement < -1 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var improvementText: String {
        guard abs(entry.improvement) > 1 else { return "steady" }
        let sign = entry.improvement > 0 ? "+" : ""
        return "\(sign)\(entry.improvement)%"
    }

    private var accessibilityLabel: String {
        (entry.score > 0 ? "Average score \(entry.score). " : "No scores yet. ")
            + "\(entry.streak) day streak. "
            + "\(entry.sessions) of \(entry.sessionsGoal) sessions this week. "
            + "Progress \(improvementText)."
    }
}

// MARK: - Widget Configuration

struct StatsRingWidget: Widget {
    let kind = "StatsRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsRingProvider()) { entry in
            StatsRingWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Stats Overview")
        .description("See your streak, sessions, score, and progress at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

#Preview("Small", as: .systemSmall) {
    StatsRingWidget()
} timeline: {
    StatsRingEntry(date: .now, streak: 5, sessions: 3, sessionsGoal: 5, score: 72, improvement: 12)
    StatsRingEntry(date: .now, streak: 0, sessions: 0, sessionsGoal: 5, score: 0, improvement: 0)
}

#Preview("Medium", as: .systemMedium) {
    StatsRingWidget()
} timeline: {
    StatsRingEntry(date: .now, streak: 5, sessions: 3, sessionsGoal: 5, score: 72, improvement: 12)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    StatsRingWidget()
} timeline: {
    StatsRingEntry(date: .now, streak: 5, sessions: 3, sessionsGoal: 5, score: 72, improvement: 12)
}
