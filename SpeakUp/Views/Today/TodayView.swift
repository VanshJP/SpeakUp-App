import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowWheel: () -> Void
    var onShowGoals: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Stats (Ring visualization)
                headerSection

                // Interactive Prompt Card (tap to start)
                interactivePromptSection

                // Prominent Start Button
                startButtonSection

                // Active Goals Preview
                if !viewModel.activeGoals.isEmpty {
                    goalsPreviewSection
                }
            }
            .padding()
        }
        .navigationTitle("Today")
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }
    
    // MARK: - Header Section

    private var headerSection: some View {
        RingStatsView(
            streak: viewModel.userStats.currentStreak,
            sessions: viewModel.userStats.totalRecordings,
            score: Int(viewModel.userStats.averageScore),
            improvement: viewModel.userStats.improvementRate
        )
    }

    // MARK: - Start Button Section

    private var startButtonSection: some View {
        GlassButton(
            title: "Start Session",
            icon: "mic.fill",
            style: .primary,
            fullWidth: true
        ) {
            onStartRecording(
                viewModel.todaysPrompt,
                viewModel.selectedDuration
            )
        }
    }
    
    // MARK: - Interactive Prompt Section
    
    private var interactivePromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Prompt")
                    .font(.headline)
                
                Spacer()
                
                GlassIconButton(icon: "circle.grid.3x3.fill", size: 36, tint: .purple) {
                    onShowWheel()
                }
            }
            
            InteractivePromptCard(
                prompt: viewModel.todaysPrompt,
                selectedDuration: $viewModel.selectedDuration,
                onTap: {
                    onStartRecording(
                        viewModel.todaysPrompt,
                        viewModel.selectedDuration
                    )
                },
                onRefresh: {
                    Task {
                        await viewModel.refreshPrompt()
                    }
                }
            )
        }
    }
    
    // MARK: - Goals Preview Section
    
    private var goalsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Goals")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    onShowGoals()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                }
            }
            
            ForEach(viewModel.activeGoals.prefix(2)) { goal in
                GoalProgressRow(goal: goal)
            }
        }
    }
}

// MARK: - Interactive Prompt Card

struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void
    let onRefresh: () -> Void

    @State private var isPulsing = false

    var body: some View {
        GlassCard(tint: categoryColor.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with category and refresh button
                HStack {
                    // Category (tappable)
                    Label(prompt?.category ?? "Loading...", systemImage: categoryIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(categoryColor)
                        .onTapGesture { onTap() }

                    Spacer()

                    // Refresh button
                    SmallIconButton(icon: "arrow.clockwise") {
                        onRefresh()
                    }
                }

                // Prompt Text (main tappable area)
                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.title3.weight(.medium))
                    .lineLimit(4)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                // Bottom row: difficulty + duration + tap hint
                HStack {
                    if let difficulty = prompt?.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                            .onTapGesture { onTap() }
                    }

                    // Duration selector (inside card, scrolls with it)
                    DurationPill(selectedDuration: $selectedDuration)

                    Spacer()

                    // Tap to start hint with pulse (tappable)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.teal)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)

                        Text("Tap to start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                }
            }
        }
        .redacted(reason: prompt == nil ? .placeholder : [])
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private var categoryColor: Color {
        guard let category = prompt?.category else { return .gray }
        return AppColors.categoryColor(category)
    }

    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}

// MARK: - Small Icon Button (for card actions)

struct SmallIconButton: View {
    let icon: String
    var badge: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration Pill Selector

struct DurationPill: View {
    @Binding var selectedDuration: RecordingDuration
    @State private var showPicker = false
    
    var body: some View {
        Menu {
            ForEach(RecordingDuration.allCases) { duration in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedDuration = duration
                    }
                } label: {
                    HStack {
                        Text(duration.displayName)
                        if duration == selectedDuration {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(selectedDuration.displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Compact Score Card

struct CompactScoreCard: View {
    let score: Int
    var trend: ScoreTrend = .stable
    
    var body: some View {
        GlassCard(tint: AppColors.scoreColor(for: score).opacity(0.2), padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                    Text("Score")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(score)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColors.scoreColor(for: score))
                    Text("/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(trend.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(trend.color)
            }
        }
    }
}

// MARK: - Difficulty Badge

struct DifficultyBadge: View {
    let difficulty: PromptDifficulty
    
    var body: some View {
        Text(difficulty.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(AppColors.difficultyColor(difficulty).opacity(0.2))
            }
            .foregroundStyle(AppColors.difficultyColor(difficulty))
    }
}

// MARK: - Goal Progress Row

struct GoalProgressRow: View {
    let goal: UserGoal
    
    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: goal.type.iconName)
                        .foregroundStyle(.teal)
                    
                    Text(goal.title)
                        .font(.subheadline.weight(.medium))
                    
                    Spacer()
                    
                    Text("\(goal.current)/\(goal.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(value: goal.progress)
                    .tint(.teal)
            }
        }
    }
}

// MARK: - Legacy Prompt Card (for reference/other uses)

struct PromptCard: View {
    let prompt: Prompt?
    
    var body: some View {
        GlassCard(tint: categoryColor.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 12) {
                // Category & Difficulty
                HStack {
                    Label(prompt?.category ?? "Loading...", systemImage: categoryIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(categoryColor)
                    
                    Spacer()
                    
                    if let difficulty = prompt?.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                    }
                }
                
                // Prompt Text
                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.body)
                    .lineLimit(4)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
            }
        }
        .redacted(reason: prompt == nil ? .placeholder : [])
    }
    
    private var categoryColor: Color {
        guard let category = prompt?.category else { return .gray }
        return AppColors.categoryColor(category)
    }
    
    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}

#Preview {
    NavigationStack {
        TodayView(
            onStartRecording: { _, _ in },
            onShowWheel: {},
            onShowGoals: {}
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
