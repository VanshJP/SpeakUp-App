import SwiftUI

/// The launch scorecard, computed on this device from the local event log.
///
/// There is no analytics backend, so this screen is how the beta gates
/// (activation rate, time to value) actually get read: a tester opens it,
/// exports the JSON, and sends it over. It doubles as the honest answer to
/// "what do you collect?" Everything recorded is right here, in full, and it
/// never leaves unless the user exports it.
struct AnalyticsDiagnosticsView: View {
    private var analytics: AnalyticsService { AnalyticsService.shared }

    @State private var showingResetAlert = false
    /// Written when the page appears, so Export is a `ShareLink` straight to
    /// the share sheet. It used to open a sheet holding a second Export button.
    @State private var exportURL: URL?

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 14) {
                    disclosureCard
                    scorecardCard
                    #if DEBUG
                    entitlementOverrideCard
                    trialOverrideCard
                    #endif
                    recentEventsCard
                    actions
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Usage Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        // The service keeps only this launch's events in memory; the stored
        // log is read here, where it is shown.
        .onAppear {
            analytics.refreshRecentEvents()
            prepareExport()
        }
        .alert("Clear diagnostics?", isPresented: $showingResetAlert) {
            Button("Clear", role: .destructive) {
                analytics.reset()
                prepareExport()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the on-device event log. Your recordings and scores are not affected.")
        }
    }

    // MARK: - Cards

    private var disclosureCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                GlassCardTitle("Stays on this device")
                Text("Big Talk records coarse events: that a session finished, roughly how long it took, which screen led where. No audio, no transcripts, no exact scores, no identifiers. Nothing is sent anywhere.")
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
                GlassCardTitle("Scorecard")

                metricRow("Sessions started", value: "\(card.practiceStarts)")
                metricRow("Analyses completed", value: "\(card.analysesCompleted)")
                metricRow("Started → scored", value: percentSummary(card.startToScoreRate))
                metricRow("Reached first result", value: card.activations > 0 ? "Yes" : "Not yet")
                metricRow("Activation rate", value: percentSummary(card.activationRate))
                metricRow("Time to first result", value: timeToValueSummary(card))
                metricRow("Cards shared", value: "\(card.shares)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if DEBUG
    private var entitlementOverrideCard: some View {
        GlassCard(padding: 14) {
            Toggle(isOn: Binding(
                get: { EntitlementStore.shared.debugOverrideEnabled },
                set: { EntitlementStore.shared.setDebugOverride($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force Lifetime (debug)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Debug builds only. Unlocks every gate without buying.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AppColors.primary)
        }
    }

    private var trialOverrideCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free trial (debug)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(trialStateSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    GlassButton(title: "Reset", style: .secondary, size: .small) {
                        EntitlementStore.shared.setDebugTrialStart(nil)
                    }
                    GlassButton(title: "Start now", style: .secondary, size: .small) {
                        EntitlementStore.shared.setDebugTrialStart(Date())
                    }
                    GlassButton(title: "Expire", style: .secondary, size: .small) {
                        EntitlementStore.shared.setDebugTrialStart(
                            Date().addingTimeInterval(-PracticeTrial.length - 60)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trialStateSummary: String {
        switch EntitlementStore.shared.trialState {
        case .notStarted: return "Not started. Begins at the first scored analysis."
        case .active(let endsOn): return "Active · \(PracticeTrial.daysRemaining(until: endsOn)) days left."
        case .expired: return "Expired. Three analyses per 30 days."
        }
    }
    #endif

    private func percentSummary(_ rate: Double?) -> String {
        guard let rate else { return "–" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private func timeToValueSummary(_ card: AnalyticsScorecard) -> String {
        guard let bucket = card.timeToValueBuckets.max(by: { $0.value < $1.value })?.key else {
            return "–"
        }
        return bucket
    }

    private var recentEventsCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                GlassCardTitle("Recent events")

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
            if let exportURL {
                ShareLink(item: exportURL) {
                    GlassButtonLabel(title: "Export events", icon: "square.and.arrow.up", style: .secondary, fullWidth: true)
                }
                .buttonStyle(GlassPressStyle())
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
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func prepareExport() {
        guard let data = analytics.exportJSON() else {
            exportURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigtalk-diagnostics.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}

#Preview {
    NavigationStack { AnalyticsDiagnosticsView() }
}
