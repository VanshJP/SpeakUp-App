import Foundation
import SwiftUI
import SwiftData
import WidgetKit
import os

@Observable
class TodayViewModel {
    private let logger = Logger.app("Today")

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
    var coachPlan: CoachPlan?
    private var modelContext: ModelContext?
    private var lastPracticeDate: Date?
    var practicedToday: Bool {
        guard let lastPracticeDate else { return false }
        return Calendar.current.isDateInToday(lastPracticeDate)
    }
    private var answeredPromptIDs: Set<String> = []
    /// Category weighting from the user's onboarding goals, gated by their
    /// enabled categories. Built once per settings load rather than per prompt,
    /// and the only place the category gate is applied now.
    private var promptMix: PromptMix = .uniform
    private var effectivePromptMix: PromptMix = .uniform
    private var hasRerolledPrompt = false
    private var vocabChallengePreferences: VocabChallengePreferences = .disabled
    private var scoreWeights: ScoreWeights = .defaults
    private var vocabUsedCounts: [String: Int] = [:]
    private var todayTranscripts: [String] = []
    private var todayVocabUsages: [VocabWordUsage] = []
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

        await loadUserSettings(context: context)

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

        await loadTodaysPrompt(context: context)

        if storyPracticeEnabled {
            await loadTodaysStory(context: context)
        }

        await loadActiveGoals(context: context)

        CoachMomentService.shared.evaluateToday(
            context: context,
            practicedToday: practicedToday,
            lastPracticeDate: lastPracticeDate
        )

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

            // Stats — prefer denormalized `overallScore` so score-only passes
            // skip Codable blob decode when the projection is populated.
            let totalRecordings = recordings.count
            let totalPracticeTime = recordings.reduce(0) { $0 + $1.actualDuration }
            let recordingDates = recordings.map(\.date)
            let currentStreak = Date.calculateStreak(from: recordingDates)

            let scoresWithAnalysis = recordings.compactMap { Self.projectedOverallScore(for: $0) }
            let averageScore: Double = scoresWithAnalysis.isEmpty
                ? 0
                : Double(scoresWithAnalysis.reduce(0, +)) / Double(scoresWithAnalysis.count)
            let bestScore = scoresWithAnalysis.max() ?? 0

            let sevenDaysAgo = Date().adding(days: -7)
            let recentRecordings = recordings.filter { $0.date >= sevenDaysAgo }
            let scoreHistory = recentRecordings.compactMap { rec -> ScoreHistoryEntry? in
                guard let score = Self.projectedOverallScore(for: rec) else { return nil }
                return ScoreHistoryEntry(date: rec.date, score: score)
            }

            let improvementRate: Double = {
                guard recentRecordings.count >= 2 else { return 0 }
                let sorted = recentRecordings.sorted { $0.date < $1.date }
                let mid = sorted.count / 2
                let firstHalf = Array(sorted.prefix(mid))
                let secondHalf = Array(sorted.suffix(from: mid))
                let firstSum = firstHalf.compactMap { Self.projectedOverallScore(for: $0) }.reduce(0, +)
                let secondSum = secondHalf.compactMap { Self.projectedOverallScore(for: $0) }.reduce(0, +)
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
                // Bind once — each `analysis` access re-decodes the blob.
                let analysis = recording.analysis
                if let usage = analysis?.vocabWordsUsed {
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

            var lexiconProfile: LexiconProfile?
            var crutchHint: CrutchHint?
            var recentSessions: [LexiconSessionInput] = []
            recentSessions.reserveCapacity(20)
            for recording in recordings.prefix(20) {
                guard let text = recording.transcriptionText, !text.isEmpty else { continue }
                let analysis = recording.analysis
                var fillerCounts: [String: Int] = [:]
                if let fillerWords = analysis?.fillerWords {
                    for filler in fillerWords where filler.count > 0 {
                        fillerCounts[filler.word.lowercased(), default: 0] += filler.count
                    }
                }
                recentSessions.append(LexiconSessionInput(
                    date: recording.date,
                    transcript: text,
                    fillerCounts: fillerCounts,
                    overallScore: recording.overallScore ?? analysis?.speechScore.overall,
                    category: recording.storyId != nil ? "Story" : recording.prompt?.category
                ))
                if recentSessions.count >= 15 { break }
            }
            lexiconProfile = LexiconInsightsEngine.profile(from: recentSessions)
            if let top = lexiconProfile?.crutchWords.first(where: { $0.category == .filler || $0.category == .hedge }),
               top.count >= CrutchHint.minimumCount {
                crutchHint = CrutchHint(word: top.word, count: top.count)
            }

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
                lastPracticeDate: recordings.first?.date
            )
        }.value
    }

    /// Prefer the denormalized projection; fall back to the Codable blob for
    /// legacy rows written before `overallScore` existed (gotchas §18).
    nonisolated private static func projectedOverallScore(for recording: Recording) -> Int? {
        recording.overallScore ?? recording.analysis?.speechScore.overall
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


        if let lastPracticeDate {
            WidgetDataProvider.updateLastPracticeDate(lastPracticeDate)
        } else {
            WidgetDataProvider.clearLastPracticeDate()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    private func loadTodaysPrompt(context: ModelContext) async {
        if hasRerolledPrompt && todaysPrompt != nil { return }

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

    @MainActor
    private func currentSpeakerLevel(context: ModelContext) -> SpeakerLevel {
        let descriptor = FetchDescriptor<UserSettings>()
        let settings = try? context.fetch(descriptor).first
        return settings?.resolvedSpeakerLevel ?? .intermediate
    }
    
    @MainActor
    func refreshPrompt() async {
        guard let context = modelContext else { return }

        let level = currentSpeakerLevel(context: context)
        let randomData = DefaultPrompts.getRandomPrompt(for: level, mix: effectivePromptMix)
        let targetId = randomData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            var allPrompts = try context.fetch(descriptor)
            var candidate = allPrompts.first { $0.id == targetId }

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
    let promptMix: PromptMix
    let lastPracticeDate: Date?
}
