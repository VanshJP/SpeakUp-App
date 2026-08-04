import Foundation

// MARK: - Product

/// The single paid SKU. One non-consumable, no tiers — the ownership offer is
/// meant to be a one-decision purchase.
enum LifetimeProduct {
    /// Must match the product identifier configured in App Store Connect and
    /// in `Products.storekit`.
    static let identifier = "com.vansh.SpeakUpMore.lifetime"
}

// MARK: - Founding Offer

/// Controls the founding-price framing on the paywall.
///
/// This only changes copy. The price itself is whatever App Store Connect
/// serves, so `deadline` must be moved and the App Store Connect price raised
/// on the same day. It ships as `nil` on purpose: an unset deadline shows no
/// urgency at all, which is the only safe default for a claim about scarcity.
enum FoundingOffer {
    static let deadline: Date? = nil

    /// The price the offer says it reverts to. StoreKit cannot supply a price
    /// for a product it is not currently selling, so this literal is the one
    /// unavoidable hardcoded price in the app — and it is only correct on the
    /// US storefront. Setting `deadline` while shipping internationally means
    /// showing some users a comparison in the wrong currency.
    static let standardDisplayPrice = "$99.99"

    static func isActive(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }
}

// MARK: - Paid Features

/// Everything that can sit behind the Lifetime purchase. Membership of the
/// gated set lives in `FreeTierPolicy`, not at the call site, so the boundary
/// can be moved in one place after launch measurement.
enum PaidFeature: String, CaseIterable, Sendable {
    /// Practice beyond the free analysis allowance.
    case unlimitedAnalyses
    /// Curriculum phases past the first.
    case fullCurriculum
    /// Journal PDF export.
    case journalExport
    /// Turning on iCloud sync (never revoked once enabled).
    case iCloudSync
    /// Then-vs-Now and milestone progress cards.
    case progressCards

    var displayName: String {
        switch self {
        case .unlimitedAnalyses: return "Unlimited practice"
        case .fullCurriculum: return "The full curriculum"
        case .journalExport: return "Journal export"
        case .iCloudSync: return "iCloud sync"
        case .progressCards: return "Progress cards"
        }
    }

    /// Why the user is seeing the paywall. Drives the paywall headline.
    var paywallReason: String {
        switch self {
        case .unlimitedAnalyses:
            return "You have used your free analyses for now."
        case .fullCurriculum:
            return "The eight-week curriculum is part of Lifetime."
        case .journalExport:
            return "Journal export is part of Lifetime."
        case .iCloudSync:
            return "iCloud sync is part of Lifetime."
        case .progressCards:
            return "Progress cards are part of Lifetime."
        }
    }
}

// MARK: - Free Tier Policy

/// The free/paid boundary in one value. Deliberately a stored policy rather
/// than scattered `if isLifetime` literals so the boundary can be tuned from
/// launch measurement without touching feature code.
struct FreeTierPolicy: Sendable, Equatable {
    /// Full analyses a new user gets immediately, before any monthly cycle
    /// starts. The first result has to be free for the score to earn trust.
    var introAnalyses: Int
    /// Full analyses per rolling month once the intro allowance is spent.
    var monthlyAnalyses: Int
    /// Features that require the Lifetime purchase.
    var gatedFeatures: Set<PaidFeature>

    func gates(_ feature: PaidFeature) -> Bool {
        gatedFeatures.contains(feature)
    }

    /// Ships with the GTM plan's allowance (three immediately, then three per
    /// month) and its ownership boundary (export, sync, complete archive).
    ///
    /// `progressCards` is intentionally *not* gated. The same plan makes
    /// Then-vs-Now sharing the primary distribution loop, and a share loop that
    /// only buyers can run cannot acquire the users it is budgeted to acquire.
    /// Add it here if measurement says otherwise.
    static let `default` = FreeTierPolicy(
        introAnalyses: 3,
        monthlyAnalyses: 3,
        gatedFeatures: [.unlimitedAnalyses, .fullCurriculum, .journalExport, .iCloudSync]
    )

    /// Everything open. Used for entitled users and for debug overrides.
    static let unrestricted = FreeTierPolicy(
        introAnalyses: .max,
        monthlyAnalyses: .max,
        gatedFeatures: []
    )
}

// MARK: - Allowance

/// Persisted counters behind the free analysis allowance. Kept separate from
/// `UserSettings` so the arithmetic is testable without SwiftData.
struct AllowanceState: Sendable, Equatable {
    var introUsed: Int = 0
    var cycleStart: Date?
    var cycleUsed: Int = 0
}

/// What the user is allowed to do right now.
enum AllowanceDecision: Sendable, Equatable {
    /// Part of the immediate intro allowance.
    case intro(remaining: Int)
    /// Part of the current monthly cycle.
    case cycle(remaining: Int, resetsOn: Date)
    /// Out of free analyses until `resetsOn`.
    case exhausted(resetsOn: Date)
    /// Entitled — no accounting at all.
    case unlimited

    var isAllowed: Bool {
        if case .exhausted = self { return false }
        return true
    }

    /// Analyses left before the paywall, or nil when unlimited.
    var remaining: Int? {
        switch self {
        case .intro(let remaining): return remaining
        case .cycle(let remaining, _): return remaining
        case .exhausted: return 0
        case .unlimited: return nil
        }
    }
}

/// Pure allowance arithmetic. No StoreKit, no SwiftData, no clock of its own —
/// `now` is always injected so the rollover is testable.
enum PracticeAllowance {
    /// A month here is a rolling 30-day window from first paid-tier use, not a
    /// calendar month. A calendar reset would hand a user who installs on the
    /// 30th two allowances in two days.
    static let cycleLength: TimeInterval = 30 * 24 * 60 * 60

    static func decision(
        state: AllowanceState,
        isEntitled: Bool,
        policy: FreeTierPolicy = .default,
        now: Date = Date()
    ) -> AllowanceDecision {
        guard !isEntitled, policy.gates(.unlimitedAnalyses) else { return .unlimited }

        if state.introUsed < policy.introAnalyses {
            return .intro(remaining: policy.introAnalyses - state.introUsed)
        }

        let normalized = normalizedCycle(state: state, now: now)
        let resetsOn = normalized.start.addingTimeInterval(cycleLength)

        guard normalized.used < policy.monthlyAnalyses else {
            return .exhausted(resetsOn: resetsOn)
        }
        return .cycle(remaining: policy.monthlyAnalyses - normalized.used, resetsOn: resetsOn)
    }

    /// Records one consumed analysis. Only ever called after an analysis
    /// actually succeeded — a failed transcription must not cost a credit.
    static func consume(
        state: AllowanceState,
        isEntitled: Bool,
        policy: FreeTierPolicy = .default,
        now: Date = Date()
    ) -> AllowanceState {
        guard !isEntitled, policy.gates(.unlimitedAnalyses) else { return state }

        var updated = state
        if updated.introUsed < policy.introAnalyses {
            updated.introUsed += 1
            return updated
        }

        let normalized = normalizedCycle(state: state, now: now)
        updated.cycleStart = normalized.start
        updated.cycleUsed = normalized.used + 1
        return updated
    }

    /// Rolls the window forward past any elapsed cycles so a user who returns
    /// after three months gets one fresh allowance, not three.
    private static func normalizedCycle(state: AllowanceState, now: Date) -> (start: Date, used: Int) {
        guard let start = state.cycleStart else { return (now, 0) }
        guard now.timeIntervalSince(start) >= cycleLength else { return (start, state.cycleUsed) }

        let elapsed = now.timeIntervalSince(start)
        let cyclesPassed = (elapsed / cycleLength).rounded(.down)
        return (start.addingTimeInterval(cyclesPassed * cycleLength), 0)
    }
}
