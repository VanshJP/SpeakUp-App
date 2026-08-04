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

    static func decision(modelContext: ModelContext, now: Date = Date()) -> AllowanceDecision {
        decision(settings: fetchSettings(modelContext), now: now)
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

    /// Recordings that were saved while the allowance was spent. Used to offer
    /// "analyze the ones you missed" once the user buys or the cycle resets.
    static func blockedRecordingCount(modelContext: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.analysisBlockedByAllowance == true }
        )
        descriptor.propertiesToFetch = [\.analysisBlockedByAllowance]
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private static func fetchSettings(_ modelContext: ModelContext) -> UserSettings? {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
