import SwiftUI
import SwiftData

struct JournalExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recording.date, order: .reverse) private var allRecordings: [Recording]
    @Query private var achievements: [Achievement]

    @State private var selectedRange: DateRangeOption = .lastMonth
    @State private var includeAchievements = true
    @State private var isExporting = false
    @State private var pdfURL: URL?
    @State private var showingShare = false

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

    private var analyzedSorted: [Recording] {
        filteredRecordings.filter { $0.analysis != nil }.sorted { $0.date < $1.date }
    }

    private var totalMinutes: Int {
        Int(filteredRecordings.reduce(0.0) { $0 + $1.actualDuration }) / 60
    }

    private var averageScore: Int {
        let scores = analyzedSorted.compactMap { $0.analysis?.speechScore.overall }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / scores.count
    }

    private var improvement: Int {
        let scores = analyzedSorted.compactMap { $0.analysis?.speechScore.overall }
        guard scores.count >= 2 else { return 0 }
        return (scores.last ?? 0) - (scores.first ?? 0)
    }

    private var unlockedAchievementsCount: Int {
        achievements.filter { $0.isUnlocked }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Date range picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Date Range", systemImage: "calendar")
                                    .font(.headline)

                                Spacer()

                                Text("\(filteredRecordings.count) sessions")
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

                        // Options
                        GlassCard {
                            Toggle(isOn: $includeAchievements) {
                                Label("Include Achievements", systemImage: "trophy")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                        }

                        // Summary preview
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Summary", systemImage: "chart.bar.fill")
                                .font(.headline)

                            FeaturedGlassCard(gradientColors: [.teal.opacity(0.12), .cyan.opacity(0.06)]) {
                                JournalSummaryView(
                                    totalSessions: filteredRecordings.count,
                                    totalMinutes: totalMinutes,
                                    averageScore: averageScore,
                                    improvement: improvement,
                                    unlockedAchievements: includeAchievements ? unlockedAchievementsCount : 0
                                )
                            }
                        }

                        GlassButton(
                            title: isExporting ? "Exporting..." : "Export PDF",
                            icon: "doc.richtext",
                            style: .secondary,
                            fullWidth: true
                        ) {
                            exportPDF()
                        }
                        .disabled(filteredRecordings.isEmpty || isExporting)
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
            .sheet(isPresented: $showingShare) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportPDF() {
        isExporting = true
        let service = JournalExportService()
        guard let data = service.generatePDF(
            recordings: filteredRecordings,
            dateRange: selectedRange.rawValue,
            includeAchievements: includeAchievements,
            achievements: achievements
        ) else {
            isExporting = false
            return
        }

        let dateString = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let fileName = "SpeakUp Recordings \(dateString).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL)
            pdfURL = tempURL
            showingShare = true
        } catch {}

        isExporting = false
    }
}

// Simple share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
