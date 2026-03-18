import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = EventViewModel()
    @State private var showingCreateEvent = false
    @State private var selectedEvent: SpeakingEvent?
    @State private var searchText = ""
    @State private var sortOption: EventSortOption = .soonest
    var onStartPractice: ((SpeakingEvent, UUID?) -> Void)?

    private var upcomingEvents: [SpeakingEvent] {
        let filtered = viewModel.upcomingEvents.filter {
            searchText.isEmpty || $0.title.localizedStandardContains(searchText)
        }
        return sortOption.sorted(filtered)
    }

    private var pastEvents: [SpeakingEvent] {
        viewModel.pastEvents.filter {
            searchText.isEmpty || $0.title.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        eventOrganizationControls

                        if viewModel.events.isEmpty {
                            EmptyStateCard(
                                icon: "calendar.badge.plus",
                                title: "No Events Yet",
                                message: "Create an event to start preparing for your next speaking opportunity.",
                                buttonTitle: "Create Event",
                                buttonAction: { showingCreateEvent = true }
                            )
                            .padding(.top, 40)
                        } else {
                            // Upcoming events
                            if !upcomingEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Upcoming", systemImage: "calendar")
                                        .font(.headline)

                                    ForEach(upcomingEvents) { event in
                                        Button {
                                            selectedEvent = event
                                        } label: {
                                            EventCard(event: event)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Past events
                            if !pastEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Past", systemImage: "clock.arrow.circlepath")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    ForEach(pastEvents) { event in
                                        Button {
                                            selectedEvent = event
                                        } label: {
                                            EventCard(event: event)
                                                .opacity(0.7)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
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
                            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var eventOrganizationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Organize", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.showArchived.toggle()
                        viewModel.loadEvents()
                    }
                } label: {
                    Text(viewModel.showArchived ? "Hide archived" : "Show archived")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EventSortOption.allCases) { option in
                        FilterChip(
                            title: option.title,
                            icon: option.icon,
                            isSelected: sortOption == option
                        ) {
                            withAnimation(.spring(response: 0.25)) {
                                sortOption = option
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(event.resolvedSessionType.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(sessionTypeColor)

                        if let audienceSize = event.audienceSize, audienceSize > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(audienceSize.formatted()) audience")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if !event.isOpenEnded {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(event.daysRemainingText)
                                .font(.caption2)
                                .foregroundStyle(daysColor)
                        }
                    }

                    // Readiness bar
                    if event.totalPracticeCount > 0 {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(AppColors.scoreGradient(for: event.readinessScore))
                                    .frame(width: geometry.size.width * CGFloat(event.readinessScore) / 100.0)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    if event.totalPracticeCount > 0 {
                        Text("\(event.readinessScore)%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: event.readinessScore))
                    }
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
        if days <= 1 { return .red }
        if days <= 3 { return .orange }
        return .secondary
    }
}

private enum EventSortOption: String, CaseIterable, Identifiable {
    case soonest
    case readiness
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soonest: return "Soonest"
        case .readiness: return "Readiness"
        case .sessions: return "Most Practiced"
        }
    }

    var icon: String {
        switch self {
        case .soonest: return "calendar"
        case .readiness: return "chart.line.uptrend.xyaxis"
        case .sessions: return "waveform"
        }
    }

    func sorted(_ events: [SpeakingEvent]) -> [SpeakingEvent] {
        switch self {
        case .soonest:
            return events.sorted { $0.eventDate < $1.eventDate }
        case .readiness:
            return events.sorted { lhs, rhs in
                if lhs.readinessScore == rhs.readinessScore {
                    return lhs.eventDate < rhs.eventDate
                }
                return lhs.readinessScore > rhs.readinessScore
            }
        case .sessions:
            return events.sorted { lhs, rhs in
                if lhs.totalPracticeCount == rhs.totalPracticeCount {
                    return lhs.eventDate < rhs.eventDate
                }
                return lhs.totalPracticeCount > rhs.totalPracticeCount
            }
        }
    }
}
