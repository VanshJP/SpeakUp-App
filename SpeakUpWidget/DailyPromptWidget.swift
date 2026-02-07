import WidgetKit
import SwiftUI

struct DailyPromptEntry: TimelineEntry {
    let date: Date
    let promptText: String
    let promptCategory: String
    let promptId: String
}

struct DailyPromptProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyPromptEntry {
        DailyPromptEntry(date: .now, promptText: "Describe a challenging project you completed.", promptCategory: "Professional Development", promptId: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyPromptEntry) -> Void) {
        let entry = DailyPromptEntry(
            date: .now,
            promptText: WidgetDataProvider.todaysPromptText,
            promptCategory: WidgetDataProvider.todaysPromptCategory,
            promptId: WidgetDataProvider.todaysPromptId
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyPromptEntry>) -> Void) {
        let entry = DailyPromptEntry(
            date: .now,
            promptText: WidgetDataProvider.todaysPromptText,
            promptCategory: WidgetDataProvider.todaysPromptCategory,
            promptId: WidgetDataProvider.todaysPromptId
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct DailyPromptWidgetView: View {
    let entry: DailyPromptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.teal)
                Text("SpeakUp")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
            }

            if !entry.promptCategory.isEmpty {
                Text(entry.promptCategory)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(entry.promptText)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)

            Spacer(minLength: 0)

            Text("Tap to practice")
                .font(.caption2)
                .foregroundStyle(.teal)
        }
        .padding()
        .widgetURL(URL(string: "speakup://record?prompt=\(entry.promptId)"))
    }
}

struct DailyPromptWidget: Widget {
    let kind = "DailyPromptWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyPromptProvider()) { entry in
            DailyPromptWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Prompt")
        .description("See today's speaking prompt.")
        .supportedFamilies([.systemMedium])
    }
}
