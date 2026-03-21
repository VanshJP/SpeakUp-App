import SwiftUI
import SwiftData

struct DataManagementView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Voice Profile Card
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Voice Profile", systemImage: "waveform.badge.person.crop")
                                .font(.headline)
                                .foregroundStyle(.white)

                            if viewModel.voiceProfileSampleCount > 0 {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Trained on \(viewModel.voiceProfileSampleCount) recording\(viewModel.voiceProfileSampleCount == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        if let lastUpdated = viewModel.voiceProfileLastUpdated {
                                            Text("Last updated \(Self.broadDateString(lastUpdated))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(viewModel.voiceProfileSampleCount >= 3 ? "Reliable" : "Learning")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(viewModel.voiceProfileSampleCount >= 3 ? AppColors.success.opacity(0.25) : AppColors.warning.opacity(0.25))
                                        )
                                        .foregroundStyle(viewModel.voiceProfileSampleCount >= 3 ? AppColors.success : AppColors.warning)
                                }

                                Divider().padding(.vertical, 4)

                                Button {
                                    Haptics.medium()
                                    viewModel.showingVoiceCalibration = true
                                } label: {
                                    HStack {
                                        Label("Recalibrate", systemImage: "mic.badge.plus")
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

                                Button {
                                    Haptics.warning()
                                    viewModel.showingVoiceProfileResetConfirmation = true
                                } label: {
                                    HStack {
                                        Label("Reset Voice Profile", systemImage: "arrow.counterclockwise")
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
                            } else {
                                Text("Calibrate your voice so SpeakUp can recognize you in conversations, or it will learn automatically as you record.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                GlassButton(title: "Calibrate Voice", icon: "mic.badge.plus", style: .primary, size: .medium) {
                                    Haptics.medium()
                                    viewModel.showingVoiceCalibration = true
                                }
                            }
                        }
                    }

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
        .alert("Reset Settings?", isPresented: $viewModel.showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetSettings() }
            }
        } message: {
            Text("This will reset all settings to their default values.")
        }
        .sheet(isPresented: $viewModel.showingVoiceCalibration) {
            VoiceCalibrationView { profile in
                viewModel.saveCalibrationProfile(profile)
            }
        }
        .alert("Reset Voice Profile?", isPresented: $viewModel.showingVoiceProfileResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetVoiceProfile()
            }
        } message: {
            Text("This will clear your learned voice signature. It will be rebuilt from your next recordings.")
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

    // MARK: - Helpers

    private static func broadDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
