import SwiftUI

struct AnalyzingView: View {
    let recording: Recording
    let isModelLoading: Bool

    @State private var currentTipIndex = 0
    @State private var showTip = true
    @State private var waveformPhase: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1
    @State private var pulseScale: CGFloat = 1.0
    @State private var progressStage = 0

    private let motivationalTips = [
        (icon: "star.fill", text: "Great job showing up! Consistency is the key to confident speaking."),
        (icon: "brain.head.profile.fill", text: "Every recording builds stronger neural pathways for fluent speech."),
        (icon: "chart.line.uptrend.xyaxis", text: "Speakers who review their recordings improve 3x faster."),
        (icon: "flame.fill", text: "You're building a habit that most people never start. Be proud."),
        (icon: "trophy.fill", text: "The best speakers in the world still practice every day."),
        (icon: "sparkles", text: "Your voice is unique. The goal isn't perfection -- it's progress."),
        (icon: "bolt.fill", text: "Each session sharpens your clarity, pace, and confidence."),
        (icon: "heart.fill", text: "Speaking gets easier the more you do it. You've already done the hard part.")
    ]

    private let stages = [
        "Transcribing your speech...",
        "Detecting filler words...",
        "Analyzing pace & pauses...",
        "Scoring your delivery..."
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Animated waveform circle
                waveformOrb

                // Status text
                VStack(spacing: 8) {
                    Text(isModelLoading ? "Preparing Speech Engine..." : stages[progressStage])
                        .font(.headline.weight(.semibold))
                        .contentTransition(.numericText())

                    Text(isModelLoading
                         ? "Loading the AI model for first-time use"
                         : "Sit tight — we're crunching the numbers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Progress dots
                progressDots

                // Motivational tip card
                motivationalCard

                // Skeleton preview of results
                skeletonPreview

                Spacer()
                    .frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Waveform Orb

    private var waveformOrb: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        Color.teal.opacity(0.08 - Double(i) * 0.02),
                        lineWidth: 1.5
                    )
                    .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                    .scaleEffect(pulseScale + CGFloat(i) * 0.03)
            }

            // Animated waveform circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.teal.opacity(0.2),
                            Color.teal.opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // Waveform bars in circular arrangement
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * (360.0 / 24.0)
                let barHeight = waveBarHeight(index: i)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.teal.opacity(0.6 + Double(i % 3) * 0.15))
                    .frame(width: 3, height: barHeight)
                    .offset(y: -45)
                    .rotationEffect(.degrees(angle))
            }

            // Center icon
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.teal)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
        .frame(height: 200)
    }

    private func waveBarHeight(index: Int) -> CGFloat {
        let base: CGFloat = 8
        let wave = sin(waveformPhase + Double(index) * 0.5) * 12
        return max(base, base + CGFloat(wave))
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= progressStage ? Color.teal : Color.white.opacity(0.15))
                    .frame(width: i == progressStage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4), value: progressStage)
            }
        }
    }

    // MARK: - Motivational Card

    private var motivationalCard: some View {
        let tip = motivationalTips[currentTipIndex]
        return FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.1), .cyan.opacity(0.05)]
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: tip.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32)

                Text(tip.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
        .opacity(showTip ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: showTip)
    }

    // MARK: - Skeleton Preview

    private var skeletonPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your results are coming...", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            // Skeleton score card
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 80, height: 32)
                        SkeletonBar(width: 120, height: 8)
                    }
                    Spacer()
                    SkeletonBar(width: 70, height: 28)
                }
            }

            // Skeleton stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    GlassCard(padding: 14) {
                        HStack(spacing: 12) {
                            SkeletonCircle(size: 24)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBar(width: 50, height: 8)
                                SkeletonBar(width: 40, height: 14)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            // Skeleton subscore rows
            GlassCard {
                VStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 10) {
                            SkeletonCircle(size: 16)
                            SkeletonBar(width: 70, height: 10)
                            Spacer()
                            SkeletonBar(width: 60, height: 6)
                            SkeletonBar(width: 24, height: 10)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Waveform animation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            waveformPhase = .pi * 2
        }

        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.06
        }

        // Cycle through tips
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { timer in
            withAnimation { showTip = false }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentTipIndex = (currentTipIndex + 1) % motivationalTips.count
                withAnimation { showTip = true }
            }
        }

        // Progress stages
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { timer in
            withAnimation(.spring(response: 0.3)) {
                progressStage = (progressStage + 1) % stages.count
            }
        }
    }
}

// MARK: - Skeleton Components

private struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat

    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmer ? width : -width)
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}

private struct SkeletonCircle: View {
    let size: CGFloat

    @State private var shimmer = false

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmer ? size : -size)
            }
            .clipShape(Circle())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}
