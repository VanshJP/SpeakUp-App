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
    let score: Int
    let coaching: String
    let actionTitle: String
    let action: Action

    /// A session where nothing is weak enough to drill — offer another rep instead.
    var isStrong: Bool { score >= 75 }

    static func from(_ subscores: SpeechSubscores) -> NextStep {
        // Required subscores are always present; optional ones only join the
        // comparison when the pipeline actually produced them.
        var candidates: [(area: String, score: Int, step: (String, String, Action))] = [
            ("Filler words", subscores.fillerUsage, (
                "Fillers creep in when you think and talk at the same time. Pause instead.",
                "Filler Elimination · 15s",
                .drill(.fillerElimination)
            )),
            ("Pace", subscores.pace, (
                "Steady pace beats fast. Aim for the target WPM band the whole way.",
                "Pace Control · 60s",
                .drill(.paceControl)
            )),
            ("Pauses", subscores.pauseQuality, (
                "Deliberate pauses read as confidence. Practice landing them on purpose.",
                "Pause Practice · 45s",
                .drill(.pausePractice)
            )),
            ("Clarity", subscores.clarity, (
                "Articulation is mechanical — reading aloud trains the mouth, not the nerves.",
                "Read Aloud",
                .readAloud
            ))
        ]

        if let vocalVariety = subscores.vocalVariety {
            candidates.append(("Vocal variety", vocalVariety, (
                "Flat delivery loses the room. Warm the voice up before you speak.",
                "Vocal Warm-Up",
                .warmUp
            )))
        }
        if let delivery = subscores.delivery {
            candidates.append(("Delivery", delivery, (
                "Energy carries the point. A warm-up raises your baseline before a session.",
                "Vocal Warm-Up",
                .warmUp
            )))
        }
        if let vocabulary = subscores.vocabulary {
            candidates.append(("Vocabulary", vocabulary, (
                "Reach for a stronger word under time pressure until it stops being a reach.",
                "Impromptu Sprint · 30s",
                .drill(.impromptuSprint)
            )))
        }
        if let structure = subscores.structure {
            candidates.append(("Structure", structure, (
                "Point, reason, example. Sprints force you to build that shape fast.",
                "Impromptu Sprint · 30s",
                .drill(.impromptuSprint)
            )))
        }
        if let relevance = subscores.relevance {
            candidates.append(("Staying on topic", relevance, (
                "Answer the question first, then support it. Don't warm up on the listener.",
                "Impromptu Sprint · 30s",
                .drill(.impromptuSprint)
            )))
        }

        let weakest = candidates.min { $0.score < $1.score } ?? candidates[0]
        guard weakest.score < 75 else {
            return NextStep(
                area: weakest.area,
                score: weakest.score,
                coaching: "Nothing scored below 75 this session. Bank another rep while it's working.",
                actionTitle: "Practice Again",
                action: .practiceAgain
            )
        }

        return NextStep(
            area: weakest.area,
            score: weakest.score,
            coaching: weakest.step.0,
            actionTitle: weakest.step.1,
            action: weakest.step.2
        )
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
