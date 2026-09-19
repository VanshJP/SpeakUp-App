import WidgetKit
import SwiftUI

struct DailyPromptEntry: TimelineEntry {
    let date: Date
    let promptText: String
    let promptCategory: String
    let promptId: String

    var hasPrompt: Bool {
        !promptText.isEmpty
    }

    /// A fresh prompt is worth surfacing in a Smart Stack; an empty one is not.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: hasPrompt ? 40 : 0)
    }
}

struct DailyPromptProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyPromptEntry {
        DailyPromptEntry(
            date: .now,
            promptText: "Describe a challenging project you completed.",
            promptCategory: "Professional Development",
            promptId: ""
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyPromptEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyPromptEntry>) -> Void) {
        let entry = currentEntry()
        // Payload only changes at daily rollover; intraday changes arrive via
        // fingerprint-gated app reloads.
        let calendar = Calendar.current
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date))
        completion(Timeline(entries: [entry], policy: .after(nextMidnight ?? entry.date)))
    }

    // MARK: - Private

    private func currentEntry() -> DailyPromptEntry {
        DailyPromptEntry(
            date: .now,
            promptText: WidgetDataProvider.todaysPromptText,
            promptCategory: WidgetDataProvider.todaysPromptCategory,
            promptId: WidgetDataProvider.todaysPromptId
        )
    }
}

// MARK: - Widget View

struct DailyPromptWidgetView: View {
    let entry: DailyPromptEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangularLayout
            default:
                systemLayout
            }
        }
        .widgetURL(recordURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - System

    private var systemLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(icon: "quote.opening", title: "Today's Prompt") {
                if !entry.promptCategory.isEmpty {
                    WidgetChip(text: entry.promptCategory)
                }
            }

            Text(displayText)
                .font(WidgetType.body)
                .foregroundStyle(entry.hasPrompt ? WidgetPalette.textPrimary : WidgetPalette.textSecondary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Spacer(minLength: 0)

                Text(entry.hasPrompt ? "Tap to practice" : "Open Big Talk")
                    .font(WidgetType.label.weight(.semibold))

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(WidgetPalette.brandBright)
            .widgetAccentable()
        }
    }

    // MARK: - Lock Screen

    private var rectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .bold))
                Text("Today's Prompt")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
            }
            .widgetAccentable()

            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var displayText: String {
        entry.hasPrompt ? entry.promptText : "Your first prompt is waiting inside."
    }

    private var recordURL: URL? {
        var components = URLComponents()
        components.scheme = "speakup"
        components.host = "record"
        if !entry.promptId.isEmpty {
            components.queryItems = [URLQueryItem(name: "prompt", value: entry.promptId)]
        }
        return components.url
    }

    private var accessibilityLabel: String {
        entry.hasPrompt
            ? "Today's prompt: \(entry.promptText). Tap to practice."
            : "No prompt yet. Open Big Talk to get today's prompt."
    }
}

// MARK: - Widget Configuration

struct DailyPromptWidget: Widget {
    let kind = "DailyPromptWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyPromptProvider()) { entry in
            DailyPromptWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Daily Prompt")
        .description("See today's speaking prompt.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

#Preview("Medium", as: .systemMedium) {
    DailyPromptWidget()
} timeline: {
    DailyPromptEntry(
        date: .now,
        promptText: "Describe a time you changed someone's mind.",
        promptCategory: "Persuasion",
        promptId: "preview"
    )
    DailyPromptEntry(date: .now, promptText: "", promptCategory: "", promptId: "")
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DailyPromptWidget()
} timeline: {
    DailyPromptEntry(
        date: .now,
        promptText: "Describe a time you changed someone's mind.",
        promptCategory: "Persuasion",
        promptId: "preview"
    )
}
