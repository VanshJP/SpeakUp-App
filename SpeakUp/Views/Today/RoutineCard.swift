import SwiftUI

// MARK: - Step identity

/// Colour and tool identity for a routine step. Kept here rather than on the
/// model because `PracticeToolKind` and `AppColors` are MainActor-isolated and
/// `RoutineStep` has to stay a pure value type (gotchas §7).
extension RoutineStep {
    var tool: PracticeToolKind? {
        switch self {
        case .calm: return .calm
        case .warmUp: return .warmUp
        case .drill: return .drills
        case .readAloud: return .readAloud
        case .session, .review: return nil
        }
    }

    var tint: Color {
        tool?.color ?? AppColors.primary
    }
}

// MARK: - Card

/// Today's routine: the chain, where the user is in it, and one control that
/// starts the link they are on.
///
/// Drawn as a horizontal rail, not a vertical checklist. Three tall rows with
/// a connector down the left cost a third of the home screen to say "three
/// things, you are on the first", and only one of them - the one named on the
/// button - could be tapped at all. Every marker on the rail is a door now, so
/// skipping ahead to the take does not mean scrolling past the routine to find
/// the session module underneath it.
struct RoutineCard: View {
    let steps: [RoutineStep]
    let completed: Set<RoutineStep>
    let onStart: (RoutineStep) -> Void
    let onEdit: () -> Void

    private var current: RoutineStep? {
        steps.first { !completed.contains($0) }
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                header

                chain

                if let current {
                    Text(current.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    GlassButton(
                        title: current.actionTitle,
                        icon: current.icon,
                        style: .secondary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        Haptics.medium()
                        onStart(current)
                    }
                } else {
                    doneFooter
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .motion(AppMotion.settle, value: completed)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Your routine")
                .eyebrowStyle()

            Spacer(minLength: 8)

            Text("\(completed.intersection(steps).count) of \(steps.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Button {
                Haptics.light()
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit routine")
        }
    }

    // MARK: Chain

    private var chain: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                stepCell(step, index: index)
            }
        }
    }

    private func stepCell(_ step: RoutineStep, index: Int) -> some View {
        let isDone = completed.contains(step)
        let isCurrent = step == current
        let leadingFilled = index > 0 && completed.contains(steps[index - 1])

        return Button {
            Haptics.light()
            onStart(step)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Rail halves rather than one line behind the row: a
                    // segment is lit by the step *before* it, so the fill
                    // tracks the chain instead of the marker it sits under.
                    HStack(spacing: 0) {
                        railHalf(filled: leadingFilled)
                            .padding(.trailing, markerRadius + 4)
                            .opacity(index == 0 ? 0 : 1)
                        railHalf(filled: isDone)
                            .padding(.leading, markerRadius + 4)
                            .opacity(index == steps.count - 1 ? 0 : 1)
                    }

                    marker(isDone: isDone, isCurrent: isCurrent, step: step)
                }
                .frame(maxWidth: .infinity)

                Text(step.shortTitle)
                    .font(.system(size: 10, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stepLabel(step, isDone: isDone, isCurrent: isCurrent))
        .accessibilityHint(step.actionTitle)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Half the marker's width. The rail stops short of it on both sides -
    /// the marker's fill is translucent glass, so running the line behind it
    /// would show through and turn the circle into a bullseye.
    private var markerRadius: CGFloat { 16 }

    private func railHalf(filled: Bool) -> some View {
        Capsule()
            .fill(filled ? AppColors.success.opacity(0.55) : AppColors.cardStroke)
            .frame(height: 2)
    }

    private func marker(isDone: Bool, isCurrent: Bool, step: RoutineStep) -> some View {
        let tint = step.tint

        return ZStack {
            Circle()
                .fill(isDone ? AppColors.success.opacity(0.18) : tint.opacity(isCurrent ? 0.22 : 0.10))

            Circle()
                .stroke(
                    isCurrent ? tint : (isDone ? AppColors.success.opacity(0.4) : AppColors.cardStroke),
                    lineWidth: isCurrent ? 1.5 : 1
                )

            Image(systemName: isDone ? "checkmark" : step.icon)
                .font(.system(size: isDone ? 12 : 13, weight: .semibold))
                .foregroundStyle(isDone ? AppColors.success : (isCurrent ? tint : tint.opacity(0.5)))
        }
        .frame(width: markerRadius * 2, height: markerRadius * 2)
        .shadow(color: isCurrent ? tint.opacity(0.3) : .clear, radius: isCurrent ? 6 : 0, y: 1)
    }

    private func stepLabel(_ step: RoutineStep, isDone: Bool, isCurrent: Bool) -> String {
        if isDone { return "\(step.title), done" }
        if isCurrent { return "\(step.title), up next. \(step.detail)" }
        return "\(step.title), later"
    }

    // MARK: Done

    private var doneFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(AppColors.success)
            Text("Routine done for today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Handoff

/// The bar that appears the moment a routine step finishes, naming the next one.
///
/// It lives over the tab surface rather than inside the screen that finished,
/// because the screen that finished is a sheet and it is about to close. Set
/// while the sheet is still up, it is simply already there when the sheet goes.
struct RoutineHandoffBar: View {
    let handoff: PracticeRoutineService.Handoff
    let onTake: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(tint: handoff.next.tint.opacity(0.10), padding: 14, elevated: true) {
            HStack(spacing: 12) {
                OnboardingGlyph(icon: handoff.next.icon, tint: handoff.next.tint, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(handoff.finished.title) done. Next up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(handoff.next.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                GlassButton(
                    title: "Go",
                    icon: "arrow.right",
                    iconPosition: .right,
                    style: .primary,
                    size: .small
                ) {
                    Haptics.medium()
                    onTake()
                }

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

#Preview("Routine card") {
    ZStack {
        AppBackground()
        VStack(spacing: 16) {
            RoutineCard(
                steps: RoutineStep.defaultSteps,
                completed: [.warmUp],
                onStart: { _ in },
                onEdit: {}
            )
            RoutineHandoffBar(
                handoff: .init(finished: .warmUp, next: .session),
                onTake: {},
                onDismiss: {}
            )
        }
        .padding()
    }
}
