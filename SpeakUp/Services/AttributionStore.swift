import Foundation
import Observation

/// Remembers where an install came from, without identifying anyone.
///
/// A campaign link carries `source`, `campaign`, and `page` as query
/// parameters; the first launch stores them and every later monetization event
/// reports the same coarse strings. No device identifier, no IDFA, no
/// AdServices token, no network call — the plan's measurement requirements are
/// met by attributing the *install*, not the person.
@MainActor
@Observable
final class AttributionStore {
    static let shared = AttributionStore()

    private enum Key {
        static let source = "attribution.source.v1"
        static let campaign = "attribution.campaign.v1"
        static let page = "attribution.page.v1"
        static let firstOpen = "attribution.firstOpenDate.v1"
    }

    /// Accepted on any deep link, not only a dedicated one, so a partner can
    /// point straight at the action they are promoting.
    private static let sourceKeys = ["source", "utm_source", "src"]
    private static let campaignKeys = ["campaign", "utm_campaign", "c"]
    private static let pageKeys = ["page", "ppid", "cpp"]

    private let defaults = UserDefaults.standard

    private(set) var source: String?
    private(set) var campaign: String?
    private(set) var page: String?
    private(set) var firstOpenDate: Date

    private init() {
        source = defaults.string(forKey: Key.source)
        campaign = defaults.string(forKey: Key.campaign)
        page = defaults.string(forKey: Key.page)

        if let stored = defaults.object(forKey: Key.firstOpen) as? Date {
            firstOpenDate = stored
        } else {
            let now = Date()
            firstOpenDate = now
            defaults.set(now, forKey: Key.firstOpen)
        }
    }

    /// Minutes since the very first launch. Feeds the time-to-value metric.
    var minutesSinceFirstOpen: Double {
        Date().timeIntervalSince(firstOpenDate) / 60
    }

    /// First attribution wins. A user who arrives from a partner link and later
    /// taps a widget is still a partner install.
    func capture(from url: URL) {
        guard source == nil else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return }

        func value(for keys: [String]) -> String? {
            for key in keys {
                if let match = items.first(where: { $0.name.lowercased() == key })?.value,
                   !match.isEmpty {
                    return String(match.prefix(64))
                }
            }
            return nil
        }

        guard let capturedSource = value(for: Self.sourceKeys) else { return }
        source = capturedSource
        campaign = value(for: Self.campaignKeys)
        page = value(for: Self.pageKeys)

        defaults.set(source, forKey: Key.source)
        defaults.set(campaign, forKey: Key.campaign)
        defaults.set(page, forKey: Key.page)
    }

    /// Logs `first_open` exactly once per install. Called after a short grace
    /// period so a launch that came in through a campaign link has already had
    /// its parameters captured by `capture(from:)`.
    func logFirstOpenIfNeeded() {
        AnalyticsService.shared.logOnce(
            .firstOpen(source: source, campaign: campaign, page: page),
            key: "first_open"
        )
    }
}
