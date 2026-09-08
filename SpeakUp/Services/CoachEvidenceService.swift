import Foundation

// MARK: - Evidence

nonisolated struct CoachEvidence: Sendable {
    var fillerBurst: (count: Int, start: TimeInterval, end: TimeInterval, word: String)?
    var structuralRepetition: (frame: String, count: Int, start: TimeInterval, example: String)?
    var opening: String?
    var openingIsHesitant: Bool = false
    var closing: String?
    var longestHesitation: (at: TimeInterval, seconds: TimeInterval)?
    var fastestStretch: (at: TimeInterval, wpm: Int)?
    var slowestStretch: (at: TimeInterval, wpm: Int)?
    var crutchPhrase: (phrase: String, count: Int)?
    var restart: String?
    var hedgeCount: Int = 0
    var weakPhraseCount: Int = 0

    var promptLines: [String] {
        var lines: [String] = []
        if let burst = fillerBurst, burst.count >= 2 {
            lines.append("- \(burst.count) \"\(burst.word)\"s clustered between \(Self.stamp(burst.start)) and \(Self.stamp(burst.end)).")
        }
        if let structural = structuralRepetition, structural.count >= 3 {
            var line = "- Repeated the opening \"\(structural.frame)\" \(structural.count) times"
            if !structural.example.isEmpty {
                line += ": \"\(structural.example)\""
            }
            line += "."
            lines.append(line)
        }
        if let opening {
            lines.append("- Opened with: \"\(opening)\"\(openingIsHesitant ? " (starts on a filler)" : "").")
        }
        if let closing {
            lines.append("- Ended with: \"\(closing)\".")
        }
        if let hesitation = longestHesitation {
            lines.append("- Longest mid-thought silence: \(String(format: "%.1f", hesitation.seconds))s at \(Self.stamp(hesitation.at)).")
        }
        if let fastest = fastestStretch, let slowest = slowestStretch, fastest.wpm - slowest.wpm >= 30 {
            lines.append("- Pace swung from \(slowest.wpm) WPM at \(Self.stamp(slowest.at)) to \(fastest.wpm) WPM at \(Self.stamp(fastest.at)).")
        }
        if let crutch = crutchPhrase {
            lines.append("- Leaned on the phrase \"\(crutch.phrase)\" \(crutch.count) times.")
        }
        if let restart {
            lines.append("- Restarted a sentence: \"\(restart)\".")
        }
        if hedgeCount >= 3 {
            lines.append("- Used \(hedgeCount) hedging words (\"maybe\", \"kind of\", \"I think\"), which read as low conviction.")
        }
        return lines
    }

    static func stamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Service

nonisolated enum CoachEvidenceService {
    private static let hesitationThreshold: TimeInterval = 1.5
    private static let burstWindow: TimeInterval = 15

    static func evidence(
        for analysis: SpeechAnalysis,
        words: [TranscriptionWord]?
    ) -> CoachEvidence {
        var evidence = CoachEvidence()

        // Classic hesitation fillers only — structural frames have their own field.
        let classicFillers = analysis.fillerWords.filter { $0.kind == .filler }
        evidence.fillerBurst = densestFillerBurst(in: classicFillers)

        let spoken = (words ?? []).filter(\.isPrimarySpeaker).sorted { $0.start < $1.start }
        if !spoken.isEmpty {
            evidence.opening = phrase(from: spoken.prefix(12))
            evidence.openingIsHesitant = spoken.first(where: { !$0.word.trimmingCharacters(in: .whitespaces).isEmpty })?.isFiller ?? false
            evidence.closing = phrase(from: spoken.suffix(10))
            evidence.longestHesitation = longestHesitation(in: spoken)
        }

        evidence.structuralRepetition = structuralRepetitionEvidence(
            from: analysis.fillerWords,
            words: spoken
        )

        if let series = analysis.wpmTimeSeries, series.count >= 3 {
            let usable = series.filter { $0.wordCount >= 3 }
            if let fastest = usable.max(by: { $0.wpm < $1.wpm }),
               let slowest = usable.min(by: { $0.wpm < $1.wpm }) {
                evidence.fastestStretch = (fastest.timestamp, Int(fastest.wpm.rounded()))
                evidence.slowestStretch = (slowest.timestamp, Int(slowest.wpm.rounded()))
            }
        }

        if let repeated = analysis.vocabComplexity?.repeatedPhrases.max(by: { $0.count < $1.count }),
           repeated.count >= 2 {
            evidence.crutchPhrase = (repeated.phrase, repeated.count)
        }

        evidence.restart = analysis.sentenceAnalysis?.restartExamples.first

        if let quality = analysis.textQuality {
            evidence.hedgeCount = quality.hedgeWordCount
            evidence.weakPhraseCount = quality.weakPhraseCount
        }

        return evidence
    }

    // MARK: - Structural repetition

    private static func structuralRepetitionEvidence(
        from fillers: [FillerWord],
        words: [TranscriptionWord]
    ) -> (frame: String, count: Int, start: TimeInterval, example: String)? {
        guard let hit = fillers
            .filter({ $0.kind == .structural && $0.count >= StructuralRepetitionDetector.minRunLength })
            .max(by: { $0.count < $1.count })
        else { return nil }

        let stamps = hit.timestamps.sorted()
        guard let start = stamps.first else { return nil }
        let example = structuralExample(stamps: stamps, words: words)
        return (hit.word, hit.count, start, example)
    }

    private static func structuralExample(
        stamps: [TimeInterval],
        words: [TranscriptionWord]
    ) -> String {
        guard !words.isEmpty else { return "" }
        let clips = stamps.prefix(3).compactMap { stamp -> String? in
            guard let startIdx = words.nearestIndex(to: stamp) else { return nil }
            let endIdx = min(words.count, startIdx + 6)
            let slice = words[startIdx..<endIdx]
            let text = slice
                .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return clips.joined(separator: " / ")
    }


    // MARK: - Filler clustering

    private static func densestFillerBurst(
        in fillers: [FillerWord]
    ) -> (count: Int, start: TimeInterval, end: TimeInterval, word: String)? {
        var best: (count: Int, start: TimeInterval, end: TimeInterval, word: String)?

        for filler in fillers where filler.timestamps.count >= 2 {
            let stamps = filler.timestamps.sorted()
            var lower = 0
            for upper in stamps.indices {
                while stamps[upper] - stamps[lower] > burstWindow { lower += 1 }
                let count = upper - lower + 1
                if count > (best?.count ?? 1) {
                    best = (count, stamps[lower], stamps[upper], filler.word)
                }
            }
        }
        return best
    }

    // MARK: - Hesitation

    private static func longestHesitation(
        in words: [TranscriptionWord]
    ) -> (at: TimeInterval, seconds: TimeInterval)? {
        var best: (at: TimeInterval, seconds: TimeInterval)?

        for index in 1..<max(1, words.count) {
            let previous = words[index - 1]
            let gap = words[index].start - previous.end
            guard gap >= hesitationThreshold else { continue }
            guard !previous.word.hasSuffixIn([".", "?", "!"]) else { continue }
            if gap > (best?.seconds ?? 0) {
                best = (previous.end, gap)
            }
        }
        return best
    }

    // MARK: - Phrasing

    private static func phrase(from words: some Collection<TranscriptionWord>) -> String? {
        let text = words
            .map { $0.word.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.count >= 8 ? text : nil
    }
}

private extension String {
    nonisolated func hasSuffixIn(_ suffixes: [String]) -> Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return suffixes.contains { trimmed.hasSuffix($0) }
    }
}
