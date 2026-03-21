import Foundation

struct CoachingTip: Identifiable {
    let icon: String
    let title: String
    let message: String
    let category: TipCategory
    let teachingPoint: String
    let suggestedDrillMode: String?

    var id: String {
        "\(category.id)|\(title)|\(message)|\(teachingPoint)|\(suggestedDrillMode ?? "")"
    }

    init(
        icon: String,
        title: String,
        message: String,
        category: TipCategory,
        teachingPoint: String = "",
        suggestedDrillMode: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.category = category
        self.teachingPoint = teachingPoint
        self.suggestedDrillMode = suggestedDrillMode
    }

    enum TipCategory {
        case pace
        case fillers
        case pauses
        case clarity
        case structure
        case delivery
        case relevance
        case encouragement

        var id: String {
            switch self {
            case .pace: return "pace"
            case .fillers: return "fillers"
            case .pauses: return "pauses"
            case .clarity: return "clarity"
            case .structure: return "structure"
            case .delivery: return "delivery"
            case .relevance: return "relevance"
            case .encouragement: return "encouragement"
            }
        }
    }
}

enum CoachingTipService {
    /// Evaluate a `SpeechAnalysis` and return 2-3 actionable tips.
    static func generateTips(from analysis: SpeechAnalysis) -> [CoachingTip] {
        var tips: [CoachingTip] = []

        let wpm = analysis.wordsPerMinute
        let fillerPct = analysis.fillerPercentage
        let overall = analysis.speechScore.overall
        let pauseQuality = analysis.speechScore.subscores.pauseQuality
        let clarity = analysis.speechScore.subscores.clarity
        let pauseCount = analysis.pauseCount
        let avgPause = analysis.averagePauseLength
        let textQuality = analysis.textQuality
        let audioIsolation = analysis.audioIsolationMetrics
        let speakerIsolation = analysis.speakerIsolationMetrics
        let lowSignalReliability =
            (audioIsolation?.residualNoiseScore ?? 70) < 45 ||
            (speakerIsolation?.separationConfidence ?? 70) < 45

        // Top filler word name
        let topFiller = analysis.fillerWords.first?.word ?? "um"
        let topFillerCount = analysis.fillerWords.first?.count ?? 0

        // --- Signal quality / conversation isolation ---
        if let speakerIsolation, speakerIsolation.conversationDetected {
            tips.append(CoachingTip(
                icon: "person.2.wave.2.fill",
                title: "Conversation Mode Detected",
                message: "Detected multiple speakers. Your score is focused on your voice where separation confidence allowed.",
                category: .clarity,
                teachingPoint: "For strongest speaker separation, begin with a 5-second voice anchor and keep the mic near your mouth during group conversations."
            ))
        } else if let speakerIsolation, speakerIsolation.separationConfidence < 50 {
            tips.append(CoachingTip(
                icon: "person.crop.circle.badge.questionmark",
                title: "Speaker Separation Is Uncertain",
                message: "Your session may include overlapping voices. Keep the microphone close and avoid side talk when scoring yourself.",
                category: .clarity,
                teachingPoint: "Separation quality improves when your voice is consistently louder than nearby speakers by a small margin."
            ))
        }

        if let audioIsolation, audioIsolation.residualNoiseScore < 45 {
            tips.append(CoachingTip(
                icon: "waveform.badge.exclamationmark",
                title: "Background Noise Is High",
                message: "Noise impacted transcript quality. A quieter space or headset mic will improve score accuracy.",
                category: .clarity,
                teachingPoint: "Noise suppression helps, but scoring is most stable when your voice clearly dominates ambient sound."
            ))
        }

        // --- Pace ---
        if wpm > 185 {
            tips.append(CoachingTip(
                icon: "tortoise.fill",
                title: "Slow Down",
                message: "You spoke at \(Int(wpm)) WPM. Aim for 130-170 WPM for clarity.",
                category: .pace,
                teachingPoint: "Research shows listeners retain more at 130-150 WPM. Try the 'pause and breathe' technique: after each key point, take a full breath before continuing.",
                suggestedDrillMode: "paceControl"
            ))
        } else if wpm > 170 {
            tips.append(CoachingTip(
                icon: "gauge.with.dots.needle.50percent",
                title: "Slightly Fast",
                message: "At \(Int(wpm)) WPM you're just above optimal. Ease off slightly to land in the 130-170 sweet spot.",
                category: .pace,
                teachingPoint: "Even slightly fast speech can reduce audience comprehension. Try deliberately slowing down at the start of each new idea to anchor your pace.",
                suggestedDrillMode: "paceControl"
            ))
        } else if wpm < 115 && wpm > 0 {
            tips.append(CoachingTip(
                icon: "hare.fill",
                title: "Pick Up the Pace",
                message: "At \(Int(wpm)) WPM, try speaking a bit faster for better engagement.",
                category: .pace,
                teachingPoint: "Too-slow speech can lose listeners' attention. Practice reading passages aloud at a brisk pace to build comfort with faster delivery.",
                suggestedDrillMode: "paceControl"
            ))
        } else if wpm >= 115 && wpm < 130 {
            tips.append(CoachingTip(
                icon: "figure.walk",
                title: "A Bit More Energy",
                message: "At \(Int(wpm)) WPM you're close to optimal. A touch more energy will bring you into the 130-170 range.",
                category: .pace,
                teachingPoint: "You're close to the ideal range. Try adding vocal energy and enthusiasm — this naturally increases pace without feeling rushed.",
                suggestedDrillMode: "paceControl"
            ))
        }

        // --- Fillers ---
        if fillerPct > 10 {
            tips.append(CoachingTip(
                icon: "exclamationmark.bubble.fill",
                title: "High Filler Usage",
                message: lowSignalReliability
                    ? "You may be using fillers (top: \"\(topFiller)\", \(topFillerCount)x), but audio conditions reduced certainty."
                    : "You used \"\(topFiller)\" \(topFillerCount) times. Practice replacing fillers with 1-second pauses.",
                category: .fillers,
                teachingPoint: "Fillers signal uncertainty to listeners. Practice the 'silent pause' technique: when you feel an '\(topFiller)' coming, close your mouth and pause for 1 second instead.",
                suggestedDrillMode: "fillerElimination"
            ))
        } else if fillerPct > 5 {
            tips.append(CoachingTip(
                icon: "bubble.left.fill",
                title: "Reduce Fillers",
                message: lowSignalReliability
                    ? "Possible filler usage detected (\"\(topFiller)\" \(topFillerCount)x), though isolation confidence is limited."
                    : "You said \"\(topFiller)\" \(topFillerCount) times. Try pausing silently instead.",
                category: .fillers,
                teachingPoint: "Awareness is the first step. Record yourself in daily conversation and count fillers. Once you hear them, you'll naturally start replacing them with confident pauses.",
                suggestedDrillMode: "fillerElimination"
            ))
        }

        // --- Pauses ---
        if pauseCount == 0 {
            tips.append(CoachingTip(
                icon: "pause.circle.fill",
                title: "Add Strategic Pauses",
                message: "You didn't pause at all. Strategic pauses are powerful for emphasis.",
                category: .pauses,
                teachingPoint: "A 1-2 second pause after a key point gives your audience time to absorb the idea. Top speakers pause 3-5 times per minute.",
                suggestedDrillMode: "pausePractice"
            ))
        } else if avgPause > 3 {
            tips.append(CoachingTip(
                icon: "clock.fill",
                title: "Shorten Pauses",
                message: "Some pauses were over 3 seconds. Keep pauses under 2 seconds.",
                category: .pauses,
                teachingPoint: "Long pauses can feel awkward. Practice the 'beat method': count one beat (about 1 second) in your head during pauses. This keeps them impactful without losing momentum.",
                suggestedDrillMode: "pausePractice"
            ))
        } else if pauseQuality < 50 {
            tips.append(CoachingTip(
                icon: "metronome.fill",
                title: "Improve Pause Quality",
                message: "Your pauses feel unnatural. Aim for 0.5-2 second pauses between ideas.",
                category: .pauses,
                teachingPoint: "Natural pauses happen at the end of thoughts, not mid-sentence. Practice reading a paragraph and pausing only at periods and commas.",
                suggestedDrillMode: "pausePractice"
            ))
        }

        // --- Clarity ---
        if clarity < 60 {
            tips.append(CoachingTip(
                icon: "waveform.badge.magnifyingglass",
                title: "Work on Articulation",
                message: "Slow down and focus on enunciating each word clearly.",
                category: .clarity,
                teachingPoint: "Try tongue twisters before speaking to warm up. Focus on consonant endings — dropping final consonants is the most common clarity issue."
            ))
        }

        // --- Structure / Conciseness ---
        if let textQuality, textQuality.concisenessScore < 55 {
            tips.append(CoachingTip(
                icon: "scissors",
                title: "Tighten Your Message",
                message: "Your phrasing can be more concise. Replace weak phrases with direct statements.",
                category: .structure,
                teachingPoint: "Use the one-breath rule: if a sentence cannot be spoken clearly in one breath, split it. Replace phrases like 'at the end of the day' with a direct claim.",
                suggestedDrillMode: "impromptuSprint"
            ))
        }

        if let textQuality, textQuality.engagementScore < 55 {
            tips.append(CoachingTip(
                icon: "person.3.sequence.fill",
                title: "Increase Audience Engagement",
                message: "Add more audience hooks like rhetorical questions and clear takeaways.",
                category: .structure,
                teachingPoint: "Try this structure: Hook question -> key point -> concrete example -> clear takeaway. Engagement rises when listeners know why each section matters.",
                suggestedDrillMode: "pausePractice"
            ))
        }

        // --- Substance & Fluency (from SpeechScoringEngine) ---
        if let em = analysis.enhancedMetrics {
            if em.substanceScore < 35 {
                tips.append(CoachingTip(
                    icon: "text.word.spacing",
                    title: "Develop Your Response",
                    message: "Your response was too short or lacked content depth. Aim for at least 30 seconds of substantive speech.",
                    category: .structure,
                    teachingPoint: "Use the PREP framework: Point → Reason → Example → Point. This naturally extends your response to a meaningful length while keeping it focused.",
                    suggestedDrillMode: "impromptuSprint"
                ))
            } else if em.substanceScore < 60 {
                tips.append(CoachingTip(
                    icon: "text.word.spacing",
                    title: "Add More Depth",
                    message: "Your speech had some substance but could be more developed. Try adding a concrete example or expanding your main point.",
                    category: .structure,
                    teachingPoint: "For every claim you make, follow it with 'For example...' or 'This matters because...'. Adding one supporting detail per point significantly increases perceived depth.",
                    suggestedDrillMode: "impromptuSprint"
                ))
            }
            if em.phonationTimeRatio < 0.45 {
                tips.append(CoachingTip(
                    icon: "waveform.and.mic",
                    title: "Reduce Dead Air",
                    message: "You spent a lot of time pausing. Aim to be speaking 55-75% of your session time.",
                    category: .pace,
                    teachingPoint: "Excessive pausing often signals hesitation or searching for words. Practice 'thinking out loud' — bridge pauses with transitional phrases like 'What I mean is...' while you formulate your next thought.",
                    suggestedDrillMode: "fillerFree"
                ))
            }
            if em.meanLengthOfRun < 4.0 && analysis.totalWords > 20 {
                tips.append(CoachingTip(
                    icon: "pause.circle",
                    title: "Speak in Longer Runs",
                    message: "Your speech is fragmented — you pause very frequently. Try to complete full thoughts before pausing.",
                    category: .pace,
                    teachingPoint: "Fluent speakers average 7-12 words between pauses. Practice reading aloud and marking natural pause points at clause boundaries, not mid-phrase.",
                    suggestedDrillMode: "pausePractice"
                ))
            }
        }
        // --- Delivery ---
        if let delivery = analysis.speechScore.subscores.delivery, delivery < 50 {
            tips.append(CoachingTip(
                icon: "speaker.wave.3",
                title: "Add Vocal Energy",
                message: "Vary your volume and tone to keep listeners engaged. Try emphasizing key words.",
                category: .delivery,
                teachingPoint: "Monotone delivery puts listeners to sleep. Practice the 'highlight' technique: pick one word per sentence to emphasize with slightly more volume and slower pace."
            ))
        }

        // --- Relevance ---
        if let relevance = analysis.speechScore.subscores.relevance, relevance < 40 {
            if analysis.promptRelevanceScore != nil {
                tips.append(CoachingTip(
                    icon: "target",
                    title: "Stay on Topic",
                    message: "Your response drifted from the prompt. Try outlining 2-3 key points before speaking.",
                    category: .relevance,
                    teachingPoint: "Before speaking, mentally outline 2-3 key points. Use the PREP framework: Point, Reason, Example, Point. This keeps you focused.",
                    suggestedDrillMode: "impromptuSprint"
                ))
            } else {
                tips.append(CoachingTip(
                    icon: "arrow.triangle.branch",
                    title: "Improve Coherence",
                    message: "Connect your ideas with transition words like \"however\", \"therefore\", or \"for example\".",
                    category: .relevance,
                    teachingPoint: "Use 'bridge phrases' between ideas: 'Building on that...', 'This connects to...', 'The key takeaway is...'. These signal logical progression to your listener.",
                    suggestedDrillMode: "impromptuSprint"
                ))
            }
        }

        // --- Encouragement ---
        if overall >= 80 {
            tips.append(CoachingTip(
                icon: "star.fill",
                title: "Great Session!",
                message: "You scored \(overall)/100. Focus on consistency by practicing daily.",
                category: .encouragement,
                teachingPoint: "Consistency is what separates good speakers from great ones. Even 2 minutes of daily practice builds muscle memory for confident delivery."
            ))
        } else if overall < 40 && overall > 0 {
            tips.append(CoachingTip(
                icon: "target",
                title: "One Step at a Time",
                message: "Focus on one thing first – try reducing your most common filler word.",
                category: .encouragement,
                teachingPoint: "Every great speaker started somewhere. Pick your weakest area and focus only on that for your next 3 sessions. Small wins compound into big improvements."
            ))
        }

        // Always return at least 1 tip, cap at 3
        if tips.isEmpty {
            tips.append(CoachingTip(
                icon: "checkmark.circle.fill",
                title: "Keep Practicing",
                message: "Consistent practice is the key to improvement. Try another session!",
                category: .encouragement,
                teachingPoint: "You're building a habit — that's the hardest part. Each session strengthens your speaking confidence, even when the scores are already good."
            ))
        }

        return Array(tips.prefix(3))
    }
}
