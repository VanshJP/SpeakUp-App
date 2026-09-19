import WidgetKit
import SwiftUI

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let sessionCount: Int
    let goalSessions: Int
    let averageScore: Int
    let practiceMinutes: Int
    let readiness: Int

    var goalFraction: Double {
        Double(sessionCount) / Double(max(goalSessions, 1))
    }

    var goalPercent: Int {
        Int((goalFraction * 100).rounded())
    }
}

struct WeeklyProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyProgressEntry {
        WeeklyProgressEntry(
            date: .now,
            sessionCount: 3,
            goalSessions: 5,
            averageScore: 75,
            practiceMinutes: 12,
            readiness: 78
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func currentEntry() -> WeeklyProgressEntry {
        WeeklyProgressEntry(
            date: .now,
            sessionCount: WidgetDataProvider.weeklySessionCount,
            goalSessions: WidgetDataProvider.weeklyGoalSessions,
            averageScore: WidgetDataProvider.weeklyAverageScore,
            practiceMinutes: WidgetDataProvider.weeklyPracticeMinutes,
            readiness: WidgetDataProvider.interviewReadinessScore
        )
    }
}

// MARK: - Widget View

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry

    /// One column per metric. Built as a list so the optional readiness column
    /// can be absent without a conditional `Spacer` shifting the other two.
    private struct Column {
        let label: String
        let value: String
        let tint: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(icon: "chart.line.uptrend.xyaxis", title: "This Week") {
                WidgetChip(text: "\(entry.goalPercent)%")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(entry.sessionCount) of \(entry.goalSessions) sessions")
                    .font(WidgetType.value)
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                WidgetMeter(progress: entry.goalFraction, tint: WidgetPalette.brandBright)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 8) {
                ForEach(columns, id: \.label) { column in
                    WidgetMetric(
                        label: column.label,
                        value: column.value,
                        tint: column.tint,
                        alignment: .leading
                    )
                }
            }
        }
        .widgetURL(URL(string: "speakup://record"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers

    private var columns: [Column] {
        var result: [Column] = [
            Column(
                label: "Avg Score",
                value: entry.averageScore > 0 ? "\(entry.averageScore)" : "—",
                tint: entry.averageScore > 0
                    ? WidgetPalette.score(for: entry.averageScore)
                    : WidgetPalette.textTertiary
            )
        ]

        // `0` means no analyzed history, not a real readiness of zero.
        if entry.readiness > 0 {
            result.append(
                Column(
                    label: "Interview",
                    value: "\(entry.readiness)",
                    tint: WidgetPalette.score(for: entry.readiness)
                )
            )
        }

        result.append(
            Column(
                label: "Practice",
                value: "\(entry.practiceMinutes) min",
                tint: WidgetPalette.textPrimary
            )
        )

        return result
    }

    private var accessibilityLabel: String {
        "Weekly progress: \(entry.sessionCount) of \(entry.goalSessions) sessions, "
            + (entry.averageScore > 0 ? "average score \(entry.averageScore), " : "")
            + (entry.readiness > 0 ? "interview readiness \(entry.readiness), " : "")
            + "\(entry.practiceMinutes) practice minutes."
    }
}

// MARK: - Widget Configuration

struct WeeklyProgressWidget: Widget {
    let kind = "WeeklyProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Weekly Progress")
        .description("Track your weekly practice sessions and scores.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Medium", as: .systemMedium) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressEntry(date: .now, sessionCount: 3, goalSessions: 5, averageScore: 75, practiceMinutes: 12, readiness: 78)
    WeeklyProgressEntry(date: .now, sessionCount: 0, goalSessions: 5, averageScore: 0, practiceMinutes: 0, readiness: 0)
}
