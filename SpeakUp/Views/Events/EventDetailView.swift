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
    @State private var draftEventDate = Date()
    @State private var draftExpectedDurationMinutes = 5
    @State private var draftDailyPracticeMinutes = 30
    @State private var showFullPrepTimeline = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    countdownHeader
                    quickActions
                    practiceMetrics
                    practiceChartSection
                    todayFocusSection
                    recommendedToolsCompactSection
                    if event.scriptText != nil { scriptAtAGlanceSection }
                    logisticsEditorSection
                    if !viewModel.linkedRecordings.isEmpty { recordingsSection }
                    dangerZone
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
            viewModel.selectedEvent = event
            viewModel.loadLinkedRecordings(for: event)
            viewModel.loadPrepTasks(for: event)
            if selectedPracticeVersionId == nil {
                selectedPracticeVersionId = event.currentScriptVersion?.id
            }
            draftEventDate = event.eventDate
            draftExpectedDurationMinutes = event.expectedDurationMinutes
            draftDailyPracticeMinutes = event.maxDailyPracticeMinutes
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
                    onStartRecording: {
                        showingTeleprompter = false
                        onStartPractice?(event, selectedPracticeVersion?.id)
                    },
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
    }

    private var scriptVersions: [ScriptVersion] {
        (event.scriptVersions ?? []).sorted { $0.versionNumber > $1.versionNumber }
    }

    private var selectedPracticeVersion: ScriptVersion? {
        guard let selectedPracticeVersionId else { return event.currentScriptVersion }
        return scriptVersions.first { $0.id == selectedPracticeVersionId } ?? event.currentScriptVersion
    }

    // MARK: - Countdown Header

    private var countdownHeader: some View {
        FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent]) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: event.resolvedSessionType.icon)
                        .font(.title2)
                        .foregroundStyle(event.resolvedSessionType.color)

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

                if event.totalPracticeCount > 0 {
                    readinessBar
                }
            }
        }
    }

    private var readinessBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Readiness")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(event.readinessScore)%")
                    .font(.caption.weight(.bold))
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
            .frame(height: 6)
            .clipShape(Capsule())
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            if let onStartPractice {
                GlassButton(title: "Practice Now", icon: "mic.fill", style: .primary, size: .large, fullWidth: true) {
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
        }
    }

    // MARK: - Practice Metrics

    private var practiceMetrics: some View {
        PracticeMetricsRow(recordings: viewModel.linkedRecordings)
    }

    // MARK: - Practice Chart

    @ViewBuilder
    private var practiceChartSection: some View {
        if !viewModel.linkedRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Score Trend", icon: "chart.line.uptrend.xyaxis")
                PracticeHistoryChart(
                    dataPoints: PracticeDataPoint.from(recordings: viewModel.linkedRecordings),
                    accentColor: event.resolvedSessionType.color
                )
            }
        }
    }

    // MARK: - Today Focus

    private var todayFocusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Today Focus", icon: "checklist")

            GlassCard(tint: AppColors.glassTintPrimary.opacity(0.55)) {
                if viewModel.prepTasks.isEmpty {
                    Text("No prep tasks yet. Save plan details to generate your timeline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    todayFocusContent
                }
            }
        }
    }

    private var todayFocusContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(completedPrepCount) / \(viewModel.prepTasks.count) completed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(prepCompletionRatio * 100))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.scoreColor(for: Int(prepCompletionRatio * 100)))
            }

            ForEach(visibleFocusTasks) { task in
                focusTaskRow(task)
            }

            if viewModel.prepTasks.count > 4 {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullPrepTimeline.toggle()
                    }
                } label: {
                    Text(showFullPrepTimeline ? "Show less" : "Show full timeline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func focusTaskRow(_ task: EventPrepTask) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.success()
                viewModel.completeTask(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(task.isCompleted ? AppColors.success : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.white)
                Text(task.taskDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(task.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var visibleFocusTasks: [EventPrepTask] {
        let sorted = viewModel.prepTasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            return lhs.scheduledDate < rhs.scheduledDate
        }
        if showFullPrepTimeline {
            return sorted
        }
        return Array(sorted.prefix(4))
    }

    // MARK: - Recommended Tools

    private var recommendedToolsCompactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Recommended Tools", icon: "star.fill")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(event.resolvedSessionType.recommendedTools.prefix(4)) { tool in
                    Button {
                        Haptics.medium()
                        launchTool(tool.action)
                    } label: {
                        GlassCard(tint: tool.color.opacity(0.08), padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: tool.icon)
                                    .font(.headline)
                                    .foregroundStyle(tool.color)
                                Text(tool.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(tool.tip)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
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

    // MARK: - Script At A Glance

    private var scriptAtAGlanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader("Script", icon: "doc.text")
                Spacer()
                Button {
                    showingScriptEditor = true
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }

            if let selectedVersion = selectedPracticeVersion {
                GlassCard(tint: AppColors.glassTintAccent) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Version \(selectedVersion.versionNumber)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                            Spacer()
                            Text("\(selectedVersion.wordCount) words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let firstSection = selectedVersion.scriptSections.first {
                            Text(firstSection.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
            } else if let script = event.scriptText {
                GlassCard(tint: AppColors.glassTintAccent) {
                    Text(script)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Logistics Editor

    private var logisticsEditorSection: some View {
        GlassCard(tint: AppColors.glassTintPrimary.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Plan Details", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    if hasLogisticsChanges {
                        Text("Unsaved")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background { Capsule().fill(AppColors.warning.opacity(0.16)) }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppColors.primary)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Event Date")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: $draftEventDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(AppColors.primary)
                    }
                    Spacer()
                }

                Divider()

                Stepper(value: $draftExpectedDurationMinutes, in: 1...180, step: 1) {
                    HStack {
                        Label("Duration", systemImage: "clock")
                            .font(.subheadline)
                        Spacer()
                        Text("\(draftExpectedDurationMinutes) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                }

                Divider()

                Stepper(value: $draftDailyPracticeMinutes, in: 10...240, step: 5) {
                    HStack {
                        Label("Daily Practice", systemImage: "timer")
                            .font(.subheadline)
                        Spacer()
                        Text("\(draftDailyPracticeMinutes) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                }

                if hasLogisticsChanges {
                    GlassButton(title: "Save Plan Details", icon: "checkmark.circle", style: .primary, size: .small) {
                        Haptics.success()
                        viewModel.updateEventLogistics(
                            event,
                            eventDate: draftEventDate,
                            expectedDurationMinutes: draftExpectedDurationMinutes,
                            maxDailyPracticeMinutes: draftDailyPracticeMinutes
                        )
                    }
                }
            }
        }
    }

    private var hasLogisticsChanges: Bool {
        let isDateChanged = abs(draftEventDate.timeIntervalSince(event.eventDate)) > 1
        return isDateChanged ||
            draftExpectedDurationMinutes != event.expectedDurationMinutes ||
            draftDailyPracticeMinutes != event.maxDailyPracticeMinutes
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Practice History", icon: "waveform")

            LazyVStack(spacing: 10) {
                ForEach(viewModel.linkedRecordings.prefix(5)) { recording in
                    GlassCard(padding: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(AppColors.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                HStack(spacing: 8) {
                                    Text(recording.formattedDuration)
                                    if let wpm = recording.analysis?.wordsPerMinute, wpm > 0 {
                                        Text("\(Int(wpm)) wpm")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let score = recording.analysis?.speechScore.overall {
                                Text("\(score)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.scoreColor(for: score))
                            }

                            if let scriptInsight = viewModel.scriptInsightsByRecordingId[recording.id] {
                                Text("\(scriptInsight.adherenceScore)%")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.scoreColor(for: scriptInsight.adherenceScore))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background {
                                        Capsule().fill(AppColors.scoreColor(for: scriptInsight.adherenceScore).opacity(0.15))
                                    }
                            }
                        }
                    }
                }
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

    private var completedPrepCount: Int {
        viewModel.prepTasks.filter(\.isCompleted).count
    }

    private var prepCompletionRatio: Double {
        guard !viewModel.prepTasks.isEmpty else { return 0 }
        return Double(completedPrepCount) / Double(viewModel.prepTasks.count)
    }
}
