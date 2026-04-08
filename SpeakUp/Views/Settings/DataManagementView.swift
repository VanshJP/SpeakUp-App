import SwiftUI
import SwiftData

struct DataManagementView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Voice Profile Card
                    GlassSectionHeader("Voice Profile", icon: "waveform.badge.person.crop")

                    GlassCard(padding: 14) {
                        VStack(spacing: 0) {
                            if viewModel.voiceProfileSampleCount > 0 {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Trained on \(viewModel.voiceProfileSampleCount) recording\(viewModel.voiceProfileSampleCount == 1 ? "" : "s")")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                        if let lastUpdated = viewModel.voiceProfileLastUpdated {
                                            Text("Updated \(Self.broadDateString(lastUpdated))")
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
                                .frame(minHeight: 40)

                                Divider().padding(.vertical, 6)

                                Button {
                                    Haptics.medium()
                                    viewModel.showingVoiceCalibration = true
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "mic.badge.plus")
                                            .font(.body)
                                            .foregroundStyle(AppColors.primary)
                                            .frame(width: 28)
                                        Text("Recalibrate")
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

                                Divider().padding(.vertical, 6)

                                Button {
                                    Haptics.warning()
                                    viewModel.showingVoiceProfileResetConfirmation = true
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28)
                                        Text("Reset Voice Profile")
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
                                VStack(alignment: .leading, spacing: 12) {
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
                    }

                    // MARK: - How It Works
                    GlassCard(tint: AppColors.glassTintPrimary, padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("How voice calibration works", systemImage: "info.circle")
                                .font(.caption.bold())
                                .foregroundStyle(AppColors.primary)

                            VStack(alignment: .leading, spacing: 8) {
                                howItWorksRow(icon: "waveform", text: "Captures your unique pitch and vocal energy")
                                howItWorksRow(icon: "person.2.fill", text: "Helps identify your voice in conversations with others")
                                howItWorksRow(icon: "arrow.trianglehead.2.clockwise", text: "Improves automatically with every recording you make")
                            }
                        }
                    }

                    // MARK: - Data Actions
                    GlassSectionHeader("Data", icon: "externaldrive.fill")

                    GlassCard(padding: 14) {
                        VStack(spacing: 0) {
                            Button {
                                Haptics.warning()
                                viewModel.showingResetConfirmation = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28)
                                    Text("Reset Settings")
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

                            Divider().padding(.vertical, 6)

                            Button {
                                Haptics.warning()
                                viewModel.showingClearDataConfirmation = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "trash")
                                        .font(.body)
                                        .foregroundStyle(AppColors.error)
                                        .frame(width: 28)
                                    Text("Clear All Data")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.error)
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

    // MARK: - Subviews

    private func howItWorksRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppColors.primary)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static func broadDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            return shortDateFormatter.string(from: date)
        }
    }
}
