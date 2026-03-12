import WidgetKit
import SwiftUI

struct DailyChallengeEntry: TimelineEntry {
    let date: Date
    let title: String
    let description: String
    let icon: String
    let isCompleted: Bool
}

struct DailyChallengeProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyChallengeEntry {
        DailyChallengeEntry(date: .now, title: "Zero Fillers", description: "Complete a session with no filler words", icon: "sparkles", isCompleted: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyChallengeEntry) -> Void) {
        let entry = DailyChallengeEntry(
            date: .now,
            title: WidgetDataProvider.dailyChallengeTitle,
            description: WidgetDataProvider.dailyChallengeDescription,
            icon: WidgetDataProvider.dailyChallengeIcon,
            isCompleted: WidgetDataProvider.dailyChallengeCompleted
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyChallengeEntry>) -> Void) {
        let entry = DailyChallengeEntry(
            date: .now,
            title: WidgetDataProvider.dailyChallengeTitle,
            description: WidgetDataProvider.dailyChallengeDescription,
            icon: WidgetDataProvider.dailyChallengeIcon,
            isCompleted: WidgetDataProvider.dailyChallengeCompleted
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct DailyChallengeWidgetView: View {
    let entry: DailyChallengeEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: entry.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(entry.isCompleted ? .green : .teal)

                if entry.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white).padding(2))
                        .offset(x: 14, y: -12)
                }
            }

            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(entry.description)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "speakup://record"))
    }
}

struct DailyChallengeWidget: Widget {
    let kind = "DailyChallengeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyChallengeProvider()) { entry in
            DailyChallengeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Challenge")
        .description("See today's speaking challenge.")
        .supportedFamilies([.systemSmall])
    }
}
