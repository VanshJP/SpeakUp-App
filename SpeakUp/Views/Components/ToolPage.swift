import SwiftUI

enum ToolPresentation: Equatable {
    case sheet
    case pushed
}

/// A single affordance a tool page may put in its nav bar.
///
/// It exists so "Add your own passage" can live in the chrome instead of
/// taking the top of the scroll view, which is where Read Aloud used to put
/// it - the first thing you saw on a page for reading passages was a form for
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
    /// Set when the page was opened from the outcome browser. The matching
    /// `FocusSection` is scrolled to rather than filtered to: arriving on
    /// "Cut filler words" should put you on that group, not hide the other
    /// six. Map before mask, taken all the way - nothing masks any more.
    var focus: PracticeFocus?
    @ViewBuilder var content: Content

    init(
        tool: PracticeToolKind,
        presentation: ToolPresentation = .sheet,
        action: ToolPageAction? = nil,
        focus: PracticeFocus? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tool = tool
        self.presentation = presentation
        self.action = action
        self.focus = focus
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

            ScrollViewReader { proxy in
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
                .task { await reveal(focus, with: proxy) }
            }
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

    /// Scrolls the arrival focus into view once the presentation has settled.
    ///
    /// A push or a sheet is still animating when `.task` first runs, and the
    /// sections below have not been measured, so an immediate `scrollTo` lands
    /// nowhere. One beat is enough, and being a `.task` it is cancelled if the
    /// page goes away first.
    private func reveal(_ focus: PracticeFocus?, with proxy: ScrollViewProxy) async {
        guard let focus else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        withAnimation(AppMotion.settle) {
            proxy.scrollTo(focus, anchor: .top)
        }
    }
}

// MARK: - Focus Section

/// One outcome heading - title, icon, count, promise - over its items.
///
/// Generic over the item so each page supplies only its own row. The four
/// copies this replaces each wrapped themselves in `AnyView` to satisfy an
/// early `guard`; returning an empty `body` does the same job without the
/// type erasure.
///
/// **This heading is the tool page's only taxonomy.** It used to sit directly
/// under a row of focus pills that said the same eight words in shorter form,
/// so every page carried its grouping twice - once as a control, once as the
/// thing the control acted on. With seven drills and a dozen warm-ups,
/// scrolling past a group is cheaper than deciding to hide it, and a page that
/// arrives pre-filtered hides material the reader never asked to lose. The
/// pills are gone; `ToolPage(focus:)` scrolls here instead.
struct FocusSection<Item: Identifiable, Row: View>: View {
    let focus: PracticeFocus
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(focus.title, icon: focus.icon) {
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(focus.promise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            // Scroll anchor for `ToolPage(focus:)`.
            .id(focus)
        }
    }
}

// MARK: - Source Story Banner

/// "Warming up for …" / "Drilling from …" - shown when a tool is opened from a
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
                    .eyebrowStyle()
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
