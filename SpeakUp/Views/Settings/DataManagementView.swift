import SwiftUI

struct DataManagementView: View {
    @Bindable var viewModel: SettingsViewModel
    /// What the last action did. After a reset or a wipe the page used to look
    /// exactly as it did before, with nothing to say it had worked.
    @State private var outcome: Outcome?

    private enum Outcome: Equatable {
        case reset, cleared, failed

        var message: String {
            switch self {
            case .reset: "Settings are back to their defaults."
            case .cleared: "All your data has been deleted."
            case .failed: "Something went wrong. Nothing was lost; try again."
            }
        }
    }

    private var syncsWithICloud: Bool { ICloudStorageService.shared.isSyncEnabled }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: AppLayout.listSpacing) {
                    // Both rows open a confirmation, not a page, so neither
                    // wears a chevron.
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        actionRow(
                            "Reset settings",
                            icon: "arrow.counterclockwise",
                            caption: "Preferences go back to their defaults. Your takes and lists stay."
                        ) {
                            viewModel.showingResetConfirmation = true
                        }

                        actionRow(
                            "Clear all data",
                            icon: "trash",
                            caption: "Deletes everything you've recorded and written.",
                            isDestructive: true
                        ) {
                            viewModel.showingClearDataConfirmation = true
                        }
                    }

                    if let outcome {
                        Label(outcome.message, systemImage: outcome == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(outcome == .failed ? AppColors.error : AppColors.success)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }

                    Text(storageFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Data Management")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset settings?", isPresented: $viewModel.showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    let didReset = await viewModel.resetSettings()
                    finish(didReset ? .reset : .failed)
                }
            }
        } message: {
            Text("Session, routine, analysis, prompt, word workout, look, and score weight preferences go back to their defaults, and reminders turn off. Your recordings, stories, word lists, custom fillers and questions, and voice profile stay.")
        }
        .alert("Clear all data?", isPresented: $viewModel.showingClearDataConfirmation) {
            TextField("Type \"I acknowledge\"", text: $viewModel.clearDataAcknowledgement)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                viewModel.clearDataAcknowledgement = ""
            }
            Button("Clear Data", role: .destructive) {
                viewModel.clearDataAcknowledgement = ""
                Task {
                    let didClear = await viewModel.clearAllData()
                    finish(didClear ? .cleared : .failed)
                }
            }
            .disabled(viewModel.clearDataAcknowledgement.trimmingCharacters(in: .whitespaces).lowercased() != "i acknowledge")
        } message: {
            Text(clearMessage)
        }
    }

    // MARK: - Copy

    /// The exact scope of `SettingsViewModel.clearAllData()`.
    private var clearMessage: String {
        let reach = syncsWithICloud ? ", here and on every device that syncs with your iCloud" : ""
        return "This permanently deletes your recordings, stories, custom prompts, word lists, custom fillers and questions, saved Read Aloud texts, voice profile, goals, achievements, lesson progress, and usage log\(reach). Your settings stay. Type \"I acknowledge\" to confirm."
    }

    private var storageFooter: String {
        syncsWithICloud
            ? "Your recordings and progress live on this device and in your private iCloud, so clearing them removes them from every synced device."
            : "Your recordings and progress are stored only on this device."
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50

    private func actionRow(
        _ title: String,
        icon: String,
        caption: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.warning()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(isDestructive ? AppColors.error : .primary)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func finish(_ result: Outcome) {
        if result == .failed {
            Haptics.error()
        } else {
            Haptics.success()
        }
        withAnimation(.easeInOut(duration: 0.2)) { outcome = result }
        UIAccessibility.post(notification: .announcement, argument: result.message)
    }
}
