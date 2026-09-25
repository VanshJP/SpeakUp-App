import SwiftUI

// MARK: - Scenario Readiness Section

struct ScenarioReadinessSection: View {
    let cards: [ScenarioReadiness]
    /// Composite over all analyzed sessions - reported in the card footer,
    /// never as a competing headline number.
    let overallScore: Int?
    let analyzedSessions: Int
    /// Starts practice in a row's scenario. The rows used to name the weak
    /// situation and stop there; nil keeps them read-only until the root
    /// passes a route.
    var onPractice: ((PracticeScenario) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if analyzedSessions < 2 || cards.isEmpty {
                quietState
            } else {
                GlassSectionHeader("Where to improve") {
                    Text("Weakest first")
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

    /// One plate of rows with hairlines that start where the row text does.
    private var readinessCard: some View {
        GlassRowGroup(dividerInset: ScenarioRowLayout.textInset) {
            ForEach(cards) { card in
                row(for: card.scenario) {
                    ScenarioRow(readiness: card, isActionable: onPractice != nil)
                }
            }

            ForEach(missingScenarios) { scenario in
                row(for: scenario) {
                    ScenarioInvitationRow(scenario: scenario, isActionable: onPractice != nil)
                }
            }

            aggregateFooter
        }
    }

    private var missingScenarios: [PracticeScenario] {
        let practiced = Set(cards.map(\.scenario))
        return PracticeScenario.allCases.filter { $0.isCore && !practiced.contains($0) }
    }

    /// A row that starts practice when the root can route it, otherwise a
    /// row that only reads.
    @ViewBuilder
    private func row<RowContent: View>(for scenario: PracticeScenario, @ViewBuilder label: () -> RowContent) -> some View {
        if let onPractice {
            Button {
                Haptics.light()
                onPractice(scenario)
            } label: {
                label()
                    .contentShape(.rect)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Starts a \(scenario.title.lowercased()) prompt")
        } else {
            label()
        }
    }

    /// The former aggregate Interview Readiness survives as this quiet footer
    /// line - present for anyone who wants the composite, never competing
    /// with the per-scenario verdicts above it.
    @ViewBuilder
    private var aggregateFooter: some View {
        if let overallScore {
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
            .padding(.horizontal, ScenarioRowLayout.padding)
            .padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Combined readiness \(overallScore) of 100 across \(analyzedSessions) analyzed sessions.")
        }
    }
}

// MARK: - Row Layout

private enum ScenarioRowLayout {
    static let padding: CGFloat = 14
    static let chipSize: CGFloat = 30
    static let chipSpacing: CGFloat = 12
    /// Where row text starts, so the group's hairlines line up with it.
    static let textInset: CGFloat = padding + chipSize + chipSpacing
}

// MARK: - Scenario Tint

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
/// this verdict twice (the hero's filled pill and this section's inline glyph),
/// and each used to carry its own switch. They had already drifted: slipping
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

    var tint: Color {
        switch self {
        case .improving: return AppColors.success
        case .steady: return Color.white.opacity(0.45)
        case .slipping: return AppColors.warning
        }
    }
}

private struct MomentumGlyph: View {
    let momentum: ScenarioMomentum

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: momentum.symbolName)
                .font(.caption2.weight(.bold))
            Text(momentum.label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(momentum.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentum \(momentum.label.lowercased())")
    }
}

/// The trailing mark of a row that starts practice.
private struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Scenario Row

private struct ScenarioRow: View {
    let readiness: ScenarioReadiness
    var isActionable = false

    private var tint: Color { ScenarioTint.color(for: readiness.scenario) }

    private var scoreColor: Color {
        guard let score = readiness.score else { return tint }
        return AppColors.scoreColor(for: score)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .top, spacing: ScenarioRowLayout.chipSpacing) {
                IconChip(icon: readiness.scenario.icon, tint: tint, size: ScenarioRowLayout.chipSize)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(readiness.scenario.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        MomentumGlyph(momentum: readiness.momentum)

                        // A dash, not "N/A": the meta line already says the
                        // bucket needs more language before it can score.
                        Text(readiness.score.map(String.init) ?? "–")
                            .font(.statValue)
                            .foregroundStyle(scoreColor)
                            .contentTransition(.numericText())
                    }

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

            if isActionable {
                RowChevron()
            }
        }
        .padding(ScenarioRowLayout.padding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var metaLine: String {
        var parts = [readiness.bandLabel, sessionCountText]
        if readiness.isEarlyRead {
            parts.append("early read")
        }
        return parts.joined(separator: " · ")
    }

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
    var isActionable = false

    private var tint: Color { ScenarioTint.color(for: scenario) }

    var body: some View {
        HStack(spacing: ScenarioRowLayout.chipSpacing) {
            // Dimmed, not a second recipe: an unpracticed scenario wears the
            // same chip at lower strength.
            IconChip(icon: scenario.icon, tint: tint, size: ScenarioRowLayout.chipSize)
                .opacity(0.6)

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

            Text("Not yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isActionable {
                RowChevron()
            }
        }
        .padding(.horizontal, ScenarioRowLayout.padding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scenario.title): no sessions yet. \(scenario.blurb)")
    }
}
