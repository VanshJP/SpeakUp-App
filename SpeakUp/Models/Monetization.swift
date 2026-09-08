import Foundation

// MARK: - Beta

/// Master switch for the public beta: everything unlocked, no paywall, no
/// allowance accounting, no buy button anywhere in the app.
///
/// StoreKit still verifies underneath. Flipping this alone does not restore
/// monetization — paywall UI was deleted. Guide: docs/features/monetization.md
nonisolated enum BetaAccess {
    static let allFeaturesFree = true
}

// MARK: - Product

nonisolated enum LifetimeProduct {
    /// Must match the product identifier configured in App Store Connect and
    /// in `Products.storekit`.
    static let identifier = "com.vansh.SpeakUpMore.lifetime"
}

// MARK: - Founding Offer

/// Controls the founding-price framing on the paywall.
/// This only changes copy. The price itself is whatever App Store Connect
/// serves, so `deadline` must be moved and the App Store Connect price raised
/// on the same day. It ships as `nil` on purpose: an unset deadline shows no
nonisolated enum FoundingOffer {
    static let deadline: Date? = nil

    /// The price the offer says it reverts to. StoreKit cannot supply a price
    /// for a product it is not currently selling, so this literal is the one
    /// unavoidable hardcoded price in the app — and it is only correct on the
    /// US storefront.
    static let standardDisplayPrice = "$99.99"

    static let standardPriceCurrencyCode = "USD"

    static func isActive(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }

    /// The "…after" comparison, or nil when it cannot be stated honestly.
    /// Returns nil on any storefront that is not selling in the currency the
    /// literal is written in, rather than putting "$99.99 after" next to a
    static func comparisonPrice(currencyCode: String?, now: Date = Date()) -> String? {
        guard isActive(now: now) else { return nil }
        guard currencyCode == standardPriceCurrencyCode else { return nil }
        return standardDisplayPrice
    }
}

// MARK: - Paid Features

/// Everything that can sit behind the Lifetime purchase. Membership of the
/// gated set lives in `FreeTierPolicy`, not at the call site, so the boundary
/// can be moved in one place after launch measurement.
nonisolated enum PaidFeature: String, CaseIterable, Sendable {
    case unlimitedAnalyses
    case fullCurriculum
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

    var paywallReason: String {
        switch self {
        case .unlimitedAnalyses:
            return "Unlimited scored practice is part of Lifetime."
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

// MARK: - Free Trial

/// The 14-day window in which everything except iCloud sync is open.
/// transcription cannot start it. `AllowanceGate.consume` is the one place that
/// starts it; `EntitlementStore` owns the date.
nonisolated enum PracticeTrial {
    static let lengthInDays = 14
    static let length = TimeInterval(lengthInDays) * 24 * 60 * 60

    static func state(startedAt: Date?, now: Date = Date()) -> TrialState {
        guard let startedAt else { return .notStarted }
        let endsOn = startedAt.addingTimeInterval(length)
        return now < endsOn ? .active(endsOn: endsOn) : .expired
    }

    static func daysRemaining(until endsOn: Date, now: Date = Date()) -> Int {
        max(0, Int((endsOn.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

nonisolated enum TrialState: Sendable, Equatable {
    case notStarted
    case active(endsOn: Date)
    case expired

    var isExpired: Bool { self == .expired }
}

// MARK: - Free Tier Policy

nonisolated struct FreeTierPolicy: Sendable, Equatable {
    var monthlyAnalyses: Int
    var gatedFeatures: Set<PaidFeature>

    func gates(_ feature: PaidFeature) -> Bool {
        gatedFeatures.contains(feature)
    }

    /// During the 14 days: see everything, then decide. Only iCloud sync stays
    /// behind the purchase, because turning it on is a commitment to a store
    /// the user would then lose access to when the trial ends.
    static let trial = FreeTierPolicy(
        monthlyAnalyses: .max,
        gatedFeatures: [.iCloudSync]
    )

    /// After the 14 days: three analyses per rolling month, and the full
    /// ownership boundary (curriculum, export, sync).
    ///
    static let expired = FreeTierPolicy(
        monthlyAnalyses: 3,
        gatedFeatures: [.unlimitedAnalyses, .fullCurriculum, .journalExport, .iCloudSync]
    )

    static let unrestricted = FreeTierPolicy(
        monthlyAnalyses: .max,
        gatedFeatures: []
    )
}

// MARK: - Allowance

/// Persisted counters behind the free analysis allowance. Kept separate from
/// `UserSettings` so the arithmetic is testable without SwiftData.
nonisolated struct AllowanceState: Sendable, Equatable {
    var cycleStart: Date?
    var cycleUsed: Int = 0
}

nonisolated enum AllowanceDecision: Sendable, Equatable {
    case trial(endsOn: Date)
    case cycle(remaining: Int, resetsOn: Date)
    case exhausted(resetsOn: Date)
    case unlimited

    var isAllowed: Bool {
        if case .exhausted = self { return false }
        return true
    }

    var remaining: Int? {
        switch self {
        case .cycle(let remaining, _): return remaining
        case .exhausted: return 0
        case .trial, .unlimited: return nil
        }
    }

    /// One line stating what is left, for the surfaces that disclose the limit
    /// *before* it is spent. Nil when there is nothing to say, which is both the
    /// entitled case and the reason an entitled user sees no plan chatter.
    var shortSummary: String? { summary(now: Date()) }

    /// `shortSummary` with an injected clock, because the trial line counts days
    /// down and a copy test cannot wait fourteen days to check it.
    func summary(now: Date) -> String? {
        func analyses(_ count: Int) -> String {
            "\(count) free \(count == 1 ? "analysis" : "analyses") left"
        }
        func day(_ date: Date) -> String {
            date.formatted(.dateTime.month(.abbreviated).day())
        }

        switch self {
        case .unlimited:
            return nil
        case .trial(let endsOn):
            let days = PracticeTrial.daysRemaining(until: endsOn, now: now)
            return days <= 1 ? "Free trial · last day" : "Free trial · \(days) days left"
        case .cycle(let remaining, let resetsOn):
            return "\(analyses(remaining)) · resets \(day(resetsOn))"
        case .exhausted(let resetsOn):
            return "No free analyses left · resets \(day(resetsOn))"
        }
    }
}

/// Pure allowance arithmetic. No StoreKit, no SwiftData, no clock of its own —
/// `now` is always injected so the rollover is testable.
nonisolated enum PracticeAllowance {
    /// A month here is a rolling 30-day window from first paid-tier use, not a
    /// calendar month. A calendar reset would hand a user who installs on the
    /// 30th two allowances in two days.
    static let cycleLength: TimeInterval = 30 * 24 * 60 * 60

    static func decision(
        state: AllowanceState,
        isEntitled: Bool,
        trial: TrialState,
        policy: FreeTierPolicy,
        now: Date = Date()
    ) -> AllowanceDecision {
        guard !isEntitled else { return .unlimited }

        switch trial {
        case .notStarted: return .trial(endsOn: now.addingTimeInterval(PracticeTrial.length))
        case .active(let endsOn): return .trial(endsOn: endsOn)
        case .expired: break
        }

        guard policy.gates(.unlimitedAnalyses) else { return .unlimited }

        let normalized = normalizedCycle(state: state, now: now)
        let resetsOn = normalized.start.addingTimeInterval(cycleLength)

        guard normalized.used < policy.monthlyAnalyses else {
            return .exhausted(resetsOn: resetsOn)
        }
        return .cycle(remaining: policy.monthlyAnalyses - normalized.used, resetsOn: resetsOn)
    }

    /// Records one consumed analysis. Only ever called after an analysis
    /// actually succeeded — a failed transcription must not cost a credit.
    /// Nothing is counted while the trial is live.
    static func consume(
        state: AllowanceState,
        isEntitled: Bool,
        trial: TrialState,
        policy: FreeTierPolicy,
        now: Date = Date()
    ) -> AllowanceState {
        guard !isEntitled, trial.isExpired, policy.gates(.unlimitedAnalyses) else { return state }

        var updated = state
        let normalized = normalizedCycle(state: state, now: now)
        updated.cycleStart = normalized.start
        updated.cycleUsed = normalized.used + 1
        return updated
    }

    private static func normalizedCycle(state: AllowanceState, now: Date) -> (start: Date, used: Int) {
        guard let start = state.cycleStart else { return (now, 0) }
        guard now.timeIntervalSince(start) >= cycleLength else { return (start, state.cycleUsed) }

        let elapsed = now.timeIntervalSince(start)
        let cyclesPassed = (elapsed / cycleLength).rounded(.down)
        return (start.addingTimeInterval(cyclesPassed * cycleLength), 0)
    }
}
