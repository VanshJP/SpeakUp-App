import SwiftUI

struct ScriptSectionDetailView: View {
    let event: SpeakingEvent
    let section: ScriptSection

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // Section header
                    GlassCard(tint: AppColors.primary.opacity(0.06)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(section.title)
                                    .font(.title3.weight(.bold))

                                Spacer()

                                Text("\(section.wordCount) words")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                    }
                            }

                            HStack(spacing: 16) {
                                // Mastery score
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(AppColors.scoreColor(for: section.masteryScore))
                                        .frame(width: 10, height: 10)
                                    Text("Mastery: \(section.masteryScore)/100")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(AppColors.scoreColor(for: section.masteryScore))
                                }

                                // Practice count
                                Label("\(section.practiceCount) practices", systemImage: "mic.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastPractice = section.lastPracticeDate {
                                Text("Last practiced: \(lastPractice.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Target duration
                            let minutes = section.targetDurationSeconds / 60
                            let seconds = section.targetDurationSeconds % 60
                            Label("Target: \(minutes)m \(seconds)s", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Script content
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Script", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(section.text)
                                .font(.body)
                                .lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    // Practice button
                    GlassButton(
                        title: "Practice This Section",
                        icon: "mic.fill",
                        style: .primary,
                        size: .large,
                        fullWidth: true
                    ) {
                        Haptics.medium()
                        // Recording launch is handled by parent navigation
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
