import Foundation

// MARK: - Evidence

/// Quotable moments from one session.
///
/// "Reduce your fillers" is advice anyone could give without listening. "Three
/// of your seven ums landed between 0:38 and 0:52, right after you finished a
/// sentence" is advice only something that actually heard the recording can
/// give — and it is the difference between feedback the user believes and
/// feedback they scroll past. Every field here is derived from data the
/// pipeline already produces; nothing new is computed at analysis time.
nonisolated struct CoachEvidence: Sendable {
    /// The densest cluster of fillers: how many, and when.
    var fillerBurst: (count: Int, start: TimeInterval, end: TimeInterval, word: String)?
    /// The speaker's actual first words — where hesitation is most audible and
    /// most fixable.
    var opening: String?
    /// True when the opening begins on a filler or hedge.
    var openingIsHesitant: Bool = false
    /// The last words spoken. Endings are where speakers trail off.
    var closing: String?
    /// Longest silence that was not a sentence boundary.
    var longestHesitation: (at: TimeInterval, seconds: TimeInterval)?
    /// Fastest and slowest measured stretch, when the pipeline produced a
    /// WPM series long enough for the comparison to mean anything.
    var fastestStretch: (at: TimeInterval, wpm: Int)?
    var slowestStretch: (at: TimeInterval, wpm: Int)?
    /// A phrase the speaker leaned on more than once.
    var crutchPhrase: (phrase: String, count: Int)?
    /// A sentence the speaker started over.
    var restart: String?
    var hedgeCount: Int = 0
    var weakPhraseCount: Int = 0

    /// Evidence as prompt lines for the LLM. Kept as plain sentences rather
    /// than a metric dump so a small local model can quote them straight back.
    var promptLines: [String] {
        var lines: [String] = []
        if let burst = fillerBurst, burst.count >= 2 {
            lines.append("- \(burst.count) \"\(burst.word)\"s clustered between \(Self.stamp(burst.start)) and \(Self.stamp(burst.end)).")
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

    /// `m:ss` for coaching copy. Timestamps are what make feedback checkable —
    /// the user can scrub straight to the moment.
    static func stamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Service

nonisolated enum CoachEvidenceService {
    /// Words either side of a hesitation for it to count as mid-thought rather
    /// than a natural sentence break.
    private static let hesitationThreshold: TimeInterval = 1.5
    /// Window the filler-cluster scan slides over the timeline.
    private static let burstWindow: TimeInterval = 15

    static func evidence(
        for analysis: SpeechAnalysis,
        words: [TranscriptionWord]?
    ) -> CoachEvidence {
        var evidence = CoachEvidence()

        evidence.fillerBurst = densestFillerBurst(in: analysis.fillerWords)

        // Scoring already decided which words are the speaker's; coaching must
        // not quote a bystander's sentence back at them as their opening.
        let spoken = (words ?? []).filter(\.isPrimarySpeaker).sorted { $0.start < $1.start }
        if !spoken.isEmpty {
            evidence.opening = phrase(from: spoken.prefix(12))
            evidence.openingIsHesitant = spoken.first(where: { !$0.word.trimmingCharacters(in: .whitespaces).isEmpty })?.isFiller ?? false
            evidence.closing = phrase(from: spoken.suffix(10))
            evidence.longestHesitation = longestHesitation(in: spoken)
        }

        if let series = analysis.wpmTimeSeries, series.count >= 3 {
            // Segments with almost no words in them report wild WPM off a
            // handful of syllables; quoting those as "you sped up" is noise.
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

    // MARK: - Filler clustering

    /// The tightest run of one filler word inside a sliding window.
    ///
    /// A raw count says the user said "um" seven times in two minutes, which
    /// sounds fine. The cluster says four of them landed in twelve seconds,
    /// which is what the listener actually heard.
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

    /// Longest gap that is not a sentence boundary. A pause after a full stop
    /// is craft; the same pause mid-clause is the speaker searching for a word,
    /// and only the second one is worth coaching.
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
