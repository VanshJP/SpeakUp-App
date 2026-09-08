import Foundation
import Observation
import StoreKit
import UIKit

/// Asks for an App Store review, but only after something actually went well.
@MainActor
@Observable
final class ReviewRequestService {
    static let shared = ReviewRequestService()

    enum Trigger: String {
        case strongResult = "strong_result"
        case shareCompleted = "share_completed"
    }

    private var askedThisLaunch = false

    /// Set once the user has seen a finished analysis. Persisted, because it
    /// describes something they have already done — held only in memory it
    /// reset on every cold launch and silently disarmed every prompt.
    private(set) var hasCompletedFirstResult: Bool

    private let defaults: UserDefaults
    private static let firstResultKey = "paywall.firstResultSeen.v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedFirstResult = defaults.bool(forKey: Self.firstResultKey)
    }

    func markFirstResultSeen() {
        guard !hasCompletedFirstResult else { return }
        hasCompletedFirstResult = true
        defaults.set(true, forKey: Self.firstResultKey)
    }

    @discardableResult
    func requestIfEligible(_ trigger: Trigger, settings: UserSettings?) -> Bool {
        guard let settings else { return false }

        let version = AnalyticsEnvironment.appVersion
        guard ReviewEligibility.shouldAsk(
            askedThisLaunch: askedThisLaunch,
            hasSeenFirstResult: hasCompletedFirstResult,
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
