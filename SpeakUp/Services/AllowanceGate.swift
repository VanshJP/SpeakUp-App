import Foundation
import SwiftData

/// Reads and writes the free-tier allowance against `UserSettings`.
///
/// Every rule lives in `PracticeAllowance`; this layer only fetches the row,
/// hands over the state, and persists the result. It fails open — a missing or
/// unreadable settings row must never stop someone from practising.
@MainActor
enum AllowanceGate {
    static func decision(
        settings: UserSettings?,
        now: Date = Date()
    ) -> AllowanceDecision {
        guard let settings else { return .unlimited }
        let store = EntitlementStore.shared
        return PracticeAllowance.decision(
            state: settings.allowanceState,
            isEntitled: store.isLifetime,
            trial: store.trialState,
            policy: store.policy,
            now: now
        )
    }

    /// Records a consumed analysis. Call only after an analysis succeeded.
    ///
    /// This is also where the 14-day trial clock starts: one call site, and it
    /// inherits the "charged only on success" invariant, so a failed
    /// transcription can never burn a day.
    static func consume(settings: UserSettings?, now: Date = Date()) {
        let store = EntitlementStore.shared
        store.startTrialIfNeeded(now: now)

        guard let settings else { return }
        settings.allowanceState = PracticeAllowance.consume(
            state: settings.allowanceState,
            isEntitled: store.isLifetime,
            trial: store.trialState,
            policy: store.policy,
            now: now
        )
    }
}
