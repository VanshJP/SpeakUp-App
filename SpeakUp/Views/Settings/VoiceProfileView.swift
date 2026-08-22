import SwiftUI

/// Your learned voice signature and the calibration that seeds it.
///
/// This used to live inside Data Management, filed next to "Clear All Data" —
/// but it is not data hygiene, it is an input to scoring. Auto Pace Target on
/// the Analysis screen reads the same profile, so the profile now hangs off
/// Analysis, one row under the target it feeds.
struct VoiceProfileView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 16) {
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
                                    Text("Calibrate your voice so Big Talk can recognize you in conversations, or it will learn automatically as you record.")
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

                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Voice Profile")
        .navigationBarTitleDisplayMode(.inline)
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
