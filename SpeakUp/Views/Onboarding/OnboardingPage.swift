import SwiftUI

// MARK: - Page Scaffold

/// Shared layout for every non-hero onboarding step: a left-aligned header
/// (step counter, glyph, title, subtitle), a scrolling body, and a pinned
/// footer that holds the call to action.
///
/// Every step used to hand-roll its own centred stack with bespoke font sizes,
/// which is what made the flow read as a template rather than part of the app.
/// Routing all pages through one scaffold keeps the header rhythm, spacing,
/// and CTA placement identical to the rest of the surfaces.
struct OnboardingPage<Content: View, Footer: View>: View {
    private let counter: String?
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let iconTint: Color
    private let content: Content
    private let footer: Footer

    init(
        counter: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: Color = AppColors.primary,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.counter = counter
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let icon {
                OnboardingGlyph(icon: icon, tint: iconTint)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let counter {
                    Text(counter)
                        .eyebrowStyle()
                }

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Glyph

/// Tinted rounded-square icon. Same treatment the settings surfaces use for
/// section glyphs, so the onboarding header reads as the same product.
struct OnboardingGlyph: View {
    let icon: String
    var tint: Color = AppColors.primary
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .stroke(AppColors.cardStroke, lineWidth: 0.5)
                    }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Primary CTA

/// The one loud element on every page. Wraps `GlassButton` so the disabled
/// treatment and the trailing chevron stay identical across all eleven steps.
struct OnboardingCTA: View {
    let title: String
    var icon: String? = "arrow.right"
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        GlassButton(
            title: title,
            icon: icon,
            iconPosition: .right,
            style: .primary,
            size: .large,
            isLoading: isLoading,
            fullWidth: true,
            action: action
        )
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .motion(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

/// Quiet tertiary action under the CTA ("Skip for now", "No thanks").
struct OnboardingTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Choice Card

/// Selectable row used by the goal step. Selection is carried by the card's
/// accent border and tint rather than a coloured glow, matching how selection
/// reads everywhere else in the app.
struct OnboardingChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(
                tint: isSelected ? tint : nil,
                padding: 12,
                accentBorder: isSelected ? tint : nil
            ) {
                HStack(spacing: 12) {
                    OnboardingGlyph(icon: icon, tint: tint, size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? tint : Color.white.opacity(0.18))
                        .symbolEffect(.bounce, value: isSelected)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Bullet Row

/// Icon + copy line used inside explanatory cards.
struct OnboardingBullet: View {
    let icon: String
    let text: String
    var tint: Color = AppColors.primary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Numbered Step Row

/// One beat of the "how it works" explainer.
struct OnboardingNumberedRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.statValue)
                .foregroundStyle(AppColors.primary)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(AppColors.primary.opacity(0.15))
                        .overlay { Circle().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Summary Row

/// Label/value line used on the ready step recap.
struct OnboardingSummaryRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = AppColors.primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Brand Orb

/// The brand orb, used only on the two hero steps. Elsewhere the header glyph
/// carries the page identity — repeating the orb on every page was the single
/// biggest reason the flow felt generated rather than designed.
struct OnboardingOrb: View {
    let size: CGFloat
    var glowColor: Color = AppColors.primary

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Image("BigTalkOrb")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: glowColor.opacity(0.45), radius: size * 0.16, y: 6)
            .shadow(color: glowColor.opacity(0.22), radius: size * 0.36, y: 12)
            .scaleEffect(pulseScale)
            .ambientLoop(AppMotion.ambient(duration: 2.8)) {
                pulseScale = 1.03
            }
            .accessibilityHidden(true)
    }
}
