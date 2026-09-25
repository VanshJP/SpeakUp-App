import SwiftUI
import SwiftData

struct PracticeResultsCard: View {
    let recording: Recording
    let activity: CurriculumActivity

    @Query private var userSettings: [UserSettings]
    /// Drives the ring's sweep and the number's count together. No odometer
    /// ticks: the take's own reveal played them a moment ago.
    @State private var counted = false
    /// Resolved once - `recording.analysis` re-decodes the Codable blob on
    /// every access, and `primaryTip` / encouragement both read it from body.
    @State private var analysis: SpeechAnalysis?
    @State private var primaryTip: CoachingTip?

    private var targetWPM: Int { userSettings.first.resolvedTargetWPM }

    var body: some View {
        GlassCard(tint: AppColors.primary.opacity(0.06)) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice complete")
                            .font(.headline)

                        Text(practiceEncouragement)
                            .font(.caption)
                            .foregroundStyle(AppColors.primary)
                    }

                    Spacer()

                    // The card opens the take's full page.
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                if let analysis {
                    resultsContent(analysis)
                        .introReveal(delay: .milliseconds(150))
                } else {
                    analyzingPlaceholder
                }
            }
        }
        .onAppear {
            resolveAnalysisIfNeeded()
            counted = true
        }
        .onChange(of: recording.overallScore) { _, _ in
            analysis = nil
            primaryTip = nil
            resolveAnalysisIfNeeded()
        }
        .onChange(of: targetWPM) { _, _ in
            refreshPrimaryTip()
        }
    }

    private func resolveAnalysisIfNeeded() {
        guard analysis == nil else { return }
        guard let decoded = recording.analysis else { return }
        analysis = decoded
        refreshPrimaryTip()
    }

    private func refreshPrimaryTip() {
        guard let analysis else { return }
        primaryTip = CoachingTipService.generateTips(
            from: analysis,
            context: CoachingContext(targetWPM: targetWPM)
        ).first
    }

    // MARK: - Results Content

    private func resultsContent(_ analysis: SpeechAnalysis) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                scoreRing(score: analysis.speechScore.overall)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall score")
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
                value: "\(wpm) wpm",
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

    /// Ring and number ride one animation, the way every animated score does:
    /// a static number beside a sweeping ring read as two clocks.
    private func scoreRing(score: Int) -> some View {
        ZStack {
            RingProgress(
                progress: counted ? Double(score) / 100.0 : 0,
                color: AppColors.scoreColor(for: score),
                lineWidth: 5
            )

            CountUpText(
                value: counted ? Double(score) : 0,
                font: .system(size: 20, weight: .bold, design: .rounded),
                color: AppColors.scoreColor(for: score)
            )
        }
        .frame(width: 56, height: 56)
        .motion(AppMotion.reveal.delay(0.2), value: counted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score)")
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
            VoiceLoader()
                .foregroundStyle(AppColors.primary)

            Text("Analyzing your recording...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Encouragement

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
