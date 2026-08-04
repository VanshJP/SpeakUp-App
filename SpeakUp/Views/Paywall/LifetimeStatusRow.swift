import SwiftData
import SwiftUI

/// Purchase state at the top of Settings: what you own, how to buy, and how to
/// get it back. Restore lives here as well as on the paywall because the person
/// who needs it most is the one who reinstalled and never sees a paywall.
struct LifetimeStatusRow: View {
    private var entitlements: EntitlementStore { EntitlementStore.shared }
    private var purchases: PurchaseService { PurchaseService.shared }

    @Query private var userSettings: [UserSettings]
    @State private var showingFAQ = false
    @State private var restoreMessage: String?

    var body: some View {
        GlassCard(tint: entitlements.isLifetime ? AppColors.glassTintSuccess : AppColors.glassTintPrimary, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((entitlements.isLifetime ? AppColors.success : AppColors.primary).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: entitlements.isLifetime ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(entitlements.isLifetime ? AppColors.success : AppColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entitlements.isLifetime ? "Big Talk Lifetime" : "Free plan")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if !entitlements.isLifetime {
                        GlassButton(title: "Unlock", style: .primary, size: .small) {
                            Haptics.medium()
                            PaywallCoordinator.shared.present(
                                .unlimitedAnalyses,
                                trigger: "settings",
                                userInitiated: true
                            )
                        }
                    }

                    GlassButton(
                        title: "Restore",
                        style: .secondary,
                        size: .small,
                        isLoading: purchases.phase == .restoring
                    ) {
                        Haptics.light()
                        Task { await restore() }
                    }

                    GlassButton(title: "Details", style: .secondary, size: .small) {
                        Haptics.light()
                        showingFAQ = true
                    }

                    Spacer(minLength: 0)
                }

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingFAQ) {
            NavigationStack { LifetimeFAQView() }
        }
    }

    private var subtitle: String {
        if entitlements.isLifetime {
            guard let date = entitlements.purchaseDate else {
                return "Everything unlocked. Thank you."
            }
            return "Owned since \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        // The live count, not the policy number. A card that says "3 analyses a
        // month" to someone who has none left is describing the plan rather
        // than answering the question they opened Settings to ask.
        guard let settings = userSettings.first,
            let summary = PracticeAllowance.decision(
                state: settings.allowanceState,
                isEntitled: false
            ).shortSummary
        else {
            return "\(FreeTierPolicy.default.monthlyAnalyses) analyses a month · one-time upgrade available"
        }
        return summary
    }

    private func restore() async {
        let restored = await purchases.restore()
        AnalyticsService.shared.log(.restoreResult(restored ? "restored" : "nothing_to_restore"))
        restoreMessage = restored
            ? "Restored. Everything is unlocked."
            : (purchases.errorMessage ?? "No previous purchase found for this Apple Account.")
    }
}

#Preview {
    ZStack {
        AppBackground()
        LifetimeStatusRow().padding()
    }
    .modelContainer(for: UserSettings.self, inMemory: true)
}
