import WidgetKit
import SwiftUI

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let sessionCount: Int
    let goalSessions: Int
    let averageScore: Int
    let practiceMinutes: Int
}

struct WeeklyProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyProgressEntry {
        WeeklyProgressEntry(date: .now, sessionCount: 3, goalSessions: 5, averageScore: 75, practiceMinutes: 12)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        let entry = WeeklyProgressEntry(
            date: .now,
            sessionCount: WidgetDataProvider.weeklySessionCount,
            goalSessions: WidgetDataProvider.weeklyGoalSessions,
            averageScore: WidgetDataProvider.weeklyAverageScore,
            practiceMinutes: WidgetDataProvider.weeklyPracticeMinutes
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let entry = WeeklyProgressEntry(
            date: .now,
            sessionCount: WidgetDataProvider.weeklySessionCount,
            goalSessions: WidgetDataProvider.weeklyGoalSessions,
            averageScore: WidgetDataProvider.weeklyAverageScore,
            practiceMinutes: WidgetDataProvider.weeklyPracticeMinutes
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.teal)
                Text("Weekly Progress")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                Spacer()
            }

            // Sessions progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(entry.sessionCount) / \(entry.goalSessions) sessions")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(Double(entry.sessionCount) / Double(max(entry.goalSessions, 1)) * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.teal)
                }
                
                ProgressView(value: Double(entry.sessionCount), total: Double(max(entry.goalSessions, 1)))
                    .tint(.teal)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
            }

            HStack(spacing: 16) {
                // Average score
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Score")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(entry.averageScore)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(scoreColor(for: entry.averageScore))
                }

                Spacer()

                // Practice minutes
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Practice")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(entry.practiceMinutes) min")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .widgetURL(URL(string: "speakup://record"))
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

struct WeeklyProgressWidget: Widget {
    let kind = "WeeklyProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.051, green: 0.071, blue: 0.165), for: .widget)
        }
        .configurationDisplayName("Weekly Progress")
        .description("Track your weekly practice sessions and scores.")
        .supportedFamilies([.systemMedium])
    }
}
