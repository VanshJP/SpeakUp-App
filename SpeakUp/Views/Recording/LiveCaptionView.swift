import SwiftUI

/// Running caption of what the speaker just said. Lives in the slot the STAR
/// overlay used to occupy — glanceable, not tappable, and a POD so the 10 Hz
/// timer does not rebuild it unless the tokens actually changed.
///
/// The slot is a fixed two lines from the first frame and the card fades in on
/// top of it. Sizing to the words instead would shove the centred timer down
/// when the first word lands, then again every time the caption re-wraps
/// between one line and two — which is every few words, mid-take.
struct LiveCaptionView: View {
    let tokens: [LiveCaptionToken]

    var body: some View {
        captionText
            // Base font only matters before the first word: an empty `Text`
            // would otherwise reserve two *body* lines and resize once the
            // subheadline tokens arrive. Per-token fonts win over this.
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 14)
            .padding(.horizontal, 4)
            .opacity(tokens.isEmpty ? 0 : 1)
            .motion(AppMotion.settle, value: tokens.isEmpty)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
