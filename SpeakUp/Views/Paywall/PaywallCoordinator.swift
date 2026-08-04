import Foundation
import Observation

/// One request to show the paywall, with the reason it was raised.
struct PaywallRequest: Identifiable, Equatable {
    let id = UUID()
    let feature: PaidFeature
    /// Where the tap came from. Reported as the paywall trigger dimension.
    let trigger: String
}

/// Routes paywall presentation so any view can raise it without owning sheet
/// state, and so the "never before a complete first result" rule is enforced in
/// one place rather than at every call site.
@MainActor
@Observable
final class PaywallCoordinator {
    static let shared = PaywallCoordinator()

    var request: PaywallRequest?

    /// Set once the user has seen a finished analysis. Until then the paywall
    /// stays shut: the free result is what earns the right to ask.
    private(set) var hasCompletedFirstResult = false

    private init() {}

    func markFirstResultSeen() {
        hasCompletedFirstResult = true
    }

    /// Raise the paywall. Returns false when it was suppressed because the user
    /// has not yet seen a complete result.
    @discardableResult
    func present(_ feature: PaidFeature, trigger: String) -> Bool {
        guard !EntitlementStore.shared.isLifetime else { return false }
        guard hasCompletedFirstResult else { return false }
        guard request == nil else { return true }

        request = PaywallRequest(feature: feature, trigger: trigger)
        AnalyticsService.shared.log(
            .paywallQualified(trigger: trigger, source: AttributionStore.shared.source)
        )
        return true
    }

    func dismiss() {
        request = nil
    }
}
