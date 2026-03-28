import WidgetKit
import SwiftUI

struct QuickStoryEntry: TimelineEntry {
    let date: Date
    let storyCount: Int
    let latestTitle: String
}

struct QuickStoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStoryEntry {
        QuickStoryEntry(date: .now, storyCount: 3, latestTitle: "My best presentation story")
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStoryEntry) -> Void) {
        let entry = QuickStoryEntry(
            date: .now,
            storyCount: WidgetDataProvider.storyCount,
            latestTitle: WidgetDataProvider.latestStoryTitle
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStoryEntry>) -> Void) {
        let entry = QuickStoryEntry(
            date: .now,
            storyCount: WidgetDataProvider.storyCount,
            latestTitle: WidgetDataProvider.latestStoryTitle
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct QuickStoryWidgetView: View {
    let entry: QuickStoryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
                Text("Story Bank")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                Spacer()
                Text("\(entry.storyCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !entry.latestTitle.isEmpty {
                Text(entry.latestTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            } else {
                Text("Capture your first story")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quick Capture")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.teal.opacity(0.15), in: Capsule())

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.teal.opacity(0.6))
            }
        }
        .padding()
        .widgetURL(URL(string: "speakup://story/new"))
    }
}

struct QuickStoryWidget: Widget {
    let kind = "QuickStoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStoryProvider()) { entry in
            QuickStoryWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(red: 0.051, green: 0.071, blue: 0.165), for: .widget)
        }
        .configurationDisplayName("Quick Story")
        .description("Quickly capture a story idea with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
