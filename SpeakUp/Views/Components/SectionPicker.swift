import SwiftUI

/// Shared pinned/sub-section selector used by History, Library, and ProgressCharts.
/// Replaces the previously duplicated inline pickers in HistoryView,
/// PracticeHubView, and ProgressChartsView so the selector is visually
/// identical wherever it appears.
struct SectionPicker<Section: Hashable & Identifiable>: View {
    enum Style { case regular, compact }
    enum Layout { case equalWidth, scrollable }

    let sections: [Section]
    @Binding var selection: Section
    let label: (Section) -> String
    let icon: (Section) -> String?
    var style: Style = .regular
    var layout: Layout = .equalWidth
    var framed: Bool = true

    @Namespace private var pickerNamespace

    init(
        sections: [Section],
        selection: Binding<Section>,
        label: @escaping (Section) -> String,
        icon: @escaping (Section) -> String? = { _ in nil },
        style: Style = .regular,
        layout: Layout = .equalWidth,
        framed: Bool = true
    ) {
        self.sections = sections
        self._selection = selection
        self.label = label
        self.icon = icon
        self.style = style
        self.layout = layout
        self.framed = framed
    }

    var body: some View {
        Group {
            switch layout {
            case .equalWidth:
                row
            case .scrollable:
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.hidden)
            }
        }
        .background {
            if framed {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.05), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                ,
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .shadow(color: framed ? .black.opacity(0.2) : .clear, radius: framed ? 8 : 0, y: framed ? 3 : 0)
    }

    private var row: some View {
        HStack(spacing: itemSpacing) {
            ForEach(sections) { section in
                item(for: section)
            }
        }
        .padding(framed ? 6 : 0)
    }

    @ViewBuilder
    private func item(for section: Section) -> some View {
        let isSelected = selection == section
        Button {
            guard selection != section else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selection = section
            }
        } label: {
            HStack(spacing: iconLabelSpacing) {
                if let symbol = icon(section) {
                    Image(systemName: symbol)
                        .font(iconFont)
                }
                Text(label(section))
                    .font(labelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
            .frame(maxWidth: layout == .equalWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.primary.opacity(0.85),
                                    AppColors.primary.opacity(0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .shadow(color: AppColors.primary.opacity(0.45), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "sectionPickerSelection", in: pickerNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Style values

    private var itemSpacing: CGFloat { style == .regular ? 6 : 4 }
    private var iconLabelSpacing: CGFloat { style == .regular ? 6 : 4 }
    private var horizontalPadding: CGFloat {
        switch (style, layout) {
        case (.regular, .equalWidth): return 0
        case (.regular, .scrollable): return 14
        case (.compact, _): return 12
        }
    }
    private var verticalPadding: CGFloat { style == .regular ? 10 : 6 }
    private var pillCornerRadius: CGFloat { style == .regular ? 14 : 12 }
    private var iconFont: Font { style == .regular ? .system(size: 13, weight: .semibold) : .caption2.weight(.semibold) }
    private var labelFont: Font { style == .regular ? .subheadline.weight(.semibold) : .caption.weight(.semibold) }
}
