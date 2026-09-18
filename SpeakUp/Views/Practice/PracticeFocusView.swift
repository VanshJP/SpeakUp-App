import SwiftUI

/// Pushing a tool page, optionally narrowed to one focus.
///
/// Value-based so a focus page can push a tool page on top of itself without
/// the hub having to thread callbacks down.
struct PracticeToolRoute: Hashable {
    let tool: PracticeToolKind
    var focus: PracticeFocus?
}

// MARK: - Focus Row

/// One outcome, as offered on the Library → Tools landing.
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
            GlassCard(cornerRadius: 16, tint: focus.color.opacity(0.06), padding: 13) {
                HStack(spacing: 12) {
                    Image(systemName: focus.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(focus.color)
                        .frame(width: 34, height: 34)
                        .background { Circle().fill(focus.color.opacity(0.18)) }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(focus.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Text(toolSummary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("\(focus.title). \(focus.promise). \(toolSummary)")
    }
}

// MARK: - Focus Detail

/// Every format that trains one outcome, on one page.
///
/// This is the screen that answers "aren't warm-ups drills too?". They are
/// both practice; they differ in how long they take and whether the mic is
/// open. Listing them together under "Be understood" — tongue twisters,
/// articulation warm-ups, and the precision read-aloud passages — makes the
/// relationship visible instead of leaving it to be inferred from four
/// separate tool pages.
struct PracticeFocusDetailView: View {
    let focus: PracticeFocus

    private var tools: [PracticeToolKind] {
        PracticeToolKind.tools(for: focus)
    }

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    VStack(spacing: 12) {
                        ForEach(tools) { tool in
                            toolCard(tool)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(focus.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(focus.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(focus.promise)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func toolCard(_ tool: PracticeToolKind) -> some View {
        let count = tool.itemCount(for: focus)

        return NavigationLink(value: PracticeToolRoute(tool: tool, focus: focus)) {
            GlassCard(cornerRadius: 16, tint: tool.color.opacity(0.06), padding: 14) {
                HStack(spacing: 13) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tool.color)
                        .frame(width: 36, height: 36)
                        .background { Circle().fill(tool.color.opacity(0.18)) }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        // The format line, not the outcome line. On this page
                        // the outcome is the heading — what differs between
                        // these four rows is what the next few minutes cost.
                        Text(tool.format)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Text("\(count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(tool.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(tool.color.opacity(0.18)) }
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(
            "\(tool.title). \(count) \(tool.itemNoun)\(count == 1 ? "" : "s") for \(focus.title). \(tool.format)"
        )
    }
}
