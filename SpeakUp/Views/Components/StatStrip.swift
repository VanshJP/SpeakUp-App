import SwiftUI

/// Shared compact stats strip used in History (quick stats / streak)
/// and Library (prompts stats). Replaces the previously duplicated
/// StreakStatItem and PromptStatItem inline structs so every stats bar
/// uses the same vertical layout, fonts, and dividers.
struct StatStrip: View {
    let items: [Item]
    var padding: CGFloat
    var dividerHeight: CGFloat
    var animateNumericChanges: Bool

    init(
        items: [Item],
        padding: CGFloat = 14,
        dividerHeight: CGFloat = 40,
        animateNumericChanges: Bool = true
    ) {
        self.items = items
        self.padding = padding
        self.dividerHeight = dividerHeight
        self.animateNumericChanges = animateNumericChanges
    }

    var body: some View {
        GlassCard(padding: padding) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    StatStripItem(item: item, animateNumericChanges: animateNumericChanges)
                    if index < items.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: dividerHeight)
    }

    // MARK: - Item

    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let value: String
        let label: String
        let color: Color
        var isHighlighted: Bool = false

        init(
            icon: String,
            value: String,
            label: String,
            color: Color,
            isHighlighted: Bool = false
        ) {
            self.icon = icon
            self.value = value
            self.label = label
            self.color = color
            self.isHighlighted = isHighlighted
        }
    }
}

private struct StatStripItem: View {
    let item: StatStrip.Item
    let animateNumericChanges: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isHighlighted ? item.color : item.color.opacity(0.85))

                Text(item.value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.color)
                    .modifier(NumericTransitionModifier(enabled: animateNumericChanges))
            }

            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NumericTransitionModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}
