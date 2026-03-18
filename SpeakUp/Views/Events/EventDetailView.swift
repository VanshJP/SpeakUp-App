import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: SpeakingEvent
    @Bindable var viewModel: EventViewModel
    var onStartPractice: ((SpeakingEvent, UUID?) -> Void)?
    @Environment(\.modelContext) private var modelContext

    @Query private var userSettings: [UserSettings]

    @State private var showingScriptEditor = false
    @State private var showingTeleprompter = false
    @State private var showingDeleteConfirm = false
    @State private var showingWarmUps = false
    @State private var showingConfidenceTools = false
    @State private var showingReadAloud = false
    @State private var showingDrillSession = false
    @State private var showingDrillCountdown = false
    @State private var selectedDrillMode: DrillMode?
    @State private var drillViewModel = DrillViewModel()
    @State private var selectedPracticeVersionId: UUID?
    @State private var showingNotificationSchedule = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Countdown header
                    countdownHeader

                    // Coaching tip
                    coachingTipCard

                    // Readiness score
                    if event.totalPracticeCount > 0 {
                        readinessCard
                    }

                    // Quick actions
                    quickActions

                    // Recommended tools
                    recommendedToolsSection

                    // Script section
                    if event.scriptText != nil {
                        scriptSection
                    }

                    // Script revision progress
                    if !viewModel.revisionMilestones.isEmpty {
                        revisionProgressSection
                    }

                    // Prep timeline
                    if !viewModel.timelineDays.isEmpty {
                        prepTasksSection
                    }

                    notificationPreviewSection

                    // Linked recordings
                    if !viewModel.linkedRecordings.isEmpty {
                        recordingsSection
                    }

                    // Event info
                    eventInfoSection

                    // Danger zone
                    dangerZone
                }
                .padding()
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure(with: modelContext)
            viewModel.selectedEvent = event
            viewModel.loadLinkedRecordings(for: event)
            viewModel.loadPrepTasks(for: event)
            if selectedPracticeVersionId == nil {
                selectedPracticeVersionId = event.currentScriptVersion?.id
            }
        }
        .sheet(isPresented: $showingScriptEditor) {
            ScriptEditorView(event: event, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingTeleprompter) {
            if let script = event.scriptText {
                TeleprompterView(
                    scriptText: script,
                    speed: event.teleprompterSpeed,
                    fontSize: event.teleprompterFontSize,
                    onSettingsChanged: { newSpeed, newFontSize in
                        event.teleprompterSpeed = newSpeed
                        event.teleprompterFontSize = newFontSize
                        try? modelContext.save()
                    }
                )
            }
        }
        .sheet(isPresented: $showingWarmUps) {
            WarmUpListView()
        }
        .sheet(isPresented: $showingConfidenceTools) {
            ConfidenceToolsView()
        }
        .sheet(isPresented: $showingReadAloud) {
            ReadAloudSelectionView()
        }
        .fullScreenCover(isPresented: $showingDrillSession) {
            DrillSessionView(viewModel: drillViewModel)
        }
        .overlay {
            if showingDrillCountdown {
                CountdownOverlayView(
                    prompt: nil,
                    duration: .thirty,
                    countdownDuration: userSettings.first?.countdownDuration ?? 15,
                    countdownStyle: CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown,
                    onComplete: {
                        showingDrillCountdown = false
                        if let mode = selectedDrillMode {
                            drillViewModel.startDrill(mode: mode)
                            showingDrillSession = true
                        }
                    },
                    onCancel: {
                        showingDrillCountdown = false
                        selectedDrillMode = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingDrillCountdown)
        .alert("Delete Event", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                viewModel.deleteEvent(event)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the event and all prep tasks.")
        }
        .sheet(isPresented: $showingNotificationSchedule) {
            NavigationStack {
                notificationScheduleView
            }
        }
    }

    private var scriptVersions: [ScriptVersion] {
        (event.scriptVersions ?? []).sorted { $0.versionNumber > $1.versionNumber }
    }

    private var selectedPracticeVersion: ScriptVersion? {
        guard let selectedPracticeVersionId else { return event.currentScriptVersion }
        return scriptVersions.first { $0.id == selectedPracticeVersionId } ?? event.currentScriptVersion
    }

    private var nextScheduledNotifications: [EventNotificationPreviewItem] {
        let now = Date()
        return viewModel.prepTasks
            .filter { !$0.isCompleted }
            .compactMap { task in
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: task.scheduledDate)
                comps.hour = 9
                comps.minute = 0
                guard let trigger = Calendar.current.date(from: comps), trigger > now else { return nil }
                return EventNotificationPreviewItem(
                    taskTitle: task.title,
                    taskDescription: task.taskDescription,
                    scheduledDate: trigger
                )
            }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    // MARK: - Countdown Header

    private var countdownHeader: some View {
        FeaturedGlassCard(gradientColors: [.teal.opacity(0.12), .cyan.opacity(0.06)]) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: event.resolvedSessionType.icon)
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)

                    Text(event.resolvedSessionType.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(event.currentPhase.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(AppColors.primary.opacity(0.2)) }
                        .foregroundStyle(AppColors.primary)
                }

                Text(event.daysRemainingText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                if !event.isOpenEnded {
                    Text(event.eventDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label("\(event.totalPracticeCount) practices", systemImage: "mic.fill")
                    if let last = event.lastPracticeDate {
                        Label("Last: \(last.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Coaching Tip Card

    private var coachingTipCard: some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                Text(event.resolvedSessionType.coachingTip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Readiness Card

    private var readinessCard: some View {
        GlassCard(tint: AppColors.scoreColor(for: event.readinessScore).opacity(0.06)) {
            VStack(spacing: 10) {
                HStack {
                    Text("Readiness")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(event.readinessScore)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: event.readinessScore))
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(AppColors.scoreGradient(for: event.readinessScore))
                            .frame(width: geometry.size.width * CGFloat(event.readinessScore) / 100.0)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            if let onStartPractice {
                GlassButton(title: "Practice", icon: "mic.fill", style: .primary) {
                    Haptics.medium()
                    onStartPractice(event, selectedPracticeVersion?.id)
                }
            }

            HStack(spacing: 12) {
                if event.scriptText != nil {
                    GlassButton(title: "Script", icon: "doc.text", style: .secondary, size: .small) {
                        showingScriptEditor = true
                    }
                    GlassButton(title: "Teleprompter", icon: "text.alignleft", style: .secondary, size: .small) {
                        showingTeleprompter = true
                    }
                } else {
                    GlassButton(title: "Add Script", icon: "doc.badge.plus", style: .secondary, size: .small) {
                        showingScriptEditor = true
                    }
                }
            }

            if let selectedPracticeVersion {
                HStack(spacing: 8) {
                    Label(
                        "Practice using v\(selectedPracticeVersion.versionNumber)",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    Spacer()
                    Text("\(selectedPracticeVersion.wordCount) words")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(AppColors.primary.opacity(0.15))
                }
            }
        }
    }

    // MARK: - Recommended Tools

    private var recommendedToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Recommended for \(event.resolvedSessionType.rawValue)", icon: "star.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(event.resolvedSessionType.recommendedTools) { tool in
                        Button {
                            Haptics.medium()
                            launchTool(tool.action)
                        } label: {
                            GlassCard(padding: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: tool.icon)
                                        .font(.title2)
                                        .foregroundStyle(tool.color)

                                    Text(tool.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Text(tool.tip)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func launchTool(_ action: ToolAction) {
        switch action {
        case .drill(let mode):
            selectedDrillMode = mode
            showingDrillCountdown = true
        case .readAloud:
            showingReadAloud = true
        case .warmUp:
            showingWarmUps = true
        case .confidence:
            showingConfidenceTools = true
        case .teleprompter:
            showingTeleprompter = true
        case .script:
            showingScriptEditor = true
        }
    }

    // MARK: - Script Section

    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Script", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                Button {
                    showingScriptEditor = true
                } label: {
                    Label("New Version", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(AppColors.primary.opacity(0.16))
                        }
                }
                .buttonStyle(.plain)
            }

            if !scriptVersions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(scriptVersions, id: \.id) { version in
                            let isSelected = selectedPracticeVersionId == version.id || (selectedPracticeVersionId == nil && version.id == event.currentScriptVersion?.id)
                            Button {
                                selectedPracticeVersionId = version.id
                            } label: {
                                HStack(spacing: 6) {
                                    Text("v\(version.versionNumber)")
                                        .font(.caption.weight(.semibold))
                                    Text("\(version.wordCount)w")
                                        .font(.caption2)
                                }
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule()
                                        .fill(isSelected ? AppColors.primary : Color.white.opacity(0.08))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let selectedVersion = selectedPracticeVersion {
                if let note = selectedVersion.changeNote, !note.isEmpty {
                    GlassCard(padding: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                ForEach(selectedVersion.scriptSections, id: \.id) { section in
                    GlassCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(section.wordCount) words")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(section.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            } else if let sections = event.scriptSections, !sections.isEmpty {
                ForEach(sections, id: \.id) { section in
                    GlassCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(section.wordCount) words")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(section.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prep Tasks Section

    private var prepTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prep Timeline", systemImage: "calendar.badge.clock")
                .font(.headline)

            GlassCard(tint: AppColors.glassTintPrimary) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeline Completion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(completedPrepCount) of \(viewModel.prepTasks.count) tasks done")
                            .font(.subheadline.weight(.semibold))
                        Text("Target near event: \(event.maxDailyPracticeMinutes) min/day")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Foundation ~\(event.phasePracticeTargets.foundation)m · Building ~\(event.phasePracticeTargets.building)m · Performance ~\(event.phasePracticeTargets.performance)m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(Int(prepCompletionRatio * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: Int(prepCompletionRatio * 100)))
                }
            }

            ForEach(visibleTimelineDays) { day in
                GlassCard(tint: day.hasOverdueTasks ? AppColors.glassTintWarning.opacity(0.3) : nil, padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(dayLabel(for: day.date, isToday: day.isToday))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(day.hasOverdueTasks ? AppColors.warning : .white)

                            Spacer()

                            Text("\(day.completedCount)/\(day.tasks.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background { Capsule().fill(.ultraThinMaterial) }

                            Text("~\(day.estimatedMinutes)m")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background { Capsule().fill(AppColors.primary.opacity(0.16)) }
                        }

                        ForEach(day.tasks) { task in
                            HStack(spacing: 12) {
                                Button {
                                    Haptics.success()
                                    viewModel.completeTask(task)
                                } label: {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .font(.subheadline.weight(.medium))
                                        .strikethrough(task.isCompleted)
                                        .foregroundStyle(task.isCompleted ? .secondary : .primary)

                                    Text(task.taskDescription)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        if task.isOverdue {
                                            Text("Overdue")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.red)
                                        }
                                        Text("~\(task.estimatedMinutes)m")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(AppColors.primary)
                                        Text(priorityLabel(for: task.priority))
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: task.type.icon)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Revision Progress

    private var revisionProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Revision Loop", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.headline)

            ForEach(viewModel.revisionMilestones.prefix(4)) { milestone in
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("v\(milestone.versionNumber)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background { Capsule().fill(AppColors.primary.opacity(0.18)) }
                                Text(milestone.createdDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(milestone.changeNote)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            Text("\(milestone.wordCount) words · \(milestone.practiceCount) practice run\(milestone.practiceCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            if let score = milestone.bestScore {
                                Text("\(score)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.scoreColor(for: score))
                            } else {
                                Text("--")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            if let delta = milestone.scoreDeltaFromPrevious {
                                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(delta >= 0 ? .green : .orange)
                            } else {
                                Text("Baseline")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleTimelineDays: [EventTimelineDay] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let overdueOrToday = viewModel.timelineDays.filter { $0.date <= startOfToday }
        let upcoming = viewModel.timelineDays.filter { $0.date > startOfToday }
        let recent = Array(overdueOrToday.suffix(2))
        let next = Array(upcoming.prefix(7))
        return recent + next
    }

    private var completedPrepCount: Int {
        viewModel.prepTasks.filter(\.isCompleted).count
    }

    private var prepCompletionRatio: Double {
        guard !viewModel.prepTasks.isEmpty else { return 0 }
        return Double(completedPrepCount) / Double(viewModel.prepTasks.count)
    }

    private func dayLabel(for date: Date, isToday: Bool) -> String {
        if isToday { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func priorityLabel(for priority: Int) -> String {
        switch priority {
        case ..<2: return "High priority"
        case 2: return "Medium priority"
        default: return "Low priority"
        }
    }

    // MARK: - Notification Preview

    private var notificationPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Smart Reminders", systemImage: "bell.badge")
                    .font(.headline)
                Spacer()
                Button {
                    showingNotificationSchedule = true
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }

            GlassCard {
                if nextScheduledNotifications.isEmpty {
                    Text("No future reminder slots yet. Complete or regenerate prep tasks to build your reminder timeline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(nextScheduledNotifications.prefix(3)) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "bell")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.primary)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.taskTitle)
                                        .font(.caption.weight(.semibold))
                                    Text(item.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var notificationScheduleView: some View {
        List {
            if nextScheduledNotifications.isEmpty {
                Text("No upcoming reminders scheduled.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nextScheduledNotifications) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.taskTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(item.taskDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Reminder Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .appBackground(.subtle)
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordings (\(viewModel.linkedRecordings.count))", systemImage: "waveform")
                    .font(.headline)
                Spacer()
            }

            ForEach(viewModel.linkedRecordings.prefix(5)) { recording in
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(AppColors.primary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(recording.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(recording.formattedDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let score = recording.analysis?.speechScore.overall {
                                Text("\(score)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.scoreColor(for: score))
                            }
                        }

                        if let practicedVersion = practicedScriptVersionLabel(for: recording) {
                            Text(practicedVersion)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule()
                                        .fill(AppColors.primary.opacity(0.15))
                                }
                        }

                        if let scriptInsight = viewModel.scriptInsightsByRecordingId[recording.id] {
                            HStack(spacing: 8) {
                                Label("\(scriptInsight.adherenceScore)% script match", systemImage: "checkmark.seal")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppColors.scoreColor(for: scriptInsight.adherenceScore))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background {
                                        Capsule()
                                            .fill(AppColors.scoreColor(for: scriptInsight.adherenceScore).opacity(0.15))
                                    }

                                if !scriptInsight.missedKeywords.isEmpty {
                                    Text("Missed: \(scriptInsight.missedKeywords.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func practicedScriptVersionLabel(for recording: Recording) -> String? {
        guard let versionId = recording.scriptVersionId,
              let version = scriptVersions.first(where: { $0.id == versionId }) else {
            return nil
        }
        return "Practiced with v\(version.versionNumber)"
    }

    // MARK: - Event Info Section

    private var eventInfoSection: some View {
        GlassCard {
            VStack(spacing: 12) {
                GlassInfoRow(label: "Duration", value: "\(event.expectedDurationMinutes) min", icon: "clock")

                if let audience = event.audienceType {
                    Divider()
                    GlassInfoRow(label: "Audience", value: audience, icon: "person.2")
                }

                Divider()
                GlassInfoRow(label: "Daily Practice Capacity", value: "\(event.maxDailyPracticeMinutes) min", icon: "timer")

                if let audienceSize = event.audienceSize, audienceSize > 0 {
                    Divider()
                    GlassInfoRow(
                        label: "Audience Size",
                        value: "\(audienceSize.formatted()) (\(event.audienceScaleLabel))",
                        icon: "person.3"
                    )
                }

                if let venue = event.venue, !venue.isEmpty {
                    Divider()
                    GlassInfoRow(label: event.resolvedSessionType.venueLabel, value: venue, icon: "mappin")
                }

                Divider()
                GlassInfoRow(label: "Created", value: event.createdDate.formatted(date: .abbreviated, time: .omitted), icon: "calendar.badge.plus")
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(spacing: 12) {
            if !event.isArchived {
                GlassButton(title: "Archive Event", icon: "archivebox", style: .secondary) {
                    Haptics.warning()
                    viewModel.archiveEvent(event)
                }
            }

            GlassButton(title: "Delete Event", icon: "trash", style: .danger) {
                Haptics.warning()
                showingDeleteConfirm = true
            }
        }
        .padding(.top, 8)
    }
}

private struct EventNotificationPreviewItem: Identifiable {
    let taskTitle: String
    let taskDescription: String
    let scheduledDate: Date

    var id: String {
        "\(taskTitle)|\(taskDescription)|\(scheduledDate.timeIntervalSince1970)"
    }
}
