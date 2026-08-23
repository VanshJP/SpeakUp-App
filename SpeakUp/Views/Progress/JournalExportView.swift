import SwiftUI
import SwiftData

/// Score + date projection of one analyzed take, decoded off the main thread
/// so summary math in `body` never re-reads analysis blobs.
nonisolated struct JournalScorePoint {
    let date: Date
    let score: Int
}

struct JournalExportView: View {
    private static let journalDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var allRecordings: [Recording]
    @Query private var achievements: [Achievement]

    @State private var selectedRange: DateRangeOption = .lastMonth
    @State private var includeAchievements = true
    @State private var isExporting = false
    @State private var errorMessage: String?
    /// Analyzed takes across all ranges, date-ascending; filtered purely per render.
    @State private var scorePoints: [JournalScorePoint] = []

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case lastWeek = "Week"
        case lastMonth = "Month"
        case last3Months = "3 Months"
        case allTime = "All Time"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .lastWeek: return "7.square"
            case .lastMonth: return "30.square"
            case .last3Months: return "calendar.badge.clock"
            case .allTime: return "infinity"
            }
        }

        var dateFilter: Date {
            switch self {
            case .lastWeek: return Date().addingTimeInterval(-7 * 24 * 3600)
            case .lastMonth: return Date().addingTimeInterval(-30 * 24 * 3600)
            case .last3Months: return Date().addingTimeInterval(-90 * 24 * 3600)
            case .allTime: return Date.distantPast
            }
        }
    }

    private var filteredRecordings: [Recording] {
        allRecordings.filter { $0.date >= selectedRange.dateFilter }
    }

    private var unlockedAchievementsCount: Int {
        achievements.filter { $0.isUnlocked }.count
    }

    /// One background decode pass on appear; range filtering is pure date
    /// math done per render against these values. A cancelled pass (view
    /// already gone) never writes.
    private func loadScorePoints() async {
        let container = modelContext.container
        let points = await Task.detached(priority: .userInitiated) { () -> [JournalScorePoint] in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            let recordings = (try? context.fetch(descriptor)) ?? []
            return recordings.compactMap { recording in
                guard let score = recording.analysis?.speechScore.overall else { return nil }
                return JournalScorePoint(date: recording.date, score: score)
            }
        }.value

        guard !Task.isCancelled else { return }
        scorePoints = points
    }

    var body: some View {
        let rangeSessions = filteredRecordings
        let totalMinutes = Int(rangeSessions.reduce(0.0) { $0 + $1.actualDuration }) / 60
        let rangeScores = scorePoints.filter { $0.date >= selectedRange.dateFilter }
        let averageScore = rangeScores.isEmpty ? 0 : rangeScores.map(\.score).reduce(0, +) / rangeScores.count
        let improvement = rangeScores.count >= 2
            ? (rangeScores.last?.score ?? 0) - (rangeScores.first?.score ?? 0)
            : 0

        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Date Range", systemImage: "calendar")
                                .font(.headline)

                            Spacer()

                            Text("\(rangeSessions.count) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DateRangeOption.allCases) { option in
                                    FilterChip(
                                        title: option.rawValue,
                                        icon: option.icon,
                                        isSelected: selectedRange == option
                                    ) {
                                        withAnimation(.spring(duration: 0.3)) {
                                            selectedRange = option
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        Toggle(isOn: $includeAchievements) {
                            Label("Include Achievements", systemImage: "trophy")
                                .font(.subheadline)
                        }
                        .tint(AppColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Summary", systemImage: "chart.bar.fill")
                            .font(.headline)

                        FeaturedGlassCard {
                            JournalSummaryView(
                                totalSessions: rangeSessions.count,
                                totalMinutes: totalMinutes,
                                averageScore: averageScore,
                                improvement: improvement,
                                unlockedAchievements: includeAchievements ? unlockedAchievementsCount : 0
                            )
                        }
                    }

                    if let errorMessage {
                        GlassCard {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.error)
                        }
                    }

                    GlassButton(
                        title: isExporting ? "Exporting..." : "Export PDF",
                        icon: "doc.richtext",
                        style: .secondary,
                        isLoading: isExporting,
                        fullWidth: true
                    ) {
                        exportPDF()
                    }
                    .disabled(rangeSessions.isEmpty || isExporting)
                }
                .padding()
            }
        }
        .navigationTitle("Progress Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await loadScorePoints()
        }
    }

    private func exportPDF() {
        isExporting = true
        errorMessage = nil

        let recordings = filteredRecordings
        let range = selectedRange.rawValue
        let withAchievements = includeAchievements
        let achievementsList = achievements

        Task {
            let service = JournalExportService()
            let data = service.generatePDF(
                recordings: recordings,
                dateRange: range,
                includeAchievements: withAchievements,
                achievements: achievementsList
            )

            guard let data else {
                errorMessage = "Failed to generate PDF."
                isExporting = false
                return
            }

            let dateString = Self.journalDateFormatter.string(from: Date())
            let fileName = "BigTalk-Journal-\(dateString).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try data.write(to: tempURL)
                isExporting = false
                SharePresenter.present(url: tempURL)
            } catch {
                errorMessage = "Could not save PDF: \(error.localizedDescription)"
                isExporting = false
            }
        }
    }
}
