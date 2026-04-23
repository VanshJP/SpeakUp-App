import SwiftUI

struct DetailAnalysisTab: View {
    let recording: Recording
    var showingScoreWeights: Binding<Bool>

    var body: some View {
        if let analysis = recording.analysis {
            subscoresSection(analysis)
            pauseAnalysisSection(analysis)

            if let volume = analysis.volumeMetrics {
                volumeSection(volume)
            }
            if let vocab = analysis.vocabComplexity {
                vocabComplexitySection(vocab)
            }
            if let sentence = analysis.sentenceAnalysis {
                sentenceAnalysisSection(sentence)
            }
            if analysis.speechScore.subscores.vocalVariety != nil {
                vocalVarietySection(analysis)
            }
            if let textQuality = analysis.textQuality {
                textQualitySection(textQuality)
            }
            if let energyArc = analysis.energyArc {
                energyArcSection(energyArc)
            }
            if let em = analysis.enhancedMetrics {
                enhancedMetricsSection(em)
            }
        }
    }

    // MARK: - Subscores Section

    @ViewBuilder
    private func subscoresSection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Score Breakdown", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showingScoreWeights.wrappedValue = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            GlassCard {
                VStack(spacing: 16) {
                    SubscoreRow(title: "Clarity", score: analysis.speechScore.subscores.clarity, icon: "waveform")
                    SubscoreRow(title: "Pace", score: analysis.speechScore.subscores.pace, icon: "speedometer")
                    SubscoreRow(title: "Filler Usage", score: analysis.speechScore.subscores.fillerUsage, icon: "text.badge.minus")
                    SubscoreRow(title: "Pauses", score: analysis.speechScore.subscores.pauseQuality, icon: "pause.circle")

                    if let vocalVariety = analysis.speechScore.subscores.vocalVariety {
                        SubscoreRow(title: "Vocal Variety", score: vocalVariety, icon: "waveform.path.ecg")
                    }
                    if let delivery = analysis.speechScore.subscores.delivery {
                        SubscoreRow(title: "Delivery", score: delivery, icon: "speaker.wave.3")
                    }
                    if let vocabulary = analysis.speechScore.subscores.vocabulary {
                        SubscoreRow(title: "Vocabulary", score: vocabulary, icon: "textformat.abc")
                    }
                    if let structure = analysis.speechScore.subscores.structure {
                        SubscoreRow(title: "Structure", score: structure, icon: "list.bullet.indent")
                    }
                    if let relevance = analysis.speechScore.subscores.relevance {
                        let isRelevanceScore = analysis.promptRelevanceScore != nil && recording.prompt != nil
                        SubscoreRow(
                            title: isRelevanceScore ? "Relevance" : "Coherence",
                            score: relevance,
                            icon: isRelevanceScore ? "target" : "arrow.triangle.branch"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Pause Analysis Section

    @ViewBuilder
    private func pauseAnalysisSection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pause Analysis", systemImage: "pause.circle.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strategic Pauses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("\(analysis.strategicPauseCount)")
                                    .font(.title3.weight(.semibold))
                                Text("for emphasis")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Hesitations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("\(analysis.hesitationPauseCount)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(analysis.hesitationPauseCount > 3 ? .orange : .primary)
                                Text("mid-sentence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if analysis.averagePauseLength > 0 {
                        HStack {
                            Text("Average pause")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f seconds", analysis.averagePauseLength))
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Volume Section

    @ViewBuilder
    private func volumeSection(_ volume: VolumeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Volume & Energy", systemImage: "speaker.wave.3.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 16) {
                    SubscoreRow(title: "Energy Level", score: volume.energyScore, icon: "bolt.fill")
                    SubscoreRow(title: "Volume Dynamics", score: volume.monotoneScore, icon: "waveform.path.ecg")
                }
            }
        }
    }

    // MARK: - Vocal Variety Section

    @ViewBuilder
    private func vocalVarietySection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vocal Variety", systemImage: "waveform.path.ecg")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What this means")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Vocal variety blends pitch movement, pace changes, and emphasis so your delivery sounds dynamic instead of flat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                    if let vv = analysis.speechScore.subscores.vocalVariety {
                        SubscoreRow(title: "Overall Variety", score: vv, icon: "waveform.path.ecg")
                    }

                    if let pitch = analysis.pitchMetrics {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pitch Range")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f semitones", pitch.f0RangeSemitones))
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Avg Pitch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f Hz", pitch.f0Mean))
                                    .font(.subheadline.weight(.medium))
                            }
                        }

                        SubscoreRow(title: "Pitch Variation", score: pitch.pitchVariationScore, icon: "music.note")
                    }

                    if let rv = analysis.rateVariation, rv.rateCV > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rate Range")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f WPM spread", rv.rateRange))
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Articulation Rate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f WPM", rv.articulationRate))
                                    .font(.subheadline.weight(.medium))
                            }
                        }

                        SubscoreRow(title: "Rate Variation", score: rv.rateVariationScore, icon: "speedometer")
                    }

                    if let em = analysis.emphasisMetrics, em.emphasisCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Emphasis Points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(em.emphasisCount)")
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Per Minute")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f", em.emphasisPerMinute))
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Distribution")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(emphasisDistributionLabel(em.distributionScore))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppColors.scoreColor(for: em.distributionScore))
                            }
                        }
                    }
                }
            }
        }
    }

    private func emphasisDistributionLabel(_ score: Int) -> String {
        if score >= 75 { return "Well Spread" }
        if score >= 50 { return "Moderate" }
        return "Clustered"
    }

    // MARK: - Vocab Complexity Section

    @ViewBuilder
    private func vocabComplexitySection(_ vocab: VocabComplexity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vocabulary", systemImage: "textformat.abc")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Complexity", score: vocab.complexityScore, icon: "textformat.abc")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unique words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(vocab.uniqueWordCount) (\(Int(vocab.uniqueWordRatio * 100))%)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Avg word length")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f chars", vocab.averageWordLength))
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    if !vocab.repeatedPhrases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repeated phrases")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(vocab.repeatedPhrases.prefix(3), id: \.phrase) { phrase in
                                HStack {
                                    Text("\"\(phrase.phrase)\"")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(phrase.count)×")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sentence Analysis Section

    @ViewBuilder
    private func sentenceAnalysisSection(_ sentence: SentenceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sentence Structure", systemImage: "text.alignleft")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Structure Score", score: sentence.structureScore, icon: "text.alignleft")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sentences")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.totalSentences)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("Restarts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.restartCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(sentence.restartCount > 3 ? .orange : .primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Incomplete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.incompleteSentences)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(sentence.incompleteSentences > 2 ? .orange : .primary)
                        }
                    }

                    if !sentence.restartExamples.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Example restarts")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(sentence.restartExamples.prefix(2), id: \.self) { example in
                                Text("\"\(example)\"")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Text Quality Section

    @ViewBuilder
    private func textQualitySection(_ tq: TextQualityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Language Quality", systemImage: "text.magnifyingglass")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Authority", score: tq.authorityScore, icon: "shield.checkered")
                    SubscoreRow(title: "Craft", score: tq.craftScore, icon: "paintbrush.pointed")
                    SubscoreRow(title: "Conciseness", score: tq.concisenessScore, icon: "scissors")
                    SubscoreRow(title: "Engagement", score: tq.engagementScore, icon: "person.3.sequence")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Power Words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text("\(tq.powerWordCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                                Text("used")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Hedge Words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text("\(tq.hedgeWordCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tq.hedgeWordCount > 5 ? .orange : .primary)
                                Text("found")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weak Phrases")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(tq.weakPhraseCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(tq.weakPhraseCount > 3 ? .orange : .primary)
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("Repeated Starts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(tq.repeatedSentenceStartCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(tq.repeatedSentenceStartCount > 1 ? .orange : .primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(tq.rhetoricalQuestionCount)")
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rhetorical Devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(tq.rhetoricalDeviceCount)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Transition Variety")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(tq.transitionVariety) types")
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    HStack {
                        Text("Calls to Action")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(tq.callToActionCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tq.callToActionCount > 0 ? .green : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - Energy Arc Section

    @ViewBuilder
    private func energyArcSection(_ arc: EnergyArcMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Energy Arc", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Arc Score", score: arc.arcScore, icon: "chart.line.uptrend.xyaxis")

                    HStack(spacing: 12) {
                        energyBar(label: "Opening", value: arc.openingEnergy)
                        energyBar(label: "Body", value: arc.bodyEnergy)
                        energyBar(label: "Closing", value: arc.closingEnergy)
                    }
                    .frame(height: 80)

                    if arc.hasClimax {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("Dynamic range detected — your energy builds and releases effectively")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Enhanced Metrics Section (MATTR, PTR, MLR, Substance)

    @ViewBuilder
    private func enhancedMetricsSection(_ em: EnhancedSpeechMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speech Depth", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Substance", score: em.substanceScore, icon: "text.word.spacing")
                    SubscoreRow(title: "Fluency", score: em.fluencyScore, icon: "waveform.and.mic")
                    SubscoreRow(title: "Lexical Sophistication", score: em.lexicalSophisticationScore, icon: "textformat.abc.dottedunderline")

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MATTR")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f", em.mattr))
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("Phonation Ratio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", em.phonationTimeRatio * 100))
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Mean Run")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f wds", em.meanLengthOfRun))
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What these mean")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("MATTR measures vocabulary diversity (higher = more varied). Phonation Ratio is the fraction of time you were speaking (0.55-0.75 is ideal). Mean Run is average words between pauses (higher = more fluent).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func energyBar(label: String, value: Double) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.4), Color.teal],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(4, geometry.size.height * CGFloat(value)))
                }
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(Int(value * 100))%")
                .font(.caption.weight(.medium).monospacedDigit())
        }
    }
}
