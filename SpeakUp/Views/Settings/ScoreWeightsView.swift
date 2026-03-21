import SwiftUI
import SwiftData

struct ScoreWeightsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingResetConfirmation = false
    @State private var didSave = false

    // Draft weights — not persisted until the user taps Save
    @State private var draftClarity: Double = 0.12
    @State private var draftPace: Double = 0.12
    @State private var draftFiller: Double = 0.12
    @State private var draftPause: Double = 0.10
    @State private var draftVocalVariety: Double = 0.14
    @State private var draftDelivery: Double = 0.10
    @State private var draftVocabulary: Double = 0.10
    @State private var draftStructure: Double = 0.10
    @State private var draftRelevance: Double = 0.10

    private var draftTotal: Double {
        draftClarity + draftPace + draftFiller + draftPause +
        draftVocalVariety + draftDelivery + draftVocabulary +
        draftStructure + draftRelevance
    }

    private var totalIsValid: Bool {
        Int(round(draftTotal * 100)) == 100
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

            ScrollView {
                VStack(spacing: 20) {
                    introCard
                    weightVisualization
                    subscoreInfoSection
                    sliderSection
                    saveButton
                    resetButton
                }
                .padding()
            }
            .scrollIndicators(.hidden)
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
        .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
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
                Label("How Your Score Works", systemImage: "function")
                    .font(.headline)

                Text("Your overall score is built in two stages. First, 9 subscores are combined using your weights. Then a Substance Gate multiplies the result based on speech length and content depth — so short or empty responses always score low regardless of weights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Weight Visualization

    private var weightVisualization: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weight Distribution")
                    .font(.subheadline.weight(.medium))

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

                // Legend
                FlowLayout(spacing: 6) {
                    ForEach(weightItems) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color.opacity(0.8))
                                .frame(width: 8, height: 8)
                            Text("\(item.name) \(Int(item.weight * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subscore Info

    private var subscoreInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What Each Score Measures", systemImage: "info.circle")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(subscoreDescriptions.enumerated()), id: \.element.name) { index, desc in
                        if index > 0 {
                            Divider().padding(.vertical, 6)
                        }

                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(desc.measures)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("How: \(desc.howCalculated)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: desc.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 20)

                                Text(desc.name)
                                    .font(.subheadline)

                                Spacer()

                                Text("\(Int(weightForSubscore(desc.key) * 100))%")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.teal)
                            }
                        }
                        .tint(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sliders

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Adjust Weights", systemImage: "slider.horizontal.3")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    weightSlider("Clarity", icon: "waveform", value: $draftClarity)
                    weightSlider("Pace", icon: "speedometer", value: $draftPace)
                    weightSlider("Filler Usage", icon: "text.badge.minus", value: $draftFiller)
                    weightSlider("Pauses", icon: "pause.circle", value: $draftPause)
                    weightSlider("Vocal Variety", icon: "waveform.path.ecg", value: $draftVocalVariety)
                    weightSlider("Delivery", icon: "speaker.wave.3", value: $draftDelivery)
                    weightSlider("Vocabulary", icon: "textformat.abc", value: $draftVocabulary)
                    weightSlider("Structure", icon: "list.bullet.indent", value: $draftStructure)
                    weightSlider("Relevance", icon: "target", value: $draftRelevance)

                    Divider()

                    totalRow
                }
            }
        }
    }

    private func weightSlider(_ name: String, icon: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 18)

                Text(name)
                    .font(.caption.weight(.medium))

                Spacer()

                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.teal)
                    .frame(width: 36, alignment: .trailing)
            }

            Slider(value: value, in: 0.0...0.30, step: 0.01)
                .tint(.teal)
                .onChange(of: value.wrappedValue) { _, _ in
                    didSave = false
                    Haptics.light()
                }
        }
    }

    private var totalRow: some View {
        let totalPercent = Int(round(draftTotal * 100))
        return VStack(spacing: 6) {
            HStack {
                Text("Total")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text("\(totalPercent)%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(totalIsValid ? .white : .orange)
            }

            if !totalIsValid {
                Text("Total must equal 100% to save. Currently \(totalPercent > 100 ? "over" : "under") by \(abs(totalPercent - 100))%.")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: totalIsValid)
    }

    // MARK: - Save

    private var saveButton: some View {
        VStack(spacing: 6) {
            GlassButton(title: "Save Weights", icon: "checkmark.circle", style: .primary) {
                Haptics.success()
                saveDraftToViewModel()
                didSave = true
            }
            .opacity(hasUnsavedChanges && totalIsValid ? 1.0 : 0.4)
            .disabled(!hasUnsavedChanges || !totalIsValid)

            if didSave {
                Text("Saved!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if hasUnsavedChanges && !totalIsValid {
                Text("Adjust weights to total 100% before saving.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if hasUnsavedChanges {
                Text("You have unsaved changes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: didSave)
        .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
    }

    // MARK: - Reset

    private var resetButton: some View {
        GlassButton(title: "Reset to Defaults", icon: "arrow.counterclockwise", style: .outline) {
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

    private var weightItems: [WeightItem] {
        [
            WeightItem(name: "Clarity", weight: draftClarity, color: .cyan),
            WeightItem(name: "Pace", weight: draftPace, color: .blue),
            WeightItem(name: "Filler", weight: draftFiller, color: .orange),
            WeightItem(name: "Pauses", weight: draftPause, color: .purple),
            WeightItem(name: "Vocal", weight: draftVocalVariety, color: .pink),
            WeightItem(name: "Delivery", weight: draftDelivery, color: .red),
            WeightItem(name: "Vocab", weight: draftVocabulary, color: .green),
            WeightItem(name: "Structure", weight: draftStructure, color: .yellow),
            WeightItem(name: "Relevance", weight: draftRelevance, color: .teal),
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
                measures: "Speaking speed and fluency. Optimal pace is conversational — not rushed or dragging.",
                howCalculated: "Bell curve comparison to your target WPM (65%), blended with rate variation bonus (20%) and fluency signals: Phonation Time Ratio and Mean Length of Run (15%)."
            ),
            SubscoreDescription(
                name: "Filler Usage", key: "filler", icon: "text.badge.minus",
                measures: "How often you use filler words like 'um', 'uh', 'like', and 'you know'.",
                howCalculated: "Uses a logarithmic curve so occasional fillers are okay, but frequent use and weak filler-like phrasing lower your score progressively."
            ),
            SubscoreDescription(
                name: "Pauses", key: "pause", icon: "pause.circle",
                measures: "Quality and placement of your pauses. Strategic pauses enhance speeches; awkward silences hurt them.",
                howCalculated: "Evaluates pause length, placement between ideas, and penalizes hesitation pauses or rushing without pauses."
            ),
            SubscoreDescription(
                name: "Vocal Variety", key: "vocalVariety", icon: "waveform.path.ecg",
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
