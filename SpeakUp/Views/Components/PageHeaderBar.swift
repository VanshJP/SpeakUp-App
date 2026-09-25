import SwiftUI

// MARK: - Root Tab Chrome

extension View {
    /// The trailing accessory on a section's search row - the filter/sort menu
    /// on Prompts, Stories and History, and the Learn trophy.
    ///
    /// It is exactly `AppLayout.minHitTarget` square with the capsule radius
    /// `InlineSearchField` uses, so the icon is the same height as the field it
    /// sits beside instead of a smaller plate floating in a 44pt box. Sizing the
    /// glass *is* the hit target here - there is no second `.frame` to pad out.
    func headerIconChrome() -> some View {
        self
            .font(.body.weight(.semibold))
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .glassBackground(cornerRadius: AppLayout.minHitTarget / 2)
            .contentShape(Rectangle())
    }

    func restoresNavigationBar() -> some View {
        toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Page Title

/// The name a root tab opens on when it has no section picker to wear as its
/// header - Today, Learn, Settings. Kicker over a title2 name, an optional
/// line under it, one accessory at the trailing edge.
///
/// Today and Learn each hand-rolled this and Settings had none, so it opened
/// on a "Practice" section header that read as the page's name.
struct PageTitle<Detail: View, Accessory: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var detail: Detail
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                detail
            }

            Spacer(minLength: 8)

            accessory
        }
        .padding(.top, 4)
    }
}

extension PageTitle where Detail == EmptyView {
    init(kicker: String, title: String, @ViewBuilder accessory: () -> Accessory) {
        self.init(kicker: kicker, title: title, detail: { EmptyView() }, accessory: accessory)
    }
}

extension PageTitle where Detail == EmptyView, Accessory == EmptyView {
    init(kicker: String, title: String) {
        self.init(kicker: kicker, title: title, detail: { EmptyView() }, accessory: { EmptyView() })
    }
}

// MARK: - Inline Search Field

/// A filter the search is narrowed to, drawn as a removable pill at the
/// field's leading edge - a search token. Prompts used to spend a whole row
/// under the field on "‹ All categories · 40 prompts" and another on the
/// difficulty tag; as tokens, "you are inside X" costs no height at all.
struct SearchScope: Identifiable {
    let title: String
    var icon: String? = nil
    var tint: Color = .white
    /// Spoken as the pill's action, e.g. "Show all categories".
    let removeLabel: String
    let onRemove: () -> Void

    var id: String { title }
}

struct InlineSearchField<Accessory: View>: View {
    @Binding var text: String
    let prompt: String
    var scopes: [SearchScope] = []
    @ViewBuilder var accessory: Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))

                ForEach(scopes) { scope in
                    scopePill(scope)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

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
        .animation(AppMotion.snap, value: scopes.map(\.id))
    }

    private func scopePill(_ scope: SearchScope) -> some View {
        Button {
            Haptics.light()
            scope.onRemove()
        } label: {
            HStack(spacing: 4) {
                if let icon = scope.icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                }
                Text(scope.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(scope.tint)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(scope.tint.opacity(0.18)))
            // The pill is small; the tap target is the field's full height.
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(scope.title)
        .accessibilityHint(scope.removeLabel)
    }
}

// MARK: - Pinned Page Header

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
