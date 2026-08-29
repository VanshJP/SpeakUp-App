import WidgetKit
import SwiftUI

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let hasPracticedToday: Bool
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 5, hasPracticedToday: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date.now
        let twoHours = calendar.date(byAdding: .hour, value: 2, to: now) ?? now
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? twoHours
        let nextUpdate = min(twoHours, nextMidnight)
        completion(Timeline(entries: [entry(at: now)], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func entry(at date: Date) -> StreakEntry {
        StreakEntry(
            date: date,
            streak: WidgetDataProvider.currentStreak,
            hasPracticedToday: WidgetDataProvider.hasPracticedToday
        )
    }
}

// MARK: - Widget View

struct StreakWidgetView: View {
    let entry: StreakEntry

    private var isOpenToday: Bool {
        entry.streak > 0 && !entry.hasPracticedToday
    }

    private var accentColor: Color {
        Color(red: 0.961, green: 0.663, blue: 0.235)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isOpenToday ? 0.25 : 0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }

                Text("\(entry.streak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if isOpenToday {
                    Text("Still open today")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                } else {
                    Text(entry.streak == 0 ? "Tap to practice" : "day streak")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.8))
                }
            }
        }
        .widgetURL(URL(string: "speakup://record"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            entry.streak == 0
                ? "No streak yet. Tap to practice."
                : "\(entry.streak) day streak.\(isOpenToday ? " Practice when you're ready." : "")"
        )
    }
}

// MARK: - Widget Configuration

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.051, green: 0.071, blue: 0.165), for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your current practice streak.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Open Today", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false)
}

