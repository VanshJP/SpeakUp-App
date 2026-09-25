import SwiftUI
import SwiftData

/// Today's topic: the brief and its action in one object. Header, prompt text,
/// words row, then the Start capsule as the footer - the button used to float
/// between this card and the tools strip as a third island.
struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var redaction: RedactionReasons {
        prompt == nil ? .placeholder : []
    }

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    // Category · difficulty, the grammar of a Library prompt
                    // row. Difficulty used to be a filled red "Hard" capsule
                    // beside the length pill and the reroll - three chip
                    // styles in one row, and error red on something that is
                    // not an error.
                    HStack(spacing: 5) {
                        Image(systemName: categoryIcon)
                        Text(categoryName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if let difficulty = prompt?.difficulty {
                            Text("·")
                            Text(difficulty.displayName)
                                .foregroundStyle(difficulty.color)
                        }
                    }
                    .eyebrowStyle(categoryColor)
                    .layoutPriority(-1)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        DurationPill(selectedDuration: $selectedDuration)

                        SmallIconButton(icon: "arrow.clockwise", label: "Different prompt", action: onRefresh)
                            .symbolEffect(.rotate, value: reduceMotion ? nil : prompt?.id)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .redacted(reason: redaction)

                // A new prompt blurs in over the old one instead of the text
                // snapping. ZStack so both share one slot mid-transition.
                ZStack(alignment: .topLeading) {
                    Text(prompt?.text ?? "Loading today's prompt...")
                        .font(.system(size: 18, weight: .semibold))
                        .lineSpacing(2)
                        .foregroundStyle(prompt == nil ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .redacted(reason: redaction)
                        .id(prompt?.id)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace(.downUp)))
                }

                words
                    .redacted(reason: redaction)

                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var categoryName: String {
        guard let category = prompt?.category else { return "Loading..." }
        return PromptCategory(rawValue: category)?.shortName ?? category
    }

    private var categoryColor: Color {
        guard let category = prompt?.category else { return AppColors.accent }
        return PromptCategory(rawValue: category)?.color ?? AppColors.accent
    }

    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}
