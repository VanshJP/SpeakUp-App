import Testing
import Foundation
@testable import SpeakUp

// Two rules that are easy to get quietly wrong and expensive when you do: what
// a share card is allowed to say, and when the app may spend one of the year's
// three review prompts.

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

@MainActor
struct ReviewEligibilityTests {
    private func shouldAsk(
        askedThisLaunch: Bool = false,
        hasSeenFirstResult: Bool = true,
        currentVersion: String = "1.0(1)",
        lastAskedVersion: String? = nil,
        lastAskedDate: Date? = nil,
        now: Date = t0
    ) -> Bool {
        ReviewEligibility.shouldAsk(
            askedThisLaunch: askedThisLaunch,
            hasSeenFirstResult: hasSeenFirstResult,
            currentVersion: currentVersion,
            lastAskedVersion: lastAskedVersion,
            lastAskedDate: lastAskedDate,
            now: now
        )
    }

    @Test func asksAfterASuccessOnAFreshInstall() {
        #expect(shouldAsk())
    }

    @Test func neverAsksBeforeTheFirstResult() {
        #expect(!shouldAsk(hasSeenFirstResult: false))
    }

    @Test func onlyOncePerLaunch() {
        #expect(!shouldAsk(askedThisLaunch: true))
    }

    @Test func onlyOncePerVersion() {
        #expect(!shouldAsk(currentVersion: "1.0(1)", lastAskedVersion: "1.0(1)"))
    }

    @Test func aNewVersionAloneDoesNotBeatTheInterval() {
        // Shipping three builds in a week must not mean three prompts.
        #expect(!shouldAsk(
            currentVersion: "1.1(4)",
            lastAskedVersion: "1.0(1)",
            lastAskedDate: t0.addingTimeInterval(-10 * day)
        ))
    }

    @Test func asksAgainOnANewVersionAfterTheInterval() {
        #expect(shouldAsk(
            currentVersion: "1.1(4)",
            lastAskedVersion: "1.0(1)",
            lastAskedDate: t0.addingTimeInterval(-61 * day)
        ))
    }
}

@MainActor
struct ProgressCardDataTests {
    private func card(
        firstScore: Int = 52,
        latestScore: Int = 71,
        sessionCount: Int = 9,
        daysApart: Int = 14,
        rows: [ProgressCardData.Row] = []
    ) -> ProgressCardData {
        ProgressCardData(
            firstDate: t0,
            latestDate: t0.addingTimeInterval(Double(daysApart) * day),
            firstScore: firstScore,
            latestScore: latestScore,
            sessionCount: sessionCount,
            rows: rows
        )
    }

    @Test func improvementLeadsWithThePointGain() {
        #expect(card().delta == 19)
        #expect(card().headline == "+19 points")
    }

    @Test func aFlatOrNegativeRunIsNotDressedUpAsAWin() {
        #expect(card(firstScore: 70, latestScore: 70).headline == "Holding steady")

        let regression = card(firstScore: 70, latestScore: 58)
        #expect(!regression.headline.contains("+"))
        #expect(regression.headline == "9 sessions in")
    }

    @Test func subheadlineCountsSessionsAndDays() {
        #expect(card(sessionCount: 1, daysApart: 1).subheadline == "1 session over 1 day")
        #expect(card(sessionCount: 9, daysApart: 14).subheadline == "9 sessions over 14 days")
        #expect(card(sessionCount: 4, daysApart: 0).subheadline == "4 sessions")
    }

    @Test func fillerRowsCountDownwardsAsImprovement() {
        let fillers = ProgressCardData.Row(label: "Fillers", before: 14, after: 5, lowerIsBetter: true)
        #expect(fillers.improved)
        #expect(fillers.changed)

        let clarity = ProgressCardData.Row(label: "Clarity", before: 61, after: 74, lowerIsBetter: false)
        #expect(clarity.improved)

        let flat = ProgressCardData.Row(label: "Pace", before: 66, after: 66, lowerIsBetter: false)
        #expect(!flat.changed)
        #expect(!flat.improved)
    }
}
