import SwiftData
import SwiftUI

/// Purchase state at the top of Settings: what you own, what is left of the free
/// allowance, what it costs, and how to get it back.
///
/// The price is shown here rather than only behind the paywall — a user opening
/// Settings to find out what this costs should not have to open a sales screen
/// to be told. Restore stays a text link on both sides of the entitlement: the
/// person who needs it most reinstalled and never sees a paywall, but it is not
/// a peer of the buy button.
struct LifetimeStatusRow: View {
    private var entitlements: EntitlementStore { EntitlementStore.shared }
    private var purchases: PurchaseService { PurchaseService.shared }

    @Query private var userSettings: [UserSettings]
    @State private var showingFAQ = false
    @State private var restoreMessage: String?

    var body: some View {
        GlassCard(
            tint: entitlements.isLifetime ? AppColors.success : AppColors.primary,
            padding: 14
        ) {
            VStack(alignment: .leading, spacing: 12) {
                identityRow

                if !entitlements.isLifetime, let allowance {
                    allowanceMeter(allowance)
                }

                actions

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingFAQ) {
            NavigationStack { LifetimeFAQView() }
        }
        .task {
            // Settings can be the first surface a user opens. Without this the
            // price slot shimmers until they happen to visit the paywall.
            await purchases.loadProduct()
        }
    }

    // MARK: - Identity

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: entitlements.isLifetime ? "checkmark.seal.fill" : "sparkles")
                .font(.body)
                .foregroundStyle(entitlements.isLifetime ? AppColors.success : AppColors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Big Talk Lifetime")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            trailingBadge
        }
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if entitlements.isLifetime {
            Text("OWNED")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(AppColors.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppColors.success.opacity(0.16)))
        } else if let price = purchases.displayPrice {
            VStack(alignment: .trailing, spacing: 0) {
                Text(price)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("once")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            // No hardcoded fallback: a literal price is only right for one
            // storefront, and a wrong currency is worse than no number yet.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(AppColors.meterTrack)
                .frame(width: 54, height: 20)
                .shimmer()
        }
    }

    private var subtitle: String {
        if entitlements.isLifetime {
            guard let date = entitlements.purchaseDate else {
                return "Everything unlocked. Thank you."
            }
            return "Owned since \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "One payment. Every future feature included."
    }

    // MARK: - Allowance

    /// The live count, not the policy number. A card that says "3 analyses a
    /// month" to someone who has none left is describing the plan rather than
    /// answering the question they opened Settings to ask.
    ///
    /// During the trial the same meter counts days instead — one tick per day
    /// of the fourteen — because that is what is actually running out.
    private var allowance: (remaining: Int, total: Int, summary: String)? {
        guard let settings = userSettings.first else { return nil }
        let decision = AllowanceGate.decision(settings: settings)
        guard let summary = decision.shortSummary else { return nil }

        if case .trial(let endsOn) = decision {
            return (
                PracticeTrial.daysRemaining(until: endsOn),
                PracticeTrial.lengthInDays,
                summary
            )
        }
        return (decision.remaining ?? 0, max(FreeTierPolicy.expired.monthlyAnalyses, 1), summary)
    }

    private func allowanceMeter(_ allowance: (remaining: Int, total: Int, summary: String)) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TickMeter(
                fraction: Double(allowance.remaining) / Double(allowance.total),
                color: meterColor(remaining: allowance.remaining),
                tickCount: allowance.total
            )
            .frame(height: 7)

            Text(allowance.summary)
                .font(.caption)
                .foregroundStyle(allowance.remaining == 0 ? AppColors.warning : .secondary)
        }
    }

    private func meterColor(remaining: Int) -> Color {
        switch remaining {
        case 0: return AppColors.error
        case 1: return AppColors.warning
        default: return AppColors.primary
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !entitlements.isLifetime {
                GlassButton(title: "Unlock Lifetime", style: .primary, size: .small, fullWidth: true) {
                    Haptics.medium()
                    PaywallCoordinator.shared.present(
                        .unlimitedAnalyses,
                        trigger: "settings",
                        userInitiated: true
                    )
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    Task { await restore() }
                } label: {
                    if purchases.phase == .restoring {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Restore purchase")
                    }
                }
                .disabled(purchases.isBusy)

                Text("·")

                Button("What's included") {
                    Haptics.light()
                    showingFAQ = true
                }

                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
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
