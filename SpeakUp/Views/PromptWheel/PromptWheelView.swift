import SwiftUI
import SwiftData

struct PromptWheelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PromptWheelViewModel()

    // Finger-on-wheel tracking. Angle is degrees around the wheel's centre;
    // velocity is a lightly smoothed degrees-per-second read from the last
    // few samples, handed to the view model on release.
    @State private var dragLastAngle: Double?
    @State private var dragLastTime: Date = .distantPast
    @State private var angularVelocity: Double = 0

    // One tick per segment edge passing the pointer — during a drag and
    // through every frame of a spin. Drives the haptic and the pointer's nod.
    @State private var detentTick = 0
    @State private var detentKick: Double = 14

    private let wheelSize: CGFloat = 280

    let onSelectPrompt: (Prompt) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(spacing: 24) {
                        headerCaption
                        wheelSection
                        statusLine

                        if let prompt = viewModel.selectedPrompt {
                            resultCard(prompt)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Color.clear.frame(height: 96)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                VStack {
                    Spacer()
                    spinButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Prompt Wheel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Header

    private var headerCaption: some View {
        VStack(spacing: 6) {
            Text("Random Discovery")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Spin to land on a category")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Wheel Section

    private var wheelSection: some View {
        ZStack {
            SpinWheel(
                categories: viewModel.categories,
                colors: segmentColors,
                rotation: viewModel.rotation
            )
            .frame(width: wheelSize, height: wheelSize)
            .contentShape(Circle())
            .highPriorityGesture(wheelDrag)
            .modifier(DetentTracker(rotation: viewModel.rotation, segments: viewModel.categories.count) { direction in
                detentKick = direction * 14
                detentTick += 1
            })
            .accessibilityLabel("Prompt wheel")
            .accessibilityHint("Flick to spin")

            centerHub

            WheelPointer(isLanded: viewModel.selectedPrompt != nil && !viewModel.isSpinning)
                // The tip gets kicked by each passing edge and springs back.
                .keyframeAnimator(initialValue: 0.0, trigger: detentTick) { pointer, angle in
                    pointer.rotationEffect(.degrees(angle), anchor: .top)
                } keyframes: { _ in
                    CubicKeyframe(detentKick, duration: 0.05)
                    SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                }
                .offset(y: -150)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isSpinning)
        .sensoryFeedback(.selection, trigger: detentTick)
    }

    private var wheelDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag in
                let angle = Self.angle(of: drag.location, in: wheelSize)
                defer {
                    dragLastAngle = angle
                    dragLastTime = drag.time
                }
                guard let last = dragLastAngle else { return }

                let delta = PromptWheelViewModel.signedDelta(angle - last)
                viewModel.drag(by: delta)

                let dt = drag.time.timeIntervalSince(dragLastTime)
                if dt > 0.001 {
                    angularVelocity = angularVelocity * 0.5 + (delta / dt) * 0.5
                }
            }
            .onEnded { _ in
                viewModel.release(angularVelocity: angularVelocity)
                dragLastAngle = nil
                angularVelocity = 0
            }
    }

    /// Degrees around the wheel's centre, clockwise from 3 o'clock — the same
    /// sense as `rotationEffect`, so a delta applies to the wheel directly.
    private static func angle(of point: CGPoint, in size: CGFloat) -> Double {
        let centre = size / 2
        return atan2(point.y - centre, point.x - centre) * 180 / .pi
    }

    private var centerHub: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            if let prompt = viewModel.selectedPrompt, !viewModel.isSpinning {
                Image(systemName: PromptCategory(rawValue: prompt.category)?.iconName ?? "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(categoryColor(for: prompt.category))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    // MARK: - Status Line

    @ViewBuilder
    private var statusLine: some View {
        if viewModel.isSpinning {
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted")
                    .font(.caption.weight(.semibold))
                Text("Spinning…")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.7))
        } else if let category = viewModel.selectedCategory {
            HStack(spacing: 8) {
                Image(systemName: PromptCategory(rawValue: category)?.iconName ?? "sparkles")
                    .font(.caption.weight(.semibold))
                Text("Landed on \(category)")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(categoryColor(for: category))
        } else {
            Text("\(viewModel.prompts.count) prompts ready")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Color Helpers

    private var segmentColors: [Color] {
        viewModel.categories.map { categoryColor(for: $0) }
    }

    private func categoryColor(for category: String) -> Color {
        PromptCategory(rawValue: category)?.color ?? AppColors.primary
    }
    
    // MARK: - Result Card

    private func resultCard(_ prompt: Prompt) -> some View {
        let color = categoryColor(for: prompt.category)

        return GlassCard(tint: color.opacity(0.10), accentBorder: color.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                        .font(.caption.weight(.semibold))
                    Text(prompt.category)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    StatusPill.difficulty(prompt.difficulty)
                }
                .foregroundStyle(color)

                Text(prompt.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                GlassButton(
                    title: "Use This Prompt",
                    icon: "mic.fill",
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    onSelectPrompt(prompt)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Spin Button

    private var spinButton: some View {
        GlassButton(
            title: viewModel.isSpinning ? "Spinning…" : "Spin the Wheel",
            icon: "arrow.trianglehead.2.clockwise.rotate.90",
            style: .primary,
            size: .large,
            isLoading: false,
            fullWidth: true
        ) {
            viewModel.spin()
        }
        .disabled(viewModel.isSpinning)
        .opacity(viewModel.isSpinning ? 0.7 : 1)
    }
}

// MARK: - Detent Tracker

/// Reports each segment edge passing the pointer. `Animatable` is what lets
/// it see the interpolated angle on every frame of a spin rather than only
/// the end value; the work per frame is one integer compare.
private struct DetentTracker: ViewModifier, Animatable {
    var rotation: Double
    let segments: Int
    /// +1 when the wheel turns clockwise, -1 otherwise.
    let onCross: (Double) -> Void

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    private var index: Int {
        guard segments > 0 else { return 0 }
        return Int((rotation / (360 / Double(segments))).rounded(.down))
    }

    func body(content: Content) -> some View {
        content.onChange(of: index) { old, new in
            onCross(new > old ? 1 : -1)
        }
    }
}

// MARK: - Spin Wheel

struct SpinWheel: View {
    let categories: [String]
    let colors: [Color]
    let rotation: Double
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            let segmentAngle = categories.isEmpty ? 360.0 : 360.0 / Double(categories.count)
            
            ZStack {
                ForEach(0..<categories.count, id: \.self) { index in
                    WheelSegment(
                        center: center,
                        radius: radius,
                        startAngle: Double(index) * segmentAngle,
                        endAngle: Double(index + 1) * segmentAngle,
                        color: colors[index % colors.count],
                        category: categories[index]
                    )
                }
            }
            .rotationEffect(.degrees(rotation))
        }
    }
}

// MARK: - Wheel Segment

struct WheelSegment: View {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: Double
    let endAngle: Double
    let color: Color
    let category: String

    var body: some View {
        let shape = SegmentShape(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        )

        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [color.opacity(0.18), color.opacity(0.42)],
                            center: .init(x: 0.5, y: 0.5),
                            startRadius: radius * 0.1,
                            endRadius: radius
                        )
                    )
                }
                .overlay {
                    shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }

            let midAngle = (startAngle + endAngle) / 2 - 90
            let iconRadius = radius * 0.65
            let x = center.x + iconRadius * cos(midAngle * .pi / 180)
            let y = center.y + iconRadius * sin(midAngle * .pi / 180)

            Image(systemName: PromptCategory(rawValue: category)?.iconName ?? "text.bubble")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: color.opacity(0.6), radius: 4)
                .position(x: x, y: y)
        }
    }
}

// MARK: - Segment Shape

struct SegmentShape: Shape {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: Double
    let endAngle: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle - 90), // -90 to start from top
            endAngle: .degrees(endAngle - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Wheel Pointer

struct WheelPointer: View {
    var isLanded: Bool = false

    private var tint: Color {
        isLanded ? AppColors.success : AppColors.primary
    }

    var body: some View {
        VStack(spacing: 2) {
            Triangle()
                .fill(tint)
                .frame(width: 22, height: 18)
                .overlay {
                    Triangle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                }

            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                }
        }
        .shadow(color: tint.opacity(isLanded ? 0.7 : 0.5), radius: isLanded ? 10 : 6, y: 2)
        .animation(.easeInOut(duration: 0.3), value: isLanded)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    PromptWheelView(onSelectPrompt: { _ in })
        .modelContainer(for: [Prompt.self], inMemory: true)
}
