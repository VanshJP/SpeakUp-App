import SwiftUI

// MARK: - Scenario Readiness Section

/// The middle band of the Progress page, answering "which situation needs
/// work". One ranked card replaces the former always-open family of featured
/// card + tile grid + separate invitation stack: practiced scenarios lead
/// weakest-first with their verdicts inline, unpracticed ones follow as quiet
/// rows in the same list. Same information, one object to parse.
struct ScenarioReadinessSection: View {
    let cards: [ScenarioReadiness]
    /// Composite over all analyzed sessions — reported in the card footer,
    /// never as a competing headline number.
    let overallScore: Int?
    let analyzedSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if analyzedSessions < 2 || cards.isEmpty {
                quietState
            } else {
                GlassSectionHeader("Where to Improve", icon: "scope") {
                    Text("weakest first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                readinessCard
            }
        }
    }

    private var quietState: some View {
        GlassCard {
            EmptyStateInline(
                icon: "scope",
                message: "Two analyzed sessions and this maps your readiness across interviews, public speaking, storytelling, and everyday conversation."
            )
        }
    }

    private var readinessCard: some View {
        GlassCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 {
                        MetricRowDivider()
                    }
                    ScenarioRow(readiness: card)
                }

                invitationRows
                aggregateFooter
            }
        }
    }

    /// The former aggregate Interview Readiness survives as this quiet footer
    /// line — present for anyone who wants the composite, never competing
    /// with the per-scenario verdicts above it.
    @ViewBuilder
    private var aggregateFooter: some View {
        if let overallScore {
            MetricRowDivider()

            HStack(spacing: 6) {
                Text("Combined readiness \(overallScore)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.scoreColor(for: overallScore))

                Text("across \(analyzedSessions) analyzed session\(analyzedSessions == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Combined readiness \(overallScore) of 100 across \(analyzedSessions) analyzed sessions.")
        }
    }

    /// Unpracticed core scenarios close the same list — context, not a
    /// separate to-do block shouting from the page.
    @ViewBuilder
    private var invitationRows: some View {
        let practiced = Set(cards.map(\.scenario))
        let missing = PracticeScenario.allCases.filter { $0.isCore && !practiced.contains($0) }

        if !missing.isEmpty {
            ForEach(missing) { scenario in
                MetricRowDivider()
                ScenarioInvitationRow(scenario: scenario)
            }
        }
    }
}

// MARK: - Scenario Tint

/// Identity tone per scenario — shared by practiced and invitation rows so
/// the list reads as one system.
private enum ScenarioTint {
    static func color(for scenario: PracticeScenario) -> Color {
        switch scenario {
        case .interviews: return AppColors.categoryTeal
        case .publicSpeaking: return AppColors.categoryCopper
        case .storytelling: return AppColors.categoryPlum
        case .conversation: return AppColors.categorySage
        case .other: return AppColors.categoryNeutralCool
        }
    }
}

// MARK: - Momentum presentation

/// How a direction of travel looks, in one place. The Progress page renders
/// this verdict twice — the hero's filled pill and this section's inline glyph
/// — and each used to carry its own switch. They had already drifted: slipping
/// was red in the hero and amber here, and steady disagreed on its opacity, on
/// the same screen. Presentation lives in the view layer because the engine
/// that emits `ScenarioMomentum` is `nonisolated` and Foundation-only; this
/// mirrors `CrutchCategory.badgeColor` in `CrutchSwapsCard`.
extension ScenarioMomentum {
    var symbolName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .slipping: return "arrow.down.right"
        }
    }

    var label: String {
        switch self {
        case .improving: return "Improving"
        case .steady: return "Steady"
        case .slipping: return "Slipping"
        }
    }

    /// Amber, not red, for slipping: a dipping practice score wants attention,
    /// and `AppColors.error` reads as "something is broken".
    var tint: Color {
        switch self {
        case .improving: return AppColors.success
        case .steady: return Color.white.opacity(0.45)
        case .slipping: return AppColors.warning
        }
    }
}

/// Direction of travel as a single glyph + word — the compact counterpart of
/// the hero's momentum pill. One verdict encoding per element; the number
/// carries level, this carries direction.
private struct MomentumGlyph: View {
    let momentum: ScenarioMomentum

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: momentum.symbolName)
                .font(.system(size: 8, weight: .bold))
            Text(momentum.label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(momentum.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentum \(momentum.label.lowercased())")
    }
}

// MARK: - Scenario Row

private struct ScenarioRow: View {
    let readiness: ScenarioReadiness

    private var tint: Color { ScenarioTint.color(for: readiness.scenario) }

    private var scoreColor: Color {
        guard let score = readiness.score else { return tint }
        return AppColors.scoreColor(for: score)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: readiness.scenario.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(tint.opacity(0.13))
                }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(readiness.scenario.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    MomentumGlyph(momentum: readiness.momentum)

                    Text(readiness.score.map(String.init) ?? "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(scoreColor)
                        .contentTransition(.numericText())
                }

                // Level as a meter — the same one the session score hero uses.
                // Two bare numbers in a stack made the reader do the
                // arithmetic; a filled bar answers "how far along" at a glance.
                if let score = readiness.score {
                    TickMeter(fraction: Double(score) / 100, color: scoreColor, tickCount: 28)
                        .frame(height: 5)
                }

                Text(metaLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                holdingBackLine
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Band, evidence, and the honesty flag on one quiet line — the verdict
    /// used to sit in a second right-hand column, competing with the score.
    private var metaLine: String {
        var parts = [readiness.bandLabel, sessionCountText]
        if readiness.isEarlyRead {
            parts.append("early read")
        }
        return parts.joined(separator: " · ")
    }

    /// The one actionable fact in the row, so it gets a full line instead of
    /// being truncated mid-word inside a shared caption.
    @ViewBuilder
    private var holdingBackLine: some View {
        if let word = readiness.holdingBackWord, let count = readiness.holdingBackCount {
            Text("\u{201C}\(word)\u{201D} costs you most here · \(count)\u{00D7} so far")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionCountText: String {
        "\(readiness.sessions) session\(readiness.sessions == 1 ? "" : "s")"
    }

    private var accessibilitySummary: String {
        [
            "\(readiness.scenario.title): \(readiness.bandLabel)",
            readiness.score.map { "\($0) of 100" } ?? "not enough language yet",
            "momentum \(readiness.momentum.label.lowercased())",
            sessionCountText,
            readiness.holdingBackWord.map { "holding back, \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

// MARK: - Invitation Row

private struct ScenarioInvitationRow: View {
    let scenario: PracticeScenario

    private var tint: Color { ScenarioTint.color(for: scenario) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: scenario.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(tint.opacity(0.07))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(scenario.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                Text(scenario.blurb)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // ponytail: states the fact instead of a "+" that led nowhere.
            // Make it a real shortcut when the section can reach the practice
            // hub with a scenario filter.
            Text("Not yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scenario.title): no sessions yet. \(scenario.blurb)")
    }
}
