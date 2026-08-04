import Testing
import Foundation
@testable import SpeakUp

// Campaign links are the one input the app cannot fix after the fact: once a
// newsletter has gone out with a URL in it, the app has to route that exact
// string forever. These cover the shapes a link can arrive in and the one
// thing that must never be dropped on the way through — the campaign query.

private let domain = "bigtalk.app"

private func route(_ string: String) -> URL? {
    guard let url = URL(string: string) else {
        Issue.record("not a URL: \(string)")
        return nil
    }
    return UniversalLink.route(from: url, domain: domain)
}

struct UniversalLinkTests {
    @Test func firstPathSegmentBecomesTheRoute() {
        #expect(route("https://bigtalk.app/record")?.absoluteString == "speakup://record")
        #expect(route("https://bigtalk.app/story")?.absoluteString == "speakup://story")
    }

    @Test func deeperPathsAreKept() {
        #expect(route("https://bigtalk.app/story/new")?.absoluteString == "speakup://story/new")
    }

    @Test func aBareLinkLandsOnTheAttributionRoute() {
        #expect(route("https://bigtalk.app")?.absoluteString == "speakup://open")
        #expect(route("https://bigtalk.app/")?.absoluteString == "speakup://open")
    }

    /// Losing these turns a paid install into an organic one in the funnel.
    @Test func campaignParametersSurviveTranslation() {
        let translated = route("https://bigtalk.app/record?prompt=42&source=newsletter&campaign=launch")
        let components = URLComponents(string: translated?.absoluteString ?? "")
        let items = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) }
        )
        #expect(components?.host == "record")
        #expect(items["prompt"] == "42")
        #expect(items["source"] == "newsletter")
        #expect(items["campaign"] == "launch")
    }

    @Test func hostMatchingIgnoresCaseAndWww() {
        #expect(route("https://WWW.BigTalk.app/record")?.absoluteString == "speakup://record")
        #expect(UniversalLink.route(
            from: URL(string: "https://bigtalk.app/record")!,
            domain: "https://www.BigTalk.app/"
        )?.absoluteString == "speakup://record")
    }

    /// A link on someone else's domain must not be treated as ours, or any site
    /// that guessed the path could drive the app.
    @Test func foreignDomainsAreRefused() {
        #expect(route("https://bigtalk.app.evil.com/record") == nil)
        #expect(route("https://notbigtalk.app/record") == nil)
    }

    @Test func nonHttpsSchemesAreRefused() {
        #expect(route("http://bigtalk.app/record") == nil)
        // Custom-scheme links reach the router directly and must not be
        // translated a second time.
        #expect(route("speakup://record") == nil)
    }

    @Test func anUnconfiguredDomainRoutesNothing() {
        let url = URL(string: "https://bigtalk.app/record")!
        #expect(UniversalLink.route(from: url, domain: "") == nil)
        #expect(UniversalLink.route(from: url, domain: "   ") == nil)
    }
}
