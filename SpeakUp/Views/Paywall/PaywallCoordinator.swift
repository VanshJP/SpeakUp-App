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

    private enum Key {
        static let firstResultSeen = "paywall.firstResultSeen.v1"
    }

    var request: PaywallRequest?

    /// Set once the user has seen a finished analysis. Until then the app does
    /// not raise the paywall on its own: the free result is what earns the
    /// right to ask.
    ///
    /// Persisted, because it describes something the user has already done. Held
    /// only in memory it reset on every cold launch, which silently disarmed
    /// every paywall entry point until the user happened to open another result.
    private(set) var hasCompletedFirstResult: Bool

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedFirstResult = defaults.bool(forKey: Key.firstResultSeen)
    }

    func markFirstResultSeen() {
        guard !hasCompletedFirstResult else { return }
        hasCompletedFirstResult = true
        defaults.set(true, forKey: Key.firstResultSeen)
    }

    /// Raise the paywall. Returns false when it was suppressed.
    ///
    /// `userInitiated` is for entry points the user tapped to see the offer — a
    /// button reading "Unlock", or a lesson that is locked because it is paid.
    /// The first-result rule exists to stop the *app* asking before it has
    /// earned it; applying it to a button the user pressed just makes the
    /// button do nothing.
    @discardableResult
    func present(_ feature: PaidFeature, trigger: String, userInitiated: Bool = false) -> Bool {
        guard !EntitlementStore.shared.isLifetime else { return false }
        guard userInitiated || hasCompletedFirstResult else { return false }
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

    /// The gate every locked feature should call. Returns true when the caller
    /// may proceed.
    ///
    /// If the paywall is suppressed — the user has not seen a first result yet —
    /// the feature is allowed through rather than doing nothing. A button that
    /// neither works nor explains itself is worse than an unsold feature.
    static func allow(_ feature: PaidFeature, trigger: String) -> Bool {
        if EntitlementStore.shared.isUnlocked(feature) { return true }
        return !shared.present(feature, trigger: trigger)
    }
}
