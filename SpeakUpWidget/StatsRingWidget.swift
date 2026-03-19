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
        let entry = StatsRingEntry(
            date: .now,
            streak: WidgetDataProvider.currentStreak,
            sessions: WidgetDataProvider.weeklySessionCount,
            sessionsGoal: WidgetDataProvider.weeklyGoalSessions,
            score: WidgetDataProvider.weeklyAverageScore,
            improvement: WidgetDataProvider.weeklyImprovementRate
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsRingEntry>) -> Void) {
        let entry = StatsRingEntry(
            date: .now,
            streak: WidgetDataProvider.currentStreak,
            sessions: WidgetDataProvider.weeklySessionCount,
            sessionsGoal: WidgetDataProvider.weeklyGoalSessions,
            score: WidgetDataProvider.weeklyAverageScore,
            improvement: WidgetDataProvider.weeklyImprovementRate
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget View

struct StatsRingWidgetView: View {
    let entry: StatsRingEntry
    @Environment(\.widgetFamily) var family

    private let streakTarget = 7

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        default:
            mediumLayout
        }
    }

    // MARK: - Small Layout

    private var smallLayout: some View {
        VStack(spacing: 6) {
            ZStack {
                // Outer ring - Streak
                WidgetRing(
                    progress: Double(min(entry.streak, streakTarget)) / Double(streakTarget),
                    color: .orange,
                    lineWidth: 7
                )
                .frame(width: 80, height: 80)

                // Middle ring - Sessions
                WidgetRing(
                    progress: Double(min(entry.sessions, entry.sessionsGoal)) / Double(max(entry.sessionsGoal, 1)),
                    color: .teal,
                    lineWidth: 7
                )
                .frame(width: 60, height: 60)

                // Inner ring - Score
                WidgetRing(
                    progress: Double(entry.score) / 100,
                    color: scoreColor,
                    lineWidth: 7
                )
                .frame(width: 40, height: 40)

                // Center score
                Text("\(entry.score)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }
            .frame(height: 90)

            // Compact metrics row
            HStack(spacing: 0) {
                miniMetric(icon: "flame.fill", value: "\(entry.streak)", color: .orange)
                miniMetric(icon: "mic.fill", value: "\(entry.sessions)/\(entry.sessionsGoal)", color: .teal)
                miniMetric(icon: improvementIcon, value: improvementText, color: improvementColor)
            }
        }
        .padding(10)
        .widgetURL(URL(string: "speakup://record"))
    }

    // MARK: - Medium Layout

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            // Rings on the left
            ZStack {
                WidgetRing(
                    progress: Double(min(entry.streak, streakTarget)) / Double(streakTarget),
                    color: .orange,
                    lineWidth: 9
                )
                .frame(width: 100, height: 100)

                WidgetRing(
                    progress: Double(min(entry.sessions, entry.sessionsGoal)) / Double(max(entry.sessionsGoal, 1)),
                    color: .teal,
                    lineWidth: 9
                )
                .frame(width: 76, height: 76)

                WidgetRing(
                    progress: Double(entry.score) / 100,
                    color: scoreColor,
                    lineWidth: 9
                )
                .frame(width: 52, height: 52)

                VStack(spacing: 0) {
                    Text("\(entry.score)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("avg")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Metrics on the right
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                    Text("Your Stats")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                }

                metricRow(icon: "flame.fill", label: "Streak", value: "\(entry.streak) \(entry.streak == 1 ? "day" : "days")", color: .orange)
                metricRow(icon: "mic.fill", label: "Sessions", value: "\(entry.sessions)/\(entry.sessionsGoal)", color: .teal)
                metricRow(icon: "chart.line.uptrend.xyaxis", label: "Score", value: "\(entry.score)", color: scoreColor)
                metricRow(icon: improvementIcon, label: "Progress", value: improvementText, color: improvementColor)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "speakup://record"))
    }

    // MARK: - Helpers

    private func miniMetric(icon: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var scoreColor: Color {
        switch entry.score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    private var improvementColor: Color {
        if entry.improvement > 1 { return .green }
        if entry.improvement < -1 { return .red }
        return .secondary
    }

    private var improvementIcon: String {
        if entry.improvement > 1 { return "arrow.up.right" }
        if entry.improvement < -1 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var improvementText: String {
        if abs(entry.improvement) < 1 { return "0%" }
        let sign = entry.improvement > 0 ? "+" : ""
        return "\(sign)\(entry.improvement)%"
    }
}

// MARK: - Widget Ring

private struct WidgetRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Widget Configuration

struct StatsRingWidget: Widget {
    let kind = "StatsRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsRingProvider()) { entry in
            StatsRingWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.051, green: 0.071, blue: 0.165), for: .widget)
        }
        .configurationDisplayName("Stats Overview")
        .description("See your streak, sessions, score, and progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
