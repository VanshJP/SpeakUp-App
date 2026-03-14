import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: SpeakingEvent
    @Bindable var viewModel: EventViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showingScriptEditor = false
    @State private var showingTeleprompter = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Countdown header
                    countdownHeader

                    // Readiness score
                    if event.totalPracticeCount > 0 {
                        readinessCard
                    }

                    // Quick actions
                    quickActions

                    // Script section
                    if event.scriptText != nil {
                        scriptSection
                    }

                    // Prep tasks
                    if !viewModel.prepTasks.isEmpty {
                        prepTasksSection
                    }

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
        }
        .sheet(isPresented: $showingScriptEditor) {
            ScriptEditorView(event: event, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingTeleprompter) {
            if let script = event.scriptText {
                TeleprompterView(
                    scriptText: script,
                    speed: event.teleprompterSpeed,
                    fontSize: event.teleprompterFontSize
                )
            }
        }
        .alert("Delete Event", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                viewModel.deleteEvent(event)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the event and all prep tasks.")
        }
    }

    // MARK: - Countdown Header

    private var countdownHeader: some View {
        FeaturedGlassCard(gradientColors: [.teal.opacity(0.12), .cyan.opacity(0.06)]) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: event.resolvedSessionType.icon)
                        .font(.title2)
                        .foregroundStyle(.teal)

                    Text(event.resolvedSessionType.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(event.currentPhase.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.teal.opacity(0.2)) }
                        .foregroundStyle(.teal)
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

    // MARK: - Script Section

    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Script", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                if event.currentVersionNumber > 0 {
                    Text("v\(event.currentVersionNumber)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(.ultraThinMaterial) }
                }
            }

            if let sections = event.scriptSections, !sections.isEmpty {
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
            Label("Prep Tasks", systemImage: "checklist")
                .font(.headline)

            let todayTasks = viewModel.prepTasks.filter { Calendar.current.isDateInToday($0.scheduledDate) || $0.isOverdue }

            ForEach(todayTasks) { task in
                GlassCard(padding: 12) {
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

                            if task.isOverdue {
                                Text("Overdue")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.red)
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
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.teal)

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
                }
            }
        }
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
