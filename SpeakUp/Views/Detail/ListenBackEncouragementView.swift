import SwiftUI

struct ListenBackEncouragementView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "headphones")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.primary)

                Text("About Hearing Your Voice")
                    .font(.title3.weight(.bold))
                    .accessibilityFocused($titleFocused)

                Text("Hearing your own voice feels weird, that's totally normal! Everyone sounds different to themselves.\n\nThis is actually a superpower for improvement. Listening back helps you notice patterns you'd never catch in the moment.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GlassButton(
                    title: "Got it, let's listen!",
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    onContinue()
                }

                Button("Not now") {
                    Haptics.light()
                    onCancel()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThickMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            Haptics.light()
            onCancel()
        }
        .onAppear {
            titleFocused = true
        }
    }
}
