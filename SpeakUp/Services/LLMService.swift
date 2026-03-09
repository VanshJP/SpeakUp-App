import Foundation
import FoundationModels

// MARK: - Types

struct CoherenceResult {
    let score: Int
    let topicFocus: String
    let logicalFlow: String
    let reason: String
}

// MARK: - LLMService

@MainActor @Observable
final class LLMService {
    var isGenerating = false

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Coherence Evaluation

    func evaluateCoherence(transcript: String) async -> CoherenceResult? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt = """
        You are a speech coherence evaluator. Score the coherence of the given transcript \
        on a 0-100 scale. Output EXACTLY in this format with no other text:
        SCORE: <number>
        TOPIC_FOCUS: <one sentence>
        LOGICAL_FLOW: <one sentence>
        REASON: <one sentence>
        """

        let userPrompt = "Evaluate the coherence of this speech transcript:\n\n\(truncated)"

        guard let output = await generate(prompt: userPrompt, systemPrompt: systemPrompt) else {
            return nil
        }

        if let result = Self.parseCoherenceResult(output) {
            return result
        }

        // Fallback: extract just a number
        let numbers = output.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        let score = numbers.first(where: { $0 >= 0 && $0 <= 100 }) ?? 50
        return CoherenceResult(score: score, topicFocus: "", logicalFlow: "", reason: "")
    }

    // MARK: - Coaching Tips

    func generateCoachingInsight(
        from analysis: SpeechAnalysis,
        transcript: String
    ) async -> String? {
        isGenerating = true
        defer { isGenerating = false }

        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let prompt = buildCoachingPrompt(from: analysis, transcript: transcript)

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: coachingSystemPrompt
            )
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            print("FoundationModels coaching error: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func generate(prompt: String, systemPrompt: String) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: systemPrompt
            )
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            print("FoundationModels generation error: \(error)")
            return nil
        }
    }

    private static func parseCoherenceResult(_ output: String) -> CoherenceResult? {
        let lines = output.components(separatedBy: "\n")
        var score: Int?
        var topicFocus = ""
        var logicalFlow = ""
        var reason = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("SCORE:") {
                let value = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                score = Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "")
            } else if trimmed.uppercased().hasPrefix("TOPIC_FOCUS:") {
                topicFocus = String(trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces))
            } else if trimmed.uppercased().hasPrefix("LOGICAL_FLOW:") {
                logicalFlow = String(trimmed.dropFirst(13).trimmingCharacters(in: .whitespaces))
            } else if trimmed.uppercased().hasPrefix("REASON:") {
                reason = String(trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces))
            }
        }

        guard let s = score else { return nil }
        return CoherenceResult(
            score: max(0, min(100, s)),
            topicFocus: topicFocus,
            logicalFlow: logicalFlow,
            reason: reason
        )
    }

    private var coachingSystemPrompt: String {
        """
        You are a supportive speech coach. Analyze the speaker's performance and provide \
        2-3 specific, actionable coaching tips. Be encouraging but honest. Focus on the \
        most impactful areas for improvement. Keep each tip to 1-2 sentences. \
        Format: Start each tip on a new line with a bullet point (•).
        """
    }

    private func buildCoachingPrompt(from analysis: SpeechAnalysis, transcript: String) -> String {
        let truncatedTranscript = String(transcript.prefix(500))

        var parts: [String] = []
        parts.append("Speech Performance Summary:")
        parts.append("- Overall Score: \(analysis.speechScore.overall)/100")
        parts.append("- Words Per Minute: \(Int(analysis.wordsPerMinute))")
        parts.append("- Total Words: \(analysis.totalWords)")
        parts.append("- Filler Words: \(analysis.totalFillerCount)")
        parts.append("- Pauses: \(analysis.pauseCount) (strategic: \(analysis.strategicPauseCount), hesitations: \(analysis.hesitationPauseCount))")

        let subscores = analysis.speechScore.subscores
        parts.append("- Clarity: \(subscores.clarity)/100")
        parts.append("- Pace: \(subscores.pace)/100")
        parts.append("- Filler Usage Score: \(subscores.fillerUsage)/100")
        parts.append("- Pause Quality: \(subscores.pauseQuality)/100")

        if let vv = subscores.vocalVariety {
            parts.append("- Vocal Variety: \(vv)/100")
        }
        if let vocab = subscores.vocabulary {
            parts.append("- Vocabulary: \(vocab)/100")
        }

        if !analysis.fillerWords.isEmpty {
            let topFillers = analysis.fillerWords.prefix(3).map { "\($0.word) (\($0.count)x)" }.joined(separator: ", ")
            parts.append("- Top filler words: \(topFillers)")
        }

        parts.append("")
        parts.append("Transcript excerpt:")
        parts.append(truncatedTranscript)
        parts.append("")
        parts.append("Based on this performance, provide 2-3 specific coaching tips to help this speaker improve.")

        return parts.joined(separator: "\n")
    }
}
