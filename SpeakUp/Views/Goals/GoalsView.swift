import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GoalsViewModel()
    @State private var showingAddGoal = false
    
    var body: some View {
        List {
            // Active Goals
            if !viewModel.activeGoals.isEmpty {
                Section("Active Goals") {
                    ForEach(viewModel.activeGoals) { goal in
                        GoalCard(goal: goal)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteGoal(goal)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            
            // Goal Templates
            Section("Add a Goal") {
                ForEach(GoalTemplate.templates, id: \.title) { template in
                    GoalTemplateRow(template: template) {
                        Task {
                            await viewModel.createGoal(from: template)
                        }
                    }
                }
            }
            
            // Completed Goals
            if !viewModel.completedGoals.isEmpty {
                Section("Completed") {
                    ForEach(viewModel.completedGoals) { goal in
                        CompletedGoalRow(goal: goal)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteGoal(goal)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .overlay {
            if viewModel.activeGoals.isEmpty && viewModel.completedGoals.isEmpty {
                ContentUnavailableView(
                    "No Goals Yet",
                    systemImage: "target",
                    description: Text("Set a goal to track your speaking progress")
                )
            }
        }
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: UserGoal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: goal.type.iconName)
                    .foregroundStyle(.teal)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(Color.teal.opacity(0.1))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.headline)
                    
                    Text(goal.goalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(goal.progressPercentage)%")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.teal)
                    
                    if goal.daysRemaining > 0 {
                        Text("\(goal.daysRemaining)d left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Expired")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            // Progress bar
            ProgressView(value: goal.progress)
                .tint(.teal)
            
            // Stats
            HStack {
                Label("\(goal.current)/\(goal.target) \(goal.type.unit)", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if goal.isExpired && !goal.isCompleted {
                    Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Goal Template Row

struct GoalTemplateRow: View {
    let template: GoalTemplate
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack {
                Image(systemName: template.type.iconName)
                    .foregroundStyle(.teal)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(Color.teal.opacity(0.1))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.teal)
            }
        }
    }
}

// MARK: - Completed Goal Row

struct CompletedGoalRow: View {
    let goal: UserGoal
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline)
                    .strikethrough(true, color: .secondary)
                
                Text("Completed \(goal.deadline.relativeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .foregroundStyle(.secondary)
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
    NavigationStack {
        GoalsView()
    }
    .modelContainer(for: [UserGoal.self], inMemory: true)
}
