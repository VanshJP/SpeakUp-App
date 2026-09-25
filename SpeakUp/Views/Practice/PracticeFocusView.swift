import SwiftUI

/// Pushing a tool page, optionally narrowed to one focus.
///
/// Value-based so a focus page can push a tool page on top of itself without
/// the hub having to thread callbacks down.
struct PracticeToolRoute: Hashable {
    let tool: PracticeToolKind
    var focus: PracticeFocus?
}

/// Pushing the outcome list itself.
struct PracticeImproveRoute: Hashable {}

// MARK: - Link Row

/// A row that pushes, on a `GlassRowGroup`: identity chip, copy, an optional
/// count, chevron.
///
/// The Improve list, the focus page, the Tools landing's entry rows and its
/// search results all push from this row. They used to be a `GlassCard` each -
/// four near-identical recipes at two chip sizes - where a list of rows belongs
/// on one plate (ui-design-system checklist 9). Wrap it in a `NavigationLink`
/// pressed with `RowPressStyle`.
struct PracticeLinkRowLabel: View {
    /// Where the group's hairlines start: under the text, not the chip.
    static let dividerInset: CGFloat = horizontalPadding + chipSize + spacing

    private static let horizontalPadding: CGFloat = 14
    private static let chipSize: CGFloat = 34
    private static let spacing: CGFloat = 12

    let icon: String
    var tint: Color = AppColors.primary
    let title: String
    var subtitle: String?
    var meta: String?
    var count: Int?

    var body: some View {
        HStack(spacing: Self.spacing) {
            IconChip(icon: icon, tint: tint, size: Self.chipSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let meta {
                    Text(meta)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let count {
                StatusPill(text: "\(count)", color: tint)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Improve entry

/// The one row the outcome axis gets on the Library → Tools landing.
///
/// It used to be the axis itself: a header, a caption, and eight full-width
/// rows above the practice grid - two doors to the same forty exercises, and
/// the longest screen in the app. The axis has not been demoted, it has been
/// put where it is decided: every tool page still groups by it. This row is
/// how you enter from the other end, when you know the problem and not the
/// format. It shares one `GlassRowGroup` with the Words entry.
struct PracticeImproveEntryRow: View {
    private var summary: String {
        let focuses = PracticeToolKind.coveredFocuses
        let total = focuses.reduce(0) { running, focus in
            running + PracticeToolKind.tools(for: focus).reduce(0) { $0 + $1.itemCount(for: focus) }
        }
        return "\(focuses.count) outcomes · \(total) exercises"
    }

    var body: some View {
        NavigationLink(value: PracticeImproveRoute()) {
            PracticeLinkRowLabel(
                icon: "target",
                title: "Not sure which one?",
                subtitle: "Start from what you want to change",
                meta: summary
            )
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("Browse by what you want to improve. \(summary).")
    }
}

// MARK: - Improve list

/// The eight outcomes, on their own screen.
struct PracticeImproveListView: View {
    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick what you want to change. Every exercise that trains it, in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassRowGroup(dividerInset: PracticeLinkRowLabel.dividerInset) {
                        ForEach(PracticeToolKind.coveredFocuses) { focus in
                            PracticeFocusRow(focus: focus)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Improve")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - Focus Row

/// One outcome, as a row on the Improve list or in Tools search results.
/// Always inside a `GlassRowGroup`.
struct PracticeFocusRow: View {
    let focus: PracticeFocus

    /// Rows are only built from `PracticeToolKind.coveredFocuses`, so there is
    /// always at least one tool here.
    private var toolSummary: String {
        let tools = PracticeToolKind.tools(for: focus)
        let total = tools.reduce(0) { $0 + $1.itemCount(for: focus) }
        let names = tools.map(\.shortTitle).joined(separator: " · ")
        return "\(total) across \(names)"
    }

    var body: some View {
        NavigationLink(value: focus) {
            PracticeLinkRowLabel(
                icon: focus.icon,
                tint: focus.color,
                title: focus.title,
                meta: toolSummary
            )
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(focus.title). \(focus.promise). \(toolSummary)")
    }
}

// MARK: - Focus Detail

/// Every format that trains one outcome, on one page.
///
/// This is the screen that answers "aren't warm-ups drills too?". They are
/// both practice; they differ in how long they take and whether the mic is
/// open. Listing them together under "Be understood" - tongue twisters,
/// articulation warm-ups, and the precision read-aloud passages - makes the
/// relationship visible instead of leaving it to be inferred from four
/// separate tool pages.
struct PracticeFocusDetailView: View {
    let focus: PracticeFocus

    private var tools: [PracticeToolKind] {
        PracticeToolKind.tools(for: focus)
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // One line under the nav title, like every tool page. The
                    // page used to open on its own title again in title3,
                    // under a nav bar that already named it.
                    Text(focus.promise)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassRowGroup(dividerInset: PracticeLinkRowLabel.dividerInset) {
                        ForEach(tools) { tool in
                            toolRow(tool)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(focus.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func toolRow(_ tool: PracticeToolKind) -> some View {
        let count = tool.itemCount(for: focus)

        return NavigationLink(value: PracticeToolRoute(tool: tool, focus: focus)) {
            // The format line, not the outcome line. On this page the outcome
            // is the heading - what differs between these rows is what the
            // next few minutes cost.
            PracticeLinkRowLabel(
                icon: tool.icon,
                tint: tool.color,
                title: tool.title,
                subtitle: tool.format,
                count: count
            )
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(
            "\(tool.title). \(count) \(tool.itemNoun)\(count == 1 ? "" : "s") for \(focus.title). \(tool.format)"
        )
    }
}
