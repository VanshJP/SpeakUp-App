import WidgetKit
import SwiftUI

struct QuickPracticeEntry: TimelineEntry {
    let date: Date
    let lastScore: Int
}

struct QuickPracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickPracticeEntry {
        QuickPracticeEntry(date: .now, lastScore: 82)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickPracticeEntry) -> Void) {
        completion(QuickPracticeEntry(date: .now, lastScore: WidgetDataProvider.lastScore))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickPracticeEntry>) -> Void) {
        let entry = QuickPracticeEntry(date: .now, lastScore: WidgetDataProvider.lastScore)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct QuickPracticeWidgetView: View {
    let entry: QuickPracticeEntry

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(.teal.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .shadow(color: .teal.opacity(0.2), radius: 8)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.teal)
                        .shadow(color: .teal.opacity(0.5), radius: 6)
                }

                if entry.lastScore > 0 {
                    Text("\(entry.lastScore)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(scoreColor(for: entry.lastScore), in: Capsule())
                        .shadow(color: scoreColor(for: entry.lastScore).opacity(0.4), radius: 4)
                        .offset(x: 10, y: -4)
                }
            }

            Text("Practice Now")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .widgetURL(URL(string: "speakup://record"))
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

struct QuickPracticeWidget: Widget {
    let kind = "QuickPracticeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickPracticeProvider()) { entry in
            QuickPracticeWidgetView(entry: entry)
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
        .configurationDisplayName("Quick Practice")
        .description("Jump straight into a practice session.")
        .supportedFamilies([.systemSmall])
    }
}
