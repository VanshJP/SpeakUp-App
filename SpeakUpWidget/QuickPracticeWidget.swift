import WidgetKit
import SwiftUI

struct QuickPracticeEntry: TimelineEntry {
    let date: Date
    let lastScore: Int

    var hasScore: Bool {
        lastScore > 0
    }
}

struct QuickPracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickPracticeEntry {
        QuickPracticeEntry(date: .now, lastScore: 82)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickPracticeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickPracticeEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func currentEntry() -> QuickPracticeEntry {
        QuickPracticeEntry(date: .now, lastScore: WidgetDataProvider.lastScore)
    }
}

// MARK: - Widget View

struct QuickPracticeWidgetView: View {
    let entry: QuickPracticeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLayout
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
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            WidgetGlyphOrb(systemName: "mic.fill", diameter: 62)

            VStack(spacing: 5) {
                Text("Practice Now")
                    .font(WidgetType.value)
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // The last score sits under the label rather than pinned to the
                // orb: a badge hung off the corner clipped the widget's edge at
                // three digits.
                if entry.hasScore {
                    WidgetChip(
                        text: "Last \(entry.lastScore)",
                        tint: WidgetPalette.score(for: entry.lastScore)
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Lock Screen

    private var circularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .medium))
        }
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        entry.hasScore
            ? "Practice now. Last score \(entry.lastScore)."
            : "Practice now."
    }
}

// MARK: - Widget Configuration

struct QuickPracticeWidget: Widget {
    let kind = "QuickPracticeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickPracticeProvider()) { entry in
            QuickPracticeWidgetView(entry: entry)
                .bigTalkCanvas()
        }
        .configurationDisplayName("Quick Practice")
        .description("Jump straight into a practice session.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

#Preview("Small", as: .systemSmall) {
    QuickPracticeWidget()
} timeline: {
    QuickPracticeEntry(date: .now, lastScore: 82)
    QuickPracticeEntry(date: .now, lastScore: 0)
}

#Preview("Circular", as: .accessoryCircular) {
    QuickPracticeWidget()
} timeline: {
    QuickPracticeEntry(date: .now, lastScore: 82)
}
