import SwiftData
import SwiftUI

struct AchievementGalleryView: View {
    @Query private var achievements: [Achievement]

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    private var totalCount: Int {
        achievements.count
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(unlockedCount) / Double(totalCount)
    }

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 20) {
                    // Progress Header
                    achievementProgressHeader

                    // Achievement Grid
                    if achievements.isEmpty {
                        EmptyStateCard(
                            icon: "trophy",
                            title: "No Achievements Yet",
                            message: "Complete practice sessions to start unlocking achievements."
                        )
                    } else {
                        // Unlocked section
                        let unlocked = achievements.filter(\.isUnlocked)
                        let locked = achievements.filter { !$0.isUnlocked }

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

    private var achievementProgressHeader: some View {
        GlassCard(padding: 20) {
            HStack(spacing: 20) {
                // Progress gauge — count lives inside the ring
                ZStack {
                    RingProgress(progress: progress, color: AppColors.warning, lineWidth: 9)

                    Text("\(unlockedCount)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Achievements")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text("\(unlockedCount) of \(totalCount) unlocked")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    TickMeter(fraction: progress, color: AppColors.warning)
                        .frame(height: 10)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unlockedCount) of \(totalCount) achievements unlocked")
    }
}

// MARK: - Achievement Card

private struct AchievementCard: View {
    let achievement: Achievement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 12) {
                // Icon well — flat, unlocked earns the warm accent
                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundStyle(achievement.isUnlocked ? AppColors.warning : Color.white.opacity(0.25))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(achievement.isUnlocked ? AppColors.warning.opacity(0.1) : Color.white.opacity(0.03))
                            .overlay {
                                Circle().stroke(AppColors.cardStroke, lineWidth: 0.5)
                            }
                    }

                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

                Text(achievement.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Date or locked indicator
                Group {
                    if let date = achievement.unlockedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: 0.4)) {
                    appeared = true
                }
            }
        }
    }

    private var accessibilitySummary: String {
        let status: String
        if let date = achievement.unlockedDate {
            status = "Unlocked \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            status = "Locked"
        }
        return "\(achievement.title). \(achievement.descriptionText). \(status)"
    }
}
