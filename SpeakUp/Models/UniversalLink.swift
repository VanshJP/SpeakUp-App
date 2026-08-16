import Foundation

/// Translates a campaign web link into the `speakup://` URL the router already
/// understands.
///
/// Partner and campaign links in the launch plan are ordinary `https://` URLs —
/// they have to survive being pasted into a newsletter, a bio, or a QR code,
/// which a custom scheme does not. Rather than growing a second router for the
/// web form, a universal link is normalised into its custom-scheme equivalent
/// and handed to the same `handleDeepLink`, so routing and attribution capture
/// cannot drift between the two entry points.
///
/// `https://bigtalk.example/record?prompt=42&source=newsletter`
/// becomes `speakup://record?prompt=42&source=newsletter`.
///
/// The domain comes from Info.plist (`BTUniversalLinkDomain`) rather than
/// source, for the same reason the support and legal URLs do: the site can be
/// stood up without a code change, and a build with the key unset ignores web
/// links instead of claiming domains it does not own.
nonisolated enum UniversalLink {
    static let infoPlistKey = "BTUniversalLinkDomain"

    /// The configured universal-link host, or nil when none is set.
    ///
    /// Must stay identical to the host in the `associated-domains` entitlement.
    /// Both read the `BT_UNIVERSAL_LINK_DOMAIN` build setting so they cannot
    /// disagree — see `RELEASE_CHECKLIST.md`.
    static var domain: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        return normalizedHost(raw)
    }

    /// The host exactly as configured, `www.` intact.
    ///
    /// Outbound links must use the host the `apple-app-site-association` file
    /// is actually served from: iOS does not follow redirects when resolving a
    /// universal link, so an apex link on a site that 308s to `www` opens
    /// Safari instead of the app. Inbound matching still uses `domain`, which
    /// is `www.`-insensitive, so both forms route.
    static var linkHost: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        return normalizedHost(raw, strippingWWW: false)
    }

    /// Reads the configured domain and routes against it.
    static func route(from url: URL) -> URL? {
        guard let domain else { return nil }
        return route(from: url, domain: domain)
    }

    /// Pure form: no Info.plist, no globals.
    ///
    /// Returns nil for anything that is not an `https` link on `domain`, which
    /// includes the `speakup://` links the router handles directly.
    static func route(from url: URL, domain: String) -> URL? {
        guard let expected = normalizedHost(domain) else { return nil }
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard let host = normalizedHost(url.host), host == expected else { return nil }

        // The first path segment plays the part the custom scheme puts in the
        // host position; everything after it stays a path. An empty path is the
        // bare campaign link, which lands on the home screen.
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        var rebuilt = URLComponents()
        rebuilt.scheme = "speakup"
        rebuilt.host = segments.first ?? "open"
        if segments.count > 1 {
            rebuilt.path = "/" + segments.dropFirst().joined(separator: "/")
        }
        // Carried verbatim: campaign parameters live here, and dropping them
        // would silently turn an attributed install into an organic one.
        rebuilt.query = url.query

        return rebuilt.url
    }

    /// Lowercased, `www.`-stripped, empty-as-nil. Applied to both sides of the
    /// comparison so a link written `https://WWW.Example.com` still matches a
    /// domain configured as `example.com`.
    private static func normalizedHost(_ raw: String?, strippingWWW: Bool = true) -> String? {
        guard let raw else { return nil }
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Tolerates a domain configured with a scheme or a trailing slash.
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        if host.hasSuffix("/") { host.removeLast() }
        if strippingWWW, host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
