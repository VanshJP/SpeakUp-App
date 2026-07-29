import SwiftUI

struct DailyChallengeCard: View {
    let challenge: DailyChallenge

    /// One row, on the same glass every other block sits on.
    ///
    /// The previous version put the accent colour on five things at once — a
    /// left rail, the icon, the icon's well, an uppercase eyebrow, and the
    /// border — which is the house style for a generated alert component, not
    /// for this app. It also broke the project's own rule that colour lives in
    /// the data: a challenge's only meaningful state is done or not done.
    ///
    /// So: no tinted fill, no rail, no coloured label. A checkbox carries the
    /// state and is the single coloured element; the title carries the content;
    /// the challenge's own glyph sits quietly on the right as identity. It
    /// reads as a task for today because that is what it is.
    var body: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            row
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily challenge: \(challenge.title), \(challenge.isCompleted ? "completed" : "active")")
    }

    private var row: some View {
        HStack(spacing: 11) {
            stateMark

            VStack(alignment: .leading, spacing: 1) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(challenge.isCompleted ? Color.secondary : Color.white)
                    .lineLimit(1)

                Text("Today's challenge")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: challenge.icon)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var stateMark: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    challenge.isCompleted ? AppColors.success : Color.white.opacity(0.25),
                    lineWidth: 1.5
                )
                .frame(width: 19, height: 19)

            if challenge.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.success)
            }
        }
    }
}
