import SwiftUI

/// The launch scorecard, computed on this device from the local event log.
///
/// There is no analytics backend, so this screen is how the beta gates
/// (activation rate, time to value, qualified paywall conversion) actually get
/// read: a tester opens it, exports the JSON, and sends it over. It doubles as
/// the honest answer to "what do you collect?" — everything recorded is right
/// here, in full, and it never leaves unless the user exports it.
struct AnalyticsDiagnosticsView: View {
    private var analytics: AnalyticsService { AnalyticsService.shared }

    @State private var showingResetAlert = false
    @State private var exportURL: URL?
    @State private var showingShare = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 14) {
                    disclosureCard
                    scorecardCard
                    recentEventsCard
                    actions
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Usage Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear diagnostics?", isPresented: $showingResetAlert) {
            Button("Clear", role: .destructive) { analytics.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the on-device event log. Your recordings and scores are not affected.")
        }
        .sheet(isPresented: $showingShare) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export events", systemImage: "square.and.arrow.up")
                }
                .padding()
                .presentationDetents([.height(160)])
            }
        }
    }

    // MARK: - Cards

    private var disclosureCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Stays on this device", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Big Talk records coarse events — that a session finished, roughly how long it took, which screen led where. No audio, no transcripts, no exact scores, no identifiers. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scorecardCard: some View {
        let card = analytics.scorecard()
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scorecard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                metricRow("Analyses completed", value: "\(card.analysesCompleted)")
                metricRow("Reached first result", value: card.activations > 0 ? "Yes" : "Not yet")
                metricRow("Time to first result", value: timeToValueSummary(card))
                metricRow("Paywalls after a result", value: "\(card.qualifiedPaywallViews)")
                metricRow("Purchases", value: "\(card.purchases)")
                metricRow("Cards shared", value: "\(card.shares)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeToValueSummary(_ card: AnalyticsScorecard) -> String {
        guard let bucket = card.timeToValueBuckets.max(by: { $0.value < $1.value })?.key else {
            return "—"
        }
        return bucket
    }

    private var recentEventsCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent events")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if analytics.recentEvents.isEmpty {
                    Text("Nothing recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analytics.recentEvents.suffix(25).reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if !event.dimensions.isEmpty {
                                Text(event.dimensions.sorted { $0.key < $1.key }
                                    .map { "\($0.key)=\($0.value)" }
                                    .joined(separator: "  "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            GlassButton(title: "Export events", icon: "square.and.arrow.up", style: .secondary, fullWidth: true) {
                Haptics.light()
                export()
            }
            GlassButton(title: "Clear diagnostics", icon: "trash", style: .outline, fullWidth: true) {
                Haptics.warning()
                showingResetAlert = true
            }
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func export() {
        guard let data = analytics.exportJSON() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigtalk-diagnostics.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            showingShare = true
        } catch {
            exportURL = nil
        }
    }
}

#Preview {
    NavigationStack { AnalyticsDiagnosticsView() }
}
