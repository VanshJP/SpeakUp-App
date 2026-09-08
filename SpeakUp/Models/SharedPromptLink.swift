import CryptoKit
import Foundation

/// Everything a share link is allowed to carry so a friend can try the same
/// prompt. Prompt *text* is opt-in at share time; scores on the card are not
/// the same as scores in the URL — `beat` is only written when the sender
/// chose to include the prompt, because that is the challenge.
///
/// Lives as a POD so tests and background URL parsing never hop to the UI.
nonisolated struct SharedPromptPayload: Equatable, Sendable {
    var promptID: String? = nil
    var text: String? = nil
    var category: String? = nil
    var difficulty: String? = nil
    var beatScore: Int? = nil
    /// `share` when this came from a score-card challenge; nil for widgets
    /// and campaign `record?prompt=` links.
    var source: String? = nil

    var isShareChallenge: Bool { source == SharedPromptLink.shareSource }

    var trimmedText: String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A pending inbound challenge, shown on Today if the recipient doesn't start
/// immediately (onboarding, cancelled countdown).
nonisolated struct SharedChallenge: Equatable, Sendable, Codable {
    var promptID: String
    var promptText: String
    var category: String? = nil
    var difficulty: String? = nil
    var beatScore: Int? = nil
}

/// Builds and parses `speakup://record` / `https://<domain>/record` links that
/// carry a prompt a friend can tap.
nonisolated enum SharedPromptLink {
    static let shareSource = "share"
    static let promptQueryName = "prompt"
    static let textQueryName = "text"
    static let textQueryShortName = "t"
    static let categoryQueryName = "cat"
    static let difficultyQueryName = "diff"
    static let beatQueryName = "beat"

    /// iMessage and many browsers start dropping or wrapping URLs around here.
    private static let maxURLLength = 1800
    private static let maxPromptTextLength = 400

    // MARK: - Parse

    /// Reads a `record` link, custom-scheme or https. Unknown keys are ignored
    /// so a future sender can add fields without breaking old apps.
    ///
    /// HTTPS is recognised by path even when `BTUniversalLinkDomain` is unset,
    /// so a share URL built against a host still round-trips in tests and in
    /// builds that have not claimed the domain yet.
    static func payload(from url: URL) -> SharedPromptPayload? {
        let routed = UniversalLink.route(from: url)
        let candidate = routed ?? url
        guard isRecordLink(candidate) else { return nil }

        let items = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ names: String...) -> String? {
            for name in names {
                if let match = items.first(where: { $0.name == name })?.value,
                   !match.isEmpty {
                    return match
                }
            }
            return nil
        }

        let promptID = value(promptQueryName)
        let text = value(textQueryName, textQueryShortName)
        let category = value(categoryQueryName)
        let difficulty = value(difficultyQueryName)
        let source = value("source", "utm_source", "src")
        let beat = value(beatQueryName).flatMap { Int($0) }.flatMap { (0...100).contains($0) ? $0 : nil }

        return SharedPromptPayload(
            promptID: promptID,
            text: text,
            category: category,
            difficulty: difficulty,
            beatScore: beat,
            source: source
        )
    }

    private static func isRecordLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "speakup" {
            return url.host?.lowercased() == "record"
        }
        if url.scheme?.lowercased() == "https" {
            let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            return segments.first?.lowercased() == "record"
        }
        return false
    }

    // MARK: - Build

    /// A tappable URL for the share sheet. Prefers the configured universal
    /// link host so a friend *without* the app still lands on the site; falls
    /// back to `speakup://` when no host is configured yet.
    static func shareURL(
        for payload: SharedPromptPayload,
        domain: String? = UniversalLink.linkHost
    ) -> URL? {
        let clipped = clippedPayload(payload)
        if let domain, let host = normalizedHost(domain),
           let https = httpsURL(host: host, payload: clipped) {
            if https.absoluteString.count <= maxURLLength { return https }
            if let shorter = httpsURL(host: host, payload: clipped.droppingText),
               shorter.absoluteString.count <= maxURLLength {
                return shorter
            }
        }
        return customSchemeURL(payload: clipped)
            ?? customSchemeURL(payload: clipped.droppingText)
    }

    static func customSchemeURL(payload: SharedPromptPayload) -> URL? {
        var components = URLComponents()
        components.scheme = "speakup"
        components.host = "record"
        components.queryItems = queryItems(for: payload)
        return components.url
    }

    private static func httpsURL(host: String, payload: SharedPromptPayload) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/record"
        components.queryItems = queryItems(for: payload)
        return components.url
    }

    private static func queryItems(for payload: SharedPromptPayload) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let id = payload.promptID, !id.isEmpty {
            items.append(URLQueryItem(name: promptQueryName, value: id))
        }
        if let text = payload.trimmedText {
            items.append(URLQueryItem(name: textQueryName, value: text))
        }
        if let category = payload.category, !category.isEmpty {
            items.append(URLQueryItem(name: categoryQueryName, value: category))
        }
        if let difficulty = payload.difficulty, !difficulty.isEmpty {
            items.append(URLQueryItem(name: difficultyQueryName, value: difficulty))
        }
        if let beat = payload.beatScore, (0...100).contains(beat) {
            items.append(URLQueryItem(name: beatQueryName, value: String(beat)))
        }
        if let source = payload.source, !source.isEmpty {
            items.append(URLQueryItem(name: "source", value: source))
        }
        return items.isEmpty ? nil : items
    }

    private static func clippedPayload(_ payload: SharedPromptPayload) -> SharedPromptPayload {
        var copy = payload
        if let text = payload.trimmedText, text.count > maxPromptTextLength {
            copy.text = String(text.prefix(maxPromptTextLength))
        }
        return copy
    }

    private static func normalizedHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        if host.hasSuffix("/") { host.removeLast() }
        // `www.` is kept: the link has to point at the host serving the AASA
        // file, and iOS does not follow redirects resolving a universal link.
        return host.isEmpty ? nil : host
    }

    // MARK: - Identity

    /// Stable id for a prompt the recipient has never seen. Same text from two
    /// friends collapses to one row instead of flooding My Prompts.
    static func stableID(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "shared-" + hex.prefix(16)
    }

    static func isCatalogID(_ id: String) -> Bool {
        !id.hasPrefix("user-") && !id.hasPrefix("shared-") && !id.isEmpty
    }

    // MARK: - Caption

    /// The message that travels *with* the image. Friends without the app still
    /// see the prompt; friends with the app get a tappable link.
    ///
    /// Kept to a headline, the prompt, and the URL. Everything the old version
    /// spelled out — that this is a score, that the link opens the same prompt —
    /// is already on the card or obvious from the link, and a caption people
    /// scroll past is a caption that shares nothing.
    static func message(
        score: Int?,
        verdict: String?,
        promptText: String?,
        url: URL?
    ) -> String {
        var lines: [String] = []

        if let score {
            let verdictSuffix = verdict.map { ", \($0)" } ?? ""
            lines.append("\(score) on Big Talk\(verdictSuffix).\(url == nil ? "" : " Beat it?")")
        } else {
            lines.append(url == nil ? "Practising on Big Talk." : "Your turn on Big Talk.")
        }

        if let promptText, !promptText.isEmpty {
            lines.append("")
            lines.append("“\(promptText)”")
        }

        if let url {
            if promptText == nil { lines.append("") }
            lines.append(url.absoluteString)
        }

        return lines.joined(separator: "\n")
    }
}

private extension SharedPromptPayload {
    nonisolated var droppingText: SharedPromptPayload {
        var copy = self
        copy.text = nil
        return copy
    }
}
