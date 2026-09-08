import Foundation

/// Translates a campaign web link into the `speakup://` URL the router already
/// understands.
///
nonisolated enum UniversalLink {
    static let infoPlistKey = "BTUniversalLinkDomain"

    static var domain: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        return normalizedHost(raw)
    }

    static var linkHost: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        return normalizedHost(raw, strippingWWW: false)
    }

    static func route(from url: URL) -> URL? {
        guard let domain else { return nil }
        return route(from: url, domain: domain)
    }

    static func route(from url: URL, domain: String) -> URL? {
        guard let expected = normalizedHost(domain) else { return nil }
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard let host = normalizedHost(url.host), host == expected else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        var rebuilt = URLComponents()
        rebuilt.scheme = "speakup"
        rebuilt.host = segments.first ?? "open"
        if segments.count > 1 {
            rebuilt.path = "/" + segments.dropFirst().joined(separator: "/")
        }
        rebuilt.query = url.query

        return rebuilt.url
    }

    private static func normalizedHost(_ raw: String?, strippingWWW: Bool = true) -> String? {
        guard let raw else { return nil }
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        if host.hasSuffix("/") { host.removeLast() }
        if strippingWWW, host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
