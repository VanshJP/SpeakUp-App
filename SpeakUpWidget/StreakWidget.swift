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
        completion(StreakEntry(
            date: .now,
            streak: WidgetDataProvider.currentStreak,
            hasPracticedToday: WidgetDataProvider.hasPracticedToday
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(
            date: .now,
            streak: WidgetDataProvider.currentStreak,
            hasPracticedToday: WidgetDataProvider.hasPracticedToday
        )
        // Refresh hourly when streak is at risk
        let hours = (entry.streak > 0 && !entry.hasPracticedToday) ? 1 : 2
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: hours, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget View

struct StreakWidgetView: View {
    let entry: StreakEntry

    private var isAtRisk: Bool {
        entry.streak > 0 && !entry.hasPracticedToday
    }

    private var urgency: Urgency {
        guard isAtRisk else { return .none }
        let hour = Calendar.current.component(.hour, from: entry.date)
        if hour >= 20 { return .critical }
        if hour >= 17 { return .high }
        if hour >= 12 { return .moderate }
        return .low
    }

    private var accentColor: Color {
        switch urgency {
        case .critical: return .red
        case .high:     return Color(red: 1.0, green: 0.4, blue: 0.2)
        default:        return .orange
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isAtRisk ? 0.25 : 0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(isAtRisk ? .red : accentColor)
                }

                Text("\(entry.streak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if isAtRisk {
                    Text(urgencyMessage)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                } else {
                    Text(entry.streak == 0 ? "Start a streak!" : "day streak")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
        .widgetURL(URL(string: "speakup://record"))
    }

    private var urgencyMessage: String {
        switch urgency {
        case .low:      return "Don't lose it!"
        case .moderate: return "Lock in today!"
        case .high:     return "Streak fading!"
        case .critical: return "Last chance!"
        case .none:     return "day streak"
        }
    }
}

private enum Urgency {
    case none, low, moderate, high, critical
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

//
//#Preview("Safe", as: .systemSmall) {
//    StreakWidget()
//} timeline: {
//    StreakEntry(date: .now, streak: 7, hasPracticedToday: true)
//}

#Preview("At Risk", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false)
}

