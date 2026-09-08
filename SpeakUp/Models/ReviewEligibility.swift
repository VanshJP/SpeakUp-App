import Foundation

/// When the app is allowed to ask for an App Store review.
///
/// Pure arithmetic, deliberately separate from `ReviewRequestService`: the
/// rules decide whether a prompt is *earned*, and that judgement should be
/// testable without StoreKit, a window scene, or a store.
///
/// The system allows three prompts per user per year. Every rule here exists to
/// stop the app spending one on somebody who is not delighted.
nonisolated enum ReviewEligibility {
    /// Two months between asks. Apple already caps the count; this keeps the
    /// app from burning the whole yearly budget in a single good week.
    static let minimumInterval: TimeInterval = 60 * 24 * 60 * 60

    static func shouldAsk(
        askedThisLaunch: Bool,
        hasSeenFirstResult: Bool,
        currentVersion: String,
        lastAskedVersion: String?,
        lastAskedDate: Date?,
        now: Date = Date(),
        minimumInterval: TimeInterval = ReviewEligibility.minimumInterval
    ) -> Bool {
        guard !askedThisLaunch else { return false }
        // Nobody rates an app they have not gotten a result out of yet.
        guard hasSeenFirstResult else { return false }
        // One ask per version: a build the user disliked does not get a retry.
        guard lastAskedVersion != currentVersion else { return false }

        if let lastAskedDate {
            guard now.timeIntervalSince(lastAskedDate) >= minimumInterval else { return false }
        }
        return true
    }
}
