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
        case .upcoming:
            return upcomingEvents
        case .past:
            return pastEvents
        case .all:
            return upcomingEvents + pastEvents
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .primary)

                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        sectionFilterCard

                        if viewModel.events.isEmpty {
                            emptyStateCard(
                                title: "No Events Yet",
                                message: "Create one event and SpeakUp builds your prep path."
                            )
                        } else if visibleEvents.isEmpty {
                            emptyStateCard(
                                title: "No Matches",
                                message: searchText.isEmpty
                                    ? "No events in this section yet."
                                    : "Try a different search term."
                            )
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(visibleEvents) { event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        EventCard(event: event)
                                            .opacity(event.isPast ? 0.75 : 1.0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search events")
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
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(AppColors.primary)
                    }
                }
            }
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView(viewModel: viewModel)
            }
            .navigationDestination(item: $selectedEvent) { event in
                EventDetailView(event: event, viewModel: viewModel, onStartPractice: onStartPractice)
            }
            .onAppear {
                viewModel.configure(with: modelContext)
            }
        }
    }

    private var summaryCard: some View {
        FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your speaking pipeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    metricPill(
                        title: "Upcoming",
                        value: "\(viewModel.upcomingEvents.count)",
                        icon: "calendar",
                        tint: AppColors.primary
                    )
                    metricPill(
                        title: "Ready 80+",
                        value: "\(viewModel.upcomingEvents.filter { $0.readinessScore >= 80 }.count)",
                        icon: "checkmark.seal.fill",
                        tint: AppColors.success
                    )
                    metricPill(
                        title: "Past",
                        value: "\(viewModel.pastEvents.count)",
                        icon: "clock.arrow.circlepath",
                        tint: AppColors.accent
                    )
                }
            }
        }
    }

    private var sectionFilterCard: some View {
        GlassCard(tint: AppColors.glassTintPrimary.opacity(0.65), padding: 12) {
            VStack(spacing: 10) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(EventListSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(viewModel.showArchived ? "Archived included" : "Archived hidden")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showArchived.toggle()
                            viewModel.loadEvents()
                        }
                    } label: {
                        Text(viewModel.showArchived ? "Hide archived" : "Show archived")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func metricPill(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
        }
    }

    private func emptyStateCard(title: String, message: String) -> some View {
        EmptyStateCard(
            icon: "calendar.badge.plus",
            title: title,
            message: message,
            buttonTitle: "Create Event",
            buttonAction: { showingCreateEvent = true }
        )
        .padding(.top, 40)
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: SpeakingEvent

    var body: some View {
        GlassCard(tint: sessionTypeColor.opacity(0.06)) {
            HStack(spacing: 14) {
                // Session type icon
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

                        if let audienceSize = event.audienceSize, audienceSize > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(audienceSize.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)

                    // Readiness bar (always show)
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

private enum EventListSection: String, CaseIterable, Identifiable {
    case upcoming
    case past
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .past:
            return "Past"
        case .all:
            return "All"
        }
    }
}
