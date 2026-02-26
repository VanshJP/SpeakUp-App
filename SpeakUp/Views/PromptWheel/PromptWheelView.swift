import SwiftUI
import SwiftData

struct PromptWheelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PromptWheelViewModel()
    
    let onSelectPrompt: (Prompt) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                VStack(spacing: 32) {
                    // Wheel
                    wheelSection
                    
                    // Result Card
                    if let prompt = viewModel.selectedPrompt {
                        resultCard(prompt)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Spin Button
                    spinButton
                }
                .padding()
            }
            .navigationTitle("Prompt Wheel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }
    
    // MARK: - Wheel Section

    private var wheelSection: some View {
        ZStack {
            // Wheel
            SpinWheel(
                categories: viewModel.categories,
                colors: viewModel.categoryColors,
                rotation: viewModel.rotation
            )
            .frame(width: 280, height: 280)

            // Center hub
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 60, height: 60)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                }

            // Pointer with landing state
            WheelPointer(isLanded: viewModel.selectedPrompt != nil && !viewModel.isSpinning)
                .offset(y: -150)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isSpinning)
    }
    
    // MARK: - Result Card
    
    private func resultCard(_ prompt: Prompt) -> some View {
        let categoryColor = viewModel.colorForCategory(prompt.category)

        return GlassCard(tint: categoryColor.opacity(0.1), accentBorder: categoryColor.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(categoryColor)

                    Spacer()

                    DifficultyBadge(difficulty: prompt.difficulty)
                }

                // Prompt text
                Text(prompt.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Use this prompt button
                Button {
                    onSelectPrompt(prompt)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Use This Prompt")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.teal, Color.cyan.opacity(0.85), Color.teal.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .teal.opacity(0.4), radius: 12, y: 4)
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Spin Button
    
    private var spinButton: some View {
        Button {
            viewModel.spin()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 16, weight: .semibold))
                Text(viewModel.isSpinning ? "Spinning..." : "Spin the Wheel")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.cyan.opacity(0.85), Color.teal.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .teal.opacity(0.5), radius: 16, y: 4)
                    .shadow(color: .cyan.opacity(0.2), radius: 30, y: 8)
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSpinning)
        .opacity(viewModel.isSpinning ? 0.7 : 1)
        .padding(.bottom, 20)
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
                // Segments
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
        ZStack {
            // Segment shape
            SegmentShape(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
            .fill(.ultraThinMaterial)
            .overlay {
                SegmentShape(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                .fill(color.opacity(0.6))
            }
            .overlay {
                SegmentShape(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                .stroke(color, lineWidth: 2)
            }

            // Category icon
            let midAngle = (startAngle + endAngle) / 2 - 90 // -90 to start from top
            let iconRadius = radius * 0.65
            let x = center.x + iconRadius * cos(midAngle * .pi / 180)
            let y = center.y + iconRadius * sin(midAngle * .pi / 180)

            Image(systemName: PromptCategory(rawValue: category)?.iconName ?? "text.bubble")
                .font(.title3)
                .foregroundStyle(color)
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

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(isLanded ? Color.green : Color.white)
                .frame(width: 24, height: 20)

            Circle()
                .fill(isLanded ? Color.green : Color.white)
                .frame(width: 8, height: 8)
        }
        .shadow(color: isLanded ? .green.opacity(0.6) : .black.opacity(0.3), radius: isLanded ? 8 : 4, y: 2)
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
