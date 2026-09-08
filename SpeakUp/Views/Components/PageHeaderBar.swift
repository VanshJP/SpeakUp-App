import SwiftUI

// MARK: - Root Tab Chrome

extension View {
    /// Chrome for an icon control in a root tab's inline header — the hit
    /// target a nav-bar item had, without the nav bar around it. The filter,
    /// sort and trophy buttons that used to live in the bar wear this and sit
    /// next to what they act on.
    func headerIconChrome() -> some View {
        self
            .font(.body.weight(.semibold))
            .frame(width: 36, height: 36)
            .glassBackground(cornerRadius: 18)
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .contentShape(Rectangle())
    }

    /// Restores the navigation bar a root tab hid, for a page pushed on top of
    /// it.
    ///
    /// SwiftUI resolves toolbar visibility per view in the stack, so a pushed
    /// page gets the default (visible) on its own. This says it out loud
    /// anyway: a detail page that silently loses its Back button is an
    /// expensive thing to be wrong about, and the roots that hide the bar are
    /// exactly the ones that push.
    func restoresNavigationBar() -> some View {
        toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Inline Search Field

/// The search field for a root tab, rendered in the page's own scroll content
/// instead of under a navigation bar.
///
/// `.searchable` costs a nav bar to hang from, and the pair of them ran to
/// ~100pt above the section picker before a single row of content. This is one
/// 44pt row that scrolls away with the content, and it takes the page's
/// trailing action along with it so filters sit beside the thing they filter.
struct InlineSearchField<Accessory: View>: View {
    @Binding var text: String
    let prompt: String
    /// Trailing controls on the same row — a filter or sort menu, typically
    /// wearing `headerIconChrome()`.
    @ViewBuilder var accessory: Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))

                TextField(
                    "",
                    text: $text,
                    prompt: Text(prompt).foregroundStyle(.white.opacity(0.4))
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.white)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(prompt)

                if !text.isEmpty {
                    Button {
                        Haptics.light()
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            // The glyph is small; the tap target is not.
                            .frame(width: 28, height: AppLayout.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .transition(.opacity)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, text.isEmpty ? 14 : 2)
            .frame(height: AppLayout.minHitTarget)
            .glassBackground(cornerRadius: AppLayout.minHitTarget / 2)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            accessory
        }
        .animation(AppMotion.settle, value: text.isEmpty)
    }
}

// MARK: - Pinned Page Header

/// The one row a root tab keeps pinned while its content scrolls: the section
/// picker, plus an optional trailing action.
///
/// Everything else that used to be permanent chrome — the tab's name, the
/// search field — either went away or moved into the scroll.
struct PinnedPageHeader<Picker: View, Accessory: View>: View {
    @ViewBuilder var picker: Picker
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            picker
            accessory
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
