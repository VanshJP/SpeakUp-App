import SwiftUI
import SwiftData

struct ComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = ComparisonViewModel()

    var body: some View {
        PageScrollView {
            VStack(spacing: AppLayout.listSpacing) {
                if !viewModel.isLoaded {
                    VoiceLoader(size: .large)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                } else if viewModel.summaries.count >= 2 {
                    heroSummarySection

                    selectorSection

                    if !viewModel.deltas.isEmpty {
                        breakdownSection
                    }
                } else {
                    EmptyStateCard(
                        icon: "chart.bar.xaxis",
                        title: "Not enough takes yet",
                        message: "Compare needs two scored takes. Record another and it lines them up here."
                    )
                }
            }
            .padding(.top, 8)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .appBackground(.subtle)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let card = viewModel.progressCard {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.medium()
                        ProgressCardRenderer.share(card, trigger: "compare") {
                            if ReviewRequestService.shared.requestIfEligible(
                                .shareCompleted,
                                settings: userSettings.first
                            ) {
                                try? modelContext.save()
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share progress card")
                }
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Hero Summary

    private var heroSummarySection: some View {
        let scoreA = viewModel.scoreA
        let scoreB = viewModel.scoreB
        let change = scoreB - scoreA
        // A drop is amber, never red; no change is neither colour.
        let changeColor: Color = change > 0 ? AppColors.success : change < 0 ? AppColors.warning : .secondary

        return FeaturedGlassCard {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Score change")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Text(change == 0 ? "No change" : "\(change > 0 ? "+" : "")\(change) points")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(changeColor)
                            .contentTransition(.numericText())
                    }

                    Spacer()

                    Image(systemName: change > 0 ? "arrow.up.right.circle.fill" : change < 0 ? "arrow.down.right.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(changeColor)
                        .opacity(0.8)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 12) {
                    StatPair(
                        value: "\(scoreA)",
                        label: "From",
                        valueColor: AppColors.scoreColor(for: scoreA),
                        valueFont: .title3.weight(.bold).monospacedDigit()
                    )
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColors.scoreColor(for: scoreA).opacity(0.6),
                                        AppColors.scoreColor(for: scoreB).opacity(0.6)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: scoreB))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                    StatPair(
                        value: "\(scoreB)",
                        label: "To",
                        valueColor: AppColors.scoreColor(for: scoreB),
                        valueFont: .title3.weight(.bold).monospacedDigit()
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
                // Painted, not glass: a second glassEffect on this card samples
                // the card and renders as a murky band (design rule 13b).
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Selector Section

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Takes")

            HStack(spacing: 12) {
                RecordingPicker(
                    label: "From",
                    icon: "a.circle.fill",
                    color: AppColors.primary,
                    selectionID: $viewModel.selectionA,
                    points: viewModel.summaries
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                RecordingPicker(
                    label: "To",
                    icon: "b.circle.fill",
                    color: AppColors.categoryBrandBright,
                    selectionID: $viewModel.selectionB,
                    points: viewModel.summaries
                )
            }
        }
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Breakdown")

            GlassRowGroup(dividerInset: 54) {
                ForEach(viewModel.deltas, id: \.label) { delta in
                    ComparisonMetricRow(delta: delta)
                }
            }
        }
    }
}

// MARK: - Comparison Metric Row

private struct ComparisonMetricRow: View {
    let delta: ComparisonViewModel.Delta

    private var metricIcon: String {
        switch delta.label {
        case "Score": return "star.fill"
        case "WPM": return "metronome"
        case "Fillers": return "bubble.left.fill"
        case "Clarity": return "waveform"
        case "Pace": return "speedometer"
        case "Pauses": return "pause.circle.fill"
        default: return "circle.fill"
        }
    }

    private var changeWord: String {
        switch delta.improved {
        case .some(true): return "improved"
        case .some(false): return "slipped"
        case .none: return "unchanged"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconChip(icon: metricIcon, tint: AppColors.primary, size: 28)

            Text(delta.label)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(delta.valueA)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Image(systemName: delta.arrowIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(delta.arrowColor)
                .frame(width: 24)

            Text(delta.valueB)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(delta.arrowColor)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta.label), \(delta.valueA) to \(delta.valueB), \(changeWord)")
    }
}

// MARK: - Recording Picker

/// One side of the comparison. The whole card opens the menu: the only way
/// in used to be a 22pt chevron in its corner that VoiceOver could not name.
private struct RecordingPicker: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var selectionID: UUID?
    let points: [ComparisonRecordingPoint]

    private var selection: ComparisonRecordingPoint? {
        points.first { $0.id == selectionID }
    }

    private var pickerSelection: Binding<UUID?> {
        Binding(
            get: { selectionID },
            set: { id in
                guard id != selectionID else { return }
                Haptics.selection()
                selectionID = id
            }
        )
    }

    var body: some View {
        Menu {
            // A Picker gives the menu its checkmark and the selected trait.
            Picker(label, selection: pickerSelection) {
                ForEach(points) { point in
                    Text("\(point.date.formatted(date: .abbreviated, time: .shortened)) · \(point.score ?? 0) pts")
                        .tag(point.id as UUID?)
                }
            }
        } label: {
            GlassCard(cornerRadius: 16, tint: color.opacity(0.06), padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(color)

                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let selection {
                        Text(selection.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("\(selection.score ?? 0)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.scoreColor(for: selection.score ?? 0))

                            Text("pts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Select")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("\(label) take")
        .accessibilityValue(selection.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)), \($0.score ?? 0) points" } ?? "None")
        .accessibilityHint("Choose a different take")
    }
}
