import SwiftUI

/// A number that counts through every value on its way to the target.
/// `value`. Under Reduce Motion the value simply lands, which is correct.
struct CountUpText: View, Animatable {
    var value: Double
    var font: Font = .displayNumeral
    var color: Color = .white

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

#Preview {
    struct Demo: View {
        @State private var shown = false
        var body: some View {
            VStack(spacing: 24) {
                CountUpText(value: shown ? 84 : 0, color: AppColors.scoreHigh)
                GlassButton(title: "Replay", style: .secondary) {
                    shown = false
                    withAnimation(AppMotion.reveal) { shown = true }
                }
            }
            .onAppear { withAnimation(AppMotion.reveal) { shown = true } }
        }
    }
    return Demo()
        .padding(40)
        .background(AppBackground())
}
