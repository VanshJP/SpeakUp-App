import Foundation
import SwiftData

/// Owns rare coach notes: detect signals, spend the weekly celebration budget,
/// hold pending notes per surface (Today / detail / overlay).
///
/// Pure judgement lives in `CoachMomentEngine`. This type owns SwiftData I/O
/// and presentation state, matching `AchievementService`.
@Observable
@MainActor
final class CoachMomentService {
    static let shared = CoachMomentService()

    private(set) var pendingToday: CoachMoment?
    private(set) var pendingDetail: CoachMoment?
    private(set) var pendingOverlay: CoachMoment?

    private init() {}

    // MARK: - Today

    /// Call after Today's heavy load. Welcome-back and anniversary / streak
    /// overlays that belong on the home surface.
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

        let budget = settings.coachMomentBudget
        if let overlay = CoachMomentEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .overlay
        ) {
            pendingOverlay = overlay
            pendingToday = nil
            return
        }

        guard let moment = CoachMomentEngine.propose(
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
    /// wins live here; anniversary overlays may also land.
    func evaluateAfterSession(
        context: ModelContext,
        analysis: SpeechAnalysis,
        practicedToday: Bool = true,
        currentStreak: Int? = nil
    ) {
        guard let settings = Self.fetchSettings(context: context) else { return }

        let newlyCleared = CoachMomentEngine.newlyCleared(
            current: analysis.speechScore.subscores,
            previouslyCleared: Set(settings.coachMomentClearedDimensionsRaw)
        )

        let snapshot = CoachMomentSnapshot(
            now: .now,
            currentStreak: currentStreak ?? 0,
            practicedToday: practicedToday,
            daysSinceLastPractice: 0,
            firstPracticeDate: Self.firstPracticeDate(context: context),
            latestOverall: analysis.speechScore.overall,
            latestFillerCount: analysis.totalFillerCount,
            latestTotalWords: analysis.totalWords,
            newlyClearedDimensions: newlyCleared,
            userName: settings.userName
        )

        let budget = settings.coachMomentBudget
        if let overlay = CoachMomentEngine.propose(
            snapshot: snapshot,
            budget: budget,
            surface: .overlay
        ) {
            pendingOverlay = overlay
            return
        }

        guard let moment = CoachMomentEngine.propose(
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

    func consume(_ moment: CoachMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }

        var budget = settings.coachMomentBudget.rolling(now: .now)
        if moment.isCelebration {
            budget.celebrationsUsed += 1
        }
        budget.deliveredIDs = CoachMomentEngine.cappedDeliveredIDs(
            budget.deliveredIDs,
            adding: moment.id
        )
        settings.apply(budget: budget)

        if moment.signal == .firstAxisClear {
            let raw = moment.id.hasPrefix("axis-")
                ? String(moment.id.dropFirst("axis-".count))
                : (moment.detailSlug ?? "")
            if CoachDimension(rawValue: raw) != nil,
               !settings.coachMomentClearedDimensionsRaw.contains(raw) {
                settings.coachMomentClearedDimensionsRaw.append(raw)
            }
        }

        try? context.save()
        AnalyticsService.shared.log(.milestone(type: "coach_moment_\(moment.signal.rawValue)"))
        clear(moment)
    }

    /// Dismiss without spending celebration budget — still mark delivered so
    /// the same note does not reappear all day.
    func dismiss(_ moment: CoachMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }
        var budget = settings.coachMomentBudget.rolling(now: .now)
        budget.deliveredIDs = CoachMomentEngine.cappedDeliveredIDs(
            budget.deliveredIDs,
            adding: moment.id
        )
        settings.apply(budget: budget)
        try? context.save()
        clear(moment)
    }

    private func clear(_ moment: CoachMoment) {
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
    ) -> CoachMomentSnapshot {
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

        return CoachMomentSnapshot(
            now: .now,
            currentStreak: stats.currentStreak,
            practicedToday: practicedToday,
            daysSinceLastPractice: daysSince,
            firstPracticeDate: firstPracticeDate(context: context),
            latestOverall: latest?.speechScore.overall ?? recent?.overallScore,
            latestFillerCount: latest?.totalFillerCount,
            latestTotalWords: latest?.totalWords,
            newlyClearedDimensions: [],
            userName: settings.userName
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
