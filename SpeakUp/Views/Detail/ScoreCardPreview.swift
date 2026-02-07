import SwiftUI

struct ScoreCardPreview: View {
    let image: UIImage
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .padding(.horizontal, 32)

                Spacer()

                GlassButton(
                    title: "Share Score Card",
                    icon: "square.and.arrow.up",
                    style: .primary,
                    fullWidth: true
                ) {
                    onShare()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Score Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }
}
