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
                IconChip(icon: "headphones", size: 72)

                Text("About hearing your voice")
                    .font(.title3.weight(.bold))
                    .accessibilityFocused($titleFocused)

                Text("Hearing your own voice can feel unfamiliar. Everyone sounds different to themselves.\n\nListening back once can help you notice patterns that are hard to catch while speaking.")
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

                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressStyle())
            }
            .padding(24)
            // Liquid Glass like every other plate; a material slab with a
            // hairline rim read as a flat grey card over the dimmed page.
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
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
