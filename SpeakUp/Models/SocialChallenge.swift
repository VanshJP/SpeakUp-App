import Foundation

struct SocialChallenge: Identifiable {
    let id = UUID()
    let promptId: String
    let promptText: String
    let challengerName: String
    let challengerScore: Int
    let date: Date

    /// Generate a deep link for sharing.
    var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "speakup"
        components.host = "challenge"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: promptId),
            URLQueryItem(name: "score", value: "\(challengerScore)"),
            URLQueryItem(name: "name", value: challengerName),
        ]
        return components.url
    }

    /// Parse an incoming deep link.
    static func from(url: URL) -> SocialChallenge? {
        guard url.scheme == "speakup", url.host == "challenge",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return nil
        }

        let dict = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let promptId = dict["prompt"],
              let scoreStr = dict["score"],
              let score = Int(scoreStr) else {
            return nil
        }

        return SocialChallenge(
            promptId: promptId,
            promptText: "",
            challengerName: dict["name"] ?? "A friend",
            challengerScore: score,
            date: Date()
        )
    }
}
