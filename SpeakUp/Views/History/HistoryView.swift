import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: Date?
    @State private var showingDayDetail = false

    var onSelectRecording: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Contribution Graph
                contributionGraphSection

                // Streak Stats
                streakSection

                // Recent Recordings
                recordingsSection
            }
            .padding()
        }
        .navigationTitle("History")
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .sheet(isPresented: $showingDayDetail) {
            if let date = selectedDate {
                DayDetailSheet(
                    date: date,
                    recordings: viewModel.recordingsForDate(date),
                    onSelectRecording: { recording in
                        showingDayDetail = false
                        onSelectRecording(recording.id.uuidString)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Contribution Graph Section

    private var contributionGraphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.headline)

                Spacer()

                Text("Last 6 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassCard {
                ContributionGraph(viewModel: viewModel) { date in
                    selectedDate = date
                    showingDayDetail = true
                }
            }
        }
    }
    
    // MARK: - Streak Section
    
    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)

            GlassCard(padding: 12) {
                HStack(spacing: 0) {
                    CompactStatItem(
                        icon: "flame.fill",
                        value: "\(viewModel.currentStreak)",
                        label: "Streak",
                        color: .orange
                    )

                    Divider().frame(height: 36)

                    CompactStatItem(
                        icon: "trophy.fill",
                        value: "\(viewModel.longestStreak)",
                        label: "Best",
                        color: .yellow
                    )

                    Divider().frame(height: 36)

                    CompactStatItem(
                        icon: "mic.fill",
                        value: "\(viewModel.recordings.count)",
                        label: "Sessions",
                        color: .teal
                    )
                }
            }
        }
    }
    
    // MARK: - Recordings Section
    
    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)

                Spacer()

                if !viewModel.recordings.isEmpty {
                    Text("\(viewModel.recordings.count) total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if viewModel.recordings.isEmpty {
                EmptyStateCard(
                    icon: "mic.slash",
                    title: "No Recordings Yet",
                    message: "Complete your first practice session to see it here."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.recordings) { recording in
                        RecordingRow(recording: recording)
                            .onTapGesture {
                                onSelectRecording(recording.id.uuidString)
                            }
                            .contextMenu {
                                Button {
                                    Task {
                                        await viewModel.toggleFavorite(recording)
                                    }
                                } label: {
                                    Label(
                                        recording.isFavorite ? "Remove Favorite" : "Add to Favorites",
                                        systemImage: recording.isFavorite ? "heart.slash" : "heart"
                                    )
                                }
                                
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteRecording(recording)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Contribution Graph

struct ContributionGraph: View {
    let viewModel: HistoryViewModel
    var onDateSelected: ((Date) -> Void)?

    private let columns = 26 // 26 weeks (half year)
    private let rows = 7 // Days of week
    private let cellSpacing: CGFloat = 3

    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let legendIntensities: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(100, geometry.size.width - 28) // Account for weekday labels, ensure minimum
            let cellSize = max(8, (availableWidth - CGFloat(columns - 1) * cellSpacing) / CGFloat(columns))

            if cellSize > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    // Weekday labels
                    HStack(spacing: cellSpacing) {
                        VStack(alignment: .trailing, spacing: cellSpacing) {
                            ForEach(0..<rows, id: \.self) { index in
                                Text(index % 2 == 1 ? weekdayLabels[index] : "")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .frame(height: cellSize)
                            }
                        }
                        .frame(width: 24)

                        // Grid - no scroll, fits to width
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<columns, id: \.self) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(0..<rows, id: \.self) { day in
                                        let date = dateForCell(week: week, day: day)
                                        let intensity = viewModel.activityLevel(for: date)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(AppColors.contributionColor(intensity: intensity))
                                            .frame(width: cellSize, height: cellSize)
                                            .onTapGesture {
                                                if intensity > 0 {
                                                    onDateSelected?(date)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Legend
                    HStack(spacing: 4) {
                        Text("Less")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(0..<legendIntensities.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.contributionColor(intensity: legendIntensities[index]))
                                .frame(width: cellSize, height: cellSize)
                        }

                        Text("More")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 120)
    }

    private func dateForCell(week: Int, day: Int) -> Date {
        let today = Date()
        let startOfWeek = today.startOfWeek
        let weeksBack = columns - 1 - week
        let targetWeek = startOfWeek.adding(weeks: -weeksBack)
        return targetWeek.adding(days: day)
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording

    private var detailedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: recording.date)
    }

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Media Type Icon
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: recording.mediaType.iconName)
                        .foregroundStyle(.teal)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Show prompt text (truncated) if available
                        Text(recording.prompt?.text ?? "Practice Session")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if recording.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Category badge (if prompt exists)
                    if let category = recording.prompt?.category {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PromptCategory(rawValue: category)?.color ?? .teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill((PromptCategory(rawValue: category)?.color ?? .teal).opacity(0.2))
                            }
                    }

                    HStack(spacing: 8) {
                        Text(detailedDateString)
                        Text("•")
                        Text(recording.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Score
                if let score = recording.analysis?.speechScore.overall {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(score)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: score))

                        Text("score")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if recording.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    let date: Date
    let recordings: [Recording]
    let onSelectRecording: (Recording) -> Void

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if recordings.isEmpty {
                        ContentUnavailableView(
                            "No Recordings",
                            systemImage: "mic.slash",
                            description: Text("No practice sessions on this day.")
                        )
                    } else {
                        ForEach(recordings) { recording in
                            RecordingRow(recording: recording)
                                .onTapGesture {
                                    onSelectRecording(recording)
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(onSelectRecording: { _ in })
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
