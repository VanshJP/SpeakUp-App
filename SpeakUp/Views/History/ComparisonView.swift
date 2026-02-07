import SwiftUI
import SwiftData

struct ComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ComparisonViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Recording selectors
                HStack(spacing: 12) {
                    RecordingPicker(
                        label: "First",
                        selection: $viewModel.recordingA,
                        recordings: viewModel.allRecordings
                    )

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    RecordingPicker(
                        label: "Latest",
                        selection: $viewModel.recordingB,
                        recordings: viewModel.allRecordings
                    )
                }

                // Comparison table
                if !viewModel.deltas.isEmpty {
                    GlassCard {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Metric")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(viewModel.recordingA?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                                    .frame(width: 60)
                                Text("")
                                    .frame(width: 30)
                                Text(viewModel.recordingB?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                                    .frame(width: 60)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                            ForEach(Array(viewModel.deltas.enumerated()), id: \.offset) { index, delta in
                                if index > 0 {
                                    Divider().padding(.vertical, 6)
                                }

                                HStack {
                                    Text(delta.label)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(delta.valueA)
                                        .font(.subheadline.weight(.medium))
                                        .frame(width: 60)

                                    Image(systemName: delta.arrowIcon)
                                        .font(.caption)
                                        .foregroundStyle(delta.arrowColor)
                                        .frame(width: 30)

                                    Text(delta.valueB)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(delta.arrowColor)
                                        .frame(width: 60)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Not Enough Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Record at least 2 sessions to compare.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Compare")
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }
}

private struct RecordingPicker: View {
    let label: String
    @Binding var selection: Recording?
    let recordings: [Recording]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(recordings) { recording in
                    Button {
                        selection = recording
                    } label: {
                        Text("\(recording.date.formatted(date: .abbreviated, time: .shortened)) - \(recording.analysis?.speechScore.overall ?? 0)pts")
                    }
                }
            } label: {
                HStack {
                    Text(selection?.date.formatted(date: .abbreviated, time: .omitted) ?? "Select")
                        .font(.subheadline)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
