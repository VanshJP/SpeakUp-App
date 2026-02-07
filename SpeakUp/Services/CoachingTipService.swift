import Foundation

struct CoachingTip: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
    let category: TipCategory

    enum TipCategory {
        case pace
        case fillers
        case pauses
        case clarity
        case encouragement
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

        // Top filler word name
        let topFiller = analysis.fillerWords.first?.word ?? "um"
        let topFillerCount = analysis.fillerWords.first?.count ?? 0

        // --- Pace ---
        if wpm > 170 {
            tips.append(CoachingTip(
                icon: "tortoise.fill",
                title: "Slow Down",
                message: "You spoke at \(Int(wpm)) WPM. Aim for 130-170 WPM for clarity.",
                category: .pace
            ))
        } else if wpm < 110 && wpm > 0 {
            tips.append(CoachingTip(
                icon: "hare.fill",
                title: "Pick Up the Pace",
                message: "At \(Int(wpm)) WPM, try speaking a bit faster for better engagement.",
                category: .pace
            ))
        }

        // --- Fillers ---
        if fillerPct > 10 {
            tips.append(CoachingTip(
                icon: "exclamationmark.bubble.fill",
                title: "High Filler Usage",
                message: "You used \"\(topFiller)\" \(topFillerCount) times. Practice replacing fillers with 1-second pauses.",
                category: .fillers
            ))
        } else if fillerPct > 5 {
            tips.append(CoachingTip(
                icon: "bubble.left.fill",
                title: "Reduce Fillers",
                message: "You said \"\(topFiller)\" \(topFillerCount) times. Try pausing silently instead.",
                category: .fillers
            ))
        }

        // --- Pauses ---
        if pauseCount == 0 {
            tips.append(CoachingTip(
                icon: "pause.circle.fill",
                title: "Add Strategic Pauses",
                message: "You didn't pause at all. Strategic pauses are powerful for emphasis.",
                category: .pauses
            ))
        } else if avgPause > 3 {
            tips.append(CoachingTip(
                icon: "clock.fill",
                title: "Shorten Pauses",
                message: "Some pauses were over 3 seconds. Keep pauses under 2 seconds.",
                category: .pauses
            ))
        } else if pauseQuality < 50 {
            tips.append(CoachingTip(
                icon: "metronome.fill",
                title: "Improve Pause Quality",
                message: "Your pauses feel unnatural. Aim for 0.5-2 second pauses between ideas.",
                category: .pauses
            ))
        }

        // --- Clarity ---
        if clarity < 60 {
            tips.append(CoachingTip(
                icon: "waveform.badge.magnifyingglass",
                title: "Work on Articulation",
                message: "Slow down and focus on enunciating each word clearly.",
                category: .clarity
            ))
        }

        // --- Encouragement ---
        if overall >= 80 {
            tips.append(CoachingTip(
                icon: "star.fill",
                title: "Great Session!",
                message: "You scored \(overall)/100. Focus on consistency by practicing daily.",
                category: .encouragement
            ))
        } else if overall < 40 && overall > 0 {
            tips.append(CoachingTip(
                icon: "target",
                title: "One Step at a Time",
                message: "Focus on one thing first – try reducing your most common filler word.",
                category: .encouragement
            ))
        }

        // Always return at least 1 tip, cap at 3
        if tips.isEmpty {
            tips.append(CoachingTip(
                icon: "checkmark.circle.fill",
                title: "Keep Practicing",
                message: "Consistent practice is the key to improvement. Try another session!",
                category: .encouragement
            ))
        }

        return Array(tips.prefix(3))
    }
}
