import SwiftUI

/// The moment the app exists for: you stopped talking, here is how it went.
///
/// The reveal is scaled to the band so the app's reaction matches the result:
///
/// - **Strong (80+)**: confetti, success haptic, the score is the celebration.
/// - **Solid (60-79)**: the number climbs and lands. Confetti only for a
///   personal best; a good session doesn't need a parade, and spending
///   confetti on every solid take would make it worthless at 90.
/// - **Building (<60)**: no celebration language at all. The verdict, then one
///   forward-looking line naming what held it back. A personal best still
///   gets its pill and its haptic, just not the party. Honest, not a failure
///   state, and never congratulatory: a low score met with confetti reads
///   as sarcasm.
struct ScoreRevealView: View {
    let score: Int
    let baselines: PersonalAverage.Baselines
    let weakestAxisLabel: String?
    /// The streak day this take earned, when it was the day's first.
    var streakDay: Int? = nil
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// With VoiceOver on, the reveal waits for a double-tap instead of moving
    /// on by itself: the timed hand-off left before the summary was read.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var counted = false
    @State private var landed = false
    @State private var showVerdict = false
    @State private var showContext = false
    @State private var showConfetti = false
    @State private var showHint = false
    @State private var showBest = false
    @State private var showStreak = false
    @State private var streakLit = false

    private static let countDuration = 0.9

    private enum Band {
        case strong, solid, building
    }

    private var band: Band {
        if score >= 80 { return .strong }
        if score >= 60 { return .solid }
        return .building
    }

    private var scoreColor: Color { AppColors.scoreColor(for: score) }

    /// Where the wheel and the count start: your average, so the turn *is*
    /// the delta. No history yet, and it turns up from zero.
    private var startScore: Double {
        Double(min(100, max(0, baselines.score ?? 0)))
    }

    private var delta: Int? {
        guard let average = baselines.score else { return nil }
        return score - average
    }

    private var personalBestLabel: String? {
        baselines.personalBestLabel(for: score)
    }

    /// A strong take, or a personal best that is at least solid. A best at 45
    /// still gets its pill and its haptic, just not the party.
    private var celebrates: Bool {
        band == .strong || (band == .solid && personalBestLabel != nil)
    }

    var body: some View {
        // No background of its own: `RecordingView` keeps the session canvas
        // under the whole act, so the score lands on the stage the take used.
        ZStack {
            if showConfetti {
                // Behind the content, launched from behind the dial, so the
                // pieces burst out of the score rather than fall on it.
                ConfettiView(origin: UnitPoint(x: 0.5, y: 0.42))
            }

            VStack(spacing: 0) {
                Spacer()

                Text("Session complete").eyebrowStyle()
                    .opacity(showVerdict ? 1 : 0)

                scoreDial
                    .padding(.top, 12)

                verdictBlock

                Spacer()

                Text("Tap for the full breakdown")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .opacity(showHint ? 1 : 0)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        // The canvas used to size this; without it the tap-anywhere surface
        // would shrink to the text column.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task { await choreograph() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onDismiss() }
    }

    // MARK: - Subviews

    /// A 0-100 crown on the shared `ArcDial`, turning from your average to
    /// this take while the number climbs in the bowl. Only the stops either
    /// side of the score are in frame, so where it lands reads as a place on
    /// a scale rather than a fraction of a ring.
    private var scoreDial: some View {
        ArcDial(
            count: 11,
            position: (counted ? Double(score) : startScore) / 10,
            fillsToMarker: true,
            label: { "\($0 * 10)" },
            isInteractive: false,
            height: 250,
            tint: { AppColors.scoreColor(for: $0 * 10) },
            glyph: { _ in EmptyView() },
            hub: { scoreHub }
        )
        // Full bleed: the wheel is meant to run off the screen.
        .padding(.horizontal, -32)
        // A bloom in the score's own color that swells as the number lands,
        // centred on the number. Outside the dial, whose clip would square
        // it off.
        .background(alignment: .top) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [scoreColor.opacity(0.32), scoreColor.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(landed ? 1 : 0.6)
                .opacity(landed ? 1 : 0)
                .padding(.top, 27)
                .allowsHitTesting(false)
        }
    }

    private var scoreHub: some View {
        VStack(spacing: 0) {
            CountUpText(
                value: counted ? Double(score) : startScore,
                font: .displayNumeral,
                color: scoreColor
            )

            Text("/ 100")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? false : landed) { hub, scale in
            hub.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.08, duration: 0.14, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
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

            if personalBestLabel != nil || streakDay != nil {
                // Laid out from the start and revealed by opacity, so the
                // second badge arriving never shoves the first sideways.
                ViewThatFits {
                    HStack(spacing: 8) { badges }
                    VStack(spacing: 8) { badges }
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let personalBestLabel {
            RevealBadge(tint: AppColors.warning, isLit: true) {
                Image(systemName: "trophy.fill")
            } label: {
                Text(personalBestLabel)
            }
            .opacity(showBest ? 1 : 0)
            .scaleEffect(showBest ? 1 : 0.8)
        }

        if let streakDay {
            // Ignites on its own beat: the flame goes from ash to amber and the
            // day rolls forward, the way the Today chip will read next visit.
            let shownDay = streakLit ? streakDay : max(streakDay - 1, 1)
            RevealBadge(tint: AppColors.warning, isLit: streakLit) {
                Image(systemName: "flame.fill")
                    .symbolEffect(.bounce, value: reduceMotion ? false : streakLit)
            } label: {
                Text(streakDay <= 1 ? "Streak started" : "Day \(shownDay) streak")
                    .contentTransition(.numericText(value: Double(shownDay)))
            }
            .opacity(showStreak ? 1 : 0)
            .scaleEffect(showStreak ? 1 : 0.8)
        }
    }

    // MARK: - Copy

    private var contextLine: String {
        switch band {
        case .building:
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
            + (streakDay.map { $0 <= 1 ? "Streak started. " : "Day \($0) streak. " } ?? "")
            + "Tap for the full breakdown."
    }

    // MARK: - Choreography

    /// Staggered rather than simultaneous: the number has to finish climbing
    /// before the verdict names it, or the verdict spoils the count.
    private func choreograph() async {
        guard !reduceMotion else {
            counted = true
            landed = true
            showVerdict = true
            showContext = true
            showBest = true
            showStreak = true
            streakLit = true
            showHint = true
            bandHaptic()
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            onDismiss()
            return
        }

        withAnimation(.easeOut(duration: Self.countDuration)) { counted = true }

        // The dial ticks at every ten it turns past - it animates on the
        // same curve as the number, from your average - then the band's
        // thump lands with the verdict.
        let landingAt = 0.85
        try? await Task.sleep(for: .seconds(landingAt))
        guard !Task.isCancelled else { return }

        withAnimation(AppMotion.settle) {
            landed = true
            showVerdict = true
        }
        bandHaptic()

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { showContext = true }

        if celebrates {
            showConfetti = true
        }

        if personalBestLabel != nil {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.settle) { showBest = true }
            Haptics.success()
        }

        if streakDay != nil {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.settle) { showStreak = true }

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.snap) { streakLit = true }
            Haptics.medium()
        }

        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { showHint = true }

        guard !voiceOverEnabled else { return }
        var linger = 1400
        if personalBestLabel != nil { linger += 500 }
        if streakDay != nil { linger += 600 }
        try? await Task.sleep(for: .milliseconds(linger))
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

// MARK: - Reveal Badge

/// The reveal's pills - personal best, streak - sized for a hero moment
/// rather than a list row. `isLit` lets a badge arrive in ash and ignite.
private struct RevealBadge<Icon: View, Title: View>: View {
    let tint: Color
    let isLit: Bool
    @ViewBuilder let icon: Icon
    @ViewBuilder let label: Title

    var body: some View {
        HStack(spacing: 6) {
            icon
                .font(.footnote.weight(.bold))
                .foregroundStyle(isLit ? tint : .white.opacity(0.35))

            label
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(tint.opacity(isLit ? 0.18 : 0.06))
                .overlay {
                    Capsule().strokeBorder(tint.opacity(isLit ? 0.4 : 0.12), lineWidth: 0.5)
                }
        }
    }
}

#Preview("Strong, personal best, streak") {
    ScoreRevealView(
        score: 91,
        baselines: .init(score: 74, best: 88, priorSessionCount: 6, seenAllHistory: true),
        weakestAxisLabel: nil,
        streakDay: 5,
        onDismiss: {}
    )
    .background { AppBackground(style: .recording) }
}

#Preview("Solid") {
    ScoreRevealView(
        score: 71,
        baselines: .init(score: 72, best: 84, priorSessionCount: 12),
        weakestAxisLabel: nil,
        onDismiss: {}
    )
    .background { AppBackground(style: .recording) }
}

#Preview("Building") {
    ScoreRevealView(
        score: 43,
        baselines: .init(score: 58, best: 77, priorSessionCount: 9),
        weakestAxisLabel: "Fillers",
        onDismiss: {}
    )
    .background { AppBackground(style: .recording) }
}

#Preview("First session") {
    ScoreRevealView(
        score: 66,
        baselines: .init(),
        weakestAxisLabel: nil,
        streakDay: 1,
        onDismiss: {}
    )
    .background { AppBackground(style: .recording) }
}
