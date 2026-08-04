import Foundation

// MARK: - Funnel

/// The six funnels the launch scorecard is built from.
enum AnalyticsFunnel: String, Codable, CaseIterable, Sendable {
    case acquisition
    case activation
    case outcome
    case advocacy
    case monetization
    case quality
}

// MARK: - Event

/// A single coarse behavioural event.
///
/// The privacy rule is structural, not a convention: an event carries a name, a
/// funnel, and a dictionary of *bucketed* dimensions. Audio, transcripts,
/// prompt or story text, exact scores, contacts, and share recipients have no
/// representation here, so they cannot be logged by accident.
struct AnalyticsEvent: Sendable, Equatable {
    let name: String
    let funnel: AnalyticsFunnel
    let dimensions: [String: String]

    init(_ name: String, funnel: AnalyticsFunnel, dimensions: [String: String] = [:]) {
        self.name = name
        self.funnel = funnel
        self.dimensions = dimensions.compactMapValues { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Schema

extension AnalyticsEvent {
    // Acquisition

    static func firstOpen(source: String?, campaign: String?, page: String?) -> AnalyticsEvent {
        AnalyticsEvent("first_open", funnel: .acquisition, dimensions: [
            "source": source ?? "organic",
            "campaign": campaign ?? "none",
            "page": page ?? "default",
            "app_version": AnalyticsEnvironment.appVersion
        ])
    }

    static func sessionStart() -> AnalyticsEvent {
        AnalyticsEvent("session_start", funnel: .acquisition, dimensions: [
            "app_version": AnalyticsEnvironment.appVersion
        ])
    }

    // Activation

    static func onboardingStep(_ step: String, action: String) -> AnalyticsEvent {
        AnalyticsEvent("onboarding_step", funnel: .activation, dimensions: [
            "step": step,
            "action": action
        ])
    }

    static func permissionResult(kind: String, granted: Bool) -> AnalyticsEvent {
        AnalyticsEvent("permission_result", funnel: .activation, dimensions: [
            "kind": kind,
            "result": granted ? "granted" : "denied"
        ])
    }

    static func practiceStarted(useCase: String, sessionNumber: Int) -> AnalyticsEvent {
        AnalyticsEvent("practice_start", funnel: .activation, dimensions: [
            "use_case": useCase,
            "session_bucket": AnalyticsBucket.sessionNumber(sessionNumber)
        ])
    }

    static func analysisCompleted(
        sessionNumber: Int,
        processingPath: String,
        elapsed: TimeInterval
    ) -> AnalyticsEvent {
        AnalyticsEvent("analysis_complete", funnel: .activation, dimensions: [
            "session_bucket": AnalyticsBucket.sessionNumber(sessionNumber),
            "path": processingPath,
            "elapsed_bucket": AnalyticsBucket.elapsed(elapsed)
        ])
    }

    static func analysisFailed(reason: String) -> AnalyticsEvent {
        AnalyticsEvent("analysis_failed", funnel: .activation, dimensions: ["reason": reason])
    }

    /// Fired once, when the user reaches their first completed analysis. The
    /// plan's definition of an activated user.
    static func activated(minutesFromFirstOpen: Double) -> AnalyticsEvent {
        AnalyticsEvent("activated", funnel: .activation, dimensions: [
            "time_to_value_bucket": AnalyticsBucket.minutes(minutesFromFirstOpen)
        ])
    }

    // Outcome

    static func nextActionTaken(area: String) -> AnalyticsEvent {
        AnalyticsEvent("next_action", funnel: .outcome, dimensions: ["weak_area": area])
    }

    static func milestone(type: String) -> AnalyticsEvent {
        AnalyticsEvent("milestone", funnel: .outcome, dimensions: ["type": type])
    }

    // Advocacy

    static func shareCompleted(cardType: String, trigger: String) -> AnalyticsEvent {
        AnalyticsEvent("share_complete", funnel: .advocacy, dimensions: [
            "card_type": cardType,
            "trigger": trigger
        ])
    }

    static func reviewRequested(trigger: String) -> AnalyticsEvent {
        AnalyticsEvent("review_requested", funnel: .advocacy, dimensions: ["trigger": trigger])
    }

    // Monetization

    /// Only ever logged for a paywall shown *after* a complete first result,
    /// which is what makes the qualified-conversion metric meaningful.
    static func paywallQualified(trigger: String, source: String?) -> AnalyticsEvent {
        AnalyticsEvent("paywall_qualified", funnel: .monetization, dimensions: [
            "trigger": trigger,
            "source": source ?? "organic"
        ])
    }

    static func purchaseResult(_ result: String, price: String, source: String?) -> AnalyticsEvent {
        AnalyticsEvent("purchase_result", funnel: .monetization, dimensions: [
            "result": result,
            "product": LifetimeProduct.identifier,
            "price_tier": price,
            "source": source ?? "organic"
        ])
    }

    static func restoreResult(_ result: String) -> AnalyticsEvent {
        AnalyticsEvent("restore_result", funnel: .monetization, dimensions: ["result": result])
    }

    static func allowanceExhausted() -> AnalyticsEvent {
        AnalyticsEvent("allowance_exhausted", funnel: .monetization)
    }

    // Quality

    static func modelDownload(tier: String, result: String) -> AnalyticsEvent {
        AnalyticsEvent("model_download", funnel: .quality, dimensions: [
            "tier": tier,
            "result": result,
            "app_version": AnalyticsEnvironment.appVersion
        ])
    }

    static func feedbackCategory(_ category: String) -> AnalyticsEvent {
        AnalyticsEvent("feedback", funnel: .quality, dimensions: ["category": category])
    }
}

// MARK: - Buckets

/// Continuous values are always reported as ranges. A precise duration or score
/// attached to a small cohort is re-identifying; a bucket is not.
enum AnalyticsBucket {
    static func elapsed(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<10: return "0-10s"
        case ..<30: return "10-30s"
        case ..<60: return "30-60s"
        case ..<120: return "1-2m"
        case ..<300: return "2-5m"
        default: return "5m+"
        }
    }

    static func minutes(_ minutes: Double) -> String {
        switch minutes {
        case ..<2: return "0-2m"
        case ..<4: return "2-4m"
        case ..<8: return "4-8m"
        case ..<20: return "8-20m"
        case ..<60: return "20-60m"
        case ..<1440: return "1-24h"
        default: return "24h+"
        }
    }

    static func sessionNumber(_ number: Int) -> String {
        switch number {
        case ..<1: return "0"
        case 1: return "1"
        case 2: return "2"
        case 3...5: return "3-5"
        case 6...10: return "6-10"
        default: return "11+"
        }
    }

    static func storage(megabytes: Double) -> String {
        switch megabytes {
        case ..<100: return "0-100MB"
        case ..<500: return "100-500MB"
        case ..<2000: return "0.5-2GB"
        default: return "2GB+"
        }
    }
}

// MARK: - Environment

enum AnalyticsEnvironment {
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short)(\(build))"
    }
}

// MARK: - Recorded Event

/// An event plus the timestamp it happened at. Persisted form.
struct RecordedAnalyticsEvent: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var funnel: String
    var dimensions: [String: String]
    var timestamp: Date

    init(event: AnalyticsEvent, timestamp: Date = Date()) {
        self.name = event.name
        self.funnel = event.funnel.rawValue
        self.dimensions = event.dimensions
        self.timestamp = timestamp
    }
}
