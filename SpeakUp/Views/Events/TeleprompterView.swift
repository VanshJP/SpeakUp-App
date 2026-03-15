import SwiftUI

struct TeleprompterView: View {
    let scriptText: String
    var speed: Double = 1.0
    var fontSize: Double = 24.0
    var onSettingsChanged: ((Double, Double) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrolling = false
    @State private var adjustedSpeed: Double
    @State private var adjustedFontSize: Double
    @State private var showControls = true
    @State private var contentHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 0
    @State private var lastTime: Date?
    @State private var manualDragOffset: CGFloat = 0

    private let basePixelsPerSecond: CGFloat = 30

    init(scriptText: String, speed: Double = 1.0, fontSize: Double = 24.0, onSettingsChanged: ((Double, Double) -> Void)? = nil) {
        self.scriptText = scriptText
        self.speed = speed
        self.fontSize = fontSize
        self.onSettingsChanged = onSettingsChanged
        self._adjustedSpeed = State(initialValue: speed)
        self._adjustedFontSize = State(initialValue: fontSize)
    }

    private var startPadding: CGFloat {
        viewHeight * 0.4
    }

    private var maxScroll: CGFloat {
        max(0, contentHeight - viewHeight * 0.4)
    }

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            GeometryReader { proxy in
                ZStack {
                    Text(scriptText)
                        .font(.system(size: adjustedFontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineSpacing(adjustedFontSize * 0.5)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { textProxy in
                                Color.clear
                                    .onAppear {
                                        contentHeight = textProxy.size.height
                                        viewHeight = proxy.size.height
                                    }
                                    .onChange(of: adjustedFontSize) {
                                        contentHeight = textProxy.size.height
                                    }
                            }
                        }
                        .offset(y: startPadding - scrollOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isScrolling {
                                        scrollOffset = max(0, min(maxScroll, scrollOffset - value.translation.height + manualDragOffset))
                                        manualDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { _ in
                                    manualDragOffset = 0
                                }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .onAppear {
                    viewHeight = proxy.size.height
                }
            }

            // Auto-scroll engine
            TimelineView(.animation(paused: !isScrolling)) { timeline in
                Color.clear
                    .onChange(of: timeline.date) { oldDate, newDate in
                        guard isScrolling else {
                            lastTime = nil
                            return
                        }
                        if let last = lastTime {
                            let delta = newDate.timeIntervalSince(last)
                            let advance = CGFloat(delta) * CGFloat(adjustedSpeed) * basePixelsPerSecond
                            scrollOffset = min(maxScroll, scrollOffset + advance)
                            if scrollOffset >= maxScroll {
                                isScrolling = false
                            }
                        }
                        lastTime = newDate
                    }
            }

            // Fade gradients
            VStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.16), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                Spacer()
                LinearGradient(colors: [.clear, Color(red: 0.05, green: 0.07, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
            }
            .ignoresSafeArea()

            // Center reading line
            Rectangle()
                .fill(AppColors.primary.opacity(0.3))
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
        .onDisappear {
            onSettingsChanged?(adjustedSpeed, adjustedFontSize)
        }
        .statusBarHidden(true)
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                GlassIconButton(icon: "xmark") {
                    dismiss()
                }

                Spacer()

                Text("Teleprompter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Reset button
                GlassIconButton(icon: "arrow.counterclockwise") {
                    Haptics.light()
                    isScrolling = false
                    lastTime = nil
                    withAnimation(.spring(response: 0.3)) {
                        scrollOffset = 0
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            // Bottom controls
            VStack(spacing: 16) {
                // Play/Pause button
                Button {
                    Haptics.medium()
                    isScrolling.toggle()
                    if !isScrolling {
                        lastTime = nil
                    }
                } label: {
                    Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background {
                            Circle()
                                .fill(AppColors.primary)
                        }
                }

                // Speed control
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $adjustedSpeed, in: 0.5...3.0, step: 0.25)
                        .tint(AppColors.primary)
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
                        .tint(AppColors.primary)
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
