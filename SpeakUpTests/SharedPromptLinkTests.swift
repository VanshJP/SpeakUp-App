import Testing
import Foundation
import SwiftData
@testable import SpeakUp

@MainActor
struct SharedPromptLinkTests {
    private let sampleText = "Describe a challenging project you completed and what you learned from it."

    private func payload(
        id: String? = "prof-1",
        text: String? = nil,
        beat: Int? = 78
    ) -> SharedPromptPayload {
        SharedPromptPayload(
            promptID: id,
            text: text ?? sampleText,
            category: "Professional Development",
            difficulty: "medium",
            beatScore: beat,
            source: SharedPromptLink.shareSource
        )
    }

    @Test func httpsShareURLRoundTripsQuery() {
        let url = SharedPromptLink.shareURL(for: payload(), domain: "bigtalk.app")
        #expect(url?.scheme == "https")
        #expect(url?.host == "bigtalk.app")
        #expect(url?.path == "/record")

        let parsed = url.flatMap { SharedPromptLink.payload(from: $0) }
        #expect(parsed?.promptID == "prof-1")
        #expect(parsed?.text == sampleText)
        #expect(parsed?.category == "Professional Development")
        #expect(parsed?.difficulty == "medium")
        #expect(parsed?.beatScore == 78)
        #expect(parsed?.isShareChallenge == true)
    }

    @Test func customSchemeIsUsedWhenNoDomainIsConfigured() {
        let url = SharedPromptLink.shareURL(for: payload(), domain: nil)
        #expect(url?.scheme == "speakup")
        #expect(url?.host == "record")
        let parsed = url.flatMap { SharedPromptLink.payload(from: $0) }
        #expect(parsed?.promptID == "prof-1")
        #expect(parsed?.isShareChallenge == true)
    }

    @Test func widgetStyleLinkIsNotAChallenge() {
        let url = URL(string: "speakup://record?prompt=prof-1")!
        let parsed = SharedPromptLink.payload(from: url)
        #expect(parsed?.promptID == "prof-1")
        #expect(parsed?.isShareChallenge == false)
        #expect(parsed?.text == nil)
    }

    @Test func shortTextQueryNameIsAccepted() {
        let url = URL(string: "speakup://record?prompt=comm-1&t=Hello%20world&source=share")!
        let parsed = SharedPromptLink.payload(from: url)
        #expect(parsed?.text == "Hello world")
        #expect(parsed?.promptID == "comm-1")
    }

    @Test func outOfRangeBeatScoreIsDropped() {
        let url = SharedPromptLink.shareURL(
            for: payload(beat: 140),
            domain: "bigtalk.app"
        )!
        let parsed = SharedPromptLink.payload(from: url)
        #expect(parsed?.beatScore == nil)
    }

    @Test func stableIDIsDeterministicAndIgnoresCase() {
        let a = SharedPromptLink.stableID(for: "  Hello World  ")
        let b = SharedPromptLink.stableID(for: "hello world")
        #expect(a == b)
        #expect(a.hasPrefix("shared-"))
        #expect(a.count == "shared-".count + 16)
    }

    @Test func catalogIDsAreRecognised() {
        #expect(SharedPromptLink.isCatalogID("prof-1"))
        #expect(!SharedPromptLink.isCatalogID("user-ABCD"))
        #expect(!SharedPromptLink.isCatalogID("shared-deadbeef"))
        #expect(!SharedPromptLink.isCatalogID(""))
    }

    @Test func messageCarriesPromptAndTappableURL() {
        let url = URL(string: "https://bigtalk.app/record?prompt=prof-1&source=share")!
        let message = SharedPromptLink.message(
            score: 78,
            verdict: "Solid",
            promptText: sampleText,
            url: url
        )
        #expect(message.contains("78"))
        #expect(message.contains("Solid"))
        #expect(message.contains(sampleText))
        #expect(message.contains(url.absoluteString))
        #expect(message.contains("Tap to try the same prompt"))
    }

    @Test func scoresOnlyMessageDoesNotLeakAPrompt() {
        let message = SharedPromptLink.message(
            score: 91,
            verdict: "Strong",
            promptText: nil,
            url: nil
        )
        #expect(message.contains("91"))
        #expect(!message.contains("Describe"))
        #expect(!message.contains("http"))
        #expect(!message.contains("speakup://"))
    }

    @Test func campaignParametersOnAShareLinkAreIgnoredNotDropped() {
        // Routing still owns source/campaign for attribution; the payload
        // only needs to recognise that this is a share.
        let url = URL(string: "https://bigtalk.app/record?prompt=prof-1&source=share&campaign=launch")!
        let parsed = SharedPromptLink.payload(from: url)
        #expect(parsed?.isShareChallenge == true)
        #expect(parsed?.promptID == "prof-1")
    }

    @Test func sourceOnlyLinkStillOpensASession() {
        let url = SharedPromptLink.shareURL(
            for: SharedPromptPayload(source: SharedPromptLink.shareSource),
            domain: "bigtalk.app"
        )
        #expect(url?.absoluteString.contains("source=share") == true)
        #expect(SharedPromptLink.payload(from: url!)?.text == nil)
        #expect(SharedPromptLink.payload(from: url!)?.isShareChallenge == true)
    }
}

@MainActor
struct SharedPromptResolverTests {
    private func context() throws -> ModelContext {
        let schema = Schema([Prompt.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    @Test func catalogIDWinsEvenWhenTextDiffers() throws {
        let context = try context()
        context.insert(Prompt(
            id: "prof-1",
            text: "Official wording.",
            category: "Professional Development",
            difficulty: .medium
        ))
        try context.save()

        let resolved = SharedPromptResolver.resolve(
            SharedPromptPayload(
                promptID: "prof-1",
                text: "A friend rewrote this.",
                source: SharedPromptLink.shareSource
            ),
            in: context
        )
        #expect(resolved?.id == "prof-1")
        #expect(resolved?.text == "Official wording.")
    }

    @Test func missingCustomPromptIsInsertedOnceUnderAStableID() throws {
        let context = try context()
        let text = "Pitch me your weirdest weekend plan."
        let payload = SharedPromptPayload(
            promptID: "user-not-on-this-phone",
            text: text,
            category: "Conversation Starters",
            difficulty: "easy",
            source: SharedPromptLink.shareSource
        )

        let first = SharedPromptResolver.resolve(payload, in: context)
        let second = SharedPromptResolver.resolve(payload, in: context)
        #expect(first?.id == SharedPromptLink.stableID(for: text))
        #expect(first?.id == second?.id)
        #expect(first?.isUserCreated == true)
        #expect(first?.text == text)
        #expect(first?.difficulty == .easy)

        let count = try context.fetchCount(FetchDescriptor<Prompt>())
        #expect(count == 1)
    }

    @Test func missingCatalogRowIsInsertedAsCatalogNotMyPrompts() throws {
        let context = try context()
        let resolved = SharedPromptResolver.resolve(
            SharedPromptPayload(
                promptID: "prof-99",
                text: "A prompt this install has not seeded yet.",
                category: "Professional Development",
                difficulty: "hard",
                source: SharedPromptLink.shareSource
            ),
            in: context
        )
        #expect(resolved?.id == "prof-99")
        #expect(resolved?.isUserCreated == false)
        #expect(resolved?.difficulty == .hard)
    }
}

@MainActor
struct SharedPromptAnalyticsTests {
    @Test func openedEventDoesNotCarryPromptOrScore() {
        let event = AnalyticsEvent.sharedPromptOpened()
        #expect(event.name == "shared_prompt_opened")
        #expect(event.funnel == .acquisition)
        #expect(event.dimensions == ["source": "share"])
    }
}
