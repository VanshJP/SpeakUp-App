import SwiftUI

struct AIModelSettingsView: View {
    @Environment(LLMService.self) private var llmService

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    featuresCard
                    privacyCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("AI Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var statusCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 40, height: 40)
                    .background(.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.headline)
                    Text("On-device language model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if llmService.isAvailable {
                    Text("Available")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green))
                } else {
                    Text("Not Available")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
        }
    }

    private var featuresCard: some View {
        GlassCard(tint: .purple.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("What does this power?", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    featureBullet(
                        icon: "brain",
                        text: "Smarter coherence scoring that understands meaning, not just keywords"
                    )
                    featureBullet(
                        icon: "sparkles",
                        text: "Personalized AI coaching tips based on your speech performance"
                    )
                }

                if !llmService.isAvailable {
                    Text("These features require a device with Apple Intelligence. Without it, SpeakUp uses rule-based analysis which still works great.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var privacyCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("100% On-Device")
                        .font(.subheadline.weight(.medium))
                    Text("All AI processing happens privately on your device. No data is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func featureBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
