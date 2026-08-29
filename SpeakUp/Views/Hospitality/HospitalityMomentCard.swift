import SwiftUI

/// Inline hospitality card — Today and session-detail surfaces.
///
/// Same grammar as `FriendChallengeCard`: glass, one eyebrow, one body, one
/// capsule CTA, optional dismiss. Not a second Start Speaking.
struct HospitalityMomentCard: View {
    let moment: HospitalityMoment
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(tint: tint, padding: 16, elevated: moment.surface == .today) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .textCase(.uppercase)
                        .tracking(0.7)

                    Spacer(minLength: 0)

                    Button("Dismiss", systemImage: "xmark") {
                        Haptics.light()
                        onDismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Dismiss")
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
                    Button {
                        Haptics.medium()
                        onAccept()
                    } label: {
                        Text(moment.actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background { Capsule().fill(Color.white.opacity(0.94)) }
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel(moment.actionTitle)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var eyebrow: String {
        moment.isLegend ? "A little something" : "Looking out for you"
    }

    private var tint: Color {
        switch moment.signal {
        case .softLanding, .returnFromLapse:
            return AppColors.info
        case .streakMilestone, .fillerBreakthrough, .firstAxisClear, .practiceAnniversary:
            return AppColors.success
        case .lifeContextPrep:
            return AppColors.primary
        }
    }
}

/// Full-screen overlay for rare legends (streak blocks, anniversaries).
struct HospitalityMomentOverlay: View {
    let moment: HospitalityMoment
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                ConfettiView()
                    .frame(height: 120)

                Image(systemName: overlayIcon)
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.primary)
                    .symbolEffect(.bounce, value: showContent)

                VStack(spacing: 8) {
                    Text("Unreasonable hospitality")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(moment.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(moment.body)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button {
                    Haptics.medium()
                    onAccept()
                } label: {
                    Text(moment.actionTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppColors.primary)
                        )
                }
                .buttonStyle(GlassPressStyle())

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
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showContent = true
            }
            Haptics.success()
        }
    }

    private var overlayIcon: String {
        switch moment.gesture {
        case .anniversaryToast: return "gift.fill"
        case .victoryMontage: return "flame.fill"
        case .axisToast: return "checkmark.seal.fill"
        default: return "sparkles"
        }
    }
}

#Preview("Card") {
    ZStack {
        AppBackground()
        HospitalityMomentCard(
            moment: HospitalityMoment(
                id: "preview",
                signal: .returnFromLapse,
                gesture: .softReturn,
                title: "Welcome back",
                body: "It's been 5 days. No lecture — a calm reset, then today's prompt.",
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
