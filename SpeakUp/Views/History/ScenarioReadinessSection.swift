import SwiftUI

// MARK: - Scenario Readiness Section

/// The middle band of the Progress page: one readiness card per practiced
/// scenario (interviews, public speaking, storytelling, conversation), weakest
/// first, then quiet invitation rows for scenarios with no sessions yet.
struct ScenarioReadinessSection: View {
    let cards: [ScenarioReadiness]
    /// Composite over all analyzed sessions — the former aggregate
    /// Interview Readiness survives as this one chip.
    let overallScore: Int?
    let analyzedSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if analyzedSessions < 2 || cards.isEmpty {
                quietState
            } else {
                header
                ForEach(cards) { card in
                    ScenarioReadinessCard(readiness: card)
                }
                invitations
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Scenario Readiness", systemImage: "target")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let overallScore {
                StatusPill(
                    text: "All scenarios · \(overallScore)",
                    color: AppColors.scoreColor(for: overallScore),
                    glyph: .dot
                )
            }
        }
    }

    private var quietState: some View {
        GlassCard {
            EmptyStateInline(
                icon: "target",
                message: "Two analyzed sessions and this maps your readiness across interviews, public speaking, storytelling, and everyday conversation."
            )
        }
    }

    private var invitations: some View {
        let practiced = Set(cards.map(\.scenario))
        let missing = PracticeScenario.allCases.filter { $0.isCore && !practiced.contains($0) }

        return VStack(spacing: 8) {
            ForEach(missing) { scenario in
                ScenarioInvitationRow(scenario: scenario)
            }
        }
    }
}

// MARK: - Scenario Card

private struct ScenarioReadinessCard: View {
    let readiness: ScenarioReadiness

    @State private var animate = false

    private var tint: Color { Self.color(for: readiness.scenario) }

    static func color(for scenario: PracticeScenario) -> Color {
        switch scenario {
        case .interviews: return AppColors.categoryTeal
        case .publicSpeaking: return AppColors.categoryCopper
        case .storytelling: return AppColors.categoryPlum
        case .conversation: return AppColors.categorySage
        case .other: return AppColors.categoryNeutralCool
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                ring

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: readiness.scenario.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)

                        Text(readiness.scenario.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        momentumBadge(readiness.momentum)
                    }

                    HStack(spacing: 6) {
                        StatusPill(
                            text: readiness.bandLabel,
                            color: scoreColor,
                            glyph: .dot
                        )

                        if readiness.isEarlyRead {
                            Text("\(readiness.sessions) session\(readiness.sessions == 1 ? "" : "s") — early read")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    holdingBackLine
                }
            }
        }
        .onAppear {
            animate = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var ring: some View {
        ZStack {
            RingProgress(
                progress: animate ? Double(readiness.score ?? 0) / 100 : 0,
                color: scoreColor,
                lineWidth: 7
            )

            if let score = readiness.score {
                Text("\(score)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .animation(.easeOut(duration: 0.9).delay(0.15), value: animate)
    }

    private var scoreColor: Color {
        guard let score = readiness.score else { return tint }
        return AppColors.scoreColor(for: score)
    }

    @ViewBuilder
    private var holdingBackLine: some View {
        if let word = readiness.holdingBackWord, let count = readiness.holdingBackCount {
            Text("Holding it back: \u{201C}\(word)\u{201D} \u{00D7}\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("\(readiness.sessions) session\(readiness.sessions == 1 ? "" : "s") so far")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func momentumBadge(_ momentum: ScenarioMomentum) -> some View {
        switch momentum {
        case .improving:
            badge(icon: "arrow.up.right", text: "Improving", color: AppColors.success)
        case .steady:
            badge(icon: "arrow.right", text: "Steady", color: Color.white.opacity(0.35))
        case .slipping:
            badge(icon: "arrow.down.right", text: "Slipping", color: AppColors.warning)
        }
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
    }

    private var accessibilitySummary: String {
        var parts = [
            "\(readiness.scenario.title): \(readiness.bandLabel)",
            readiness.score.map { "\($0) of 100" } ?? "not enough language yet",
            "momentum \(readiness.momentum == .improving ? "improving" : readiness.momentum == .slipping ? "slipping" : "steady")"
        ]
        if let word = readiness.holdingBackWord {
            parts.append("holding it back, \(word)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Invitation Row

private struct ScenarioInvitationRow: View {
    let scenario: PracticeScenario

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: scenario.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ScenarioReadinessCard.color(for: scenario))
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(ScenarioReadinessCard.color(for: scenario).opacity(0.13))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Text("No sessions yet · \(scenario.blurb)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scenario.title): no sessions yet. \(scenario.blurb)")
    }
}
