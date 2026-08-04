import StoreKit
import SwiftData
import SwiftUI

/// The one purchase decision in the app.
///
/// Structure follows the offer: what you already proved to yourself, what the
/// purchase adds, one price, one button, and the ownership scope in the same
/// words the App Store description and the FAQ use.
struct PaywallView: View {
    let request: PaywallRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var purchases: PurchaseService { PurchaseService.shared }
    private var entitlements: EntitlementStore { EntitlementStore.shared }

    @State private var showingFAQ = false
    @State private var showingRedeemCode = false
    @State private var didSucceed = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        includedCard
                        priceBlock
                        ownershipScope
                        secondaryActions
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Big Talk Lifetime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingFAQ) {
                NavigationStack { LifetimeFAQView() }
            }
            .offerCodeRedemption(isPresented: $showingRedeemCode) { result in
                Task {
                    if case .success = result {
                        await purchases.refreshEntitlement()
                        AnalyticsService.shared.log(.restoreResult("offer_code"))
                    }
                    if entitlements.isLifetime { didSucceed = true }
                }
            }
            .task {
                await purchases.loadProduct()
                markPaywallSeen()
            }
            .onChange(of: entitlements.isLifetime) { _, owned in
                if owned { didSucceed = true }
            }
            .onChange(of: didSucceed) { _, succeeded in
                guard succeeded else { return }
                Haptics.success()
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("BigTalkOrb")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .padding(.top, 8)

            Text(didSucceed ? "You own Big Talk." : "Keep the whole gym.")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(didSucceed
                 ? "Everything is unlocked on this Apple Account, on every device."
                 : request.feature.paywallReason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - What's included

    private var includedCard: some View {
        GlassCard(tint: AppColors.glassTintPrimary, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.includedRows, id: \.title) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct IncludedRow {
        let icon: String
        let title: String
        let detail: String
    }

    private static let includedRows: [IncludedRow] = [
        IncludedRow(
            icon: "infinity",
            title: "Unlimited scored practice",
            detail: "Record and analyze as often as you want, on device."
        ),
        IncludedRow(
            icon: "book.closed",
            title: "The full improvement plan",
            detail: "Eight-week curriculum, every drill, warm-up, and read-aloud passage."
        ),
        IncludedRow(
            icon: "chart.line.uptrend.xyaxis",
            title: "Your complete history",
            detail: "Every session, charts, comparisons, and the first-versus-latest replay."
        ),
        IncludedRow(
            icon: "icloud",
            title: "Sync and export",
            detail: "iCloud sync across your devices and journal export you can keep."
        )
    ]

    // MARK: - Price

    private var priceBlock: some View {
        VStack(spacing: 12) {
            if FoundingOffer.isActive() {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.caption2)
                    Text("Founding price — \(FoundingOffer.standardDisplayPrice) after")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppColors.warning)
            }

            GlassButton(
                title: didSucceed ? "Unlocked" : "Unlock Lifetime · \(purchases.displayPrice)",
                icon: didSucceed ? "checkmark" : nil,
                style: .primary,
                size: .large,
                isLoading: purchases.phase == .purchasing,
                fullWidth: true
            ) {
                Haptics.medium()
                Task { await buy() }
            }
            .disabled(didSucceed)

            Text("One payment. No subscription.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if purchases.phase == .pendingApproval {
                statusLine(
                    icon: "clock",
                    text: "Waiting for approval. Big Talk unlocks by itself once it goes through.",
                    color: AppColors.info
                )
            }

            if let message = purchases.errorMessage {
                statusLine(icon: "exclamationmark.triangle", text: message, color: AppColors.error)
            }
        }
    }

    private func statusLine(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4)
    }

    // MARK: - Ownership scope

    private var ownershipScope: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What you own")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(Self.ownershipScopeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Kept identical to the App Store description, the FAQ, and the support
    /// site. A purchase scope that reads differently in three places is how
    /// refund requests start.
    static let ownershipScopeText = """
    Pay once to keep Big Talk Lifetime's on-device feature set. No subscription \
    is required for the features you own. Optional future services with ongoing \
    delivery costs may be sold separately.
    """

    // MARK: - Secondary

    private var secondaryActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassButton(
                    title: "Restore",
                    style: .secondary,
                    size: .small,
                    isLoading: purchases.phase == .restoring
                ) {
                    Haptics.light()
                    Task { await restore() }
                }

                GlassButton(title: "Redeem code", style: .secondary, size: .small) {
                    Haptics.light()
                    showingRedeemCode = true
                }

                GlassButton(title: "What's included", style: .secondary, size: .small) {
                    Haptics.light()
                    showingFAQ = true
                }
            }

            Text("Purchases are tied to your Apple Account and restore on any device you sign in to.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func buy() async {
        let succeeded = await purchases.purchase()
        let result: String
        switch purchases.phase {
        case .purchased: result = "purchased"
        case .cancelled: result = "cancelled"
        case .pendingApproval: result = "pending"
        case .failed: result = "failed"
        default: result = succeeded ? "purchased" : "unknown"
        }
        AnalyticsService.shared.log(
            .purchaseResult(result, price: purchases.displayPrice, source: AttributionStore.shared.source)
        )
        if succeeded { didSucceed = true }
    }

    private func restore() async {
        let restored = await purchases.restore()
        AnalyticsService.shared.log(.restoreResult(restored ? "restored" : "nothing_to_restore"))
        if restored { didSucceed = true }
    }

    private func markPaywallSeen() {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        guard let settings = try? modelContext.fetch(descriptor).first, !settings.hasSeenPaywall else { return }
        settings.hasSeenPaywall = true
        try? modelContext.save()
    }
}

#Preview {
    PaywallView(request: PaywallRequest(feature: .unlimitedAnalyses, trigger: "preview"))
        .modelContainer(for: [UserSettings.self], inMemory: true)
}
