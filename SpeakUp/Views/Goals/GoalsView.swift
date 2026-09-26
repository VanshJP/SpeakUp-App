import SwiftUI
import os.log
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GoalsViewModel()
    @State private var goalToDelete: UserGoal?

    var body: some View {
        NavigationStack {
            PageScrollView {
                VStack(spacing: 16) {
                    if viewModel.hasAnyGoal {
                        summaryCard
                    } else {
                        EmptyStateCard(
                            icon: "target",
                            title: "No goals yet",
                            message: "Pick a template below to set your first one."
                        )
                    }

                    if !viewModel.activeGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("Active goals")

                            ForEach(viewModel.activeGoals) { goal in
                                GoalCard(goal: goal, onDelete: {
                                    goalToDelete = goal
                                })
                            }
                        }
                    }

                    // Past the deadline and not met. These used to stay on top
                    // of Active forever in red, removable only by a long-press.
                    if !viewModel.endedGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("Ended")

                            GlassRowGroup(dividerInset: GoalRowLayout.textInset) {
                                ForEach(viewModel.endedGoals) { goal in
                                    EndedGoalRow(
                                        goal: goal,
                                        onRestart: restartAction(for: goal),
                                        onDelete: { goalToDelete = goal }
                                    )
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        GlassSectionHeader("Add a goal")

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(GoalTemplate.templates, id: \.title) { template in
                                GoalTemplateCard(
                                    template: template,
                                    isAdded: viewModel.hasActiveGoal(of: template.type)
                                ) {
                                    Task { await viewModel.createGoal(from: template) }
                                }
                            }
                        }
                    }

                    if !viewModel.completedGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("Completed")

                            GlassRowGroup(dividerInset: GoalRowLayout.textInset) {
                                ForEach(viewModel.completedGoals) { goal in
                                    CompletedGoalRow(goal: goal, onDelete: {
                                        goalToDelete = goal
                                    })
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
            .appBackground(.subtle)
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear {
                viewModel.configure(with: modelContext)
            }
            .alert("Delete Goal?", isPresented: Binding(
                get: { goalToDelete != nil },
                set: { if !$0 { goalToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { goalToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let goal = goalToDelete {
                        Task { await viewModel.deleteGoal(goal) }
                    }
                    goalToDelete = nil
                }
            } message: {
                Text("Progress on this goal will be lost.")
            }
        }
    }

    /// Starts the same goal over from its template, replacing the ended one.
    private func restartAction(for goal: UserGoal) -> (() -> Void)? {
        guard let template = GoalTemplate.templates.first(where: { $0.type == goal.type }) else { return nil }
        return {
            Task { await viewModel.createGoal(from: template, replacing: goal) }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        FeaturedGlassCard {
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
                    label: "Avg progress",
                    icon: "chart.bar.fill",
                    tint: AppColors.primary
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
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
        }
        .accessibilityElement(children: .combine)
    }

    /// A dash with no active goal to average. This returned a bare comma.
    private var averageProgressText: String {
        guard !viewModel.activeGoals.isEmpty else { return "–" }
        let avg = viewModel.activeGoals.map(\.progressPercentage).reduce(0, +) / viewModel.activeGoals.count
        return "\(avg)%"
    }
}

// MARK: - Row Layout

private enum GoalRowLayout {
    static let padding: CGFloat = 14
    static let chipSize: CGFloat = 28
    static let chipSpacing: CGFloat = 12
    /// Where row text starts, so a group's hairlines line up with it.
    static let textInset: CGFloat = padding + chipSize + chipSpacing
}

// MARK: - Goal Options Menu

/// The visible way to manage a goal. Delete used to live only in a
/// long-press context menu, which nothing on the card hinted at.
private struct GoalOptionsMenu: View {
    var onRestart: (() -> Void)? = nil
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if let onRestart {
                Button(action: onRestart) {
                    Label("Try again", systemImage: "arrow.counterclockwise")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete goal", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("Goal options")
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: UserGoal
    var onDelete: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconChip(icon: goal.type.iconName, tint: AppColors.primary, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(goal.goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(goal.progressPercentage)%")
                            .font(.metricValue)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        Text(goal.daysRemaining > 0 ? "\(goal.daysRemaining)d left" : "Last day")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if let onDelete {
                        GoalOptionsMenu(onDelete: onDelete)
                    }
                }

                // Progress toward a finish line, not a score: the score ramp
                // painted a goal on its first day red, as if it were failing.
                TickMeter(
                    fraction: goal.progress,
                    color: goal.progress >= 1 ? AppColors.success : AppColors.primary,
                    tickCount: 28
                )
                .frame(height: 10)

                Label("\(goal.current)/\(goal.target) \(goal.type.unit)", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .monospacedDigit()
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

// MARK: - Goal Template Card

struct GoalTemplateCard: View {
    let template: GoalTemplate
    /// An active goal of this type already exists. Repeat taps used to stack
    /// duplicate goals, with nothing on the card to say one had been added.
    var isAdded = false
    let onAdd: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onAdd()
        } label: {
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        IconChip(icon: template.type.iconName, tint: AppColors.primary, size: 28)

                        Spacer()

                        Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isAdded ? AppColors.success : AppColors.primary)
                            .symbolSwap(isAdded)
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

                    Text(isAdded ? "Added" : "\(template.durationDays) days")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isAdded ? Color.secondary : AppColors.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isAdded)
        .accessibilityHint(isAdded ? "Already one of your active goals" : "Adds this goal")
    }
}

// MARK: - Ended Goal Row

private struct EndedGoalRow: View {
    let goal: UserGoal
    var onRestart: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: GoalRowLayout.chipSpacing) {
            IconChip(icon: goal.type.iconName, tint: AppColors.primary, size: GoalRowLayout.chipSize)
                .opacity(0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Ended \(goal.deadline.relativeFormatted) · \(goal.current)/\(goal.target) \(goal.type.unit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            GoalOptionsMenu(onRestart: onRestart, onDelete: onDelete)
        }
        .padding(.leading, GoalRowLayout.padding)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
    }
}

// MARK: - Completed Goal Row

struct CompletedGoalRow: View {
    let goal: UserGoal
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: GoalRowLayout.chipSpacing) {
            IconChip(icon: "checkmark", tint: AppColors.success, size: GoalRowLayout.chipSize)

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
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let onDelete {
                GoalOptionsMenu(onDelete: onDelete)
            }
        }
        .padding(.leading, GoalRowLayout.padding)
        .padding(.trailing, onDelete == nil ? GoalRowLayout.padding : 4)
        .padding(.vertical, onDelete == nil ? 12 : 6)
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
    private let logger = Logger.app("Goals")
    var activeGoals: [UserGoal] = []
    /// Past the deadline without being met.
    var endedGoals: [UserGoal] = []
    var completedGoals: [UserGoal] = []

    private var modelContext: ModelContext?

    var hasAnyGoal: Bool {
        !activeGoals.isEmpty || !endedGoals.isEmpty || !completedGoals.isEmpty
    }

    func hasActiveGoal(of type: GoalType) -> Bool {
        activeGoals.contains { $0.type == type }
    }

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

        let activeDescriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isActive && !$0.isCompleted },
            sortBy: [SortDescriptor(\.deadline)]
        )

        let completedDescriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.deadline, order: .reverse)]
        )

        do {
            // `isExpired` is computed, so it splits the fetched rows here
            // rather than in the predicate.
            let open = try context.fetch(activeDescriptor)
            activeGoals = open.filter { !$0.isExpired }
            endedGoals = Array(open.filter(\.isExpired).reversed())
            completedGoals = try context.fetch(completedDescriptor)
        } catch {
            logger.error("Error loading goals: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    /// Adds a goal from a template, replacing `ended` when the user starts an
    /// ended goal over. One active goal per type: the cards say "Added", and
    /// this holds even if a tap slips through.
    @MainActor
    func createGoal(from template: GoalTemplate, replacing ended: UserGoal? = nil) async {
        guard let context = modelContext, !hasActiveGoal(of: template.type) else { return }

        if let ended {
            context.delete(ended)
        }

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
            logger.error("Error creating goal: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    @MainActor
    func deleteGoal(_ goal: UserGoal) async {
        guard let context = modelContext else { return }

        context.delete(goal)

        do {
            try context.save()
            Haptics.success()
            await loadGoals()
        } catch {
            logger.error("Error deleting goal: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
}

#Preview {
    GoalsView()
        .modelContainer(for: [UserGoal.self], inMemory: true)
}
