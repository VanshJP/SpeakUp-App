import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct EventCountdownEntry: TimelineEntry {
    let date: Date
    let eventTitle: String
    let daysRemaining: Int
    let readinessScore: Int
    let hasEvent: Bool
}

// MARK: - Timeline Provider

struct EventCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> EventCountdownEntry {
        EventCountdownEntry(date: Date(), eventTitle: "Team Presentation", daysRemaining: 14, readinessScore: 45, hasEvent: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (EventCountdownEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EventCountdownEntry>) -> Void) {
        let entry = createEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> EventCountdownEntry {
        let provider = WidgetDataProvider.self
        let title = provider.eventTitle
        let days = provider.eventDaysRemaining
        let score = provider.eventReadinessScore

        return EventCountdownEntry(
            date: Date(),
            eventTitle: title,
            daysRemaining: days,
            readinessScore: score,
            hasEvent: !title.isEmpty && title != "No event"
        )
    }
}

// MARK: - Widget View

struct EventCountdownWidgetView: View {
    let entry: EventCountdownEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.hasEvent {
            eventContent
        } else {
            noEventContent
        }
    }

    private var eventContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.teal)
                    .shadow(color: .teal.opacity(0.5), radius: 4)
                Spacer()
                Text("\(entry.readinessScore)%")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(scoreColor)
                    .background(scoreColor.opacity(0.15), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(scoreColor.opacity(0.2), lineWidth: 0.5)
                    }
            }

            Text(entry.eventTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .foregroundStyle(.white)

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(entry.daysRemaining)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.3), radius: 4)
                Text(entry.daysRemaining == 1 ? "DAY" : "DAYS")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.teal)
            }
        }
        .padding()
    }

    private var noEventContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No upcoming events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scoreColor: Color {
        if entry.readinessScore >= 80 { return .green }
        if entry.readinessScore >= 60 { return .yellow }
        if entry.readinessScore >= 40 { return .orange }
        return .red
    }
}

// MARK: - Widget

struct EventCountdownWidget: Widget {
    let kind: String = "EventCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EventCountdownProvider()) { entry in
            EventCountdownWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color(red: 0.051, green: 0.071, blue: 0.165)
                        LinearGradient(
                            colors: [.teal.opacity(0.2), .clear],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    }
                }
        }
        .configurationDisplayName("Event Countdown")
        .description("See days until your next speaking event and your readiness score.")
        .supportedFamilies([.systemSmall])
    }
}
