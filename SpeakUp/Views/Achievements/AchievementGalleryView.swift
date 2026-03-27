import SwiftData
import SwiftUI

struct AchievementGalleryView: View {
    @Query private var achievements: [Achievement]

    var body: some View {
        let sections = partitionAchievements()
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Progress Header
                    achievementProgressHeader(
                        unlockedCount: sections.unlocked.count,
                        totalCount: sections.totalCount
                    )

                    // Achievement Grid
                    if achievements.isEmpty {
                        EmptyStateCard(
                            icon: "trophy",
                            title: "No Achievements Yet",
                            message: "Complete practice sessions to start unlocking achievements."
                        )
                    } else {
                        let unlocked = sections.unlocked
                        let locked = sections.locked

                        if !unlocked.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Unlocked", systemImage: "star.fill")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 12
                                ) {
                                    ForEach(unlocked, id: \.id) { achievement in
                                        AchievementCard(achievement: achievement)
                                    }
                                }
                            }
                        }

                        if !locked.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 12
                                ) {
                                    ForEach(locked, id: \.id) { achievement in
                                        AchievementCard(achievement: achievement)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Awards")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Progress Header

    private func achievementProgressHeader(unlockedCount: Int, totalCount: Int) -> some View {
        let progress = totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0
        FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.12), .cyan.opacity(0.06)]
        ) {
            HStack(spacing: 20) {
                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.teal.opacity(0.15), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Trophy icon in center
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(unlockedCount) of \(totalCount)")
                        .font(.title2.weight(.bold))

                    Text("achievements unlocked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.teal.opacity(0.15))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.teal.opacity(0.7), .teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())

                    Text("\(Int(progress * 100))% complete")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.teal)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func partitionAchievements() -> (unlocked: [Achievement], locked: [Achievement], totalCount: Int) {
        var unlocked: [Achievement] = []
        var locked: [Achievement] = []
        unlocked.reserveCapacity(achievements.count)
        locked.reserveCapacity(achievements.count)

        for achievement in achievements {
            if achievement.isUnlocked {
                unlocked.append(achievement)
            } else {
                locked.append(achievement)
            }
        }

        return (unlocked: unlocked, locked: locked, totalCount: achievements.count)
    }
}

// MARK: - Achievement Card

private struct AchievementCard: View {
    let achievement: Achievement
    @State private var appeared = false

    var body: some View {
        GlassCard(
            tint: achievement.isUnlocked ? .teal.opacity(0.1) : .clear,
            padding: 16,
            accentBorder: achievement.isUnlocked ? .teal.opacity(0.2) : nil
        ) {
            VStack(spacing: 12) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(
                            achievement.isUnlocked
                                ? LinearGradient(
                                    colors: [.teal.opacity(0.2), .cyan.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [.gray.opacity(0.1), .gray.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: achievement.icon)
                        .font(.title2)
                        .foregroundStyle(
                            achievement.isUnlocked
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.teal, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                : AnyShapeStyle(.gray.opacity(0.35))
                        )
                }

                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

                Text(achievement.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Date or locked indicator
                Group {
                    if let date = achievement.unlockedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.teal)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                            Text("Locked")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.quaternary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
        .opacity(achievement.isUnlocked ? 1 : 0.6)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(duration: 0.4)) {
                appeared = true
            }
        }
    }
}
