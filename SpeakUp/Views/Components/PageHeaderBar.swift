import SwiftUI

// MARK: - Root Tab Chrome

extension View {
    func headerIconChrome() -> some View {
        self
            .font(.body.weight(.semibold))
            .frame(width: 36, height: 36)
            .glassBackground(cornerRadius: 18)
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .contentShape(Rectangle())
    }

    func restoresNavigationBar() -> some View {
        toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Inline Search Field

struct InlineSearchField<Accessory: View>: View {
    @Binding var text: String
    let prompt: String
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
