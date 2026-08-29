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

    /// Call after Today's heavy load. A welcome-back note wins over a
    /// celebration when both apply; care should never be displaced by confetti.
    func evaluateToday(
        context: ModelContext,
        stats: UserStats,
        practicedToday: Bool,
        lastPracticeDate: Date?
    ) {
        // A visible celebration owns the moment until the user accepts or
        // dismisses it. Never silently replace it during a concurrent reload.
        guard pendingOverlay == nil else { return }
        guard let settings = Self.fetchSettings(context: context) else { return }

        let snapshot = Self.buildSnapshot(
            context: context,
            settings: settings,
            stats: stats,
            practicedToday: practicedToday,
            lastPracticeDate: lastPracticeDate
        )

        let budget = settings.coachMomentBudget
        guard let moment = CoachMomentEngine.propose(
            snapshot: snapshot,
            budget: budget
        ) else {
            pendingToday = nil
            pendingOverlay = nil
            return
        }

        switch moment.surface {
        case .today:
            pendingToday = moment
            pendingOverlay = nil
        case .overlay:
            pendingOverlay = moment
            pendingToday = nil
        case .detail:
            // Today's snapshot has no latest-take metrics, so no detail signal
            // can be produced. Keep the guard explicit if that ever changes.
            pendingOverlay = nil
            pendingToday = nil
        }
    }

    // MARK: - After session

    /// Call once the results screen has analysis. Soft landings and first-axis
    /// wins live here; anniversary overlays may also land.
    func evaluateAfterSession(
        context: ModelContext,
        analysis: SpeechAnalysis,
        practicedToday: Bool = true
    ) {
        guard pendingOverlay == nil else { return }
        guard let settings = Self.fetchSettings(context: context) else { return }

        let newlyCleared = CoachMomentEngine.newlyCleared(
            current: analysis.speechScore.subscores,
            previouslyCleared: Set(settings.coachMomentClearedDimensionsRaw)
        )

        let snapshot = CoachMomentSnapshot(
            now: .now,
            // Streak celebrations are evaluated on Today, where the full
            // stats snapshot already exists. Avoid a second history scan here.
            currentStreak: 0,
            practicedToday: practicedToday,
            daysSinceLastPractice: 0,
            firstPracticeDate: Self.firstPracticeDate(context: context),
            latestOverall: analysis.speechScore.overall,
            latestFillerCount: analysis.totalFillerCount,
            latestTotalWords: analysis.totalWords,
            newlyClearedDimensions: newlyCleared,
            userName: settings.userName
        )

        guard let moment = CoachMomentEngine.propose(
            snapshot: snapshot,
            budget: settings.coachMomentBudget
        ) else {
            pendingDetail = nil
            pendingOverlay = nil
            return
        }

        switch moment.surface {
        case .detail:
            pendingDetail = moment
            pendingOverlay = nil
        case .overlay:
            pendingOverlay = moment
            pendingDetail = nil
        case .today:
            pendingDetail = nil
            pendingOverlay = nil
        }
    }

    // MARK: - Consume

    func consume(_ moment: CoachMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }

        let budget = settings.coachMomentBudget.recordingDelivery(
            of: moment,
            now: .now
        )
        settings.apply(budget: budget)
        markAxisClearedIfNeeded(for: moment, settings: settings)

        try? context.save()
        AnalyticsService.shared.log(.milestone(type: "coach_moment_\(moment.signal.rawValue)"))
        clear(moment)
    }

    /// Dismiss still records delivery. A celebration that was seen and waved
    /// away spent its weekly slot; another one must not replace it.
    func dismiss(_ moment: CoachMoment, context: ModelContext) {
        guard let settings = Self.fetchSettings(context: context) else {
            clear(moment)
            return
        }
        let budget = settings.coachMomentBudget.recordingDelivery(
            of: moment,
            now: .now
        )
        settings.apply(budget: budget)
        markAxisClearedIfNeeded(for: moment, settings: settings)
        try? context.save()
        clear(moment)
    }

    private func markAxisClearedIfNeeded(
        for moment: CoachMoment,
        settings: UserSettings
    ) {
        guard moment.signal == .firstAxisClear else { return }
        let raw = moment.id.hasPrefix("axis-")
            ? String(moment.id.dropFirst("axis-".count))
            : (moment.detailSlug ?? "")
        guard CoachDimension(rawValue: raw) != nil,
              !settings.coachMomentClearedDimensionsRaw.contains(raw) else {
            return
        }
        settings.coachMomentClearedDimensionsRaw.append(raw)
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
        lastPracticeDate: Date?
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

        return CoachMomentSnapshot(
            now: .now,
            currentStreak: stats.currentStreak,
            practicedToday: practicedToday,
            daysSinceLastPractice: daysSince,
            firstPracticeDate: firstPracticeDate(context: context),
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

    private static func fetchSettings(context: ModelContext) -> UserSettings? {
        try? context.fetch(FetchDescriptor<UserSettings>()).first
    }
}
