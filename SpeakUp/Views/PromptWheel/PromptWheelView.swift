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
                // Background
                LinearGradient(
                    colors: [Color(white: 0.05), Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
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
                    .foregroundStyle(.white)
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
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

            // Pointer with landing state
            WheelPointer(isLanded: viewModel.selectedPrompt != nil && !viewModel.isSpinning)
                .offset(y: -150)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isSpinning)
    }
    
    // MARK: - Result Card
    
    private func resultCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(viewModel.colorForCategory(prompt.category))
                
                Spacer()
                
                DifficultyBadge(difficulty: prompt.difficulty)
            }
            
            // Prompt text
            Text(prompt.text)
                .font(.body)
                .foregroundStyle(.white)
            
            // Use this prompt button
            Button {
                onSelectPrompt(prompt)
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Use This Prompt")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(viewModel.colorForCategory(prompt.category))
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(viewModel.colorForCategory(prompt.category).opacity(0.1))
                }
        }
    }
    
    // MARK: - Spin Button
    
    private var spinButton: some View {
        Button {
            viewModel.spin()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title3)
                    .rotationEffect(.degrees(viewModel.isSpinning ? 360 : 0))
                    .animation(viewModel.isSpinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isSpinning)
                
                Text(viewModel.isSpinning ? "Spinning..." : "Spin the Wheel")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.9), Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
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

    // Abbreviated category labels
    private var abbreviatedLabel: String {
        switch category {
        case "Professional Development": return "PROF"
        case "Communication Skills": return "COMM"
        case "Personal Growth": return "GROWTH"
        case "Problem Solving": return "SOLVE"
        case "Current Events": return "NEWS"
        case "Quick Fire": return "QUICK"
        case "Debate & Persuasion": return "DEBATE"
        default: return String(category.prefix(4)).uppercased()
        }
    }

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
                .fill(color.opacity(0.6)) // Increased from 0.3
            }
            .overlay {
                SegmentShape(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                .stroke(color, lineWidth: 2) // Full color instead of 0.5 opacity
            }

            // Category icon and label
            let midAngle = (startAngle + endAngle) / 2 - 90 // -90 to start from top
            let iconRadius = radius * 0.55
            let labelRadius = radius * 0.78
            let x = center.x + iconRadius * cos(midAngle * .pi / 180)
            let y = center.y + iconRadius * sin(midAngle * .pi / 180)
            let labelX = center.x + labelRadius * cos(midAngle * .pi / 180)
            let labelY = center.y + labelRadius * sin(midAngle * .pi / 180)

            Image(systemName: PromptCategory(rawValue: category)?.iconName ?? "text.bubble")
                .font(.title3)
                .foregroundStyle(color)
                .position(x: x, y: y)

            // Abbreviated text label
            Text(abbreviatedLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .position(x: labelX, y: labelY)
                .rotationEffect(.degrees(midAngle + 90)) // Rotate to follow segment
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
