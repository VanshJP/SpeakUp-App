import SwiftUI

struct FillerCounterOverlay: View {
    let count: Int

    private var tint: Color { count > 0 ? AppColors.warning : .white.opacity(0.55) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.footnote.weight(.semibold))

            Text("\(count)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.2), value: count)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(count > 0 ? AppColors.warning.opacity(0.3) : .clear, lineWidth: 1)
                }
        }
        .animation(AppMotion.settle, value: count > 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) filler words so far")
    }
}
