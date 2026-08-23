import WidgetKit
import SwiftUI

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let hasPracticedToday: Bool
    let urgency: Urgency
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 5, hasPracticedToday: true, urgency: .none)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let calendar = Calendar.current
        var entries = [entry(at: .now)]

        // Bake the message for each urgency band into its own entry so it
        // flips on time even when the next system refresh lands late.
        if entries[0].urgency != .none {
            entries.append(contentsOf: urgencyBoundaries(after: .now, calendar: calendar)
                .prefix(3)
                .map { entry(at: $0) })
        }

        let tail = entries[entries.count - 1]
        let hours = (entries[0].urgency != .none) ? 1 : 2
        var nextUpdate = calendar.date(byAdding: .hour, value: hours, to: tail.date) ?? tail.date
        if entries[0].urgency != .none {
            // At-risk, the tail band entry can sit ~24h out (tomorrow's last
            // boundary), which would freeze the baked-in streak/hasPracticed
            // state until then. Cap the system refresh at an hour from now;
            // the band entries above still flip their messages on time.
            nextUpdate = min(nextUpdate, calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now)
        }
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func entry(at date: Date) -> StreakEntry {
        StreakEntry(
            date: date,
            streak: WidgetDataProvider.currentStreak,
            hasPracticedToday: WidgetDataProvider.hasPracticedToday,
            urgency: Self.urgency(
                at: date,
                isAtRisk: WidgetDataProvider.currentStreak > 0 && !WidgetDataProvider.hasPracticedToday
            )
        )
    }

    private static func urgency(at date: Date, isAtRisk: Bool) -> Urgency {
        guard isAtRisk else { return .none }
        switch Calendar.current.component(.hour, from: date) {
        case ..<12: return .low
        case ..<17: return .moderate
        case ..<20: return .high
        default: return .critical
        }
    }

    /// Next local 12:00 / 17:00 / 20:00 rollovers after `date`.
    private func urgencyBoundaries(after date: Date, calendar: Calendar) -> [Date] {
        var boundaries: [Date] = []
        for dayOffset in 0...1 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else { continue }
            for hour in [12, 17, 20] {
                guard let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart),
                      boundary > date else { continue }
                boundaries.append(boundary)
            }
        }
        return boundaries.sorted()
    }
}

// MARK: - Widget View

struct StreakWidgetView: View {
    let entry: StreakEntry

    private var isAtRisk: Bool {
        entry.streak > 0 && !entry.hasPracticedToday
    }

    private var urgency: Urgency {
        entry.urgency
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            entry.streak == 0
                ? "No streak yet. Tap to start practicing."
                : "\(entry.streak) day streak.\(isAtRisk ? " At risk, practice today to keep it." : "")"
        )
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

enum Urgency {
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

#Preview("At Risk", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false, urgency: .high)
}

