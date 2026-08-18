import SwiftUI

/// Running caption of what the speaker just said. Lives in the slot the STAR
/// overlay used to occupy — glanceable, not tappable, and a POD so the 10 Hz
/// timer does not rebuild it unless the tokens actually changed.
struct LiveCaptionView: View {
    let tokens: [LiveCaptionToken]

    var body: some View {
        if tokens.isEmpty {
            EmptyView()
        } else {
            captionText
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 14)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Concatenated `Text` so hesitations can take `AppColors.warning` without
    /// an `AttributedString` font dance, and so the line still wraps.
    private var captionText: Text {
        tokens.enumerated().reduce(Text("")) { acc, pair in
            let (index, token) = pair
            let space = index == 0 ? Text("") : Text(" ")
            let word = Text(token.text)
                .font(.subheadline.weight(token.isFiller ? .semibold : .medium))
                .foregroundStyle(token.isFiller ? AppColors.warning : Color.white.opacity(0.92))
            return acc + space + word
        }
    }
}
