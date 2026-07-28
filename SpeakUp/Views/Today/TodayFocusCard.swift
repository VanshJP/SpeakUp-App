import SwiftUI

/// Today's recommendation: the one thing to work on, and the button that does it.
///
/// `NextStepCard` answers "what should I do about *that session*". This answers
/// "what should I do about *my speaking right now*" by running the same weakest-
/// area logic over a rolling window of recent sessions, so a single bad rep
/// doesn't redirect the whole practice plan.
struct TodayFocusCard: View {
    let step: NextStep
    /// How many analyzed sessions fed the average — shown so the recommendation
    /// is legibly evidence-based rather than arbitrary.
    let sessionCount: Int
    let onAction: (NextStep.Action) -> Void

    var body: some View {
        GlassCard(padding: 18, elevated: true) {
            VStack(alignment: .leading, spacing: 14) {
                header

                if step.isStrong {
                    Text("Nothing is averaging below 75 across your last \(sessionCount) session\(sessionCount == 1 ? "" : "s"). Keep banking reps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    areaLine
                    Text(step.coaching)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: step.isStrong ? "checkmark.seal.fill" : "scope")
                .font(.system(size: 10, weight: .semibold))
            Text(step.isStrong ? "On track" : "Today's focus")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer()

            Text("Last \(sessionCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }

    private var areaLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(step.area)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("\(step.score)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.scoreColor(for: step.score))

            Text("avg")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var actionButton: some View {
        Button {
            Haptics.medium()
            onAction(step.action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: actionIcon)
                    .font(.system(size: 15, weight: .semibold))
                Text(step.actionTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background { Capsule().fill(Color.white.opacity(0.94)) }
        }
        .buttonStyle(GlassPressStyle())
    }

    private var actionIcon: String {
        switch step.action {
        case .drill: return "bolt.fill"
        case .warmUp: return "wind"
        case .readAloud: return "text.book.closed"
        case .practiceAgain: return "mic.fill"
        }
    }
}

// MARK: - Rolling Average

extension SpeechSubscores {
    /// Mean of each subscore across recent sessions. Optional subscores average
    /// only over the sessions that actually produced them, so a metric the
    /// pipeline skipped never drags the average toward zero.
    static func rollingAverage(_ samples: [SpeechSubscores]) -> SpeechSubscores? {
        guard !samples.isEmpty else { return nil }

        func mean(_ values: [Int]) -> Int {
            guard !values.isEmpty else { return 0 }
            return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }

        func optionalMean(_ values: [Int?]) -> Int? {
            let present = values.compactMap { $0 }
            return present.isEmpty ? nil : mean(present)
        }

        return SpeechSubscores(
            clarity: mean(samples.map(\.clarity)),
            pace: mean(samples.map(\.pace)),
            fillerUsage: mean(samples.map(\.fillerUsage)),
            pauseQuality: mean(samples.map(\.pauseQuality)),
            vocalVariety: optionalMean(samples.map(\.vocalVariety)),
            delivery: optionalMean(samples.map(\.delivery)),
            vocabulary: optionalMean(samples.map(\.vocabulary)),
            structure: optionalMean(samples.map(\.structure)),
            relevance: optionalMean(samples.map(\.relevance))
        )
    }
}

#Preview {
    ZStack {
        AppBackground()
        VStack(spacing: 16) {
            TodayFocusCard(
                step: .from(SpeechSubscores(clarity: 80, pace: 74, fillerUsage: 52, pauseQuality: 70)),
                sessionCount: 6,
                onAction: { _ in }
            )
            TodayFocusCard(
                step: .from(SpeechSubscores(clarity: 88, pace: 84, fillerUsage: 91, pauseQuality: 79)),
                sessionCount: 3,
                onAction: { _ in }
            )
        }
        .padding()
    }
}
