import Foundation
import Observation
import StoreKit
import UIKit

/// Asks for an App Store review, but only after something actually went well.
///
/// Ratings are the cheapest acquisition channel this app has, and the system
/// budget is three prompts per user per year. Spending one on a bad session, a
/// first launch, or the instant after a paywall is spending it on someone who
/// is not about to write five stars. Every ask therefore has to clear a success
/// trigger *and* the throttles in `ReviewEligibility`.
@MainActor
@Observable
final class ReviewRequestService {
    static let shared = ReviewRequestService()

    /// What just went well. Reported as the `trigger` dimension so the funnel
    /// shows which moment is worth asking on.
    enum Trigger: String {
        case strongResult = "strong_result"
        case shareCompleted = "share_completed"
        case achievementUnlocked = "achievement_unlocked"
    }

    /// One ask per launch, regardless of how many good things happen.
    private var askedThisLaunch = false

    private init() {}

    /// Raises the system review prompt when the moment and the throttles allow.
    ///
    /// `settings` carries the persisted throttle state, so the caller has to be
    /// a surface that already owns a `UserSettings` — which every success
    /// trigger is. Returns whether the prompt was requested.
    @discardableResult
    func requestIfEligible(_ trigger: Trigger, settings: UserSettings?) -> Bool {
        guard let settings else { return false }

        let version = AnalyticsEnvironment.appVersion
        guard ReviewEligibility.shouldAsk(
            askedThisLaunch: askedThisLaunch,
            hasSeenFirstResult: PaywallCoordinator.shared.hasCompletedFirstResult,
            paywallOnScreen: PaywallCoordinator.shared.request != nil,
            currentVersion: version,
            lastAskedVersion: settings.lastReviewRequestVersion,
            lastAskedDate: settings.lastReviewRequestDate
        ) else { return false }

        guard let scene = activeScene else { return false }

        askedThisLaunch = true
        settings.lastReviewRequestVersion = version
        settings.lastReviewRequestDate = Date()

        AnalyticsService.shared.log(.reviewRequested(trigger: trigger.rawValue))
        AppStore.requestReview(in: scene)
        return true
    }

    private var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
