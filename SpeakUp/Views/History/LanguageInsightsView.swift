import SwiftUI
import Charts

// MARK: - Language Insights View

/// Supporting detail under scenario readiness: the cross-session lexicon
/// profile. The former aggregate Interview Readiness card and the By Practice
/// Type rows lived here; both are superseded by the per-scenario readiness
/// cards (`ScenarioReadinessSection`).
struct LanguageInsightsView: View {
    let profile: LexiconProfile?

    var body: some View {
        VStack(spacing: 12) {
            if let profile, profile.hasData {
                wordPrintHero(profile)

                if !profile.crutchWords.isEmpty {
                    crutchWordsCard(profile)
                }

                if !profile.powerVerbs.isEmpty {
                    powerVerbsCard(profile)
                }

                if !profile.contentWords.isEmpty {
                    commonWordsCard(profile)
                }

                if profile.trendPoints.count >= 2 {
                    trendCard(profile)
                }

                if !profile.suggestions.isEmpty {
                    suggestionsCard(profile)
                }
            } else {
                GlassCard {
                    EmptyStateInline(
                        icon: "textformat",
                        message: "Record a session and your word patterns, crutch words, and interview language land here."
                    )
                }
            }
        }
    }

    // MARK: Word print hero

    private func wordPrintHero(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Your Language Print", systemImage: "character.magnify")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(profile.totalWords) words tracked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    rateStat(
                        title: "Weak language",
                        value: String(format: "%.1f", profile.weakRate),
                        color: AppColors.categoryAmber,
                        delta: -profile.weakRateDelta
                    )

                    Spacer()

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 0.5, height: 56)

                    Spacer()

                    rateStat(
                        title: "Impact verbs",
                        value: String(format: "%.1f", profile.powerRate),
                        color: AppColors.success,
                        delta: profile.powerRateDelta,
                        alignment: .trailing
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Language print: weak language \(String(format: "%.1f", profile.weakRate)) per 100 words, impact verbs \(String(format: "%.1f", profile.powerRate)) per 100 words."
        )
    }

    private func rateStat(
        title: String,
        value: String,
        color: Color,
        delta: Double,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            StatPair(value: value, label: title, valueColor: color, alignment: alignment)

            deltaCaption(delta)
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
        }
    }

    @ViewBuilder
    private func deltaCaption(_ delta: Double) -> some View {
        if abs(delta) >= 0.3 {
            Label(
                "\(delta > 0 ? "+" : "")\(String(format: "%.1f", delta)) recent half",
                systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(delta > 0 ? AppColors.success : AppColors.error)
        } else {
            Text("steady")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Crutch words

    private func crutchWordsCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Crutch Words", systemImage: "exclamationmark.bubble.fill")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("lower is better")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(profile.crutchWords.prefix(6).enumerated()), id: \.element.id) { index, usage in
                        if index > 0 {
                            MetricRowDivider()
                        }

                        crutchRow(rank: index + 1, usage: usage)
                    }
                }
            }
        }
    }

    private func crutchRow(rank: Int, usage: WordUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\u{201C}\(usage.word)\u{201D}")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                StatusPill(
                    text: categoryLabel(usage.category),
                    color: categoryColor(usage.category),
                    fillOpacity: 0.2
                )

                Spacer(minLength: 6)

                directionBadge(usage.direction)

                Text("\(usage.count)\u{00D7}")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.warning)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(usage.word), \(categoryLabel(usage.category)), \(usage.count) times, \(directionLabel(usage.direction)).")

            if !usage.swapsPreview.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(usage.swapsPreview, id: \.self) { swap in
                        Text(swap)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AppColors.primary.opacity(0.13)))
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryLabel(_ category: CrutchCategory?) -> String {
        category?.label ?? "Habit"
    }

    private func categoryColor(_ category: CrutchCategory?) -> Color {
        category?.badgeColor ?? AppColors.info
    }

    @ViewBuilder
    private func directionBadge(_ direction: UsageDirection) -> some View {
        switch direction {
        case .rising:
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.error)
                .accessibilityLabel("rising")
        case .falling:
            Image(systemName: "arrow.down.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.success)
                .accessibilityLabel("falling")
        case .steady:
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityLabel("steady")
        }
    }

    private func directionLabel(_ direction: UsageDirection) -> String {
        direction.rawValue
    }

    // MARK: Power verbs

    private func powerVerbsCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Impact Verbs You Lean On", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("higher is better")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                FlowLayout(spacing: 8) {
                    ForEach(profile.powerVerbs.prefix(15)) { usage in
                        WordCountChip(word: usage.word, count: usage.count, color: AppColors.success)
                    }
                }
            }
        }
    }

    // MARK: Most used words

    private func commonWordsCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Most Used Content Words", systemImage: "text.justify.left")
                    .font(.subheadline.weight(.semibold))

                FlowLayout(spacing: 8) {
                    ForEach(profile.contentWords.prefix(12)) { usage in
                        WordCountChip(word: usage.word, count: usage.count, color: AppColors.primary, showsBadge: false)
                    }
                }
            }
        }
    }

    // MARK: Weekly trend

    private func trendCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Language Over Time", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    legendDot(color: AppColors.categoryAmber, label: "Weak")
                    legendDot(color: AppColors.success, label: "Impact")
                }

                Chart {
                    ForEach(profile.trendPoints.sorted { $0.weekStart < $1.weekStart }) { point in
                        LineMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Rate", point.weakRate),
                            series: .value("Metric", "Weak")
                        )
                        .foregroundStyle(AppColors.categoryAmber)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Rate", point.powerRate),
                            series: .value("Metric", "Power")
                        )
                        .foregroundStyle(AppColors.success)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .accessibilityLabel(
                    "Weekly weak language versus impact verb rates across \(profile.trendPoints.count) weeks."
                )

                Text("Weak = fillers, hedges, softeners, vague nouns per 100 words. Impact = action verbs per 100.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Suggestions

    private func suggestionsCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Coach Notes", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))

                VStack(spacing: 0) {
                    ForEach(Array(profile.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        if index > 0 {
                            MetricRowDivider()
                                .padding(.vertical, 8)
                        }

                        suggestionRow(suggestion)
                    }
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: LexiconSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toneColor(suggestion.tone))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(toneColor(suggestion.tone).opacity(0.13))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(suggestion.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func toneColor(_ tone: LexiconSuggestion.Tone) -> Color {
        switch tone {
        case .focus: return AppColors.primary
        case .warning: return AppColors.warning
        case .positive: return AppColors.success
        }
    }
}

// MARK: - Swaps preview

private extension WordUsageSummary {
    /// First few alternatives shown inline on the Words tab; the full list
    /// lives in the engine map and surfaces on the session card.
    var swapsPreview: [String] {
        Array((LexiconInsightsEngine.alternativesFor(word) ?? []).prefix(3))
    }
}
