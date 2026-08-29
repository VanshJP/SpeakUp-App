import SwiftUI
import SwiftData

struct PracticeResultsCard: View {
    let recording: Recording
    let activity: CurriculumActivity

    @Query private var userSettings: [UserSettings]
    @State private var appeared = false

    private var analysis: SpeechAnalysis? { recording.analysis }

    private var targetWPM: Int { userSettings.first.resolvedTargetWPM }

    /// Same tip engine as Recording Detail — curriculum practice should not invent
    /// a second coaching voice.
    private var primaryTip: CoachingTip? {
        guard let analysis else { return nil }
        return CoachingTipService.generateTips(
            from: analysis,
            context: CoachingContext(targetWPM: targetWPM)
        ).first
    }

    var body: some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.success)
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .opacity(appeared ? 1.0 : 0)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice Complete")
                            .font(.headline)

                        Text(practiceEncouragement)
                            .font(.caption)
                            .foregroundStyle(AppColors.primary)
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

                    if let tip = primaryTip {
                        Text(tip.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                        Text(tip.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !tip.teachingPoint.isEmpty {
                            Text(tip.teachingPoint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    } else {
                        Text("Bank another rep while scoring is still loading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            Divider().opacity(0.3)

            // Relevant metrics for this lesson
            relevantMetrics(analysis)
        }
    }

    private func relevantMetrics(_ analysis: SpeechAnalysis) -> some View {
        let wpm = Int(analysis.wordsPerMinute.rounded())
        let onPace = abs(wpm - targetWPM) <= 25

        return HStack(spacing: 0) {
            metricPill(
                icon: "text.bubble",
                label: "Fillers",
                value: "\(analysis.totalFillerCount)",
                color: analysis.totalFillerCount <= 2 ? AppColors.success : (analysis.totalFillerCount <= 5 ? AppColors.warning : AppColors.error)
            )

            Spacer()

            metricPill(
                icon: "speedometer",
                label: "Pace",
                value: "\(wpm)",
                color: onPace ? AppColors.success : AppColors.warning
            )

            Spacer()

            metricPill(
                icon: "pause.circle",
                label: "Pauses",
                value: "\(analysis.strategicPauseCount)",
                color: analysis.strategicPauseCount >= 2 ? AppColors.success : AppColors.warning
            )
        }
    }

    // MARK: - Subviews

    private func scoreRing(score: Int) -> some View {
        ZStack {
            RingProgress(
                progress: appeared ? Double(score) / 100.0 : 0,
                color: AppColors.scoreColor(for: score),
                lineWidth: 5
            )
            .motion(AppMotion.reveal.delay(0.2), value: appeared)

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
                .tint(AppColors.primary)

            Text("Analyzing your recording...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Encouragement

    /// Short status line only — the coaching tip below carries technique.
    private var practiceEncouragement: String {
        guard let analysis else { return "Recording saved" }
        if let tip = primaryTip, tip.kind == .win || tip.kind == .focus {
            return tip.kind == .win ? "Clean take" : "One focus for next rep"
        }
        let score = analysis.speechScore.overall
        if score >= 80 { return "Strong session" }
        if score >= 60 { return "Solid rep" }
        if score >= 40 { return "Useful data" }
        return "First read complete"
    }
}
