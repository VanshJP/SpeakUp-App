import SwiftUI
import SwiftData

struct AchievementGalleryView: View {
    @Query private var achievements: [Achievement]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(achievements, id: \.id) { achievement in
                    AchievementCard(achievement: achievement)
                }
            }
            .padding()
        }
        .navigationTitle("Achievements")
    }
}

private struct AchievementCard: View {
    let achievement: Achievement

    var body: some View {
        GlassCard(tint: achievement.isUnlocked ? .teal.opacity(0.1) : .clear, padding: 16) {
            VStack(spacing: 10) {
                Image(systemName: achievement.icon)
                    .font(.largeTitle)
                    .foregroundStyle(achievement.isUnlocked ? .teal : .gray.opacity(0.4))

                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

                Text(achievement.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Always reserve space for the date line so cards stay consistent height
                Group {
                    if let date = achievement.unlockedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.teal)
                    } else {
                        Text(" ")
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        }
        .opacity(achievement.isUnlocked ? 1 : 0.5)
    }
}
