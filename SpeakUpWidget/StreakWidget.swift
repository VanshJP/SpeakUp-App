import WidgetKit
import SwiftUI

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let hasPracticedToday: Bool

    /// Today's session is still open - an invitation, never a warning.
    /// See docs/features/widgets.md invariant 8.
    var isOpenToday: Bool {
        streak > 0 && !hasPracticedToday
    }

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: isOpenToday ? 60 : 20)
    }
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 5, hasPracticedToday: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLayout
            case .accessoryRectangular:
                rectangularLayout
            case .accessoryInline:
                Label(inlineText, systemImage: "flame.fill")
            default:
                smallLayout
            }
        }
        .widgetURL(URL(string: "speakup://record"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Home Screen

    private var smallLayout: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            WidgetGlyphOrb(systemName: "flame.fill", tint: WidgetPalette.ember, diameter: 52)

            VStack(spacing: 0) {
                Text("\(entry.streak)")
                    .font(WidgetType.numeralLarge)
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())

                Text("day streak")
                    .font(WidgetType.caption)
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)
            }

            Spacer(minLength: 0)

            Text(statusLine)
                .font(WidgetType.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.ember)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetAccentable()
        }
    }

    // MARK: - Lock Screen

    private var circularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: -1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("\(entry.streak)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var rectangularLayout: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.streak == 0 ? "No streak yet" : "\(entry.streak) day streak")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy
    //
    // Invitational only: no countdown, no "last chance", no red panic state.

    private var statusLine: String {
        if entry.streak == 0 { return "Tap to practice" }
        return entry.isOpenToday ? "Still open today" : "Logged today"
    }

    private var inlineText: String {
        entry.streak == 0 ? "Tap to practice" : "\(entry.streak) day streak"
    }

    private var accessibilityLabel: String {
        if entry.streak == 0 { return "No streak yet. Tap to practice." }
        return "\(entry.streak) day streak.\(entry.isOpenToday ? " Practice when you're ready." : "")"
    }
}

// MARK: - Widget Configuration

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Streak")
        .description("Your current practice streak.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview("Small", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false)
    StreakEntry(date: .now, streak: 128, hasPracticedToday: true)
    StreakEntry(date: .now, streak: 0, hasPracticedToday: false)
}

#Preview("Circular", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, hasPracticedToday: false)
}
