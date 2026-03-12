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
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
                    .shadow(color: .teal.opacity(0.5), radius: 4)
                Text("SpeakUp")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                Spacer()
            }

            if !entry.promptCategory.isEmpty {
                Text(entry.promptCategory)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.teal)
                    .background(.teal.opacity(0.15), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.teal.opacity(0.2), lineWidth: 0.5)
                    }
            }

            Text(entry.promptText)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text("Tap to practice")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.teal)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.teal)
            }
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
        .configurationDisplayName("Daily Prompt")
        .description("See today's speaking prompt.")
        .supportedFamilies([.systemMedium])
    }
}
