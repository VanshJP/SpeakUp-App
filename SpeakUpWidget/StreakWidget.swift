import WidgetKit
import SwiftUI

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, streak: WidgetDataProvider.currentStreak))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: .now, streak: WidgetDataProvider.currentStreak)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct StreakWidgetView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .shadow(color: .orange.opacity(0.2), radius: 6)
                
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 8)
            }

            VStack(spacing: 0) {
                Text("\(entry.streak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("day streak")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .widgetURL(URL(string: "speakup://record"))
    }
}

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color(red: 0.051, green: 0.071, blue: 0.165)
                        LinearGradient(
                            colors: [.orange.opacity(0.2), .clear],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    }
                }
        }
        .configurationDisplayName("Streak")
        .description("Your current practice streak.")
        .supportedFamilies([.systemSmall])
    }
}
