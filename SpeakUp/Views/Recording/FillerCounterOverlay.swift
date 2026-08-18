import SwiftUI

/// Live filler count, in the top-bar status row beside the mic indicator.
///
/// It used to be a wide "N / fillers (live)" pill sitting directly above the
/// record button — the one spot on the screen the eye aims at to *stop*, and it
/// mounted the moment recording began, shoving the button down. Filler count is
/// status, not a control, so it belongs with the other status at the top.
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
