import SwiftUI
import SwiftData

struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = EventPrepViewModel()
    let event: SpeakingEvent

    @State private var selectedSection: ScriptSection?
    @State private var showingAllTasks = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Readiness Ring
                    readinessSection

                    // Script Heat Map
                    if let sections = event.scriptSections, !sections.isEmpty {
                        scriptHeatMap(sections)
                    }

                    // Next Task
                    if let task = viewModel.nextTask {
                        nextTaskSection(task)
                    }

                    // Upcoming Tasks
                    if !viewModel.upcomingTasks.isEmpty {
                        upcomingTasksSection
                    }

                    // Quick Actions
                    quickActionsSection

                    // Stats
                    statsSection
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
            viewModel.loadTasks(for: event)
        }
        .navigationDestination(item: $selectedSection) { section in
            ScriptSectionDetailView(event: event, section: section)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        GlassCard(tint: AppColors.primary.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.eventDate.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(event.daysRemainingText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(event.daysRemaining <= 3 ? AppColors.warning : AppColors.primary)
                    }

                    Spacer()

                    // Phase badge
                    Text(event.currentPhase.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(phaseColor(event.currentPhase))
                        }
                }

                if let audience = event.audienceType {
                    Label(audience, systemImage: "person.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let venue = event.venue {
                    Label(venue, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Readiness Ring

    private var readinessSection: some View {
        GlassCard {
            VStack(spacing: 12) {
                Text("Readiness Score")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: Double(event.readinessScore) / 100.0)
                        .stroke(
                            AppColors.scoreGradient(for: event.readinessScore),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(event.readinessScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: event.readinessScore))

                        Text("/100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress bar
                HStack(spacing: 16) {
                    statPill(label: "Completed", value: "\(viewModel.completedTaskCount)/\(viewModel.tasks.count)", icon: "checkmark.circle")
                    statPill(label: "Practices", value: "\(event.totalPracticeCount)", icon: "mic.fill")
                }
            }
        }
    }

    private func statPill(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(AppColors.primary)
            Text(value)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Script Heat Map

    private func scriptHeatMap(_ sections: [ScriptSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Script Sections", icon: "doc.text.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.scoreColor(for: section.masteryScore).opacity(0.6))
                                    .frame(width: 50, height: 40)
                                    .overlay {
                                        Text("\(section.masteryScore)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }

                                Text(section.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Next Task

    private func nextTaskSection(_ task: EventPrepTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Next Up", icon: "arrow.right.circle.fill")

            EventPrepTaskRow(
                task: task,
                onStart: { startTask(task) },
                onComplete: { viewModel.completeTask(task) }
            )
        }
    }

    // MARK: - Upcoming Tasks

    private var upcomingTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader("Upcoming", icon: "list.bullet")
                Spacer()
                if viewModel.upcomingTasks.count > 5 {
                    Button {
                        showingAllTasks = true
                    } label: {
                        Text("See All")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                    }
                }
            }

            ForEach(Array(viewModel.upcomingTasks.prefix(5))) { task in
                EventPrepTaskRow(
                    task: task,
                    onStart: { startTask(task) },
                    onComplete: { viewModel.completeTask(task) }
                )
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            GlassIconButton(icon: "play.circle.fill", tint: .teal) {
                // Full rehearsal: create an ad-hoc task
                Haptics.medium()
            }

            if event.scriptText != nil {
                GlassIconButton(icon: "pencil.circle.fill", tint: .blue) {
                    Haptics.light()
                }
            }

            GlassIconButton(icon: "list.bullet.circle.fill", tint: .purple) {
                showingAllTasks = true
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        GlassCard(tint: AppColors.glassTintAccent) {
            VStack(spacing: 12) {
                GlassSectionHeader("Stats", icon: "chart.bar.fill")

                HStack(spacing: 0) {
                    statItem(
                        value: "\(viewModel.completedTaskCount)",
                        label: "Completed",
                        color: AppColors.success
                    )
                    statItem(
                        value: "\(event.totalPracticeCount)",
                        label: "Practices",
                        color: AppColors.primary
                    )
                    statItem(
                        value: "\(event.expectedDurationMinutes)m",
                        label: "Duration",
                        color: AppColors.info
                    )
                }
            }
        }
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func phaseColor(_ phase: EventPrepPhase) -> Color {
        switch phase {
        case .foundation: return .blue
        case .building: return .orange
        case .performance: return .red
        }
    }

    private func startTask(_ task: EventPrepTask) {
        // Task launching is handled via the parent ContentView callbacks
        // For now, mark as started
        Haptics.medium()
    }
}
