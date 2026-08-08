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
        static let trialStartedAt = "entitlement.trial.startedAt.v1"
        static let debugOverride = "debug.forceLifetimeEntitlement"
    }

    /// Shared with the widget extension. Falls back to standard defaults if the
    /// App Group is unavailable so entitlement never silently resets.
    private let defaults: UserDefaults

    private(set) var isLifetime: Bool
    private(set) var purchaseDate: Date?

    /// When the 14-day trial clock was started, or nil if it never has been.
    /// Lives in device defaults rather than SwiftData: every gate resolves
    /// entitlement synchronously from here, and a second copy in `UserSettings`
    /// would be a second thing to keep in sync. A reinstall therefore grants a
    /// fresh 14 days — generous on purpose, and the alternative would need a
    /// CloudKit round-trip before anyone could practise.
    private(set) var trialStartedAt: Date?

    /// True when the value came from a StoreKit response this launch rather
    /// than from the cache. Used to avoid showing "Free" copy before the first
    /// entitlement refresh lands.
    private(set) var hasVerifiedThisLaunch = false

    private init() {
        let suite = UserDefaults(suiteName: WidgetDataProvider.suiteName) ?? .standard
        defaults = suite
        isLifetime = suite.bool(forKey: Key.isLifetime)
        purchaseDate = suite.object(forKey: Key.purchasedAt) as? Date
        trialStartedAt = suite.object(forKey: Key.trialStartedAt) as? Date

        #if DEBUG
        if suite.bool(forKey: Key.debugOverride) || UserDefaults.standard.bool(forKey: Key.debugOverride) {
            isLifetime = true
        }
        #endif
    }

    var trialState: TrialState {
        PracticeTrial.state(startedAt: trialStartedAt)
    }

    /// Starts the 14 days. Idempotent — the two callers (the first successful
    /// analysis, and first launch of this build on an install that already has
    /// recordings) both funnel through here, and only the first one writes.
    func startTrialIfNeeded(now: Date = Date()) {
        guard trialStartedAt == nil else { return }
        trialStartedAt = now
        defaults.set(now, forKey: Key.trialStartedAt)
    }

    /// The active free/paid boundary. Feature code asks this, never `isLifetime`
    /// directly, so the boundary stays in one place.
    var policy: FreeTierPolicy {
        if isLifetime { return .unrestricted }
        return trialState.isExpired ? .expired : .trial
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

    /// Moves the trial clock so both sides of the 14 days can be exercised
    /// without waiting two weeks. `nil` puts it back to "never started".
    func setDebugTrialStart(_ date: Date?) {
        trialStartedAt = date
        if let date {
            defaults.set(date, forKey: Key.trialStartedAt)
        } else {
            defaults.removeObject(forKey: Key.trialStartedAt)
        }
    }
    #endif
}
