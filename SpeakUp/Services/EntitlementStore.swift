import Foundation
import Observation

/// Single source of truth for "does this user own Lifetime".
///
/// StoreKit is authoritative but not always reachable — first launch offline,
/// airplane-mode practice, a widget process that never talks to the App Store.
/// The last verified answer is therefore mirrored into the shared App Group so
/// every process can resolve entitlement synchronously at startup, and
/// `PurchaseService` corrects it as soon as StoreKit responds.
@MainActor
@Observable
final class EntitlementStore {
    static let shared = EntitlementStore()

    private enum Key {
        static let isLifetime = "entitlement.lifetime.v1"
        static let purchasedAt = "entitlement.lifetime.purchasedAt.v1"
        static let debugOverride = "debug.forceLifetimeEntitlement"
    }

    /// Shared with the widget extension. Falls back to standard defaults if the
    /// App Group is unavailable so entitlement never silently resets.
    private let defaults: UserDefaults

    private(set) var isLifetime: Bool
    private(set) var purchaseDate: Date?

    /// True when the value came from a StoreKit response this launch rather
    /// than from the cache. Used to avoid showing "Free" copy before the first
    /// entitlement refresh lands.
    private(set) var hasVerifiedThisLaunch = false

    private init() {
        let suite = UserDefaults(suiteName: WidgetDataProvider.suiteName) ?? .standard
        defaults = suite
        isLifetime = suite.bool(forKey: Key.isLifetime)
        purchaseDate = suite.object(forKey: Key.purchasedAt) as? Date

        #if DEBUG
        if suite.bool(forKey: Key.debugOverride) || UserDefaults.standard.bool(forKey: Key.debugOverride) {
            isLifetime = true
        }
        #endif
    }

    /// The active free/paid boundary. Feature code asks this, never `isLifetime`
    /// directly, so the boundary stays in one place.
    var policy: FreeTierPolicy {
        isLifetime ? .unrestricted : .default
    }

    func isUnlocked(_ feature: PaidFeature) -> Bool {
        isLifetime || !policy.gates(feature)
    }

    /// Applies a verified StoreKit answer.
    func apply(isLifetime owned: Bool, purchasedAt date: Date?) {
        hasVerifiedThisLaunch = true

        #if DEBUG
        if defaults.bool(forKey: Key.debugOverride) || UserDefaults.standard.bool(forKey: Key.debugOverride) {
            isLifetime = true
            return
        }
        #endif

        guard owned != isLifetime || date != purchaseDate else { return }
        isLifetime = owned
        purchaseDate = date
        defaults.set(owned, forKey: Key.isLifetime)
        if let date {
            defaults.set(date, forKey: Key.purchasedAt)
        } else {
            defaults.removeObject(forKey: Key.purchasedAt)
        }
    }

    #if DEBUG
    /// Developer switch for exercising both sides of the paywall without a
    /// sandbox purchase. DEBUG-only so it can never ship enabled.
    func setDebugOverride(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Key.debugOverride)
        defaults.set(enabled, forKey: Key.debugOverride)
        if enabled {
            isLifetime = true
        } else {
            isLifetime = defaults.bool(forKey: Key.isLifetime)
        }
    }

    var debugOverrideEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.debugOverride)
    }
    #endif
}
