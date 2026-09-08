import Foundation

nonisolated enum ReviewEligibility {
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
