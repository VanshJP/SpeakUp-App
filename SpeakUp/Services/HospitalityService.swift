import Foundation
import SwiftData

/// Frontline dream weaver — detects ghosts, spends the weekly legend budget,
/// and holds pending moments per surface (Today / detail / overlay).
///
/// Pure judgement lives in `HospitalityEngine`. This type owns SwiftData I/O
/// and presentation state, matching `AchievementService`.
@Observable
@MainActor
final class HospitalityService {
    static let shared = HospitalityService()

    private(set) var pendingToday: HospitalityMoment?
    private(set) var pendingDetail: HospitalityMoment?
    private(set) var pendingOverlay: HospitalityMoment?

    /// Convenience for overlays that only care about the full-screen legend.
    var pendingMoment: HospitalityMoment? { pendingOverlay }

    private init() {}

    // MARK: - Today

    /// Call after Today's heavy load. Prefers return-from-lapse and anniversary
    /// / life-context legends that belong on the home surface.
    func evaluateToday(
        context: ModelContext,
        stats: UserStats,
        practicedToday: Bool,
        lastPracticeDate: Date?
    ) {
        guard let settings = Self.fetchSettings(context: context) else { return }

        let snapshot = Self.buildSnapshot(
            context: context,
            settings: settings,
            stats: stats,
            practicedToday: practicedToday,
            lastPracticeDate: lastPracticeDate,
            latest: nil
        )

        let budget = settings.hospitalityBudget
        // Prefer overlay legends when both could fire — the full-screen moment
        // is rarer and should not lose to an inline card on the same visit.
        if let overlay = HospitalityEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .overlay
        ) {
            pendingOverlay = overlay
            pendingToday = nil
            return
        }

        guard let moment = HospitalityEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .today
        ) else {
            pendingToday = nil
            return
        }
        pendingToday = moment
    }

    // MARK: - After session

    /// Call once the results screen has analysis. Soft landings and first-axis
    /// wins live here; overlay legends (anniversary) may also land.
    func evaluateAfterSession(
        context: ModelContext,
        analysis: SpeechAnalysis,
        transcript: String?,
        practicedToday: Bool = true,
        currentStreak: Int? = nil
    ) {
        guard let settings = Self.fetchSettings(context: context) else { return }

        let newlyCleared = HospitalityEngine.newlyCleared(
            current: analysis.speechScore.subscores,
            previouslyCleared: Set(settings.hospitalityClearedDimensionsRaw)
        )

        let snapshot = HospitalitySnapshot(
            now: .now,
            currentStreak: currentStreak ?? 0,
            practicedToday: practicedToday,
            daysSinceLastPractice: 0,
            firstPracticeDate: Self.firstPracticeDate(context: context),
            latestOverall: analysis.speechScore.overall,
            latestFillerCount: analysis.totalFillerCount,
            latestTotalWords: analysis.totalWords,
            latestTranscript: transcript,
            newlyClearedDimensions: newlyCleared,
            userName: settings.userName,
            lifeContext: transcript.flatMap { HospitalityLifeContext.detect(in: $0) }
        )

        let budget = settings.hospitalityBudget
        if let overlay = HospitalityEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .overlay
        ) {
            pendingOverlay = overlay
            return
        }

        guard let moment = HospitalityEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .detail
        ) else {
            pendingDetail = nil
            return
        }
        pendingDetail = moment
    }

    // MARK: - Consume

    /// Persist delivery (budget + cleared axes + delivered ids) and clear the
    /// matching pending slot.
    func consume(_ moment: HospitalityMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }

        var budget = settings.hospitalityBudget.rolling(now: .now)
        if moment.isLegend {
            budget.legendsUsed += 1
        }
        budget.deliveredIDs = HospitalityEngine.cappedDeliveredIDs(
            budget.deliveredIDs,
            adding: moment.id
        )
        settings.apply(budget: budget)

        if moment.signal == .firstAxisClear {
            let raw = moment.id.hasPrefix("axis-")
                ? String(moment.id.dropFirst("axis-".count))
                : (moment.detailSlug ?? "")
            if CoachDimension(rawValue: raw) != nil,
               !settings.hospitalityClearedDimensionsRaw.contains(raw) {
                settings.hospitalityClearedDimensionsRaw.append(raw)
            }
        }

        try? context.save()
        AnalyticsService.shared.log(.milestone(type: "hospitality_\(moment.signal.rawValue)"))
        clear(moment)
    }

    /// Dismiss without spending budget — still mark delivered so the same
    /// legend does not re-fire all day.
    func dismiss(_ moment: HospitalityMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }
        var budget = settings.hospitalityBudget.rolling(now: .now)
        budget.deliveredIDs = HospitalityEngine.cappedDeliveredIDs(
            budget.deliveredIDs,
            adding: moment.id
        )
        settings.apply(budget: budget)
        try? context.save()
        clear(moment)
    }

    private func clear(_ moment: HospitalityMoment) {
        switch moment.surface {
        case .today:
            if pendingToday?.id == moment.id { pendingToday = nil }
        case .detail:
            if pendingDetail?.id == moment.id { pendingDetail = nil }
        case .overlay:
            if pendingOverlay?.id == moment.id { pendingOverlay = nil }
        }
    }

    // MARK: - Snapshot builders

    private static func buildSnapshot(
        context: ModelContext,
        settings: UserSettings,
        stats: UserStats,
        practicedToday: Bool,
        lastPracticeDate: Date?,
        latest: SpeechAnalysis?
    ) -> HospitalitySnapshot {
        let calendar = Calendar.current
        let daysSince: Int? = {
            guard let last = lastPracticeDate else { return nil }
            return calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: .now)
            ).day
        }()

        let recent = latestRecording(context: context)
        let transcript = recent?.transcriptionText
        let life = transcript.flatMap { HospitalityLifeContext.detect(in: $0) }

        return HospitalitySnapshot(
            now: .now,
            currentStreak: stats.currentStreak,
            practicedToday: practicedToday,
            daysSinceLastPractice: daysSince,
            firstPracticeDate: firstPracticeDate(context: context),
            latestOverall: latest?.speechScore.overall ?? recent?.overallScore,
            latestFillerCount: latest?.totalFillerCount,
            latestTotalWords: latest?.totalWords,
            latestTranscript: transcript,
            newlyClearedDimensions: [],
            userName: settings.userName,
            lifeContext: life
        )
    }

    private static func firstPracticeDate(context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.date
    }

    private static func latestRecording(context: ModelContext) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchSettings(context: ModelContext) -> UserSettings? {
        try? context.fetch(FetchDescriptor<UserSettings>()).first
    }
}
