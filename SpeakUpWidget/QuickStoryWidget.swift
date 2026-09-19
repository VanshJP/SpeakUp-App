import WidgetKit
import SwiftUI

struct QuickStoryEntry: TimelineEntry {
    let date: Date
    let storyCount: Int
    let latestTitle: String

    var hasStories: Bool {
        !latestTitle.isEmpty || storyCount > 0
    }
}

struct QuickStoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStoryEntry {
        QuickStoryEntry(date: .now, storyCount: 3, latestTitle: "My best presentation story")
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStoryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStoryEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func currentEntry() -> QuickStoryEntry {
        QuickStoryEntry(
            date: .now,
            storyCount: WidgetDataProvider.storyCount,
            latestTitle: WidgetDataProvider.latestStoryTitle
        )
    }
}

// MARK: - Widget View

struct QuickStoryWidgetView: View {
    let entry: QuickStoryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .widgetURL(URL(string: "speakup://story/new"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Small
    //
    // Small has no room for a title without truncating it to nonsense, so it
    // carries the count and the action instead of a two-line stub.

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "book.pages.fill", title: "Story Bank")

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.storyCount)")
                    .font(WidgetType.numeralLarge)
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(entry.storyCount == 1 ? "story saved" : "stories saved")
                    .font(WidgetType.caption)
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            WidgetChip(text: "Quick Capture", icon: "mic.badge.plus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(icon: "book.pages.fill", title: "Story Bank") {
                Text(entry.storyCount == 1 ? "1 story" : "\(entry.storyCount) stories")
                    .font(WidgetType.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.textTertiary)
            }

            if entry.hasStories {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest")
                        .font(WidgetType.caption)
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .foregroundStyle(WidgetPalette.textTertiary)

                    Text(entry.latestTitle)
                        .font(WidgetType.body)
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Capture your first story")
                    .font(WidgetType.body)
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                WidgetChip(text: "Quick Capture", icon: "mic.badge.plus")

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.brandBright.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        guard entry.hasStories else {
            return "Story bank is empty. Tap for quick capture."
        }
        let stories = entry.storyCount == 1 ? "1 story" : "\(entry.storyCount) stories"
        return "Story bank, \(stories). Tap for quick capture."
    }
}

// MARK: - Widget Configuration

struct QuickStoryWidget: Widget {
    let kind = "QuickStoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStoryProvider()) { entry in
            QuickStoryWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Quick Story")
        .description("Quickly capture a story idea with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Small", as: .systemSmall) {
    QuickStoryWidget()
} timeline: {
    QuickStoryEntry(date: .now, storyCount: 12, latestTitle: "My best presentation story")
    QuickStoryEntry(date: .now, storyCount: 0, latestTitle: "")
}

#Preview("Medium", as: .systemMedium) {
    QuickStoryWidget()
} timeline: {
    QuickStoryEntry(date: .now, storyCount: 12, latestTitle: "The quarter we shipped two weeks early")
    QuickStoryEntry(date: .now, storyCount: 0, latestTitle: "")
}
