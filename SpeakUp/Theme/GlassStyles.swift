import SwiftUI

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil

    @Environment(\.glassAppearance) private var glassAppearance

    func body(content: Content) -> some View {
        let glass: Glass = {
            if let tint { return .regular.tint(tint) }
            return .regular.tint(glassAppearance.glassTint)
        }()
        content
            .environment(\.isOnGlass, true)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            // Matches `GlassCard`'s unelevated shadow - same name, same plate.
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Material fallback when a non-card surface still wants a soft glass plate
    /// (text fields, compact chips that are not `GlassCard`).
    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Round, interactive glass behind an icon-only control - a runner's ✕
    /// and transport buttons.
    func glassCircle() -> some View {
        self.glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Glass Section Header

/// A page chapter's name. Text only: the grey glyph each header used to carry
/// was decoration (an ellipsis for "Review", a wrench for "Prep tools"), and
/// half the headers had one while History's weeks and Learn's chapters did
/// not, so the same role wore two faces across the tabs.
struct GlassSectionHeader<Accessory: View>: View {
    let title: String
    var accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer()
            accessory
        }
        .padding(.horizontal, 4)
    }
}

extension GlassSectionHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Row Label Style

/// A settings row's name: its glyph in a fixed column, so every title on a
/// card starts on the same line whatever each symbol's width. Plain `Label`s
/// drifted by up to 10pt - "Audio Cues" sat right of "Speaker Level" on the
/// same card. Apply it to the card, not each row.
struct RowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .frame(width: 24)
            configuration.title
        }
    }
}

extension LabelStyle where Self == RowLabelStyle {
    static var row: RowLabelStyle { RowLabelStyle() }
}

// MARK: - Glass Card Title

/// Card-level title row - the quieter sibling of `GlassSectionHeader`: same
/// anatomy (icon, name, trailing accessory), one register down in size.
/// Chart cards and multi-card sections use it so card headers stop being
/// hand-rolled `Label`s with drifting fonts, while section headers keep the
/// headline weight above them.
struct GlassCardTitle<Accessory: View>: View {
    let title: String
    let icon: String?
    var accessory: Accessory

    init(_ title: String, icon: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            accessory
        }
    }
}

extension GlassCardTitle where Accessory == EmptyView {
    init(_ title: String, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}
