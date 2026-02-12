import SwiftUI
import SwiftData

struct ComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ComparisonViewModel()

    private var scoreChange: Int {
        guard let a = viewModel.recordingA?.analysis?.speechScore.overall,
              let b = viewModel.recordingB?.analysis?.speechScore.overall else { return 0 }
        return b - a
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.allRecordings.count >= 2 {
                        // Hero score summary
                        heroSummarySection

                        // Recording selectors
                        selectorSection

                        // Comparison breakdown
                        if !viewModel.deltas.isEmpty {
                            breakdownSection
                        }
                    } else {
                        EmptyStateCard(
                            icon: "chart.bar.xaxis",
                            title: "Not Enough Data",
                            message: "Record at least 2 sessions to compare your progress."
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Compare")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Hero Summary

    private var heroSummarySection: some View {
        let scoreA = viewModel.recordingA?.analysis?.speechScore.overall ?? 0
        let scoreB = viewModel.recordingB?.analysis?.speechScore.overall ?? 0
        let change = scoreB - scoreA

        return FeaturedGlassCard(
            gradientColors: [
                (change >= 0 ? Color.green : Color.red).opacity(0.12),
                (change >= 0 ? Color.teal : Color.orange).opacity(0.06)
            ]
        ) {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Progress")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Text(change >= 0 ? "+\(change) points" : "\(change) points")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(change >= 0 ? .green : .red)
                    }

                    Spacer()

                    Image(systemName: change >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(change >= 0 ? .green : .red)
                        .opacity(0.8)
                }

                // Score comparison bar
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("\(scoreA)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: scoreA))
                        Text("First")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Progress arrow
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

                    VStack(spacing: 4) {
                        Text("\(scoreB)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: scoreB))
                        Text("Latest")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
        }
    }

    // MARK: - Selector Section

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sessions", systemImage: "mic.fill")
                .font(.headline)

            HStack(spacing: 12) {
                RecordingPicker(
                    label: "First",
                    icon: "a.circle.fill",
                    color: .teal,
                    selection: $viewModel.recordingA,
                    recordings: viewModel.allRecordings
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                RecordingPicker(
                    label: "Latest",
                    icon: "b.circle.fill",
                    color: .cyan,
                    selection: $viewModel.recordingB,
                    recordings: viewModel.allRecordings
                )
            }
        }
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(Array(viewModel.deltas.enumerated()), id: \.offset) { _, delta in
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

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: metricIcon)
                    .font(.caption)
                    .foregroundStyle(delta.arrowColor == .secondary ? .teal : delta.arrowColor)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill((delta.arrowColor == .secondary ? Color.teal : delta.arrowColor).opacity(0.15))
                    }

                // Label
                Text(delta.label)
                    .font(.subheadline.weight(.medium))

                Spacer()

                // Values
                Text(delta.valueA)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: delta.arrowIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(delta.arrowColor)
                    .frame(width: 24)

                Text(delta.valueB)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(delta.arrowColor)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Recording Picker

private struct RecordingPicker: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var selection: Recording?
    let recordings: [Recording]

    private var score: Int {
        selection?.analysis?.speechScore.overall ?? 0
    }

    var body: some View {
        GlassCard(cornerRadius: 16, tint: color, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)

                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let sel = selection {
                    Text(sel.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(score)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: score))

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
            .overlay(alignment: .topTrailing) {
                Menu {
                    ForEach(recordings) { recording in
                        Button {
                            selection = recording
                        } label: {
                            HStack {
                                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text("\(recording.analysis?.speechScore.overall ?? 0) pts")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                }
                        }
                }
            }
        }
    }
}
