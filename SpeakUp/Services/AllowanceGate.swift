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
        return PracticeAllowance.decision(
            state: settings.allowanceState,
            isEntitled: EntitlementStore.shared.isLifetime,
            policy: .default,
            now: now
        )
    }

    /// Records a consumed analysis. Call only after an analysis succeeded.
    static func consume(settings: UserSettings?, now: Date = Date()) {
        guard let settings else { return }
        settings.allowanceState = PracticeAllowance.consume(
            state: settings.allowanceState,
            isEntitled: EntitlementStore.shared.isLifetime,
            policy: .default,
            now: now
        )
    }
}
