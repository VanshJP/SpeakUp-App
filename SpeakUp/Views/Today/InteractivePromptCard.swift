import SwiftUI
import SwiftData

/// Today's topic: the brief and its action in one object. Header, prompt text,
/// words row, then the Start capsule as the footer — the button used to float
/// between this card and the tools strip as a third island.
struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    private var redaction: RedactionReasons {
        prompt == nil ? .placeholder : []
    }

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(prompt?.category ?? "Loading...")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(categoryColor)

                    Spacer(minLength: 4)

                    if let difficulty = prompt?.difficulty {
                        StatusPill.difficulty(difficulty)
                    }

                    DurationPill(selectedDuration: $selectedDuration)

                    SmallIconButton(icon: "arrow.clockwise", label: "Different prompt", action: onRefresh)
                        .padding(.trailing, -6)
                        .padding(.vertical, -6)
                }
                .redacted(reason: redaction)

                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.system(size: 18, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: redaction)

                words
                    .redacted(reason: redaction)

                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
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
