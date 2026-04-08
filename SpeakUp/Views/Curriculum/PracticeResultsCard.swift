import SwiftUI
import SwiftData

struct PracticeResultsCard: View {
    let recording: Recording
    let activity: CurriculumActivity

    @State private var appeared = false

    private var analysis: SpeechAnalysis? { recording.analysis }

    var body: some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .opacity(appeared ? 1.0 : 0)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice Complete")
                            .font(.headline)

                        Text(practiceEncouragement)
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }

                    Spacer()
                }

                if let analysis {
                    resultsContent(analysis)
                        .opacity(appeared ? 1.0 : 0)
                } else {
                    analyzingPlaceholder
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    // MARK: - Results Content

    private func resultsContent(_ analysis: SpeechAnalysis) -> some View {
        VStack(spacing: 12) {
            // Overall score ring
            HStack(spacing: 20) {
                scoreRing(score: analysis.speechScore.overall)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Score")
                        .font(.subheadline.weight(.medium))

                    Text(coachingMessage(for: analysis))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider().opacity(0.3)

            // Relevant metrics for this lesson
            relevantMetrics(analysis)
        }
    }

    private func relevantMetrics(_ analysis: SpeechAnalysis) -> some View {
        HStack(spacing: 0) {
            metricPill(
                icon: "text.bubble",
                label: "Fillers",
                value: "\(analysis.totalFillerCount)",
                color: analysis.totalFillerCount <= 2 ? .green : (analysis.totalFillerCount <= 5 ? .orange : .red)
            )

            Spacer()

            metricPill(
                icon: "speedometer",
                label: "Pace",
                value: "\(Int(analysis.wordsPerMinute))",
                color: (130...170).contains(Int(analysis.wordsPerMinute)) ? .green : .orange
            )

            Spacer()

            metricPill(
                icon: "pause.circle",
                label: "Pauses",
                value: "\(analysis.strategicPauseCount)",
                color: analysis.strategicPauseCount >= 2 ? .green : .orange
            )
        }
    }

    // MARK: - Subviews

    private func scoreRing(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(.gray.opacity(0.2), lineWidth: 5)

            Circle()
                .trim(from: 0, to: appeared ? Double(score) / 100.0 : 0)
                .stroke(AppColors.scoreColor(for: score), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8).delay(0.2), value: appeared)

            Text("\(score)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.scoreColor(for: score))
        }
        .frame(width: 56, height: 56)
    }

    private func metricPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var analyzingPlaceholder: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.teal)

            Text("Analyzing your recording...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Encouragement

    private var practiceEncouragement: String {
        guard let analysis else { return "Great job showing up!" }
        let score = analysis.speechScore.overall
        if score >= 80 { return "Incredible session!" }
        if score >= 60 { return "Really solid work!" }
        if score >= 40 { return "Every rep counts!" }
        return "Showing up is half the battle!"
    }

    private func coachingMessage(for analysis: SpeechAnalysis) -> String {
        let score = analysis.speechScore.overall
        if score >= 80 {
            return "Excellent work! You're nailing this."
        } else if score >= 60 {
            return "Solid practice session. Keep building on this."
        } else if score >= 40 {
            return "Good effort — each session gets you closer."
        } else {
            return "Great start! Awareness is the first step to improvement."
        }
    }
}
