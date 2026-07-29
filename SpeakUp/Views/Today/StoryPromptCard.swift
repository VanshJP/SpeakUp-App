import SwiftUI

struct StoryPromptCard: View {
    let story: Story
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        GlassCard(padding: 20, elevated: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Story")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                    .foregroundStyle(AppColors.primary)

                    Spacer()

                    if story.practiceCount > 0 {
                        Text("\(story.practiceCount) practice\(story.practiceCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(story.title.isEmpty ? "Untitled Story" : story.title)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !story.contentPreview.isEmpty {
                    Text(story.contentPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    DurationPill(selectedDuration: $selectedDuration)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)

                        Text("Tap to practice")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Whole card starts practice; the duration Menu still wins its own taps.
            .contentShape(Rectangle())
            .onTapGesture { Haptics.medium(); onTap() }
        }
        .ambientLoop(AppMotion.ambient(duration: 1.2)) { isPulsing = true }
    }
}
