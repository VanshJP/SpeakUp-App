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
/// Rendered as a labelled ladder rather than a checklist of equals. Everything
/// before the current step is a tick, the current step carries the only action
/// on the card, and everything after is a preview — so the card answers "what
/// now" in one glance instead of offering five choices again.
struct RoutineCard: View {
    let steps: [RoutineStep]
    let completed: Set<RoutineStep>
    let onStart: (RoutineStep) -> Void
    let onEdit: () -> Void

    private var current: RoutineStep? {
        steps.first { !completed.contains($0) }
    }

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                        row(step, isLast: index == steps.count - 1)
                    }
                }

                if let current {
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

    // MARK: Row

    private func row(_ step: RoutineStep, isLast: Bool) -> some View {
        let isDone = completed.contains(step)
        let isCurrent = step == current

        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker(isDone: isDone, isCurrent: isCurrent, tint: step.tint)
                if !isLast {
                    // The rail is what makes this read as a chain rather than a
                    // list. It stops at the last marker so the card does not
                    // trail a line into nothing.
                    Rectangle()
                        .fill(AppColors.cardStroke)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                    .strikethrough(isDone, color: .secondary)

                if isCurrent {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stepLabel(step, isDone: isDone, isCurrent: isCurrent))
    }

    private func marker(isDone: Bool, isCurrent: Bool, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(isDone ? AppColors.success.opacity(0.18) : tint.opacity(isCurrent ? 0.18 : 0.08))
                .frame(width: 22, height: 22)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.success)
            } else {
                Circle()
                    .fill(isCurrent ? tint : tint.opacity(0.35))
                    .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 8 : 6)
            }
        }
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
