import SwiftUI
import SwiftData

/// Date, length, and score of one take, read off the main thread so summary
/// math in `body` never touches a model object or an analysis blob.
nonisolated struct JournalTakePoint {
    let date: Date
    let duration: TimeInterval
    let score: Int?
}

struct JournalExportView: View {
    private static let journalDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var achievements: [Achievement]

    @State private var selectedRange: DateRangeOption = .lastMonth
    @State private var includeAchievements = true
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var takes: [JournalTakePoint] = []
    /// False until the first pass lands, so the summary does not flash zeros
    /// and a disabled Export before the takes arrive.
    @State private var hasLoadedTakes = false

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case lastWeek = "Week"
        case lastMonth = "Month"
        case last3Months = "3 months"
        case allTime = "All time"

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

    private var unlockedAchievementsCount: Int {
        achievements.filter { $0.isUnlocked }.count
    }

    /// One background decode pass on appear; range filtering is pure date
    /// math done per render against these values. A cancelled pass (view
    /// already gone) never writes.
    private func loadTakes() async {
        let container = modelContext.container
        let points = await Task.detached(priority: .userInitiated) { () -> [JournalTakePoint] in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            let recordings = (try? context.fetch(descriptor)) ?? []
            return recordings.map { recording in
                JournalTakePoint(
                    date: recording.date,
                    duration: recording.actualDuration,
                    score: recording.analysis?.speechScore.overall
                )
            }
        }.value

        guard !Task.isCancelled else { return }
        takes = points
        hasLoadedTakes = true
    }

    var body: some View {
        let rangeTakes = takes.filter { $0.date >= selectedRange.dateFilter }
        let totalMinutes = Int(rangeTakes.reduce(0.0) { $0 + $1.duration }) / 60
        let rangeScores = rangeTakes.compactMap(\.score)
        let averageScore = rangeScores.isEmpty ? 0 : rangeScores.reduce(0, +) / rangeScores.count
        let improvement = rangeScores.count >= 2
            ? (rangeScores.last ?? 0) - (rangeScores.first ?? 0)
            : 0

        PageScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionHeader("Date range") {
                        if hasLoadedTakes {
                            Text(rangeTakes.count == 1 ? "1 session" : "\(rangeTakes.count) sessions")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
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
                        Label("Include achievements", systemImage: "trophy")
                            .font(.subheadline)
                    }
                    .tint(AppColors.primary)
                }
                .labelStyle(.row)

                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionHeader("Summary")

                    FeaturedGlassCard {
                        if hasLoadedTakes {
                            JournalSummaryView(
                                totalSessions: rangeTakes.count,
                                totalMinutes: totalMinutes,
                                averageScore: averageScore,
                                improvement: improvement,
                                unlockedAchievements: includeAchievements ? unlockedAchievementsCount : 0
                            )
                        } else {
                            VoiceLoader(size: .large)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                }

                if let errorMessage {
                    GlassCard {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.error)
                    }
                }
            }
            .padding(.top, 8)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        // The sheet's one action stays in reach under the scroll, as a bar
        // with the tab bar's soft edge rather than a slab.
        .safeAreaBar(edge: .bottom) {
            GlassButton(
                title: isExporting ? "Exporting…" : "Export PDF",
                icon: "doc.richtext",
                style: .primary,
                isLoading: isExporting,
                fullWidth: true
            ) {
                exportPDF()
            }
            .disabled(!hasLoadedTakes || rangeTakes.isEmpty || isExporting)
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.vertical, 10)
        }
        .appBackground(.subtle)
        .navigationTitle("Progress Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { dismiss() }
            }
        }
        .task {
            await loadTakes()
        }
    }

    /// Fetch, snapshot, render, and write all run in one detached task - an
    /// "All Time" journal lays out every transcript, which froze the spinner
    /// when it ran on the main actor. Only the result hops back.
    private func exportPDF() {
        isExporting = true
        errorMessage = nil

        let container = modelContext.container
        let since = selectedRange.dateFilter
        let range = selectedRange.rawValue
        let withAchievements = includeAchievements
        let fileName = "BigTalk-Journal-\(Self.journalDateFormatter.string(from: Date())).pdf"

        Task {
            let result = await Task.detached(priority: .userInitiated) { () throws -> URL in
                let context = ModelContext(container)
                // Predicate on `date` only - never on the analysis blob (gotchas §2).
                let descriptor = FetchDescriptor<Recording>(
                    predicate: #Predicate { $0.date >= since },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
                let entries = try context.fetch(descriptor).map(JournalEntry.init)
                let achievements = withAchievements
                    ? try context.fetch(FetchDescriptor<Achievement>(predicate: #Predicate { $0.isUnlocked }))
                        .map { JournalAchievement(icon: $0.icon, title: $0.title) }
                    : []

                let data = JournalExportService().generatePDF(
                    entries: entries,
                    dateRange: range,
                    achievements: achievements
                )
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try data.write(to: tempURL)
                return tempURL
            }.result

            isExporting = false
            switch result {
            case .success(let url):
                SharePresenter.present(url: url)
            case .failure(let error):
                errorMessage = "Could not save PDF: \(error.localizedDescription)"
            }
        }
    }
}
