import Foundation

/// Detects structural repetition (anaphora-as-tic): the same clause-opening
/// frame repeated across consecutive or near-consecutive clauses.
///
/// Distinct from classic fillers (`um`, `like`). Each clause can be clean yet
/// the repeated frame still weakens delivery — e.g. "I'm going to get socks,
/// I'm going to get tomatoes, I'm going to get eggs."
///
/// Emits `[FillerWord]` with `kind == .structural` so the existing filler UI
/// path works. Callers must pass primary-speaker words only when diarization
/// ran.
nonisolated enum StructuralRepetitionDetector {

    // MARK: - Constants

    /// Shortest opening n-gram considered a shared frame.
    static let minOpeningNGram = 3

    /// Longest opening n-gram tried (prefer longer matches when they agree).
    static let maxOpeningNGram = 5

    /// Minimum repeated clauses before flagging. Two is often intentional
    /// parallelism; three starts looking like a tic.
    static let minRunLength = 3

    /// Non-matching clauses allowed between matching ones ("near-consecutive").
    static let maxInterveningClauses = 1

    /// Gap that starts a new clause when Whisper omitted commas/periods.
    /// Aligned with pause detection in `SpeechAnalysisPipeline.analyze`.
    static let clausePauseThreshold: TimeInterval = 0.4

    /// Openings that signal intentional list/rhetoric structure (curriculum
    /// "First… Second… Third…"), not a tic — never flag these runs.
    static let intentionalListOpeners: Set<String> = [
        "first", "second", "third", "fourth", "fifth",
        "finally", "lastly", "next", "then",
        "one", "two", "three",
        "primarily", "secondarily"
    ]

    // MARK: - Public API

    /// Detect structural-repetition runs in already speaker-filtered words.
    /// Returns one `FillerWord` per distinct opening frame (aggregated).
    static func detect(in words: [TranscriptionWord]) -> [FillerWord] {
        guard words.count >= minOpeningNGram * minRunLength else { return [] }

        let clauses = splitIntoClauses(words)
        guard clauses.count >= minRunLength else { return [] }

        let runs = findRuns(in: clauses)
        guard !runs.isEmpty else { return [] }

        var aggregates: [String: (display: String, count: Int, timestamps: [TimeInterval])] = [:]
        for run in runs {
            var entry = aggregates[run.normalizedKey]
                ?? (display: run.displayLabel, count: 0, timestamps: [])
            entry.count += run.timestamps.count
            entry.timestamps.append(contentsOf: run.timestamps)
            aggregates[run.normalizedKey] = entry
        }

        return aggregates.map { _, value in
            FillerWord(
                word: value.display,
                count: value.count,
                timestamps: value.timestamps.sorted(),
                kind: .structural
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.word < rhs.word
        }
    }

    /// Word IDs that make up flagged opening frames — for plum transcript
    /// highlights. One span per occurrence timestamp (surface length of the
    /// frame label), matched by start time like coach evidence.
    static func highlightedWordIDs(
        in words: [TranscriptionWord],
        hits: [FillerWord]
    ) -> Set<UUID> {
        let structural = hits.filter {
            $0.kind == .structural && $0.count >= minRunLength
        }
        guard !structural.isEmpty, !words.isEmpty else { return [] }

        let sorted = words.sorted { $0.start < $1.start }
        var ids = Set<UUID>()

        for hit in structural {
            let frameLen = max(minOpeningNGram, hit.word.split(separator: " ").count)
            for stamp in hit.timestamps {
                guard let startIdx = nearestWordIndex(for: stamp, in: sorted) else { continue }
                let endIdx = min(sorted.count, startIdx + frameLen)
                for index in startIdx..<endIdx {
                    ids.insert(sorted[index].id)
                }
            }
        }
        return ids
    }

    private static func nearestWordIndex(for stamp: TimeInterval, in words: [TranscriptionWord]) -> Int? {
        var bestIndex: Int?
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for (index, word) in words.enumerated() {
            let delta = abs(word.start - stamp)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
            if word.start > stamp + 0.08 { break }
        }
        if let bestIndex, bestDelta <= 0.08 {
            return bestIndex
        }
        return words.firstIndex(where: { $0.start >= stamp - 0.01 })
    }

    // MARK: - Clause splitting

    private struct Clause {
        let words: [TranscriptionWord]
        let normalizedTokens: [String]
        var startTime: TimeInterval { words.first?.start ?? 0 }
    }

    /// Split on punctuation, coordinating conjunctions, and pause gaps.
    private static func splitIntoClauses(_ words: [TranscriptionWord]) -> [Clause] {
        var clauses: [Clause] = []
        var current: [TranscriptionWord] = []

        func flush() {
            let trimmed = dropLeadingCoordinators(current)
            current = []
            guard !trimmed.isEmpty else { return }

            var tokens: [String] = []
            for word in trimmed {
                tokens.append(contentsOf: normalizeWord(word.word))
            }
            guard tokens.count >= minOpeningNGram else { return }
            clauses.append(Clause(words: trimmed, normalizedTokens: tokens))
        }

        for word in words {
            let raw = word.word
            let stripped = stripTrailingPunctuation(raw).lowercased()

            // Pause gap with no punctuation — Whisper often drops commas.
            if let previous = current.last,
               word.start - previous.end >= clausePauseThreshold {
                flush()
            }

            // Coordinating conjunction starts a new clause (not part of it).
            if isCoordinator(stripped), !current.isEmpty {
                flush()
                continue
            }

            current.append(word)

            if endsClause(raw) {
                flush()
            }
        }

        flush()
        return clauses
    }

    private static func isCoordinator(_ token: String) -> Bool {
        token == "and" || token == "but" || token == "or"
    }

    private static func dropLeadingCoordinators(_ words: [TranscriptionWord]) -> [TranscriptionWord] {
        var result = words
        while let first = result.first {
            let token = stripTrailingPunctuation(first.word).lowercased()
            if isCoordinator(token) {
                result.removeFirst()
            } else {
                break
            }
        }
        return result
    }

    private static func endsClause(_ raw: String) -> Bool {
        guard let last = raw.last else { return false }
        return last == "," || last == "." || last == "?" || last == "!" || last == ";"
    }

    // MARK: - Run detection

    private struct Run {
        let normalizedKey: String
        let displayLabel: String
        let timestamps: [TimeInterval]
    }

    private static func findRuns(in clauses: [Clause]) -> [Run] {
        let openings = clauses.map { openingKey(for: $0) }

        var runs: [Run] = []
        var index = 0

        while index < clauses.count {
            let seed = openings[index]
            guard !seed.isEmpty else {
                index += 1
                continue
            }

            // Intentional list rhetoric — leave for craft, do not flag as tic.
            if isIntentionalListOpening(seed) {
                index += 1
                continue
            }

            var matchIndices = [index]
            var cursor = index + 1
            var intervening = 0

            while cursor < clauses.count {
                let candidate = openings[cursor]
                if !candidate.isEmpty,
                   !isIntentionalListOpening(candidate),
                   keysCompatible(seed, candidate) {
                    matchIndices.append(cursor)
                    intervening = 0
                    cursor += 1
                } else if intervening < maxInterveningClauses {
                    intervening += 1
                    cursor += 1
                } else {
                    break
                }
            }

            if matchIndices.count >= minRunLength {
                let sharedKey = longestSharedKey(matchIndices.map { openings[$0] })
                let display = displayLabel(
                    for: sharedKey,
                    surface: clauses[matchIndices[0]].words
                )
                let stamps = matchIndices.map { clauses[$0].startTime }
                runs.append(Run(
                    normalizedKey: sharedKey,
                    displayLabel: display,
                    timestamps: stamps
                ))
                index = (matchIndices.last ?? index) + 1
            } else {
                index += 1
            }
        }

        return runs
    }

    private static func isIntentionalListOpening(_ key: String) -> Bool {
        guard let first = key.split(separator: " ").first.map(String.init) else { return false }
        return intentionalListOpeners.contains(first)
    }

    private static func openingKey(for clause: Clause) -> String {
        let n = min(maxOpeningNGram, clause.normalizedTokens.count)
        guard n >= minOpeningNGram else { return "" }
        return clause.normalizedTokens.prefix(n).joined(separator: " ")
    }

    private static func keysCompatible(_ a: String, _ b: String) -> Bool {
        let aTokens = a.split(separator: " ").map(String.init)
        let bTokens = b.split(separator: " ").map(String.init)
        guard aTokens.count >= minOpeningNGram, bTokens.count >= minOpeningNGram else {
            return false
        }
        return Array(aTokens.prefix(minOpeningNGram)) == Array(bTokens.prefix(minOpeningNGram))
    }

    private static func longestSharedKey(_ keys: [String]) -> String {
        guard let first = keys.first else { return "" }
        var shared = first.split(separator: " ").map(String.init)
        for key in keys.dropFirst() {
            let tokens = key.split(separator: " ").map(String.init)
            var next: [String] = []
            for (lhs, rhs) in zip(shared, tokens) {
                if lhs == rhs {
                    next.append(lhs)
                } else {
                    break
                }
            }
            shared = next
            if shared.count < minOpeningNGram { break }
        }
        if shared.count < minOpeningNGram {
            return first.split(separator: " ").prefix(minOpeningNGram).joined(separator: " ")
        }
        return Array(shared.prefix(maxOpeningNGram)).joined(separator: " ")
    }

    private static func displayLabel(for normalizedKey: String, surface: [TranscriptionWord]) -> String {
        let needed = normalizedKey.split(separator: " ").count
        var collected: [String] = []
        var expandedCount = 0
        for word in surface {
            let surfaceToken = stripTrailingPunctuation(word.word).lowercased()
            guard !surfaceToken.isEmpty else { continue }
            collected.append(surfaceToken)
            expandedCount += normalizeWord(word.word).count
            if expandedCount >= needed { break }
        }
        return collected.isEmpty ? normalizedKey : collected.joined(separator: " ")
    }

    // MARK: - Normalization

    private static let contractions: [String: [String]] = [
        "i'm": ["i", "am"],
        "i'll": ["i", "will"],
        "i've": ["i", "have"],
        "i'd": ["i", "would"],
        "you're": ["you", "are"],
        "you'll": ["you", "will"],
        "you've": ["you", "have"],
        "we're": ["we", "are"],
        "we'll": ["we", "will"],
        "we've": ["we", "have"],
        "they're": ["they", "are"],
        "they'll": ["they", "will"],
        "they've": ["they", "have"],
        "that's": ["that", "is"],
        "it's": ["it", "is"],
        "there's": ["there", "is"],
        "here's": ["here", "is"],
        "who's": ["who", "is"],
        "what's": ["what", "is"],
        "don't": ["do", "not"],
        "doesn't": ["does", "not"],
        "didn't": ["did", "not"],
        "won't": ["will", "not"],
        "can't": ["can", "not"],
        "couldn't": ["could", "not"],
        "shouldn't": ["should", "not"],
        "wouldn't": ["would", "not"],
        "isn't": ["is", "not"],
        "aren't": ["are", "not"],
        "wasn't": ["was", "not"],
        "weren't": ["were", "not"],
        "let's": ["let", "us"]
    ]

    private static func normalizeWord(_ raw: String) -> [String] {
        let stripped = stripTrailingPunctuation(raw).lowercased()
        guard !stripped.isEmpty else { return [] }
        if let expansion = contractions[stripped] {
            return expansion
        }
        return [stripped]
    }

    private static func stripTrailingPunctuation(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
