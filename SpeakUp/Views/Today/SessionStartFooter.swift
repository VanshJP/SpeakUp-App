import SwiftUI

// MARK: - Session Start Footer

struct SessionStartFooter: View {
    var startTitle = "Start Speaking"
    var showFreeTalk = true
    let startHint: String
    let freeHint: String
    let onStart: () -> Void
    let onFreeTalk: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            GlassButton(
                title: startTitle,
                icon: "mic.fill",
                style: .primary,
                size: .large,
                fullWidth: true
            ) {
                Haptics.medium()
                onStart()
            }
            .accessibilityHint(startHint)

            if showFreeTalk {
                Button {
                    Haptics.light()
                    onFreeTalk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Talk without a prompt")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(freeHint)
            }
        }
    }
}
