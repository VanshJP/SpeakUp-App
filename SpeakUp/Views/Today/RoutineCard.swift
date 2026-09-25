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

    /// The word on the step's button. A score is opened, not started.
    var verb: String {
        self == .review ? "Open" : "Start"
    }
}

// MARK: - Card

/// Today's routine, dealt one card at a time.
///
/// Only the step the user is on is drawn: its name, why it is in the chain,
/// and Start. Finishing it deals the next card, and the ones still to come
/// show as the edges of a stack underneath - the way iOS stacks notifications -
/// so the chain reads as three cards without spending the room to draw three.
/// It was one card holding the whole chain as a timeline of waveform clips
/// with a playhead, which was a lot of machinery on the home screen to say
/// "do the warm-up".
///
/// The take is always one tap away in the prompt card under this, so the
/// stack does not need a door to every step (routine.md invariant 4).
struct RoutineCard: View {
    let steps: [RoutineStep]
    let completed: Set<RoutineStep>
    /// Length of today's take, so the time left counts the step it is all for.
    var takeSeconds: Int = 60
    let onStart: (RoutineStep) -> Void
    let onEdit: () -> Void

    private var current: RoutineStep? {
        RoutineProgress.upNext(in: steps, completed: completed)
    }

    /// What is left in the stack: the card on top and the unfinished ones
    /// after it. Links passed on the way are not in it.
    private var dealt: [RoutineStep] {
        guard let current, let index = steps.firstIndex(of: current) else { return [] }
        return steps[index...].filter { !completed.contains($0) }
    }

    private var minutesLeft: Int {
        dealt.reduce(0) { $0 + $1.estimatedMinutes(takeSeconds: takeSeconds) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(TodayHomeModule.routine.title) {
                headerAccessory
            }

            // `.identity`: the step card and the done card are different glass
            // plates, and a glass plate cross-fading into another renders as a
            // dark slab for a beat (today-library invariant 13c).
            if let current {
                stack(current)
                    .transition(.identity)
            } else {
                doneCard
                    .transition(.identity)
            }
        }
        .motion(AppMotion.settle, value: current)
    }

    // MARK: Header

    private var headerAccessory: some View {
        HStack(spacing: 6) {
            // Nothing once the chain is done - the card under it says so.
            if current != nil {
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Button {
                Haptics.light()
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressStyle())
            // A 44pt target that lays out at the title's height, so this header
            // lines up with "Today's prompt" and "Prep tools" below it.
            .padding(-11)
            .accessibilityLabel("Edit routine")
        }
    }

    private var statusLine: String {
        completed.isDisjoint(with: steps) ? "About \(minutesLeft) min" : "\(minutesLeft) min left"
    }

    // MARK: Stack

    /// The step on top, then the edges of the cards still to come. The face
    /// changes inside one plate, so dealing the next step never swaps glass.
    private func stack(_ step: RoutineStep) -> some View {
        VStack(spacing: -2) {
            Button {
                Haptics.medium()
                onStart(step)
            } label: {
                GlassCard(padding: 16) {
                    ZStack {
                        stepFace(step)
                            .id(step)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 10)),
                                removal: .opacity.combined(with: .offset(y: -10))
                            ))
                    }
                }
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Step \(position(of: step)) of \(steps.count): \(step.title). \(step.detail)")
            .accessibilityHint(step.actionTitle)
            .zIndex(2)

            ForEach(Array(dealt.dropFirst().prefix(2).enumerated()), id: \.element) { depth, _ in
                stackEdge(depth: depth)
                    .zIndex(Double(1 - depth))
            }
        }
    }

    private func stepFace(_ step: RoutineStep) -> some View {
        HStack(spacing: 14) {
            IconChip(icon: step.icon, tint: step.tint, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("Step \(position(of: step)) of \(steps.count)")
                    .eyebrowStyle()

                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Secondary, never white - Start speaking is the only primary on
            // Today (today-library invariant 15).
            GlassButtonLabel(title: step.verb, style: .secondary, size: .small)
        }
    }

    /// A card still to come: the bottom edge of a plate peeking out from under
    /// the one on top. Painted, not glass - it sits against a glass plate, and
    /// glass laid against glass samples the plate instead of the canvas.
    private func stackEdge(depth: Int) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(depth == 0 ? 0.10 : 0.06))
            .frame(height: 40)
            .frame(height: 9, alignment: .bottom)
            .clipped()
            .padding(.horizontal, CGFloat(depth + 1) * 14)
            .accessibilityHidden(true)
    }

    private func position(of step: RoutineStep) -> Int {
        (steps.firstIndex(of: step) ?? 0) + 1
    }

    // MARK: Done

    private var doneCard: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                IconChip(icon: "checkmark", tint: AppColors.success, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Routine done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("That's today. It starts fresh tomorrow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Handoff

/// The bar that appears the moment a routine step finishes, naming the next one.
///
/// It lives on the tab surface rather than inside the screen that finished,
/// because the screen that finished is a sheet and it is about to close. Set
/// while the sheet is still up, it is simply already there when the sheet goes.
/// `ContentView` hosts it in each tab's bottom `safeAreaBar`, above the tab bar.
struct RoutineHandoffBar: View {
    let handoff: PracticeRoutineService.Handoff
    let onTake: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(tint: handoff.next.tint.opacity(0.10), padding: 14, elevated: true) {
            HStack(spacing: 12) {
                IconChip(icon: handoff.next.icon, tint: handoff.next.tint, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    // Not "<step> done": step titles are imperatives, so that
                    // read "Run a drill done" and "Settle nerves done".
                    Text("Done. Next up:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(handoff.next.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                // Same verb and capsule as the routine card's button, so the
                // bar and the card read as the same next step. Secondary:
                // the bar floats over Today, where Start speaking is the one
                // white primary.
                GlassButton(title: handoff.next.verb, style: .secondary, size: .small) {
                    Haptics.medium()
                    onTake()
                }
                .accessibilityHint(handoff.next.actionTitle)

                DismissButton(label: "Not now", action: onDismiss)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

#Preview("Routine card") {
    ZStack {
        AppBackground()
        VStack(spacing: 24) {
            RoutineCard(
                steps: RoutineStep.defaultSteps,
                completed: [],
                onStart: { _ in },
                onEdit: {}
            )
            RoutineCard(
                steps: [.calm, .warmUp, .drill, .session, .review],
                completed: [.calm, .warmUp],
                takeSeconds: 90,
                onStart: { _ in },
                onEdit: {}
            )
            RoutineCard(
                steps: RoutineStep.defaultSteps,
                completed: Set(RoutineStep.defaultSteps),
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
