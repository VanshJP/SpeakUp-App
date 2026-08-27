import SwiftUI

/// Today's story, in the same slot and the same skeleton as
/// `InteractivePromptCard`: header, text, words row, Start footer.
///
/// A reading surface, not a control. The whole-card tap it used to carry needed
/// a pulsing "Tap to practice" caption to be discoverable at all, which is the
/// tell that it was the wrong affordance — the Start capsule in the footer is
/// the action now, and reroll moved into the header with the length.
struct StoryPromptCard: View {
    let story: Story
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Story")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                    .foregroundStyle(AppColors.primary)

                    Spacer(minLength: 4)

                    if story.practiceCount > 0 {
                        Text("\(story.practiceCount) practice\(story.practiceCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    DurationPill(selectedDuration: $selectedDuration)

                    // Negative gutter trims the 44pt tap frame back to the
                    // header's height and edge; the target itself stays 44pt.
                    SmallIconButton(icon: "arrow.clockwise", label: "Different story", action: onRefresh)
                        .padding(.trailing, -6)
                        .padding(.vertical, -6)
                }

                Text(story.title.isEmpty ? "Untitled Story" : story.title)
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

                // Same footer as the prompt card — one hero action on the page,
                // owned by whichever brief renders.
                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
