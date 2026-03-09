import SwiftUI
import SwiftData

struct AnalysisSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $viewModel.trackPauses) {
                                Label("Track Pauses", systemImage: "pause.circle")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            Divider().padding(.vertical, 8)

                            Toggle(isOn: $viewModel.trackFillerWords) {
                                Label("Track Filler Words", systemImage: "text.bubble")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            Divider().padding(.vertical, 8)

                            VStack(spacing: 8) {
                                HStack {
                                    Label("Target Pace", systemImage: "speedometer")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(viewModel.targetWPM) WPM")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.teal)
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.targetWPM) },
                                        set: { viewModel.targetWPM = Int($0) }
                                    ),
                                    in: 100...200,
                                    step: 5
                                )
                                .tint(.teal)
                            }
                            .frame(minHeight: 60)

                            Divider().padding(.vertical, 8)

                            NavigationLink {
                                ScoreWeightsView()
                            } label: {
                                HStack {
                                    Label("Score Weights", systemImage: "slider.horizontal.3")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.hasCustomWeights {
                                        Text("Custom")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.teal)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background { Capsule().fill(.teal.opacity(0.15)) }
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Analyze your speech patterns for pauses and filler words. Target pace sets the ideal WPM for your pace score (default 150). Score weights let you customize how each metric contributes to your overall score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.configure(with: modelContext) }
        .onChange(of: viewModel.trackPauses) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.trackFillerWords) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.targetWPM) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
    }
}
