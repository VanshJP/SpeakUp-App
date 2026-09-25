import SwiftUI

struct VoiceProfileView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: AppLayout.listSpacing) {
                    if viewModel.voiceProfileSampleCount > 0 {
                        GlassRowGroup(dividerInset: Self.dividerInset) {
                            statusRow

                            // Both open something - a sheet, a confirmation -
                            // rather than a page, so neither wears a chevron.
                            actionRow("Recalibrate", icon: "mic.badge.plus") {
                                Haptics.medium()
                                viewModel.showingVoiceCalibration = true
                            }

                            actionRow("Reset voice profile", icon: "arrow.counterclockwise") {
                                Haptics.warning()
                                viewModel.showingVoiceProfileResetConfirmation = true
                            }
                        }
                    } else {
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Calibrate your voice so Big Talk can recognize you in conversations, or it will learn automatically as you record.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                GlassButton(title: "Calibrate voice", icon: "mic.badge.plus", style: .primary, size: .medium) {
                                    Haptics.medium()
                                    viewModel.showingVoiceCalibration = true
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // MARK: - How It Works
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassCardTitle("How voice calibration works")

                            VStack(alignment: .leading, spacing: 8) {
                                howItWorksRow(icon: "waveform", text: "Captures your unique pitch and vocal energy")
                                howItWorksRow(icon: "person.2.fill", text: "Helps identify your voice in conversations with others")
                                howItWorksRow(icon: "arrow.trianglehead.2.clockwise", text: "Improves automatically with every recording you make")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .labelStyle(.row)
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
        .alert("Reset voice profile?", isPresented: $viewModel.showingVoiceProfileResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetVoiceProfile()
            }
        } message: {
            Text("This will clear your learned voice signature. It will be rebuilt from your next recordings.")
        }
    }

    // MARK: - Subviews

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50

    /// The stored count is a trust weight, not a number of takes - a manual
    /// calibration sets it to 3 - so it is read as a state, never "trained on
    /// N recordings".
    private var statusRow: some View {
        let isReady = viewModel.voiceProfileSampleCount >= 3
        return HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReady ? "Your voice profile is ready" : "Still learning your voice")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    if let lastUpdated = viewModel.voiceProfileLastUpdated {
                        Text("Updated \(Self.broadDateString(lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "waveform.and.person.filled")
                    .font(.subheadline)
            }

            Spacer(minLength: 8)

            StatusPill(
                text: viewModel.voiceProfileStatus,
                color: isReady ? AppColors.success : AppColors.warning,
                glyph: .dot
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func howItWorksRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
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
