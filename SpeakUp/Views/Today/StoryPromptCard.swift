import SwiftUI

struct StoryPromptCard: View {
    let story: Story
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        GlassCard(tint: .purple.opacity(0.1), accentBorder: .purple.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Story", systemImage: "book.pages")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)

                    Spacer()

                    if story.practiceCount > 0 {
                        Text("\(story.practiceCount) practice\(story.practiceCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(story.title.isEmpty ? "Untitled Story" : story.title)
                    .font(.title3.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.medium(); onTap() }

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
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)

                        Text("Tap to practice")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.medium(); onTap() }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
