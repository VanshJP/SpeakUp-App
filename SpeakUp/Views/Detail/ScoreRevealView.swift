import SwiftUI

/// The moment the app exists for: you stopped talking, here is how it went.
///
/// Before this screen, finishing a recording silently switched tabs and pushed
/// a detail page — a 95 and a 45 arrived identically. The reveal is scaled to
/// the band so the app's reaction matches the result:
///
/// - **Strong (80+)** — confetti, success haptic, the score is the celebration.
/// - **Solid (60–79)** — the number climbs and lands. No particles; a good
///   session doesn't need a parade, and spending confetti here would make it
///   worthless at 90.
/// - **Building (<60)** — no celebration language at all. The verdict, then one
///   forward-looking line naming what held it back. Honest, not a failure state,
///   and never congratulatory — a low score met with confetti reads as sarcasm.
struct ScoreRevealView: View {
    let score: Int
    /// Rolling baselines excluding this session. All-nil on a first session.
    let baselines: PersonalAverage.Baselines
    /// Label of the lowest-scoring axis, used only in the building band.
    let weakestAxisLabel: String?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var counted = false
    @State private var showVerdict = false
    @State private var showContext = false
    @State private var showConfetti = false
    @State private var showHint = false
    @State private var showBest = false

    private enum Band {
        case strong, solid, building
    }

    private var band: Band {
        if score >= 80 { return .strong }
        if score >= 60 { return .solid }
        return .building
    }

    private var scoreColor: Color { AppColors.scoreColor(for: score) }

    private var delta: Int? {
        guard let average = baselines.score else { return nil }
        return score - average
    }

    private var personalBestLabel: String? {
        baselines.personalBestLabel(for: score)
    }

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()

                Text("Session complete").eyebrowStyle()
                    .opacity(showVerdict ? 1 : 0)

                scoreDial
                    .padding(.top, 24)

                verdictBlock
                    .padding(.top, 28)

                Spacer()

                Text("Tap for the full breakdown")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .opacity(showHint ? 1 : 0)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task { await choreograph() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews

    /// The numeral sits inside a ring that fills as it climbs, so the score is
    /// read twice — once as a value, once as a position on the scale.
    private var scoreDial: some View {
        ZStack {
            RingProgress(
                progress: counted ? Double(score) / 100 : 0,
                color: scoreColor,
                lineWidth: 10
            )
            .frame(width: 240, height: 240)

            VStack(spacing: 0) {
                CountUpText(
                    value: counted ? Double(score) : 0,
                    font: .displayNumeral,
                    color: scoreColor
                )

                Text("/ 100")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)
            }
        }
    }

    private var verdictBlock: some View {
        VStack(spacing: 10) {
            Text(AppColors.scoreVerdict(for: score))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(showVerdict ? 1 : 0)
                .scaleEffect(showVerdict ? 1 : 0.85)

            Text(contextLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(showContext ? 1 : 0)

            // Lands after the delta, so the reveal builds rather than dumping
            // every fact at once. Rare by construction — it only ever shows on
            // an actual new high.
            if let personalBestLabel {
                StatusPill(
                    text: personalBestLabel,
                    color: AppColors.warning,
                    glyph: .icon("trophy.fill"),
                    fillOpacity: 0.18
                )
                .opacity(showBest ? 1 : 0)
                .scaleEffect(showBest ? 1 : 0.8)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Copy

    private var contextLine: String {
        switch band {
        case .building:
            // Name the lever rather than the shortfall — the detail screen's
            // next-step card picks this same thread up.
            if let weakestAxisLabel {
                return "Next lever: \(weakestAxisLabel)"
            }
            return "Every take is data. Let's look at why."

        case .solid, .strong:
            guard let delta else { return "Your first scored session" }
            // Inside ±2 is run-to-run variance, not a trend.
            if abs(delta) <= 2 { return "Right on par with your average" }
            return delta > 0
                ? "\(delta) above your average"
                : "\(abs(delta)) below your average"
        }
    }

    private var accessibilitySummary: String {
        "Session complete. Score \(score) out of 100, "
            + "\(AppColors.scoreVerdict(for: score)). \(contextLine). "
            + (personalBestLabel.map { "\($0). " } ?? "")
            + "Tap for the full breakdown."
    }

    // MARK: - Choreography

    /// Staggered rather than simultaneous: the number has to finish climbing
    /// before the verdict names it, or the verdict spoils the count.
    private func choreograph() async {
        guard !reduceMotion else {
            counted = true
            showVerdict = true
            showContext = true
            showBest = true
            showHint = true
            // Reduce Motion removes movement, not feedback — the band still
            // gets its own haptic.
            bandHaptic()
            try? await Task.sleep(for: .seconds(2.4))
            onDismiss()
            return
        }

        withAnimation(AppMotion.reveal) { counted = true }

        try? await Task.sleep(for: .milliseconds(850))
        guard !Task.isCancelled else { return }
        withAnimation(AppMotion.settle) { showVerdict = true }
        bandHaptic()

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { showContext = true }

        if band == .strong {
            showConfetti = true
        }

        if personalBestLabel != nil {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.settle) { showBest = true }
            Haptics.success()
        }

        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { showHint = true }

        // Long enough to land, short enough that it never feels like a gate.
        // A new high earns a beat more.
        try? await Task.sleep(for: .milliseconds(personalBestLabel != nil ? 1900 : 1400))
        guard !Task.isCancelled else { return }
        onDismiss()
    }

    private func bandHaptic() {
        switch band {
        case .strong: Haptics.success()
        case .solid: Haptics.medium()
        case .building: Haptics.light()
        }
    }
}

#Preview("Strong, personal best") {
    ScoreRevealView(
        score: 91,
        baselines: .init(score: 74, best: 88, priorSessionCount: 6),
        weakestAxisLabel: nil,
        onDismiss: {}
    )
}

#Preview("Solid") {
    ScoreRevealView(
        score: 71,
        baselines: .init(score: 72, best: 84, priorSessionCount: 12),
        weakestAxisLabel: nil,
        onDismiss: {}
    )
}

#Preview("Building") {
    ScoreRevealView(
        score: 43,
        baselines: .init(score: 58, best: 77, priorSessionCount: 9),
        weakestAxisLabel: "Fillers",
        onDismiss: {}
    )
}

#Preview("First session") {
    ScoreRevealView(
        score: 66,
        baselines: .init(),
        weakestAxisLabel: nil,
        onDismiss: {}
    )
}
