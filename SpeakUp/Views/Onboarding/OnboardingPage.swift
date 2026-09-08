import SwiftUI

// MARK: - Page Scaffold

/// Shared layout for non-hero onboarding steps: header, scrolling body, pinned footer.
struct OnboardingPage<Content: View, Footer: View>: View {
    private let counter: String?
    private let title: String
    private let subtitle: String?
    private let content: Content
    private let footer: Footer

    init(
        counter: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.counter = counter
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Glyph

struct OnboardingGlyph: View {
    let icon: String
    var tint: Color = AppColors.primary
    var size: CGFloat = 38

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

struct OnboardingChoiceCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color { AppColors.primary }

    var body: some View {
        Button(action: action) {
            GlassCard(
                tint: isSelected ? tint : nil,
                padding: 14,
                accentBorder: isSelected ? tint : nil
            ) {
                HStack(spacing: 12) {
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

struct OnboardingBullet: View {
    let icon: String
    let text: String
    var tint: Color = AppColors.primary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Fixed width so copy left-aligns; height unbound so glyph sits on first line.
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Brand Orb

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
