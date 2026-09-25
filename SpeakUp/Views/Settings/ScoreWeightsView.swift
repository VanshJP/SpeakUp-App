import SwiftUI

struct ScoreWeightsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingResetConfirmation = false
    @State private var didSave = false

    // Draft weights - not persisted until the user taps Save
    @State private var draftClarity: Double
    @State private var draftPace: Double
    @State private var draftFiller: Double
    @State private var draftPause: Double
    @State private var draftVocalVariety: Double
    @State private var draftDelivery: Double
    @State private var draftVocabulary: Double
    @State private var draftStructure: Double
    @State private var draftRelevance: Double

    /// Drafts start at the stored weights. They used to start at constants
    /// and jump on appear, which fired every slider's step haptic at once.
    init(viewModel: SettingsViewModel) {
        _viewModel = Bindable(viewModel)
        _draftClarity = State(initialValue: viewModel.clarityWeight)
        _draftPace = State(initialValue: viewModel.paceWeight)
        _draftFiller = State(initialValue: viewModel.fillerWeight)
        _draftPause = State(initialValue: viewModel.pauseWeight)
        _draftVocalVariety = State(initialValue: viewModel.vocalVarietyWeight)
        _draftDelivery = State(initialValue: viewModel.deliveryWeight)
        _draftVocabulary = State(initialValue: viewModel.vocabularyWeight)
        _draftStructure = State(initialValue: viewModel.structureWeight)
        _draftRelevance = State(initialValue: viewModel.relevanceWeight)
    }

    private var draftTotal: Double {
        draftClarity + draftPace + draftFiller + draftPause +
        draftVocalVariety + draftDelivery + draftVocabulary +
        draftStructure + draftRelevance
    }

    /// Weights are relative: `SpeechService.calculateOverallScore` normalizes
    /// them (`ScoreWeights.normalized`), so any mix is valid as long as one
    /// skill counts at all. Save used to stay locked until nine sliders summed
    /// to exactly 100%, which only restated what scoring already does.
    private var canSave: Bool {
        hasUnsavedChanges && draftTotal > 0.0001
    }

    /// A weight's share of the overall score, as the scorer will apply it.
    private func share(_ weight: Double) -> Int {
        guard draftTotal > 0 else { return 0 }
        return Int((weight / draftTotal * 100).rounded())
    }

    private var hasUnsavedChanges: Bool {
        abs(draftClarity - viewModel.clarityWeight) > 0.001 ||
        abs(draftPace - viewModel.paceWeight) > 0.001 ||
        abs(draftFiller - viewModel.fillerWeight) > 0.001 ||
        abs(draftPause - viewModel.pauseWeight) > 0.001 ||
        abs(draftVocalVariety - viewModel.vocalVarietyWeight) > 0.001 ||
        abs(draftDelivery - viewModel.deliveryWeight) > 0.001 ||
        abs(draftVocabulary - viewModel.vocabularyWeight) > 0.001 ||
        abs(draftStructure - viewModel.structureWeight) > 0.001 ||
        abs(draftRelevance - viewModel.relevanceWeight) > 0.001
    }

    private var hasDraftCustomWeights: Bool {
        let d = ScoreWeights.defaults
        return abs(draftClarity - d.clarity) > 0.001 || abs(draftPace - d.pace) > 0.001 ||
               abs(draftFiller - d.filler) > 0.001 || abs(draftPause - d.pause) > 0.001 ||
               abs(draftVocalVariety - d.vocalVariety) > 0.001 || abs(draftDelivery - d.delivery) > 0.001 ||
               abs(draftVocabulary - d.vocabulary) > 0.001 || abs(draftStructure - d.structure) > 0.001 ||
               abs(draftRelevance - d.relevance) > 0.001
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: AppLayout.chapterSpacing) {
                    introCard
                    weightVisualization
                    subscoreInfoSection
                    sliderSection
                    resetButton
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
            // Save rides under the sliders instead of eighteen rows below them.
            .safeAreaBar(edge: .bottom) { saveBar }
        }
        .navigationTitle("Score Weights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            syncDraftFromViewModel()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if !isLoading {
                syncDraftFromViewModel()
            }
        }
        .alert("Reset weights?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Haptics.success()
                resetDraftToDefaults()
            }
        } message: {
            Text("This will restore all weights to their default values. Press Save to apply.")
        }
    }

    // MARK: - Draft Sync

    private func syncDraftFromViewModel() {
        draftClarity = viewModel.clarityWeight
        draftPace = viewModel.paceWeight
        draftFiller = viewModel.fillerWeight
        draftPause = viewModel.pauseWeight
        draftVocalVariety = viewModel.vocalVarietyWeight
        draftDelivery = viewModel.deliveryWeight
        draftVocabulary = viewModel.vocabularyWeight
        draftStructure = viewModel.structureWeight
        draftRelevance = viewModel.relevanceWeight
    }

    private func saveDraftToViewModel() {
        viewModel.clarityWeight = draftClarity
        viewModel.paceWeight = draftPace
        viewModel.fillerWeight = draftFiller
        viewModel.pauseWeight = draftPause
        viewModel.vocalVarietyWeight = draftVocalVariety
        viewModel.deliveryWeight = draftDelivery
        viewModel.vocabularyWeight = draftVocabulary
        viewModel.structureWeight = draftStructure
        viewModel.relevanceWeight = draftRelevance
        Task { await viewModel.saveSettings() }
    }

    private func resetDraftToDefaults() {
        let d = ScoreWeights.defaults
        draftClarity = d.clarity
        draftPace = d.pace
        draftFiller = d.filler
        draftPause = d.pause
        draftVocalVariety = d.vocalVariety
        draftDelivery = d.delivery
        draftVocabulary = d.vocabulary
        draftStructure = d.structure
        draftRelevance = d.relevance
    }

    // MARK: - Intro Card

    private var introCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassCardTitle("How your score works")

                Text("Your overall score is built in two stages. First, 9 subscores are combined using your weights. Then a Substance Gate multiplies the result based on speech length and content depth, so short or empty responses always score low regardless of weights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Weight Visualization

    private var weightVisualization: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Weight distribution")

                GeometryReader { geo in
                    let items = weightItems
                    let total = items.reduce(0.0) { $0 + $1.weight }
                    HStack(spacing: 1) {
                        ForEach(items) { item in
                            let fraction = total > 0 ? item.weight / total : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.color.opacity(0.8))
                                .frame(width: max(2, geo.size.width * fraction - 1))
                        }
                    }
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

                FlowLayout(spacing: 6) {
                    ForEach(weightItems) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color.opacity(0.8))
                                .frame(width: 8, height: 8)
                            Text("\(item.name) \(share(item.weight))%")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subscore Info

    private var subscoreInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("What each score measures")

            GlassRowGroup(dividerInset: 14) {
                ForEach(subscoreDescriptions, id: \.name) { desc in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(desc.measures)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("How: \(desc.howCalculated)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 8) {
                            Label(desc.name, systemImage: desc.icon)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(share(weightForSubscore(desc.key)))%")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: AppLayout.minHitTarget)
                    }
                    .tint(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Sliders

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Adjust weights")

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    weightSlider("Clarity", icon: "waveform", tone: 0, value: $draftClarity)
                    weightSlider("Pace", icon: "speedometer", tone: 1, value: $draftPace)
                    weightSlider("Filler usage", icon: "text.badge.minus", tone: 2, value: $draftFiller)
                    weightSlider("Pauses", icon: "pause.circle", tone: 3, value: $draftPause)
                    weightSlider("Vocal variety", icon: "waveform.path.ecg", tone: 4, value: $draftVocalVariety)
                    weightSlider("Delivery", icon: "speaker.wave.3", tone: 5, value: $draftDelivery)
                    weightSlider("Vocabulary", icon: "textformat.abc", tone: 6, value: $draftVocabulary)
                    weightSlider("Structure", icon: "list.bullet.indent", tone: 7, value: $draftStructure)
                    weightSlider("Relevance", icon: "target", tone: 8, value: $draftRelevance)

                    Divider()

                    Text(draftTotal > 0.0001
                         ? "Weights are relative. Raising one lowers the share of every other skill; each percentage is that skill's share of your score."
                         : "Give at least one skill some weight.")
                        .font(.caption)
                        .foregroundStyle(draftTotal > 0.0001 ? Color.secondary : AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// `tone` matches the legend above, so a slider and its slice of the bar
    /// read as the same thing.
    private func weightSlider(_ name: String, icon: String, tone: Int, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(name, systemImage: icon)
                    .font(.caption.weight(.medium))

                Spacer()

                Text("\(share(value.wrappedValue))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 40, alignment: .trailing)
            }
            .accessibilityHidden(true)

            Slider(value: value, in: 0.0...0.30, step: 0.01)
                .tint(AppColors.subscoreTone(tone))
                .accessibilityLabel(name)
                .accessibilityValue("\(share(value.wrappedValue)) percent of your score")
                .onChange(of: value.wrappedValue) { _, _ in
                    didSave = false
                    Haptics.light()
                }
        }
    }

    // MARK: - Save

    @ViewBuilder
    private var saveBar: some View {
        if hasUnsavedChanges || didSave {
            VStack(spacing: 6) {
                if hasUnsavedChanges {
                    GlassButton(title: "Save weights", icon: "checkmark.circle", style: .primary, fullWidth: true) {
                        Haptics.success()
                        saveDraftToViewModel()
                        didSave = true
                    }
                    .opacity(canSave ? 1.0 : 0.4)
                    .disabled(!canSave)
                } else {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.success)
                        .frame(minHeight: AppLayout.minHitTarget)
                }
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.bottom, 8)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        GlassButton(title: "Reset to defaults", icon: "arrow.counterclockwise", style: .outline) {
            Haptics.warning()
            showingResetConfirmation = true
        }
        .opacity(hasDraftCustomWeights ? 1.0 : 0.4)
        .disabled(!hasDraftCustomWeights)
    }

    // MARK: - Helpers

    private struct WeightItem: Identifiable {
        let name: String
        let weight: Double
        let color: Color
        var id: String { name }
    }

    /// Identity tones, not judgement. These distinguish nine weights from one
    /// another - they must never be read as good/bad, which is why they come
    /// from the muted jewel set rather than the score ramp. The previous
    /// mapping used seven raw system hues and rendered as a rainbow.
    private var weightItems: [WeightItem] {
        [
            WeightItem(name: "Clarity", weight: draftClarity, color: AppColors.subscoreTone(0)),
            WeightItem(name: "Pace", weight: draftPace, color: AppColors.subscoreTone(1)),
            WeightItem(name: "Filler", weight: draftFiller, color: AppColors.subscoreTone(2)),
            WeightItem(name: "Pauses", weight: draftPause, color: AppColors.subscoreTone(3)),
            WeightItem(name: "Vocal", weight: draftVocalVariety, color: AppColors.subscoreTone(4)),
            WeightItem(name: "Delivery", weight: draftDelivery, color: AppColors.subscoreTone(5)),
            WeightItem(name: "Vocab", weight: draftVocabulary, color: AppColors.subscoreTone(6)),
            WeightItem(name: "Structure", weight: draftStructure, color: AppColors.subscoreTone(7)),
            WeightItem(name: "Relevance", weight: draftRelevance, color: AppColors.subscoreTone(8)),
        ]
    }

    private struct SubscoreDescription {
        let name: String
        let key: String
        let icon: String
        let measures: String
        let howCalculated: String
    }

    private var subscoreDescriptions: [SubscoreDescription] {
        [
            SubscoreDescription(
                name: "Clarity", key: "clarity", icon: "waveform",
                measures: "How clearly you articulate words. Clear pronunciation makes your message easier to understand.",
                howCalculated: "Combines voiced frame ratio (articulation quality), word duration consistency, ASR word confidence, hedge word penalty, and an authority score from language analysis."
            ),
            SubscoreDescription(
                name: "Pace", key: "pace", icon: "speedometer",
                measures: "Speaking speed and fluency. Optimal pace is conversational, not rushed or dragging.",
                howCalculated: "Gaussian comparison to your target WPM (wider tolerance ±30 WPM), with optional rate variation (18%) and fluency signals (14%) blended in when available."
            ),
            SubscoreDescription(
                name: "Filler usage", key: "filler", icon: "text.badge.minus",
                measures: "How often you use filler words like 'um', 'uh', 'like', and 'you know'.",
                howCalculated: "Uses a gentle logarithmic curve: occasional fillers (under 3%) barely affect the score, while frequent use lowers it progressively."
            ),
            SubscoreDescription(
                name: "Pauses", key: "pause", icon: "pause.circle",
                measures: "Quality and placement of your pauses. Strategic pauses enhance speeches; awkward silences hurt them.",
                howCalculated: "Evaluates pause length, placement between ideas, and penalizes hesitation pauses or rushing without pauses."
            ),
            SubscoreDescription(
                name: "Vocal variety", key: "vocalVariety", icon: "waveform.path.ecg",
                measures: "How dynamically you vary your pitch, volume, and speaking rate throughout your speech.",
                howCalculated: "Combines pitch variation, volume dynamics, rate variation, and pitch-energy correlation scores."
            ),
            SubscoreDescription(
                name: "Delivery", key: "delivery", icon: "speaker.wave.3",
                measures: "Your overall energy, emphasis on key points, and presentation arc from opening to close.",
                howCalculated: "Weighs energy level, volume variation, content density, emphasis distribution, energy arc shape, and language engagement signals."
            ),
            SubscoreDescription(
                name: "Vocabulary", key: "vocabulary", icon: "textformat.abc",
                measures: "Word choice sophistication and diversity. Using varied, precise words improves this score.",
                howCalculated: "Blends MATTR (Moving Average Type-Token Ratio, the academic standard for lexical diversity), word rarity via on-device language model, repetition penalty, and word length diversity. MATTR is length-invariant so longer speeches are not penalized."
            ),
            SubscoreDescription(
                name: "Structure", key: "structure", icon: "list.bullet.indent",
                measures: "Sentence organization, flow, and rhetorical quality of your speech.",
                howCalculated: "Evaluates sentence variety, completeness, rhetorical devices, transition usage, plus conciseness and audience engagement quality."
            ),
            SubscoreDescription(
                name: "Relevance", key: "relevance", icon: "target",
                measures: "How well your speech stays on topic (with a prompt) or maintains internal coherence (free practice).",
                howCalculated: "Uses keyword overlap, semantic similarity, and sentence alignment to measure topic relevance or coherence."
            ),
        ]
    }

    private func weightForSubscore(_ key: String) -> Double {
        switch key {
        case "clarity": return draftClarity
        case "pace": return draftPace
        case "filler": return draftFiller
        case "pause": return draftPause
        case "vocalVariety": return draftVocalVariety
        case "delivery": return draftDelivery
        case "vocabulary": return draftVocabulary
        case "structure": return draftStructure
        case "relevance": return draftRelevance
        default: return 0
        }
    }
}
