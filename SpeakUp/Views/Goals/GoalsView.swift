import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GoalsViewModel()
    @State private var showingAddGoal = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 16) {
                        // Summary header
                        if !viewModel.activeGoals.isEmpty || !viewModel.completedGoals.isEmpty {
                            summaryCard
                        }

                        // Active Goals
                        if !viewModel.activeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                GlassSectionHeader("Active Goals", icon: "target")

                                ForEach(viewModel.activeGoals) { goal in
                                    GoalCard(goal: goal, onDelete: {
                                        Task { await viewModel.deleteGoal(goal) }
                                    })
                                }
                            }
                        }

                        // Goal Templates
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("Add a Goal", icon: "plus.circle")

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(GoalTemplate.templates, id: \.title) { template in
                                    GoalTemplateCard(template: template) {
                                        Task { await viewModel.createGoal(from: template) }
                                    }
                                }
                            }
                        }

                        // Completed Goals
                        if !viewModel.completedGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                GlassSectionHeader("Completed", icon: "checkmark.circle")

                                ForEach(viewModel.completedGoals) { goal in
                                    CompletedGoalRow(goal: goal, onDelete: {
                                        Task { await viewModel.deleteGoal(goal) }
                                    })
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }

                if viewModel.activeGoals.isEmpty && viewModel.completedGoals.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "target")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Goals Yet")
                            .font(.headline)
                        Text("Set a goal below to track your speaking progress")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .onAppear {
                viewModel.configure(with: modelContext)
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent]) {
            HStack(spacing: 12) {
                summaryMetric(
                    value: "\(viewModel.activeGoals.count)",
                    label: "Active",
                    icon: "flame.fill",
                    tint: AppColors.primary
                )
                summaryMetric(
                    value: "\(viewModel.completedGoals.count)",
                    label: "Done",
                    icon: "checkmark.seal.fill",
                    tint: AppColors.success
                )
                summaryMetric(
                    value: averageProgressText,
                    label: "Avg Progress",
                    icon: "chart.bar.fill",
                    tint: .orange
                )
            }
        }
    }

    private func summaryMetric(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
        }
    }

    private var averageProgressText: String {
        guard !viewModel.activeGoals.isEmpty else { return "—" }
        let avg = viewModel.activeGoals.map(\.progressPercentage).reduce(0, +) / viewModel.activeGoals.count
        return "\(avg)%"
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: UserGoal
    var onDelete: (() -> Void)?

    var body: some View {
        GlassCard(tint: AppColors.glassTintPrimary.opacity(0.65)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: goal.type.iconName)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(AppColors.primary.opacity(0.15))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(goal.goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(goal.progressPercentage)%")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: goal.progressPercentage))

                        if goal.daysRemaining > 0 {
                            Text("\(goal.daysRemaining)d left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Expired")
                                .font(.caption2)
                                .foregroundStyle(AppColors.error)
                        }
                    }
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(AppColors.scoreGradient(for: goal.progressPercentage))
                            .frame(width: geometry.size.width * goal.progress)
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())

                // Stats row
                HStack {
                    Label("\(goal.current)/\(goal.target) \(goal.type.unit)", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if goal.isExpired && !goal.isCompleted {
                        Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Goal Template Card

struct GoalTemplateCard: View {
    let template: GoalTemplate
    let onAdd: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            onAdd()
        }) {
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: template.type.iconName)
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(AppColors.primary.opacity(0.15))
                            }

                        Spacer()

                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppColors.primary)
                    }

                    Text(template.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(template.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(template.durationDays) days")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Completed Goal Row

struct CompletedGoalRow: View {
    let goal: UserGoal
    var onDelete: (() -> Void)?

    var body: some View {
        GlassCard(tint: AppColors.glassTintSuccess.opacity(0.5), padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Completed \(goal.deadline.relativeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(goal.target) \(goal.type.unit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Goals View Model

@Observable
class GoalsViewModel {
    var activeGoals: [UserGoal] = []
    var completedGoals: [UserGoal] = []

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await loadGoals()
        }
    }

    @MainActor
    func loadGoals() async {
        guard let context = modelContext else { return }
        GoalProgressService.refreshGoals(in: context)

        // Active goals
        let activeDescriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isActive && !$0.isCompleted },
            sortBy: [SortDescriptor(\.deadline)]
        )

        // Completed goals
        let completedDescriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.deadline, order: .reverse)]
        )

        do {
            activeGoals = try context.fetch(activeDescriptor)
            completedGoals = try context.fetch(completedDescriptor)
        } catch {
            print("Error loading goals: \(error)")
        }
    }

    @MainActor
    func createGoal(from template: GoalTemplate) async {
        guard let context = modelContext else { return }

        let deadline = Date().adding(days: template.durationDays)

        let goal = UserGoal(
            type: template.type,
            title: template.title,
            goalDescription: template.description,
            target: template.target,
            deadline: deadline
        )

        context.insert(goal)

        do {
            try context.save()
            Haptics.success()
            await loadGoals()
        } catch {
            print("Error creating goal: \(error)")
        }
    }

    @MainActor
    func deleteGoal(_ goal: UserGoal) async {
        guard let context = modelContext else { return }

        context.delete(goal)

        do {
            try context.save()
            Haptics.error()
            await loadGoals()
        } catch {
            print("Error deleting goal: \(error)")
        }
    }
}

#Preview {
    GoalsView()
        .modelContainer(for: [UserGoal.self], inMemory: true)
}
