import SwiftUI

struct ChallengeShareView: View {
    let recording: Recording
    let onShare: (SocialChallenge) -> Void
    let onDismiss: () -> Void

    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.2.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal)

                Text("Challenge a Friend")
                    .font(.title2.weight(.bold))

                Text("Share this prompt and your score. Your friend will try to beat it!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Score display
                if let score = recording.analysis?.speechScore.overall {
                    HStack(spacing: 4) {
                        Text("Your score:")
                            .foregroundStyle(.secondary)
                        Text("\(score)/100")
                            .font(.headline)
                            .foregroundStyle(AppColors.scoreColor(for: score))
                    }
                }

                // Name input
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)

                Spacer()

                GlassButton(
                    title: "Share Challenge",
                    icon: "square.and.arrow.up",
                    style: .primary,
                    fullWidth: true
                ) {
                    let challenge = SocialChallenge(
                        promptId: recording.prompt?.id ?? "",
                        promptText: recording.prompt?.text ?? "",
                        challengerName: name.isEmpty ? "Someone" : name,
                        challengerScore: recording.analysis?.speechScore.overall ?? 0,
                        date: Date()
                    )
                    onShare(challenge)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }
}
