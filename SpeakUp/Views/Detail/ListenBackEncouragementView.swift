import SwiftUI

struct ListenBackEncouragementView: View {
    let onDismiss: () -> Void

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

                Text("Hearing your own voice feels weird — that's totally normal! Everyone sounds different to themselves.\n\nThis is actually a superpower for improvement. Listening back helps you notice patterns you'd never catch in the moment.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    onDismiss()
                } label: {
                    Text("Got it, let's listen!")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.94)))
                }
                .buttonStyle(GlassPressStyle())
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
    }
}
