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
                let color: Color = entry.isCompleted ? .green : .teal
                
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: entry.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)

                if entry.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white).padding(2))
                        .offset(x: 18, y: -18)
                }
            }

            VStack(spacing: 2) {
                Text(entry.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(entry.description)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .widgetURL(URL(string: "speakup://record"))
    }
}

struct DailyChallengeWidget: Widget {
    let kind = "DailyChallengeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyChallengeProvider()) { entry in
            DailyChallengeWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.051, green: 0.071, blue: 0.165), for: .widget)
        }
        .configurationDisplayName("Daily Challenge")
        .description("See today's speaking challenge.")
        .supportedFamilies([.systemSmall])
    }
}
