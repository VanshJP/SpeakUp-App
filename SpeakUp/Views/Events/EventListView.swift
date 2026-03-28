import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = EventViewModel()
    @State private var showingCreateEvent = false
    @State private var selectedEvent: SpeakingEvent?
    @State private var searchText = ""
    @State private var selectedSection: EventListSection = .upcoming
    var onStartPractice: ((SpeakingEvent, UUID?) -> Void)?
    var isSheet: Bool = true

    private var upcomingEvents: [SpeakingEvent] {
        viewModel.upcomingEvents
            .filter {
            searchText.isEmpty || $0.title.localizedStandardContains(searchText)
        }
            .sorted { $0.eventDate < $1.eventDate }
    }

    private var pastEvents: [SpeakingEvent] {
        viewModel.pastEvents
            .filter {
            searchText.isEmpty || $0.title.localizedStandardContains(searchText)
        }
            .sorted { $0.eventDate > $1.eventDate }
    }

    private var visibleEvents: [SpeakingEvent] {
        switch selectedSection {
        case .upcoming: return upcomingEvents
        case .past: return pastEvents
        case .all: return upcomingEvents + pastEvents
        }
    }

    var body: some View {
        let content = ZStack {
            AppBackground(style: .primary)

            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.events.isEmpty {
                        summaryCard
                    }

                    quickAddCard
                    sectionFilterPills

                    if viewModel.events.isEmpty {
                        EmptyStateCard(
                            icon: "calendar.badge.plus",
                            title: "No Events Yet",
                            message: "Add a speaking engagement and SpeakUp will guide your preparation with smart scheduling, scripts, and practice tracking.",
                            buttonTitle: "Create Event",
                            buttonAction: { showingCreateEvent = true }
                        )
                        .padding(.top, 20)
                    } else if visibleEvents.isEmpty {
                        EmptyStateCard(
                            icon: "magnifyingglass",
                            title: "No Matches",
                            message: searchText.isEmpty
                                ? "No events in this section."
                                : "Try a different search term."
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleEvents) { event in
                                Button {
                                    selectedEvent = event
                                } label: {
                                    EventCard(event: event)
                                        .opacity(event.isPast ? 0.75 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if let onStartPractice {
                                        Button {
                                            onStartPractice(event, event.currentScriptVersion?.id)
                                        } label: {
                                            Label("Practice", systemImage: "mic")
                                        }
                                    }

                                    Button {
                                        if event.isArchived {
                                            viewModel.unarchiveEvent(event)
                                        } else {
                                            viewModel.archiveEvent(event)
                                        }
                                        Haptics.light()
                                    } label: {
                                        Label(event.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.deleteEvent(event)
                                        Haptics.warning()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .searchable(text: $searchText, prompt: "Search events...")
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(viewModel: viewModel)
        }
        .navigationDestination(item: $selectedEvent) { event in
            EventDetailView(event: event, viewModel: viewModel, onStartPractice: onStartPractice)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }

        if isSheet {
            NavigationStack {
                content
                    .navigationTitle("Events")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Haptics.light()
                                showingCreateEvent = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }
            }
        } else {
            content
                .navigationTitle("Events")
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.light()
                            showingCreateEvent = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
        }
    }

    // MARK: - Quick Add Card

    private var quickAddCard: some View {
        Button {
            Haptics.medium()
            showingCreateEvent = true
        } label: {
            FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent]) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primary.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "calendar.badge.plus")
                            .font(.title3)
                            .foregroundStyle(AppColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add Speaking Event")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Set a deadline and let SpeakUp plan your prep")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                PromptStatItem(
                    icon: "calendar",
                    value: "\(viewModel.upcomingEvents.count)",
                    label: "Upcoming",
                    color: AppColors.primary
                )

                statsCardDivider

                PromptStatItem(
                    icon: "checkmark.seal.fill",
                    value: "\(readyCount)",
                    label: "Ready",
                    color: AppColors.success
                )

                statsCardDivider

                PromptStatItem(
                    icon: "mic.fill",
                    value: "\(totalPracticeCount)",
                    label: "Sessions",
                    color: .orange
                )

                statsCardDivider

                PromptStatItem(
                    icon: "clock.arrow.circlepath",
                    value: "\(viewModel.pastEvents.count)",
                    label: "Past",
                    color: AppColors.accent
                )
            }
        }
    }

    private var statsCardDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    private var readyCount: Int {
        viewModel.upcomingEvents.filter { $0.readinessScore >= 80 }.count
    }

    private var totalPracticeCount: Int {
        viewModel.events.reduce(0) { $0 + $1.totalPracticeCount }
    }

    // MARK: - Section Filter Pills

    private var sectionFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventListSection.allCases) { section in
                    sectionPill(section)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showArchived.toggle()
                        viewModel.loadEvents()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox")
                        Text(viewModel.showArchived ? "Hide Archived" : "Show Archived")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(viewModel.showArchived ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(viewModel.showArchived ? AppColors.accent : .ultraThinMaterial)
                    }
                }
            }
        }
    }

    private func sectionPill(_ section: EventListSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: section.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(section.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(AppColors.primary)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: SpeakingEvent

    var body: some View {
        GlassCard(tint: sessionTypeColor.opacity(0.06)) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(sessionTypeColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: event.resolvedSessionType.icon)
                        .font(.title3)
                        .foregroundStyle(sessionTypeColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(event.resolvedSessionType.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(sessionTypeColor)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !event.isOpenEnded {
                            Text(event.daysRemainingText)
                                .font(.caption2)
                                .foregroundStyle(daysColor)
                        } else {
                            Text("Open-ended")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if event.totalPracticeCount > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(event.totalPracticeCount) sessions")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                            if event.totalPracticeCount > 0 {
                                Capsule()
                                    .fill(AppColors.scoreGradient(for: event.readinessScore))
                                    .frame(width: geometry.size.width * CGFloat(event.readinessScore) / 100.0)
                            }
                        }
                    }
                    .frame(height: 4)
                }
                .frame(minHeight: 52, alignment: .center)

                Spacer(minLength: 4)

                VStack(spacing: 4) {
                    Text(event.totalPracticeCount > 0 ? "\(event.readinessScore)%" : "New")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(event.totalPracticeCount > 0 ? AppColors.scoreColor(for: event.readinessScore) : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var sessionTypeColor: Color {
        event.resolvedSessionType.color
    }

    private var daysColor: Color {
        let days = event.daysRemaining
        if days <= 1 { return AppColors.error }
        if days <= 3 { return AppColors.warning }
        return AppColors.accent
    }
}

// MARK: - Event List Section

enum EventListSection: String, CaseIterable, Identifiable {
    case upcoming
    case past
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .past: return "Past"
        case .all: return "All"
        }
    }

    var icon: String {
        switch self {
        case .upcoming: return "calendar"
        case .past: return "clock.arrow.circlepath"
        case .all: return "square.grid.2x2"
        }
    }
}
