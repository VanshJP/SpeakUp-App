import SwiftUI

struct NextStep {
    enum Action: Equatable {
        case drill(DrillMode)
        case warmUp
        case readAloud
        case practiceAgain
    }

    let area: String
    let areaSlug: String
    let score: Int
    let coaching: String
    let actionTitle: String
    let action: Action

    var isStrong: Bool { score >= 75 }

    static func from(_ subscores: SpeechSubscores, plan: CoachPlan? = nil) -> NextStep {
        if let plan, !plan.isGraduating {
            let route = route(for: plan.focus)
            return NextStep(
                area: plan.focus.title,
                areaSlug: plan.focus.analyticsSlug,
                score: plan.focus.subscore(in: subscores) ?? plan.focusAverage,
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
                    GlassButton(
                        title: step.actionTitle,
                        style: .primary,
                        fullWidth: true
                    ) {
                        Haptics.medium()
                        AnalyticsService.shared.log(.nextActionTaken(area: step.areaSlug))
                        onAction(step.action)
                    }

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
