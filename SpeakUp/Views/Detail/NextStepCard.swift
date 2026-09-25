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
    /// The named move, when there is one. Nil on the branches that have no
    /// technique to hand over - a clean session, or no scored subscore at all.
    let technique: String?
    /// One instruction. The reasoning behind it lives on the Coaching tab,
    /// where there is room for it.
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
                technique: plan.focus.technique.name,
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
                technique: nil,
                coaching: "Bank another rep while it's working.",
                actionTitle: "Practice again",
                action: .practiceAgain
            )
        }

        guard weakest.1 < 75 else {
            return NextStep(
                area: weakest.0.title,
                areaSlug: weakest.0.analyticsSlug,
                score: weakest.1,
                technique: nil,
                coaching: plan?.headline ?? "Nothing scored below 75 this session. Bank another rep while it's working.",
                actionTitle: "Practice again",
                action: .practiceAgain
            )
        }

        let route = route(for: weakest.0)
        return NextStep(
            area: weakest.0.title,
            areaSlug: weakest.0.analyticsSlug,
            score: weakest.1,
            technique: weakest.0.technique.name,
            coaching: weakest.0.technique.how,
            actionTitle: route.title,
            action: route.action
        )
    }

    private static func route(for dimension: CoachDimension) -> (title: String, action: Action) {
        let route = dimension.practiceRoute
        switch route {
        case .readAloud:
            return (route.actionTitle ?? "Practice again", .readAloud)
        case .warmUp:
            return (route.actionTitle ?? "Practice again", .warmUp)
        case .drill(let raw):
            guard let mode = DrillMode(rawValue: raw), let title = route.actionTitle else {
                return ("Practice again", .practiceAgain)
            }
            return ("\(title) · \(mode.currentDurationSeconds)s", .drill(mode))
        }
    }
}

// MARK: - Route titles

extension CoachPracticeRoute {
    /// Verb-first CTA naming the tool the way the Library does
    /// (`PracticeToolKind`, drill names from `DrillMode`). Shared by the next
    /// step and the coaching tip rows, which used to print "Read Aloud" and
    /// "Vocal Warm-Up" as bare Title Case nouns on a button.
    var actionTitle: String? {
        switch self {
        case .readAloud:
            return "Open \(PracticeToolKind.readAloud.title)"
        case .warmUp:
            return "Open \(PracticeToolKind.warmUp.title)"
        case .drill(let raw):
            guard let mode = DrillMode(rawValue: raw) else { return nil }
            return "Start \(mode.title)"
        }
    }
}

// MARK: - Card

struct NextStepCard: View {
    let step: NextStep
    let analyticsSource: String
    let onAction: (NextStep.Action) -> Void
    let onPracticeAgain: () -> Void

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(step.isStrong ? "Nice session" : "Work on this next")
                    .eyebrowStyle()

                if !step.isStrong {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(step.area)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(step.score)")
                            .font(.statValue)
                            .foregroundStyle(AppColors.scoreColor(for: step.score))

                        // Said out loud because the Coaching tab prints the
                        // same dimension against its rolling average. Two
                        // different numbers under one word read as a bug.
                        Text("this take")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 8)

                        if let technique = step.technique {
                            Text(technique)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .accessibilityLabel("Technique: \(technique)")
                        }
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
                        AnalyticsService.shared.log(
                            .nextActionTaken(area: step.areaSlug, source: analyticsSource)
                        )
                        onAction(step.action)
                    }

                    if step.action != .practiceAgain {
                        Button {
                            Haptics.light()
                            AnalyticsService.shared.log(
                                .nextActionTaken(area: step.areaSlug, source: analyticsSource)
                            )
                            onPracticeAgain()
                        } label: {
                            // Painted like `GlassButton.secondary` on a plate:
                            // a material disc on a glass card read as a grey
                            // smudge (glass on glass, rule 13b).
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background { Circle().fill(Color.white.opacity(0.10)) }
                                .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
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
                analyticsSource: "preview",
                onAction: { _ in },
                onPracticeAgain: {}
            )
            NextStepCard(
                step: .from(SpeechSubscores(clarity: 88, pace: 84, fillerUsage: 91, pauseQuality: 79)),
                analyticsSource: "preview",
                onAction: { _ in },
                onPracticeAgain: {}
            )
        }
        .padding()
    }
}
