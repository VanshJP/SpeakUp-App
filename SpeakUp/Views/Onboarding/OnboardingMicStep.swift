import SwiftUI

// MARK: - Microphone

struct OnboardingMicStep: View {
    let counter: String?
    let viewModel: OnboardingViewModel
    let onContinue: () -> Void

    private var hasPermission: Bool { viewModel.hasMicPermission }
    private var isRequesting: Bool { viewModel.isRequestingMicPermission }
    private var heardVoice: Bool { viewModel.hasHeardVoice }

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: hasPermission ? "Sound check" : "Let's make sure we can hear you",
            subtitle: subtitle
        ) {
            GlassCard(tint: hasPermission ? AppColors.glassTintPrimary : nil, padding: 16) {
                VStack(spacing: 14) {
                    LiveMicWaveform(viewModel: viewModel, isLive: hasPermission)
                        .frame(height: 104)
                        .opacity(hasPermission ? 1 : 0.3)

                    if heardVoice {
                        StatusPill(
                            text: "Loud and clear",
                            color: AppColors.success,
                            glyph: .icon("checkmark")
                        )
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(hasPermission ? "Listening…" : "Microphone off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .motion(AppMotion.settle, value: heardVoice)
            }
        } footer: {
            if hasPermission {
                OnboardingCTA(title: "I'm ready", action: onContinue)
            } else {
                OnboardingCTA(
                    title: isRequesting ? "Asking…" : "Allow microphone",
                    icon: isRequesting ? nil : "arrow.right",
                    isLoading: isRequesting,
                    action: { Task { await viewModel.requestMicAndStartTest() } }
                )
            }
        }
        .motion(AppMotion.settle, value: hasPermission)
    }

    /// "Sound check" is the load-bearing reframe: roadies do sound checks;
    /// nobody judges a sound check. Nothing here is kept or scored, and the
    /// copy never asks the user to perform.
    private var subtitle: String {
        if !hasPermission {
            return "Big Talk listens only while you're recording. Audio stays on this iPhone."
        }
        if heardVoice {
            return "Mic looks good. Nothing is saved until you press record."
        }
        return "Say anything. Try \"testing, one two three.\""
    }
}

private struct LiveMicWaveform: View {
    let viewModel: OnboardingViewModel
    let isLive: Bool

    var body: some View {
        OnboardingWaveform(level: isLive ? viewModel.micLevel : 0)
    }
}

/// Live input meter. Centre bars react hardest so the shape reads as a voice
/// rather than a level bar.
///
/// Drawn as one `Canvas` on a `TimelineView` clock. It used to be 28 sibling
/// views, each holding its own `@State` phase on a `repeatForever` animation:
/// 28 view bodies re-evaluating every frame for what is a single picture.
struct OnboardingWaveform: View {
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 28
    private let spacing: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                let phase = context.date.timeIntervalSinceReferenceDate * (2 * Double.pi / 0.6)
                let barWidth = max(1, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))

                for index in 0..<barCount {
                    let position = Double(index) / Double(barCount - 1)
                    let distance = abs(position - 0.5) * 2
                    let centerWeight = 1 - distance * 0.7
                    let noise = (sin(phase + Double(index) * 0.4) + 1) / 2
                    let amplitude = max(0.05, Double(level)) * centerWeight * (0.6 + noise * 0.6)
                    let height = max(5, CGFloat(amplitude) * size.height)
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(AppColors.primary))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
