import SwiftUI

enum ToolPresentation: Equatable {
    case sheet
    case pushed
}

/// A single affordance a tool page may put in its nav bar.
///
/// It exists so "Add your own passage" can live in the chrome instead of
/// taking the top of the scroll view, which is where Read Aloud used to put
/// it — the first thing you saw on a page for reading passages was a form for
/// writing one, and the catalog started below the fold. Library already solves
/// this for Prompts and Stories with a FAB; a tool page is pushed and titled,
/// so the nav bar is the equivalent spot.
struct ToolPageAction {
    let icon: String
    /// Spoken label. Also the menu title if this ever grows a menu.
    let label: String
    let perform: () -> Void

    init(icon: String, label: String, perform: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.perform = perform
    }
}

struct ToolPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let tool: PracticeToolKind
    var presentation: ToolPresentation = .sheet
    var action: ToolPageAction?
    @ViewBuilder var content: Content

    init(
        tool: PracticeToolKind,
        presentation: ToolPresentation = .sheet,
        action: ToolPageAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tool = tool
        self.presentation = presentation
        self.action = action
        self.content = content()
    }

    var body: some View {
        switch presentation {
        case .sheet:
            NavigationStack { hostedBody }
        case .pushed:
            hostedBody
        }
    }

    private var hostedBody: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tool.outcome)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close")
                }
            }

            if let action {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        action.perform()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(action.label)
                }
            }
        }
    }
}

// MARK: - Filter Bar

struct ToolFilterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Source Story Banner

/// "Warming up for …" / "Drilling from …" — shown when a tool is opened from a
/// Story via Library send-to. One component because the two callers had
/// hand-rolled the same card with different tints and corner treatments.
struct SourceStoryBanner: View {
    let eyebrow: String
    let title: String
    var tint: Color = AppColors.primary
    var trailingTag: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let trailingTag {
                Text(trailingTag)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(tint.opacity(0.18)) }
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
