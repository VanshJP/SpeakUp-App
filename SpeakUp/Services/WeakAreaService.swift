import Foundation

struct WeakArea: Identifiable {
    let id: String
    let metricName: String
    let averageScore: Int
    let trend: String
    let suggestedDrillMode: String?
    let suggestedExercises: [String]
}

struct SuggestedActivity {
    let title: String
    let description: String
    let icon: String
    let type: SuggestionType

    enum SuggestionType {
        case drill(DrillMode)
        case exercise(String)
        case practice
    }
}

@Observable
class WeakAreaService {
    var weakAreas: [WeakArea] = []
    var suggestion: SuggestedActivity?

    func analyze(recordings: [Recording]) {
        let recent = Array(recordings.prefix(10))
        guard !recent.isEmpty else {
            suggestion = SuggestedActivity(
                title: "Start Practicing",
                description: "Record your first session to get personalized suggestions.",
                icon: "mic.fill",
                type: .practice
            )
            return
        }

        let analyzed = recent.filter { $0.analysis != nil }
        guard !analyzed.isEmpty else { return }

        // Compute averages per subscore
        var metrics: [(name: String, avg: Int, drill: DrillMode?)] = []

        let clarityAvg = analyzed.compactMap { $0.analysis?.speechScore.subscores.clarity }.reduce(0, +) / max(1, analyzed.count)
        metrics.append(("Clarity", clarityAvg, nil))

        let paceAvg = analyzed.compactMap { $0.analysis?.speechScore.subscores.pace }.reduce(0, +) / max(1, analyzed.count)
        metrics.append(("Pace", paceAvg, .paceControl))

        let fillerAvg = analyzed.compactMap { $0.analysis?.speechScore.subscores.fillerUsage }.reduce(0, +) / max(1, analyzed.count)
        metrics.append(("Filler Usage", fillerAvg, .fillerElimination))

        let pauseAvg = analyzed.compactMap { $0.analysis?.speechScore.subscores.pauseQuality }.reduce(0, +) / max(1, analyzed.count)
        metrics.append(("Pause Quality", pauseAvg, .pausePractice))

        let deliveryScores = analyzed.compactMap { $0.analysis?.speechScore.subscores.delivery }
        if !deliveryScores.isEmpty {
            let deliveryAvg = deliveryScores.reduce(0, +) / deliveryScores.count
            metrics.append(("Delivery", deliveryAvg, nil))
        }

        let vocabScores = analyzed.compactMap { $0.analysis?.speechScore.subscores.vocabulary }
        if !vocabScores.isEmpty {
            let vocabAvg = vocabScores.reduce(0, +) / vocabScores.count
            metrics.append(("Vocabulary", vocabAvg, .impromptuSprint))
        }

        // Sort by score (weakest first)
        metrics.sort { $0.avg < $1.avg }

        weakAreas = metrics.prefix(2).map { metric in
            WeakArea(
                id: metric.name,
                metricName: metric.name,
                averageScore: metric.avg,
                trend: metric.avg < 60 ? "needs work" : "improving",
                suggestedDrillMode: metric.drill?.rawValue,
                suggestedExercises: []
            )
        }

        // Generate suggestion from weakest area
        if let weakest = metrics.first {
            if let drill = weakest.drill {
                suggestion = SuggestedActivity(
                    title: "\(drill.title) Drill",
                    description: "Your \(weakest.name.lowercased()) has averaged \(weakest.avg)/100. Try this drill to improve.",
                    icon: drill.icon,
                    type: .drill(drill)
                )
            } else {
                suggestion = SuggestedActivity(
                    title: "Practice Session",
                    description: "Your \(weakest.name.lowercased()) has averaged \(weakest.avg)/100. A focused practice session can help.",
                    icon: "mic.fill",
                    type: .practice
                )
            }
        }
    }
}
