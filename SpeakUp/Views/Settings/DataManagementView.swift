import SwiftUI
import SwiftData

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Button {
                                Haptics.warning()
                                viewModel.showingResetConfirmation = true
                            } label: {
                                HStack {
                                    Label("Reset Settings", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.vertical, 8)

                            Button {
                                Haptics.warning()
                                viewModel.showingClearDataConfirmation = true
                            } label: {
                                HStack {
                                    Label("Clear All Data", systemImage: "trash")
                                        .font(.subheadline)
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Your recordings and progress are stored locally on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Data Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.configure(with: modelContext) }
        .alert("Reset Settings?", isPresented: $viewModel.showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetSettings() }
            }
        } message: {
            Text("This will reset all settings to their default values.")
        }
        .alert("Clear All Data?", isPresented: $viewModel.showingClearDataConfirmation) {
            TextField("Type \"I acknowledge\"", text: $viewModel.clearDataAcknowledgement)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                viewModel.clearDataAcknowledgement = ""
            }
            Button("Clear Data", role: .destructive) {
                Task { await viewModel.clearAllData() }
                viewModel.clearDataAcknowledgement = ""
            }
            .disabled(viewModel.clearDataAcknowledgement.trimmingCharacters(in: .whitespaces).lowercased() != "i acknowledge")
        } message: {
            Text("This will permanently delete all your recordings, goals, achievements, and curriculum progress. Type \"I acknowledge\" to confirm.")
        }
    }
}
