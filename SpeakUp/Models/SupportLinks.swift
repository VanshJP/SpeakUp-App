import Foundation

/// Outbound support and legal destinations.
///
/// The values come from Info.plist rather than source so the site can be stood
/// up without a code change, and so a build that has not had them filled in
/// simply hides those rows instead of shipping a dead link. The in-app
/// `LifetimeFAQView` carries the ownership scope and storage disclosure, so a
/// missing website degrades the experience rather than breaking a requirement.
nonisolated enum SupportLinks {
    private static func url(for key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://") else { return nil }
        return URL(string: trimmed)
    }

    static var support: URL? { url(for: "BTSupportURL") }
    static var privacyPolicy: URL? { url(for: "BTPrivacyPolicyURL") }
    static var terms: URL? { url(for: "BTTermsURL") }

    static let feedbackEmail = "vansh@trygoldfinch.com"

    static var feedbackMailto: URL? {
        URL(string: "mailto:\(feedbackEmail)")
    }

    static var hasAnyWebDestination: Bool {
        support != nil || privacyPolicy != nil || terms != nil
    }
}
