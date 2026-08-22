import SwiftUI
import Charts

// MARK: - Language Insights View

/// Supporting detail under scenario readiness: the cross-session lexicon
/// profile plus the Word Bank practice words. This tab is deliberately the
/// ONE language home on the Progress page — every section names what it
/// counts and why it matters, and suggestions read as sentences ("Try
/// instead: …"), never as unlabeled chips.
struct LanguageInsightsView: View {
    let profile: LexiconProfile?
    /// Saved Word Bank words spotted across takes. Lives here so the page
    /// has one word story instead of a lexicon tab plus an orphaned chip
    /// rail at the page tail.
    var vocabWords: [VocabCount] = []

    var body: some View {
        VStack(spacing: 12) {
            if let profile, profile.hasData {
                wordPrintHero(profile)

                if !profile.crutchWords.isEmpty {
                    crutchWordsCard(profile)
                }

                if !profile.powerVerbs.isEmpty || !profile.contentWords.isEmpty {
                    wordMixCard(profile)
                }

                if !vocabWords.isEmpty {
                    vocabPracticeCard
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
                GlassCardTitle("Your Language Print", icon: "character.magnify") {
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

                Text("Counts per 100 spoken words.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                GlassCardTitle("Crutch Words", icon: "exclamationmark.bubble.fill") {
                    Text("lower is better")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Words that soften a point instead of making it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(profile.crutchWords.prefix(6).enumerated()), id: \.element.id) { index, usage in
                        if index > 0 {
                            MetricRowDivider()
                        }

                        crutchRow(usage)
                    }
                }
            }
        }
    }

    private func crutchRow(_ usage: WordUsageSummary) -> some View {
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
                // Advice, not vocabulary. As capsules these sat one card above
                // the Word Mix chips and read as "more words you said" — and a
                // pill saying "cut it" is indistinguishable from a pill saying
                // "significant". As a sentence, the quoted entries are the
                // wording to borrow and the unquoted ones are the move to make.
                (
                    Text("Try instead  ").foregroundStyle(.tertiary)
                        + Text(usage.swapsPreview.joined(separator: "  ·  "))
                        .foregroundStyle(AppColors.primary)
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The interpunct scans well but VoiceOver reads it aloud.
                .accessibilityLabel("Try instead: \(usage.swapsPreview.joined(separator: ", "))")
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

    // MARK: Word mix

    /// Impact verbs and recurring topics in ONE card with labeled groups —
    /// the former two separate chip stacks read as two unexplained word
    /// lists; now the card says what each group is for.
    private func wordMixCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Word Mix", icon: "square.grid.2x2")

                if !profile.powerVerbs.isEmpty {
                    wordGroup(
                        label: "Impact verbs",
                        context: "Action words that land a result. These are what lift the Impact rate above.",
                        words: Array(profile.powerVerbs.prefix(15)),
                        tint: AppColors.success
                    )
                }

                if !profile.contentWords.isEmpty {
                    if !profile.powerVerbs.isEmpty {
                        MetricRowDivider()
                    }

                    wordGroup(
                        label: "Topics you return to",
                        context: "What your answers keep circling back to. A short list means a narrow story bank — worth widening before an interview.",
                        words: Array(profile.contentWords.prefix(12)),
                        tint: AppColors.primary
                    )
                }
            }
        }
    }

    /// Label, one line of why it matters, then the chips. One tint drives the
    /// label and its chips together — a group whose heading disagreed with its
    /// own chips is the drift this consolidation exists to prevent.
    private func wordGroup(
        label: String,
        context: String,
        words: [WordUsageSummary],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(context)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 8) {
                ForEach(words) { usage in
                    WordCountChip(word: usage.word, count: usage.count, color: tint)
                }
            }
        }
    }

    // MARK: Word Bank practice

    /// The user's saved practice words and how often they landed in real
    /// takes. Formerly a clipped chip rail at the very bottom of the page;
    /// here it sits inside the language story with one line of context.
    private var vocabPracticeCard: some View {
        let totalUses = vocabWords.reduce(0) { $0 + $1.count }

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassCardTitle("Word Bank in Practice", icon: "character.book.closed") {
                    Text("\(totalUses) uses")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Saved words from your daily workouts, counted across your takes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(vocabWords.prefix(15), id: \.word) { item in
                        WordCountChip(word: item.word, count: item.count, color: AppColors.categoryBrandBright)
                    }
                }
            }
        }
    }

    // MARK: Weekly trend

    private func trendCard(_ profile: LexiconProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Language Over Time", icon: "chart.line.uptrend.xyaxis") {
                    HStack(spacing: 10) {
                        legendDot(color: AppColors.categoryAmber, label: "Weak")
                        legendDot(color: AppColors.success, label: "Impact")
                    }
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
                .frame(height: TrendChart.plotHeight)
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
                GlassCardTitle("Coach Notes", icon: "lightbulb.fill")

                // Says only what `makeSuggestions` actually does: it fires a
                // fixed set of rules against the numbers on this page and
                // keeps the first four. It does NOT rank by impact, and the
                // list can include positive notes — so no "N things to fix".
                Text("What your numbers on this page add up to. At most four at a time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
