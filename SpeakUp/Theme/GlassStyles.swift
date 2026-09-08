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
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            // Matches `GlassCard`'s unelevated shadow — same name, same plate.
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Section Header

struct GlassSectionHeader<Accessory: View>: View {
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
    init(_ title: String, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}

// MARK: - Glass Card Title

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
