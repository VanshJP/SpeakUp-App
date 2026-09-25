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

            PageScrollView {
                VStack(spacing: AppLayout.chapterSpacing) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassCardTitle("Your name")

                            TextField(
                                "Your name",
                                text: $viewModel.userName,
                                prompt: Text("Your name").foregroundStyle(.white.opacity(0.35))
                            )
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit { commit() }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            // Painted, not material: this sits on a glass card,
                            // and glass on glass samples the plate (rule 13b).
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                Color.white.opacity(nameFocused ? 0.4 : 0.16),
                                                lineWidth: 1
                                            )
                                    }
                            }
                        }
                    }

                    Label {
                        Text("Your name is always added to the on-device dictation dictionary, so transcripts spell it right whenever you say it.")
                    } icon: {
                        Image(systemName: "character.book.closed.fill")
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
        // An empty name is the reason to be here, so the field is ready.
        .task {
            if viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameFocused = true
            }
        }
        // Saved on Return and on the way out, not per keystroke: every save is
        // a store write, a CloudKit export, and a reminder reschedule.
        .onDisappear { commit() }
    }

    private func commit() {
        nameFocused = false
        Task { await viewModel.commitUserName() }
    }
}
