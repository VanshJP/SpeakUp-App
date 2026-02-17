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
    @State private var pdfData: Data?
    @State private var showingShare = false

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case lastWeek = "Last Week"
        case lastMonth = "Last Month"
        case last3Months = "Last 3 Months"
        case allTime = "All Time"

        var id: String { rawValue }

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

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Date range picker
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Date Range", systemImage: "calendar")
                                .font(.headline)

                            GlassCard {
                                Picker("Range", selection: $selectedRange) {
                                    ForEach(DateRangeOption.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                .pickerStyle(.segmented)
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

                        // Preview stats
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Export Preview")
                                    .font(.subheadline.weight(.semibold))

                                HStack(spacing: 16) {
                                    statPreview(label: "Sessions", value: "\(filteredRecordings.count)")
                                    statPreview(label: "Analyzed", value: "\(filteredRecordings.filter { $0.analysis != nil }.count)")
                                    if includeAchievements {
                                        statPreview(label: "Achievements", value: "\(achievements.filter { $0.isUnlocked }.count)")
                                    }
                                }
                            }
                        }

                        // Export button
                        Button {
                            exportPDF()
                        } label: {
                            HStack {
                                if isExporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "doc.richtext")
                                }
                                Text("Export PDF")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.teal))
                        }
                        .disabled(filteredRecordings.isEmpty || isExporting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Progress Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let data = pdfData {
                    ShareSheet(items: [data])
                }
            }
        }
    }

    private func statPreview(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func exportPDF() {
        isExporting = true
        let service = JournalExportService()
        pdfData = service.generatePDF(
            recordings: filteredRecordings,
            dateRange: selectedRange.rawValue,
            includeAchievements: includeAchievements,
            achievements: achievements
        )
        isExporting = false
        if pdfData != nil {
            showingShare = true
        }
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
