import SwiftUI

/// Turns a finished session into a next action.
///
/// Scores tell the user *how they did*; this tells them *what to do about it*.
/// Picks the weakest subscore and routes to the practice tool that targets it,
/// so the practice loop closes on this screen instead of dead-ending in metrics.
struct NextStep {
    enum Action: Equatable {
        case drill(DrillMode)
        case warmUp
        case readAloud
        case practiceAgain
    }

    let area: String
    /// Stable identifier for the weak area, reported to the outcome funnel.
    /// Separate from `area` so rewording the card copy doesn't fork the data.
    let areaSlug: String
    let score: Int
    let coaching: String
    let actionTitle: String
    let action: Action

    /// A session where nothing is weak enough to drill — offer another rep instead.
    var isStrong: Bool { score >= 75 }

    /// The action to take after this session.
    ///
    /// Follows the cross-session plan when there is one. Picking the weakest
    /// subscore of the session in hand sends the user somewhere new every time
    /// — clarity today, pauses tomorrow — which is how people end up with nine
    /// half-trained habits and no fixed ones. The plan's focus only moves once
    /// the dimension is actually trained.
    static func from(_ subscores: SpeechSubscores, plan: CoachPlan? = nil) -> NextStep {
        if let plan, !plan.isGraduating {
            let route = route(for: plan.focus)
            return NextStep(
                area: plan.focus.title,
                areaSlug: plan.focus.analyticsSlug,
                score: plan.focus.subscore(in: subscores) ?? plan.focusAverage,
                // The technique, not `plan.headline`: the focus card on the
                // coaching tab already carries the where-you-are line, and
                // both are on screen once the user scrolls. This card is the
                // action, so it says what to do.
                coaching: plan.focus.technique.how,
                actionTitle: route.title,
                action: route.action
            )
        }

        let candidates = CoachDimension.allCases.compactMap { dimension -> (CoachDimension, Int)? in
            dimension.subscore(in: subscores).map { (dimension, $0) }
        }
        guard let weakest = candidates.min(by: { $0.1 < $1.1 }) else {
            return NextStep(
                area: "Practice",
                areaSlug: "none",
                score: 100,
                coaching: "Bank another rep while it's working.",
                actionTitle: "Practice Again",
                action: .practiceAgain
            )
        }

        guard weakest.1 < 75 else {
            return NextStep(
                area: weakest.0.title,
                areaSlug: weakest.0.analyticsSlug,
                score: weakest.1,
                coaching: plan?.headline ?? "Nothing scored below 75 this session. Bank another rep while it's working.",
                actionTitle: "Practice Again",
                action: .practiceAgain
            )
        }

        let route = route(for: weakest.0)
        return NextStep(
            area: weakest.0.title,
            areaSlug: weakest.0.analyticsSlug,
            score: weakest.1,
            coaching: weakest.0.technique.how,
            actionTitle: route.title,
            action: route.action
        )
    }

    /// The CTA for a dimension, from the one route definition on
    /// `CoachDimension`. This card used to carry its own copy of the mapping.
    private static func route(for dimension: CoachDimension) -> (title: String, action: Action) {
        switch dimension.practiceRoute {
        case .readAloud:
            return ("Read Aloud", .readAloud)
        case .warmUp:
            return ("Vocal Warm-Up", .warmUp)
        case .drill(let raw):
            guard let mode = DrillMode(rawValue: raw) else {
                return ("Practice Again", .practiceAgain)
            }
            return ("\(mode.title) · \(mode.defaultDurationSeconds)s", .drill(mode))
        }
    }
}

// MARK: - Card

struct NextStepCard: View {
    let step: NextStep
    let onAction: (NextStep.Action) -> Void
    let onPracticeAgain: () -> Void

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(step.isStrong ? "Nice session" : "Work on this next")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                if !step.isStrong {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(step.area)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(step.score)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: step.score))
                    }
                }

                Text(step.coaching)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Haptics.medium()
                        // Logged here rather than at each call site so every
                        // surface that shows this card reports the same event.
                        AnalyticsService.shared.log(.nextActionTaken(area: step.areaSlug))
                        onAction(step.action)
                    } label: {
                        Text(step.actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background { Capsule().fill(Color.white.opacity(0.94)) }
                    }
                    .buttonStyle(GlassPressStyle())

                    if step.action != .practiceAgain {
                        Button {
                            Haptics.light()
                            AnalyticsService.shared.log(.nextActionTaken(area: step.areaSlug))
                            onPracticeAgain()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background { Circle().fill(.ultraThinMaterial) }
                                .overlay { Circle().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                        }
                        .buttonStyle(GlassPressStyle())
                        .accessibilityLabel("Practice this prompt again")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ZStack {
        AppBackground()
        VStack(spacing: 16) {
            NextStepCard(
                step: .from(SpeechSubscores(clarity: 80, pace: 74, fillerUsage: 52, pauseQuality: 70)),
                onAction: { _ in },
                onPracticeAgain: {}
            )
            NextStepCard(
                step: .from(SpeechSubscores(clarity: 88, pace: 84, fillerUsage: 91, pauseQuality: 79)),
                onAction: { _ in },
                onPracticeAgain: {}
            )
        }
        .padding()
    }
}
