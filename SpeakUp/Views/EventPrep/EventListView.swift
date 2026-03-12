import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<SpeakingEvent> { !$0.isArchived },
        sort: \SpeakingEvent.eventDate
    ) private var events: [SpeakingEvent]

    @State private var showingCreateEvent = false
    @State private var selectedEvent: SpeakingEvent?
    @State private var eventPrepService = EventPrepService()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 16) {
                    // Create button
                    GlassButton(title: "New Event", icon: "plus", style: .primary, size: .medium, fullWidth: true) {
                        Haptics.medium()
                        showingCreateEvent = true
                    }

                    if events.isEmpty {
                        EmptyStateCard(
                            icon: "calendar",
                            title: "No Upcoming Events",
                            message: "Create an event to start your personalized preparation plan.",
                            buttonTitle: "Create Event"
                        ) {
                            showingCreateEvent = true
                        }
                        .padding(.top, 20)
                    } else {
                        ForEach(events) { event in
                            Button {
                                selectedEvent = event
                            } label: {
                                eventCard(event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Speaking Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingCreateEvent) {
            NavigationStack {
                CreateEventView { event in
                    showingCreateEvent = false
                    selectedEvent = event
                }
            }
        }
        .navigationDestination(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }

    // MARK: - Event Card

    private func eventCard(_ event: SpeakingEvent) -> some View {
        GlassCard(tint: AppColors.primary.opacity(0.06)) {
            HStack(spacing: 14) {
                // Readiness ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 52, height: 52)

                    Circle()
                        .trim(from: 0, to: Double(event.readinessScore) / 100.0)
                        .stroke(
                            AppColors.scoreColor(for: event.readinessScore),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))

                    Text("\(event.readinessScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: event.readinessScore))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(event.eventDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Label(event.daysRemainingText, systemImage: "clock")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(event.daysRemaining <= 3 ? AppColors.warning : AppColors.primary)

                        if let audience = event.audienceType {
                            Text(audience)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule()
                                        .fill(.white.opacity(0.08))
                                }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
