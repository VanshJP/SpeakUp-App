import SwiftUI

struct TeleprompterView: View {
    let scriptText: String
    var speed: Double = 1.0
    var fontSize: Double = 24.0

    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrolling = false
    @State private var adjustedSpeed: Double
    @State private var adjustedFontSize: Double
    @State private var showControls = true
    @State private var timer: Timer?
    @State private var contentHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 0

    init(scriptText: String, speed: Double = 1.0, fontSize: Double = 24.0) {
        self.scriptText = scriptText
        self.speed = speed
        self.fontSize = fontSize
        self._adjustedSpeed = State(initialValue: speed)
        self._adjustedFontSize = State(initialValue: fontSize)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    Text(scriptText)
                        .font(.system(size: adjustedFontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineSpacing(adjustedFontSize * 0.5)
                        .padding(.horizontal, 24)
                        .padding(.top, proxy.size.height * 0.4)
                        .padding(.bottom, proxy.size.height * 0.6)
                        .background {
                            GeometryReader { textProxy in
                                Color.clear.onAppear {
                                    contentHeight = textProxy.size.height
                                    viewHeight = proxy.size.height
                                }
                            }
                        }
                }
                .scrollIndicators(.hidden)
            }

            // Fade gradients
            VStack {
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                Spacer()
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
            }
            .ignoresSafeArea()

            // Center reading line
            Rectangle()
                .fill(Color.teal.opacity(0.3))
                .frame(height: 2)

            // Controls overlay
            if showControls {
                controlsOverlay
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background { Circle().fill(.ultraThinMaterial) }
                }

                Spacer()

                Text("Teleprompter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Placeholder for symmetry
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            // Bottom controls
            VStack(spacing: 16) {
                // Speed control
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $adjustedSpeed, in: 0.5...3.0, step: 0.25)
                        .tint(.teal)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fx", adjustedSpeed))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 40)
                }

                // Font size control
                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(.secondary)
                    Slider(value: $adjustedFontSize, in: 16...48, step: 2)
                        .tint(.teal)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(.secondary)
                    Text("\(Int(adjustedFontSize))pt")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .transition(.opacity)
    }
}
