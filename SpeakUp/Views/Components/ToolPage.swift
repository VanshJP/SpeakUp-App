import SwiftUI

/// Shared skeleton for the four practice-tool pages — Warm-Ups, Drills,
/// Read Aloud, Calm.
///
/// They had drifted into four dialects: three different content paddings, a
/// nav title that disagreed with the tool catalog ("Quick Drills" vs `Drills`),
/// filter rows that were double-inset on one page and flush on another, and a
/// grid of fixed-height tiles on one page where the rest used rows. All of the
/// page chrome lives here now, so a fifth dialect can't be invented by
/// accident — a tool page supplies its filters and its items, nothing else.
struct ToolPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let tool: PracticeToolKind
    /// Pushed onto a caller-owned `NavigationStack` (Library → Tools): no inner
    /// stack, and the sheet-only ✕ gives way to the system back button.
    var isPushed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        if isPushed {
            page
        } else {
            NavigationStack { page }
        }
    }

    private var page: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // The only header: the nav bar already names the page, so
                    // this says what the tool gets you and gets out of the way.
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
            // The ✕ is a sheet affordance; a pushed page closes with Back.
            if !isPushed {
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
        }
    }
}

// MARK: - Filter Bar

/// The horizontal pill row every tool page filters with. Owning the spacing
/// here is the point: one page used to inset its pills inside the already
/// padded column, so its filters sat visibly further in than its cards.
///
/// `scrollClipDisabled` lets the pills run to the screen edge while the column
/// around them keeps its padding — the row reads as scrollable instead of
/// stopping short.
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
    }
}
