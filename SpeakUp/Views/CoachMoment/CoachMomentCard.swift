import SwiftUI

/// Inline coach note - Today and session-detail surfaces.
///
/// Same grammar as `FriendChallengeCard`: glass, one eyebrow, one body, one
/// capsule CTA, easy dismiss. Never competes with Start speaking.
struct CoachMomentCard: View {
    let moment: CoachMoment
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(tint: tint.opacity(0.10), padding: 16, elevated: moment.surface == .today) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Coach note")
                        .eyebrowStyle(tint)

                    Spacer(minLength: 0)

                    DismissButton(label: "Dismiss coach note", action: onDismiss)
                }

                Text(moment.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(moment.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer(minLength: 0)
                    GlassButton(
                        title: moment.actionTitle,
                        style: .primary,
                        size: .small
                    ) {
                        Haptics.medium()
                        onAccept()
                    }
                    .accessibilityLabel("\(moment.actionTitle), coach note action")
                    .accessibilityHint(moment.title)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch moment.signal {
        case .softLanding, .returnFromLapse:
            return AppColors.info
        case .firstAxisClear, .practiceAnniversary:
            return AppColors.success
        }
    }
}

struct CoachMomentOverlay: View {
    let moment: CoachMoment
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.light()
                    onDismiss()
                }

            // Full screen: squeezed into a 120pt strip inside the card, the
            // burst had nowhere to go.
            ConfettiView(origin: UnitPoint(x: 0.5, y: 0.3))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.primary)
                    .symbolEffect(.bounce, value: reduceMotion ? false : showContent)

                VStack(spacing: 8) {
                    Text("Coach note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(moment.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityFocused($titleFocused)

                    Text(moment.body)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                GlassButton(
                    title: moment.actionTitle,
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    onAccept()
                }

                Button("Not now") {
                    Haptics.light()
                    onDismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal, 28)
            .scaleEffect(showContent ? 1 : 0.92)
            .opacity(showContent ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            Haptics.light()
            onDismiss()
        }
        .onAppear {
            if reduceMotion {
                showContent = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showContent = true
                }
            }
            Haptics.success()
            titleFocused = true
        }
    }

}

#Preview("Card") {
    ZStack {
        AppBackground()
        CoachMomentCard(
            moment: CoachMoment(
                id: "preview",
                signal: .returnFromLapse,
                title: "Welcome back",
                body: "No catch-up quiz. A short calm reset, then today's prompt when you're ready.",
                actionTitle: "Ease back in",
                action: .openConfidence,
                surface: .today,
                detailSlug: nil
            ),
            onAccept: {},
            onDismiss: {}
        )
        .padding()
    }
}
