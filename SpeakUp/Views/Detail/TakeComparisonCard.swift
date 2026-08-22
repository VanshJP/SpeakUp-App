import SwiftUI

/// This take against the last time the user answered the same thing.
///
/// A new prompt every session is variety, not practice. What actually moves a
/// speaker is the same sixty seconds twice with feedback in between — and the
/// second attempt only teaches anything if the difference is visible. Without
/// this the app records the rep and then throws away the only comparison that
/// was ever going to show whether the coaching worked.
struct TakeComparisonCard: View {
    let takeNumber: Int
    let previous: Int
    let current: Int
    let previousDate: Date
    /// The dimension the coach is on, so the delta that matters most is named
    /// rather than left for the user to find.
    let focus: CoachDimension?
    let focusPrevious: Int?
    let focusCurrent: Int?

    private var delta: Int { current - previous }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Take \(takeNumber) · same prompt")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Spacer()

                    Text(previousDate, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(previous)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)

                    Text("\(current)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: current))

                    Spacer()

                    DeltaBadge(delta: delta)
                }

                Text(verdict)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let focus, let focusPrevious, let focusCurrent {
                    HStack(spacing: 6) {
                        Image(systemName: focus.icon)
                            .font(.caption2)
                            .foregroundStyle(AppColors.tint(for: focus))

                        Text("\(focus.title): \(focusPrevious) → \(focusCurrent)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)

                        DeltaBadge(delta: focusCurrent - focusPrevious, compact: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Take \(takeNumber) of this prompt. Previously \(previous), now \(current). \(verdict)")
    }

    /// Names what the repeat proved. A delta with no reading attached is just
    /// two numbers next to each other.
    private var verdict: String {
        // ±3 on a 0-100 score is inside session noise. Calling that an
        // improvement would teach the user to trust a number that is lying.
        if delta >= 8 {
            return "Clear improvement on the second run at this. Whatever you changed, that was it."
        } else if delta >= 3 {
            return "Moved in the right direction. Run it once more and see if it holds."
        } else if delta <= -8 {
            return "Worse than last time. Second takes often are, you are thinking about the mechanics instead of the point. Run a third."
        } else if delta <= -3 {
            return "Slightly down. One take either way is noise; the third one tells you which."
        }
        return "Effectively the same score. Same result from a different attempt usually means the habit, not the effort, is what needs changing."
    }
}

private struct DeltaBadge: View {
    let delta: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: delta == 0 ? "equal" : (delta > 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: compact ? 8 : 10, weight: .bold))
            Text(delta == 0 ? "0" : "\(delta > 0 ? "+" : "−")\(abs(delta))")
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    private var color: Color {
        if delta >= 3 { return AppColors.success }
        if delta <= -3 { return AppColors.warning }
        return AppColors.categoryNeutralCool
    }
}

#Preview {
    ZStack {
        AppBackground()
        VStack(spacing: 16) {
            TakeComparisonCard(
                takeNumber: 2,
                previous: 68,
                current: 77,
                previousDate: .now.addingTimeInterval(-86_400),
                focus: .fillers,
                focusPrevious: 54,
                focusCurrent: 71
            )
            TakeComparisonCard(
                takeNumber: 3,
                previous: 74,
                current: 73,
                previousDate: .now.addingTimeInterval(-3_600),
                focus: nil,
                focusPrevious: nil,
                focusCurrent: nil
            )
        }
        .padding()
    }
}
