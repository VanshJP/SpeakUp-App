import SwiftUI

struct StoryPromptCard: View {
    let story: Story
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    // Same header grammar as the prompt card: facts ride the
                    // eyebrow, controls sit on the right in one family.
                    HStack(spacing: 5) {
                        Image(systemName: "book.pages")
                        Text("Story")
                        if story.practiceCount > 0 {
                            Text("·")
                            Text("\(story.practiceCount) practice\(story.practiceCount == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .eyebrowStyle(AppColors.primary)
                    .layoutPriority(-1)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        DurationPill(selectedDuration: $selectedDuration)

                        SmallIconButton(icon: "arrow.clockwise", label: "Different story", action: onRefresh)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Text(story.title.isEmpty ? "Untitled story" : story.title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !story.contentPreview.isEmpty {
                    Text(story.contentPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                words

                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
