import Charts
import SwiftUI

/// The two personalised steps that run ahead of the offer.
///
/// They exist because the strongest argument for keeping a practice tool is the
/// practice already in it. Step one is what the user has moved so far; step two
/// is what is still on the table and how slowly the free tier gets there. Both
/// are built only from the user's own recordings — no claims about other people,
/// no invented projection curve.
///
/// Neither step is shown to a user with nothing in their library: `PaywallView`
/// drops straight to the offer, because an empty progress screen in front of a
/// price is a toll booth.

// MARK: - Step 1 — how far you've come

struct PaywallProgressStep: View {
    let proof: PaywallProof

    var body: some View {
        PageScrollView {
            VStack(spacing: 18) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                journeyCard

                if proof.recentScores.count >= 3 { trendCard }

                statsRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var title: String {
        guard let gain = proof.gain, gain > 0 else { return "You've put in the reps." }
        return "You're \(gain) points better than your first take."
    }

    private var subtitle: String {
        let takes = proof.takes == 1 ? "1 take" : "\(proof.takes) takes"
        return "\(takes), all scored on your own device. Here's the movement."
    }

    /// First score to best score, side by side. The delta is the whole point of
    /// the screen, so it gets the middle and the colour.
    private var journeyCard: some View {
        GlassCard(cornerRadius: 22, padding: 18) {
            HStack(alignment: .center, spacing: 0) {
                milestone(
                    label: "First take",
                    value: proof.firstScore ?? 0,
                    color: AppColors.scoreColor(for: proof.firstScore ?? 0)
                )

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tertiary)
                    if let gain = proof.gain, gain > 0 {
                        Text("+\(gain)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.success)
                    }
                }
                .frame(width: 54)

                milestone(
                    label: "Your best",
                    value: proof.best,
                    color: AppColors.scoreColor(for: proof.best)
                )
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("First take \(proof.firstScore ?? 0), best \(proof.best)")
    }

    private func milestone(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var trendCard: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR LAST \(proof.recentScores.count) TAKES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                Chart(Array(proof.recentScores.indices), id: \.self) { index in
                    AreaMark(
                        x: .value("Take", index),
                        y: .value("Score", proof.recentScores[index])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.primary.opacity(0.32), AppColors.primary.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Take", index),
                        y: .value("Score", proof.recentScores[index])
                    )
                    .foregroundStyle(AppColors.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 74)
                .accessibilityLabel("Your recent scores, oldest to newest")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("\(proof.takes)", proof.takes == 1 ? "take" : "takes", .white)
            statTile("\(proof.streak)", "day streak", AppColors.warning)
        }
    }

    private func statTile(_ value: String, _ label: String, _ color: Color) -> some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Step 2 — what's left

struct PaywallHeadroomStep: View {
    let proof: PaywallProof
    let headroom: PaywallHeadroom

    var body: some View {
        PageScrollView {
            VStack(spacing: 18) {
                Text("There are \(headroom.points) points still on the table.")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Your recent takes average \(headroom.current). This is where the missing points are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                gapsCard

                if let months = proof.monthsToCloseOnFreeTier { paceCard(months: months) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var gapsCard: some View {
        GlassCard(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(headroom.gaps) { gap in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(gap.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Text("+\(gap.worth) pts")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppColors.subscoreTone(gap.toneIndex))
                        }

                        TickMeter(
                            fraction: Double(gap.value) / 100,
                            color: AppColors.subscoreTone(gap.toneIndex)
                        )
                        .frame(height: 12)

                        Text("At \(gap.value) now")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(gap.name), at \(gap.value), worth \(gap.worth) more points")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The one forward-looking number on the paywall, and it is arithmetic on
    /// the user's own rate of improvement rather than a promise about outcomes.
    private func paceCard(months: Int) -> some View {
        GlassCard(cornerRadius: 20, tint: AppColors.warning.opacity(0.10), padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.warning)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("On the free tier, that's about \(paceLabel(months)) of practice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(FreeTierPolicy.expired.monthlyAnalyses) analyses every 30 days, at the rate you've been improving. Unlimited practice is the part you control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paceLabel(_ months: Int) -> String {
        guard months >= 24 else { return months == 1 ? "a month" : "\(months) months" }
        return "\(months / 12) years"
    }
}
