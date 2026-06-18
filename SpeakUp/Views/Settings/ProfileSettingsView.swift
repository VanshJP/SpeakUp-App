import SwiftUI

/// Lets the user view and edit their display name after onboarding. The name is
/// permanently linked into the transcription bias terms (see
/// `UserSettings.transcriptionBiasTerms`), so it always sits in the dictation
/// dictionary and transcripts spell it correctly whenever it's spoken.
struct ProfileSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your name", systemImage: "person.text.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            TextField(
                                "",
                                text: $viewModel.userName,
                                prompt: Text("Your name").foregroundStyle(.white.opacity(0.35))
                            )
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit { commit() }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                nameFocused ? AppColors.primary.opacity(0.55) : Color.white.opacity(0.10),
                                                lineWidth: nameFocused ? 1.2 : 0.5
                                            )
                                    }
                            }
                        }
                    }

                    Label {
                        Text("Your name is always added to the on-device dictation dictionary, so transcripts spell it right whenever you say it.")
                    } icon: {
                        Image(systemName: "character.book.closed.fill")
                            .foregroundStyle(AppColors.primary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        // Persist on every change so the name + its dictionary linkage survive
        // even if the user leaves without tapping Done.
        .onChange(of: viewModel.userName) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        nameFocused = false
        Task { await viewModel.commitUserName() }
    }
}
