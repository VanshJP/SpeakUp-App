import Foundation
import SwiftUI
import SwiftData
import WidgetKit
import os

@Observable
class TodayViewModel {
    private let logger = Logger(subsystem: "com.vansh.SpeakUpMore", category: "Today")

    var todaysPrompt: Prompt?
    var userStats: UserStats = UserStats()
    var activeGoals: [UserGoal] = []
    var selectedDuration: RecordingDuration = .sixty
    var isLoading = true
    var weeklyProgress: WeeklyProgressData?
    var vocabChallenge: DailyVocabChallenge?
    var hideAnsweredPrompts: Bool = false
    var weeklyGoalSessions: Int = 5
    var storyPracticeEnabled: Bool = false
    var todaysStory: Story?
    /// What the speaker is working on. Same engine as the session coaching
    /// screen — Today used to run its own weaker version (lowest rolling
    /// subscore over ten sessions, zero-score captures included) and the two
    /// disagreed about which area to send the user after.
    var coachPlan: CoachPlan?
    private var modelContext: ModelContext?
    private var lastPracticeDate: Date?
    /// Drives the once-a-day arrival moment in the Today header.
    var practicedToday: Bool {
        guard let lastPracticeDate else { return false }
        return Calendar.current.isDateInToday(lastPracticeDate)
    }
    private var answeredPromptIDs: Set<String> = []
    /// Category weighting from the user's onboarding goals, gated by their
    /// enabled categories. Built once per settings load rather than per prompt,
    /// and the only place the category gate is applied now.
    private var promptMix: PromptMix = .uniform
    /// `promptMix` blended with lexicon weakness boosts — the mix prompt
    /// selection actually uses. Settings goals stay the base; adaptation only
    /// tilts categories the user demonstrably struggles in.
    private var effectivePromptMix: PromptMix = .uniform
    private var hasRerolledPrompt = false
    private var vocabChallengePreferences: VocabChallengePreferences = .disabled
    private var scoreWeights: ScoreWeights = .defaults
    private var vocabUsedCounts: [String: Int] = [:]
    private var todayTranscripts: [String] = []
    private var todayVocabUsages: [VocabWordUsage] = []
    /// Cross-session interview readiness, written to the widget payload.
    private var readinessScore = 0

    nonisolated init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await loadData()
        }
    }
    
    @MainActor
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard let context = modelContext else { return }
        let container = context.container

        // Load user settings first (needed for prompt filtering)
        await loadUserSettings(context: context)

        // Heavy fetch + stats computation off main thread
        let heavy = await Self.fetchAndCompute(
            container: container,
            hideAnsweredPrompts: hideAnsweredPrompts,
            weeklyGoalSessions: weeklyGoalSessions,
            scoreWeights: scoreWeights,
            promptMix: promptMix
        )

        self.userStats = heavy.userStats
        self.weeklyProgress = heavy.weeklyProgress
        self.coachPlan = heavy.coachPlan
        self.answeredPromptIDs = heavy.answeredPromptIDs
        self.lastPracticeDate = heavy.lastPracticeDate
        self.vocabUsedCounts = heavy.vocabUsedCounts
        self.todayTranscripts = heavy.todayTranscripts
        self.todayVocabUsages = heavy.todayVocabUsages
        self.readinessScore = heavy.readinessScore
        self.effectivePromptMix = heavy.promptMix

        refreshVocabChallenge()

        // Load today's prompt (uses answeredPromptIDs populated above)
        await loadTodaysPrompt(context: context)

        // Load today's story if story practice is enabled
        if storyPracticeEnabled {
            await loadTodaysStory(context: context)
        }

        // Load active goals
        await loadActiveGoals(context: context)

        // Schedule streak-at-risk notification if applicable
        await scheduleStreakNotificationIfNeeded()

        // Coach notes — welcome-back / streak overlay. Detail-surface notes are
        // owned by RecordingDetailView after a take.
        CoachMomentService.shared.evaluateToday(
            context: context,
            stats: userStats,
            practicedToday: practicedToday,
            lastPracticeDate: lastPracticeDate
        )

        // Update widget data
        updateWidgetData()
    }

    // MARK: - Background fetch

    private static func fetchAndCompute(
        container: ModelContainer,
        hideAnsweredPrompts: Bool,
        weeklyGoalSessions: Int,
        scoreWeights: ScoreWeights,
        promptMix: PromptMix
    ) async -> TodayHeavyResult {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let recordings = (try? context.fetch(descriptor)) ?? []

            let answered: Set<String> = hideAnsweredPrompts
                ? Set(recordings.compactMap { $0.prompt?.id })
                : []

            // Stats
            let totalRecordings = recordings.count
            let totalPracticeTime = recordings.reduce(0) { $0 + $1.actualDuration }
            let recordingDates = recordings.map(\.date)
            let currentStreak = Date.calculateStreak(from: recordingDates)

            let scoresWithAnalysis = recordings.compactMap { $0.analysis?.speechScore.overall }
            let averageScore: Double = scoresWithAnalysis.isEmpty
                ? 0
                : Double(scoresWithAnalysis.reduce(0, +)) / Double(scoresWithAnalysis.count)
            let bestScore = scoresWithAnalysis.max() ?? 0

            let sevenDaysAgo = Date().adding(days: -7)
            let recentRecordings = recordings.filter { $0.date >= sevenDaysAgo }
            let scoreHistory = recentRecordings.compactMap { rec -> ScoreHistoryEntry? in
                guard let score = rec.analysis?.speechScore.overall else { return nil }
                return ScoreHistoryEntry(date: rec.date, score: score)
            }

            // Improvement rate (inline)
            let improvementRate: Double = {
                guard recentRecordings.count >= 2 else { return 0 }
                let sorted = recentRecordings.sorted { $0.date < $1.date }
                let mid = sorted.count / 2
                let firstHalf = Array(sorted.prefix(mid))
                let secondHalf = Array(sorted.suffix(from: mid))
                let firstSum = firstHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
                let secondSum = secondHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
                guard firstSum > 0 else { return 0 }
                let firstAvg = Double(firstSum) / Double(max(firstHalf.count, 1))
                let secondAvg = Double(secondSum) / Double(max(secondHalf.count, 1))
                return ((secondAvg - firstAvg) / firstAvg) * 100
            }()

            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let weeklySessionCount = recordings.filter { $0.date >= weekStart }.count

            let userStats = UserStats(
                totalRecordings: totalRecordings,
                totalPracticeTime: totalPracticeTime,
                currentStreak: currentStreak,
                averageScore: averageScore,
                bestScore: bestScore,
                scoreHistory: scoreHistory,
                improvementRate: improvementRate,
                weeklySessionCount: weeklySessionCount,
                weeklyGoalSessions: weeklyGoalSessions
            )

            let weeklyProgress = WeeklyProgressService.calculate(recordings: recordings)

            let todayStart = calendar.startOfDay(for: Date())
            let todayRecordings = recordings.filter { $0.date >= todayStart }

            var vocabUsedCounts: [String: Int] = [:]
            var todayTranscripts: [String] = []
            var todayVocabUsages: [VocabWordUsage] = []
            for recording in recordings {
                if let usage = recording.analysis?.vocabWordsUsed {
                    for item in usage where item.count > 0 {
                        let key = item.word.lowercased()
                        vocabUsedCounts[key, default: 0] += item.count
                    }
                }
            }
            for recording in todayRecordings {
                if let text = recording.transcriptionText, !text.isEmpty {
                    todayTranscripts.append(text)
                }
                if let usage = recording.analysis?.vocabWordsUsed {
                    todayVocabUsages.append(contentsOf: usage)
                }
            }

            // The focus, from the same window and the same weighting the
            // session coaching screen uses. The crutch hint comes from a
            // bounded recent-window lexicon pass so the filler focus names
            // the user's actual #1 habit.
            var lexiconProfile: LexiconProfile?
            var crutchHint: CrutchHint?
            var recentSessions: [LexiconSessionInput] = []
            recentSessions.reserveCapacity(20)
            for recording in recordings.prefix(20) {
                guard let text = recording.transcriptionText, !text.isEmpty else { continue }
                var fillerCounts: [String: Int] = [:]
                if let fillerWords = recording.analysis?.fillerWords {
                    for filler in fillerWords where filler.count > 0 {
                        fillerCounts[filler.word.lowercased(), default: 0] += filler.count
                    }
                }
                recentSessions.append(LexiconSessionInput(
                    date: recording.date,
                    transcript: text,
                    fillerCounts: fillerCounts,
                    overallScore: recording.analysis?.speechScore.overall,
                    category: recording.storyId != nil ? "Story" : recording.prompt?.category
                ))
                if recentSessions.count >= 15 { break }
            }
            lexiconProfile = LexiconInsightsEngine.profile(from: recentSessions)
            if let top = lexiconProfile?.crutchWords.first(where: { $0.category == .filler || $0.category == .hedge }),
               top.count >= CrutchHint.minimumCount {
                crutchHint = CrutchHint(word: top.word, count: top.count)
            }

            // Practice types the user demonstrably struggles in get a
            // proportional weight bump, so Today steers back toward the
            // weakest material without overriding goals or the settings gate.
            let weakRatesByCategory: [String: (sessions: Int, weakRate: Double)] = Dictionary(
                uniqueKeysWithValues: (lexiconProfile?.categoryBreakdown ?? []).map {
                    ($0.category, (sessions: $0.sessions, weakRate: $0.weakRate))
                }
            )
            let adaptedMix = promptMix.adapted(weakRatesByCategory: weakRatesByCategory)

            let coachPlan = CoachPlanService.plan(
                window: recordings.prefix(PersonalAverage.window).compactMap(\.analysis),
                weights: scoreWeights,
                crutchHint: crutchHint
            )

            return TodayHeavyResult(
                userStats: userStats,
                weeklyProgress: weeklyProgress,
                answeredPromptIDs: answered,
                coachPlan: coachPlan,
                vocabUsedCounts: vocabUsedCounts,
                todayTranscripts: todayTranscripts,
                todayVocabUsages: todayVocabUsages,
                readinessScore: lexiconProfile?.interviewReadiness?.score ?? 0,
                promptMix: adaptedMix,
                // Recordings are date-descending; first = latest practice of
                // any kind, analyzed or not (feeds the streak widget).
                lastPracticeDate: recordings.first?.date
            )
        }.value
    }

    private func updateWidgetData() {
        let lastScore = userStats.scoreHistory.first?.score
        let recentScores = userStats.scoreHistory.map(\.score)
        let avgScore = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / recentScores.count
        let practiceMinutes = Int(weeklyProgress?.totalMinutes ?? 0)

        // Fingerprint-gate: loadData runs on every Today appearance and
        // pull-to-refresh, so skip both the writes and the reload when nothing
        // the widgets display changed.
        var payload: [String] = [
            String(userStats.currentStreak),
            todaysPrompt?.text ?? "",
            todaysPrompt?.category ?? "",
            todaysPrompt?.id ?? "",
        ]
        payload.append(lastScore.map(String.init) ?? "")
        payload.append(String(userStats.weeklySessionCount))
        payload.append(String(userStats.weeklyGoalSessions))
        payload.append(String(avgScore))
        payload.append(String(practiceMinutes))
        payload.append(String(userStats.improvementRate.rounded()))
        payload.append(String(readinessScore))
        payload.append(lastPracticeDate.map { String($0.timeIntervalSince1970) } ?? "")
        guard WidgetDataProvider.todayPayloadChanged(payload) else { return }

        WidgetDataProvider.updateStreak(userStats.currentStreak)
        if let prompt = todaysPrompt {
            WidgetDataProvider.updateTodaysPrompt(text: prompt.text, category: prompt.category, id: prompt.id)
        }
        if let lastScore {
            WidgetDataProvider.updateLastScore(lastScore)
        }

        // Weekly progress
        WidgetDataProvider.updateWeeklyProgress(
            sessionCount: userStats.weeklySessionCount,
            goalSessions: userStats.weeklyGoalSessions,
            averageScore: avgScore,
            practiceMinutes: practiceMinutes,
            improvementRate: Int(userStats.improvementRate.rounded())
        )

        // Unconditional writes: the fingerprint above already recorded the new
        // payload, so skipping a regressed value here would strand stale widget
        // data marked current forever. The gate is the only skip mechanism.
        WidgetDataProvider.updateInterviewReadiness(readinessScore)


        // Track last practice date for streak-at-risk widget. Any recording
        // counts — a session whose transcription failed is still practice.
        if let lastPracticeDate {
            WidgetDataProvider.updateLastPracticeDate(lastPracticeDate)
        } else {
            WidgetDataProvider.clearLastPracticeDate()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleStreakNotificationIfNeeded() async {
        let streak = userStats.currentStreak
        guard streak >= 1 else { return }

        // Check if user has already recorded today
        guard let context = modelContext else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= today }
        )

        let todayCount = (try? context.fetchCount(descriptor)) ?? 0
        let notificationService = NotificationService()
        await notificationService.checkPermission()

        if todayCount == 0 {
            await notificationService.scheduleStreakAtRiskNotification(currentStreak: streak)
        } else {
            notificationService.cancelStreakAtRiskNotification()
        }
    }
    
    @MainActor
    private func loadTodaysPrompt(context: ModelContext) async {
        // If the user has rerolled the prompt this session, keep it
        if hasRerolledPrompt && todaysPrompt != nil { return }

        // Get today's prompt based on date seed, weighted by self-reported
        // speaker level for difficulty and by the user's practice goals for
        // category, so beginners see easier rotations and someone practising
        // for interviews mostly meets interview-shaped prompts.
        let level = currentSpeakerLevel(context: context)
        let todayData = DefaultPrompts.getTodaysPrompt(for: level, mix: effectivePromptMix)
        let targetId = todayData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            var allPrompts = try context.fetch(descriptor)
            todaysPrompt = allPrompts.first { $0.id == targetId }

            // If the prompt isn't in the DB yet (new prompts added, seeding hasn't run yet),
            // insert it directly so we don't have to wait for the full seed pass.
            if todaysPrompt == nil {
                let newPrompt = Prompt(
                    id: todayData.id,
                    text: todayData.text,
                    category: todayData.category,
                    difficulty: todayData.difficulty
                )
                context.insert(newPrompt)
                try context.save()
                todaysPrompt = newPrompt
                allPrompts.append(newPrompt)
            }

            // If hiding answered prompts and current prompt was already
            // answered, pick an unanswered one — still through the mix, so the
            // substitute leans the same way the day's prompt would have.
            if hideAnsweredPrompts, let current = todaysPrompt, answeredPromptIDs.contains(current.id) {
                let unanswered = allPrompts.filter { !answeredPromptIDs.contains($0.id) }
                todaysPrompt = effectivePromptMix.pick(
                    from: unanswered,
                    seed: DefaultPrompts.todaySeed(),
                    category: \.category
                ) ?? current
            }
        } catch {
            logger.error("Error loading today's prompt: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    @MainActor
    private func loadActiveGoals(context: ModelContext) async {
        GoalProgressService.refreshGoals(in: context)
        let descriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isActive && !$0.isCompleted },
            sortBy: [SortDescriptor(\.deadline)]
        )
        
        do {
            activeGoals = try context.fetch(descriptor)
        } catch {
            logger.error("Error loading active goals: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    @MainActor
    private func loadUserSettings(context: ModelContext) async {
        let descriptor = FetchDescriptor<UserSettings>()

        do {
            if let settings = try context.fetch(descriptor).first {
                selectedDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
                hideAnsweredPrompts = settings.hideAnsweredPrompts
                weeklyGoalSessions = settings.weeklyGoalSessions
                storyPracticeEnabled = settings.storyPracticeEnabled
                promptMix = settings.promptMix
                vocabChallengePreferences = settings.vocabChallengePreferences
                // The focus is ranked against the user's own weights, so it
                // reflects what actually moves *their* score.
                scoreWeights = ScoreWeights(from: settings)
            }
        } catch {
            logger.error("Error loading user settings: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }

    }

    private func loadAnsweredPromptIDs(context: ModelContext) {
        let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        answeredPromptIDs = Set(recordings.compactMap { $0.prompt?.id })
    }

    /// Read the user's stored speaker level. Defaults to `.intermediate`
    /// when no settings row exists yet (cold launch / first install).
    @MainActor
    private func currentSpeakerLevel(context: ModelContext) -> SpeakerLevel {
        let descriptor = FetchDescriptor<UserSettings>()
        let settings = try? context.fetch(descriptor).first
        return settings?.resolvedSpeakerLevel ?? .intermediate
    }
    
    @MainActor
    func refreshPrompt() async {
        guard let context = modelContext else { return }

        // Get a random prompt biased by the user's speaker level and goals
        let level = currentSpeakerLevel(context: context)
        let randomData = DefaultPrompts.getRandomPrompt(for: level, mix: effectivePromptMix)
        let targetId = randomData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            var allPrompts = try context.fetch(descriptor)
            var candidate = allPrompts.first { $0.id == targetId }

            // If the prompt isn't in the DB yet, insert it directly
            if candidate == nil {
                let newPrompt = Prompt(
                    id: randomData.id,
                    text: randomData.text,
                    category: randomData.category,
                    difficulty: randomData.difficulty
                )
                context.insert(newPrompt)
                try context.save()
                candidate = newPrompt
                allPrompts.append(newPrompt)
            }

            // If hiding answered prompts, prefer an unanswered one
            if hideAnsweredPrompts {
                loadAnsweredPromptIDs(context: context)
                let unanswered = allPrompts.filter { !answeredPromptIDs.contains($0.id) }
                if let pick = effectivePromptMix.pickRandom(from: unanswered, category: \.category) {
                    candidate = pick
                }
            }

            withAnimation {
                todaysPrompt = candidate
            }
            hasRerolledPrompt = true
        } catch {
            logger.error("Error refreshing prompt: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    // MARK: - Story Practice

    @MainActor
    private func loadTodaysStory(context: ModelContext) async {
        let descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            let stories = try context.fetch(descriptor)
            guard !stories.isEmpty else {
                storyPracticeEnabled = false
                return
            }
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            todaysStory = stories[dayOfYear % stories.count]
        } catch {
            logger.error("Error loading today's story: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    @MainActor
    func refreshStory() async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Story>()

        do {
            let stories = try context.fetch(descriptor)
            guard !stories.isEmpty else { return }
            withAnimation {
                todaysStory = stories.randomElement()
            }
        } catch {
            logger.error("Error refreshing story: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    // MARK: - Word Workout

    @MainActor
    func skipVocabWord(_ word: VocabChallengeWord) {
        _ = VocabChallengeService.skip(
            word.text,
            preferences: vocabChallengePreferences,
            usedCounts: vocabUsedCounts
        )
        withAnimation(.spring(duration: 0.25)) {
            refreshVocabChallenge()
        }
    }

    @MainActor
    private func refreshVocabChallenge() {
        guard let built = VocabChallengeService.todaysChallenge(
            preferences: vocabChallengePreferences,
            usedCounts: vocabUsedCounts
        ) else {
            vocabChallenge = nil
            return
        }
        let evaluation = VocabChallengeService.evaluate(
            built,
            transcripts: todayTranscripts,
            usages: todayVocabUsages
        )
        vocabChallenge = VocabChallengeService.applying(evaluation, to: built)
    }

    /// Asks the on-device model to top up the fresh-word pool when it is
    /// running low. Detached from the UI: no state change, no error surface,
    /// and the curated lexicon covers every failure.
    @MainActor
    func warmVocabFreshWords(llmService: LLMService) {
        let preferences = vocabChallengePreferences
        Task { await VocabFreshWordGenerator.refillIfNeeded(preferences: preferences, llmService: llmService) }
    }
}

// MARK: - Sendable result types

nonisolated private struct TodayHeavyResult: Sendable {
    let userStats: UserStats
    let weeklyProgress: WeeklyProgressData?
    let answeredPromptIDs: Set<String>
    let coachPlan: CoachPlan?
    let vocabUsedCounts: [String: Int]
    let todayTranscripts: [String]
    let todayVocabUsages: [VocabWordUsage]
    let readinessScore: Int
    /// Settings mix after weakness adaptation — what selection consumes.
    let promptMix: PromptMix
    let lastPracticeDate: Date?
}
