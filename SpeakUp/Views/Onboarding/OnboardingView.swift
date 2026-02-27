import SwiftUI

// Fixed layout constants for consistent text positioning across all pages
private enum OnboardingLayout {
    static let heroTopPadding: CGFloat = 60
    static let heroHeight: CGFloat = 160
    static let heroToTitleSpacing: CGFloat = 28
    static let titleToContentSpacing: CGFloat = 24
    static let bottomPadding: CGFloat = 140 // space for controls
}

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    var onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isSmallScreen = geometry.size.height < 700
            let heroHeight = isSmallScreen ? geometry.size.height * 0.18 : 160.0
            let topPadding = isSmallScreen ? geometry.size.height * 0.05 : 60.0
            
            ZStack {
                // Premium dynamic background that shifts with pages
                PremiumOnboardingBackground(currentPage: viewModel.currentPage, size: geometry.size)
                    .ignoresSafeArea()

                TabView(selection: $viewModel.currentPage) {
                    welcomePage(heroHeight: heroHeight, topPadding: topPadding).tag(0)
                    analysisPage(heroHeight: heroHeight, topPadding: topPadding).tag(1)
                    practiceToolkitPage(heroHeight: heroHeight, topPadding: topPadding).tag(2)
                    curriculumPage(heroHeight: heroHeight, topPadding: topPadding).tag(3)
                    trackProgressPage(heroHeight: heroHeight, topPadding: topPadding).tag(4)
                    notificationPage(heroHeight: heroHeight, topPadding: topPadding).tag(5)
                    micPermissionPage(heroHeight: heroHeight, topPadding: topPadding).tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack {
                    Spacer()
                    bottomControls(safeAreaInsets: geometry.safeAreaInsets, isSmallScreen: isSmallScreen)
                }
            }
        }
        .onAppear {
            viewModel.checkMicPermission()
            Task { await viewModel.checkNotificationPermission() }
        }
    }

    // MARK: - Bottom Controls

    private func bottomControls(safeAreaInsets: EdgeInsets, isSmallScreen: Bool) -> some View {
        VStack(spacing: isSmallScreen ? 16 : 24) {
            // Animated Page Indicators (Magnetic effect)
            HStack(spacing: 8) {
                ForEach(0..<viewModel.totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == viewModel.currentPage ? Color.teal : Color.white.opacity(0.15))
                        .frame(
                            width: index == viewModel.currentPage ? 28 : 8,
                            height: 8
                        )
                        .overlay {
                            if index == viewModel.currentPage {
                                Capsule()
                                    .stroke(Color.teal.opacity(0.5), lineWidth: 4)
                                    .blur(radius: 4)
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.currentPage)
                }
            }

            GlassButton(
                title: buttonTitle,
                icon: buttonIcon,
                iconPosition: .right,
                style: .primary,
                size: .large,
                fullWidth: true
            ) {
                if viewModel.isLastPage {
                    Haptics.success()
                    onComplete()
                } else {
                    viewModel.nextPage()
                }
            }
            .padding(.horizontal, 24)
            .shadow(color: .teal.opacity(viewModel.currentPage == 6 ? 0.3 : 0), radius: 20)
            .scaleEffect(viewModel.currentPage == 6 ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.currentPage)
        }
        .padding(.bottom, max(20, safeAreaInsets.bottom + (isSmallScreen ? 10 : 20)))
    }

    private var buttonTitle: String {
        if viewModel.isLastPage {
            return viewModel.hasMicPermission ? "Get Started" : "Continue Without Mic"
        }
        return "Continue"
    }

    private var buttonIcon: String? {
        if viewModel.isLastPage {
            return viewModel.hasMicPermission ? "arrow.right" : nil
        }
        return "arrow.right"
    }

    // MARK: - Shared Page Layout

    /// Consistent page structure with STAGGERED animations
    private func onboardingPage<Hero: View, Detail: View>(
        pageIndex: Int,
        title: String,
        subtitle: String,
        heroHeight: CGFloat,
        topPadding: CGFloat,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        let isCurrent = viewModel.currentPage == pageIndex
        
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 1. Hero Area (Staggered Entrance)
                hero()
                    .frame(height: heroHeight)
                    .padding(.top, topPadding)
                    .scaleEffect(isCurrent ? 1 : 0.85)
                    .opacity(isCurrent ? 1 : 0)
                    .blur(radius: isCurrent ? 0 : 10)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: isCurrent)

                // 2. Title & Subtitle (Staggered Entrance)
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: heroHeight > 140 ? 32 : 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .glow(color: .teal.opacity(0.3), radius: 10)

                    Text(subtitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineSpacing(4)
                }
                .padding(.top, OnboardingLayout.heroToTitleSpacing)
                .offset(y: isCurrent ? 0 : 20)
                .opacity(isCurrent ? 1 : 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.25), value: isCurrent)

                // 3. Detail Content (Staggered Entrance)
                detail()
                    .padding(.top, OnboardingLayout.titleToContentSpacing)
                    .offset(y: isCurrent ? 0 : 30)
                    .opacity(isCurrent ? 1 : 0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.4), value: isCurrent)

                Spacer(minLength: OnboardingLayout.bottomPadding)
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Page 1: Welcome

    private func welcomePage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 0,
            title: "Speak with\nConfidence",
            subtitle: "Your AI-powered coach for mastering public speaking and daily communication.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            WaveformHeroView()
        } detail: {
            HStack(spacing: 8) {
                FeaturePill(icon: "waveform", text: "Analyze")
                FeaturePill(icon: "flame.fill", text: "Practice")
                FeaturePill(icon: "chart.line.uptrend.xyaxis", text: "Master")
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 2: Smart Analysis

    private func analysisPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 1,
            title: "Smart Insights",
            subtitle: "Every session is analyzed across 6 dimensions to map your growth path.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                // Animated background glow for score
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)
                    .scaleEffect(viewModel.scoreAnimationTriggered ? 1.1 : 0.8)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: viewModel.scoreAnimationTriggered)

                // Main Score Ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: heroHeight * 0.75, height: heroHeight * 0.75)

                Circle()
                    .trim(from: 0, to: viewModel.scoreAnimationTriggered ? 0.82 : 0)
                    .stroke(
                        LinearGradient(
                            colors: [.teal, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: heroHeight * 0.75, height: heroHeight * 0.75)
                    .rotationEffect(.degrees(-90))
                    .animation(.expoOut(duration: 2.0), value: viewModel.scoreAnimationTriggered)
                    .glow(color: .teal.opacity(0.5), radius: 10)

                VStack(spacing: 0) {
                    Text("82")
                        .font(.system(size: heroHeight * 0.25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("MASTER")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.5))
                        .kerning(1)
                }
                .scaleEffect(viewModel.scoreAnimationTriggered ? 1 : 0.5)
                .opacity(viewModel.scoreAnimationTriggered ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5), value: viewModel.scoreAnimationTriggered)
            }
        } detail: {
            VStack(spacing: 12) {
                AnimatedScoreRow(icon: "waveform", title: "Clarity", targetWidth: 0.85, color: .blue, delay: 0.6, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "speedometer", title: "Pace", targetWidth: 0.72, color: .green, delay: 0.7, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "text.badge.minus", title: "Fillers", targetWidth: 0.90, color: .orange, delay: 0.8, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "pause.circle", title: "Pausing", targetWidth: 0.78, color: .purple, delay: 0.9, animate: viewModel.scoreAnimationTriggered)
            }
            .padding(.horizontal, 16)
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 1 {
                viewModel.triggerScoreAnimation()
            }
        }
    }

    // MARK: - Page 3: Practice Toolkit

    private func practiceToolkitPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 2,
            title: "Practice Toolkit",
            subtitle: "Techniques for every scenario—from tongue twisters to impromptu speaking.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.2))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)

                Image(systemName: "sparkles")
                    .font(.system(size: heroHeight * 0.4))
                    .foregroundStyle(.teal)
                    .symbolEffect(.bounce, options: .repeating, value: viewModel.currentPage == 2)
                    .glow(color: .teal, radius: 20)
            }
        } detail: {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ToolkitCard(
                        icon: "wind",
                        title: "Warm-Ups",
                        subtitle: "Vocal & breathing",
                        color: .cyan,
                        isVisible: viewModel.toolsRevealed >= 1
                    )
                    ToolkitCard(
                        icon: "bolt.circle",
                        title: "Drills",
                        subtitle: "Active training",
                        color: .orange,
                        isVisible: viewModel.toolsRevealed >= 2
                    )
                }

                HStack(spacing: 16) {
                    ToolkitCard(
                        icon: "leaf",
                        title: "Calm",
                        subtitle: "Mental preparation",
                        color: .green,
                        isVisible: viewModel.toolsRevealed >= 3
                    )
                    ToolkitCard(
                        icon: "bubble.left.and.text.bubble.right",
                        title: "Prompts",
                        subtitle: "Topic library",
                        color: .purple,
                        isVisible: viewModel.toolsRevealed >= 4
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 2 {
                viewModel.revealTools()
            }
        }
    }

    // MARK: - Page 4: Curriculum

    private func curriculumPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 3,
            title: "Expert Pathway",
            subtitle: "A structured curriculum built to transform your speaking in just 4 weeks.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)

                Image(systemName: "map.fill")
                    .font(.system(size: heroHeight * 0.35))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, value: viewModel.currentPage == 3)
            }
        } detail: {
            VStack(spacing: 12) {
                CurriculumPhaseRow(
                    week: "Weeks 1–2",
                    title: "The Foundation",
                    subtitle: "Mastering the basics of delivery",
                    icon: "1.circle.fill",
                    color: .green
                )
                CurriculumPhaseRow(
                    week: "Weeks 3–4",
                    title: "Advanced Impact",
                    subtitle: "Persuasion and storytelling",
                    icon: "2.circle.fill",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Page 5: Track Progress

    private func trackProgressPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 4,
            title: "Your Growth",
            subtitle: "Watch your confidence soar with detailed progress tracking and streaks.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: heroHeight * 0.35))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative, value: viewModel.currentPage == 4)
            }
        } detail: {
            VStack(spacing: 12) {
                CompactProgressRow(
                    icon: "flame.fill",
                    title: "Daily Consistency",
                    subtitle: "Build a lasting practice habit",
                    color: .orange,
                    isVisible: viewModel.progressItemsRevealed >= 1
                )
                
                MiniContributionGraph()
                    .padding(.top, 4)
                    .opacity(viewModel.progressItemsRevealed >= 2 ? 1 : 0)
                    .scaleEffect(viewModel.progressItemsRevealed >= 2 ? 1 : 0.95)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: viewModel.progressItemsRevealed)
            }
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 4 {
                viewModel.revealProgressItems()
            }
        }
    }

    // MARK: - Page 6: Notifications

    private func notificationPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 5,
            title: viewModel.hasNotificationPermission ? "All Set!" : "Stay Inspired",
            subtitle: viewModel.hasNotificationPermission
                ? "We'll keep you motivated with timely practice reminders."
                : "Enable notifications for daily tips and practice reminders to keep your streak alive.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                Circle()
                    .fill((viewModel.hasNotificationPermission ? Color.green : Color.orange).opacity(0.2))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)

                Image(systemName: viewModel.hasNotificationPermission ? "bell.badge.fill" : "bell.badge")
                    .font(.system(size: heroHeight * 0.45))
                    .foregroundStyle(viewModel.hasNotificationPermission ? .green : .orange)
                    .symbolEffect(.bounce, value: viewModel.notificationJustGranted)
            }
        } detail: {
            VStack(spacing: 20) {
                if !viewModel.hasNotificationPermission {
                    GlassButton(
                        title: "Enable Reminders",
                        icon: "bell.fill",
                        style: .primary,
                        size: .large,
                        isLoading: viewModel.isRequestingNotificationPermission
                    ) {
                        Haptics.medium()
                        Task { await viewModel.requestNotificationPermission() }
                    }
                    .padding(.horizontal, 16)
                } else {
                    StatusCard(
                        icon: "checkmark.seal.fill",
                        title: "Notifications Enabled",
                        subtitle: "You're ready for daily growth reminders.",
                        color: .green
                    )
                }

                HStack(spacing: 24) {
                    PrivacyBadge(icon: "flame.fill", text: "Streaks")
                    PrivacyBadge(icon: "trophy.fill", text: "Awards")
                    PrivacyBadge(icon: "star.fill", text: "Tips")
                }
                .opacity(viewModel.hasNotificationPermission ? 0.6 : 1.0)
            }
        }
    }

    // MARK: - Page 7: Mic Permission

    private func micPermissionPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 6,
            title: viewModel.hasMicPermission ? "Ready to Go!" : "Voice Access",
            subtitle: viewModel.hasMicPermission
                ? "The stage is yours. Let's start your first practice session."
                : "We need microphone access to analyze your speech. Everything stays on your device.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            ZStack {
                Circle()
                    .fill((viewModel.hasMicPermission ? Color.green : Color.teal).opacity(0.2))
                    .frame(width: heroHeight * 0.8, height: heroHeight * 0.8)
                    .blur(radius: 20)

                Image(systemName: viewModel.hasMicPermission ? "mic.circle.fill" : "mic.circle")
                    .font(.system(size: heroHeight * 0.5))
                    .foregroundStyle(viewModel.hasMicPermission ? .green : .teal)
                    .symbolEffect(.pulse, isActive: !viewModel.hasMicPermission)
            }
        } detail: {
            VStack(spacing: 20) {
                if !viewModel.hasMicPermission {
                    GlassButton(
                        title: "Enable Microphone",
                        icon: "mic.fill",
                        style: .primary,
                        size: .large,
                        isLoading: viewModel.isRequestingPermission
                    ) {
                        Haptics.medium()
                        Task { await viewModel.requestMicPermission() }
                    }
                    .padding(.horizontal, 16)
                } else {
                    StatusCard(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        subtitle: "Analysis is performed 100% on-device.",
                        color: .green
                    )
                }

                HStack(spacing: 24) {
                    PrivacyBadge(icon: "iphone", text: "Local")
                    PrivacyBadge(icon: "lock.fill", text: "Private")
                    PrivacyBadge(icon: "cloud.slash.fill", text: "Offline ✈️")
                }
            }
        }
    }
}

// MARK: - Premium Background

struct PremiumOnboardingBackground: View {
    let currentPage: Int
    let size: CGSize
    
    var body: some View {
        ZStack {
            // Deep obsidian base
            Color(red: 0.02, green: 0.03, blue: 0.06)
                .ignoresSafeArea()
            
            // Dynamic breathing orbs
            OrbView(
                color: Color.teal.opacity(0.15),
                position: orbPosition(for: 0),
                screenSize: size,
                orbSize: 450,
                delay: 0
            )
            
            OrbView(
                color: Color.indigo.opacity(0.12),
                position: orbPosition(for: 1),
                screenSize: size,
                orbSize: 400,
                delay: 1.0
            )
            
            OrbView(
                color: Color.cyan.opacity(0.08),
                position: orbPosition(for: 2),
                screenSize: size,
                orbSize: 350,
                delay: 2.0
            )
        }
        .drawingGroup() // High performance for complex gradients
    }
    
    private func orbPosition(for index: Int) -> UnitPoint {
        let positions: [UnitPoint] = [
            .init(x: 0.1, y: 0.1), .init(x: 0.9, y: 0.2), .init(x: 0.5, y: 0.8),
            .init(x: 0.8, y: 0.1), .init(x: 0.2, y: 0.7), .init(x: 0.6, y: 0.3),
            .init(x: 0.1, y: 0.9)
        ]
        
        let targetIndex = (currentPage + index) % positions.count
        return positions[targetIndex]
    }
}

struct OrbView: View {
    let color: Color
    let position: UnitPoint
    let screenSize: CGSize
    let orbSize: CGFloat
    let delay: Double
    
    @State private var floating = false
    
    var body: some View {
        RadialGradient(
            colors: [color, .clear],
            center: .center,
            startRadius: 0,
            endRadius: orbSize / 2
        )
        .frame(width: orbSize, height: orbSize)
        .position(
            x: position.x * screenSize.width,
            y: position.y * screenSize.height
        )
        .blur(radius: 50)
        .scaleEffect(floating ? 1.1 : 0.9)
        .opacity(floating ? 1.0 : 0.7)
        .animation(.spring(response: 3.0, dampingFraction: 0.9).delay(delay), value: position)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0 + delay).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

// MARK: - Enhanced Waveform Hero

private struct WaveformHeroView: View {
    @State private var animating = false

    var body: some View {
        ZStack {
            // Liquid background glow
            Circle()
                .fill(Color.teal.opacity(0.15))
                .blur(radius: 40)
                .scaleEffect(animating ? 1.2 : 0.8)
            
            // Multiple layers of fluid waveforms
            ForEach(0..<3) { layer in
                FluidWaveform(layer: layer, animating: animating)
                    .frame(width: 200, height: 100)
            }
            
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .glow(color: .teal, radius: 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

struct FluidWaveform: View {
    let layer: Int
    let animating: Bool
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time: Double = timeline.date.timeIntervalSinceReferenceDate
                let width: CGFloat = size.width
                let height: CGFloat = size.height
                let midY: CGFloat = height / 2.0

                // Precompute speeds and amplitudes to reduce inline math
                let baseSpeed: Double = 1.2
                let layerSpeed: Double = baseSpeed + (Double(layer) * 0.4)
                let amplitude: CGFloat = 25.0
                let step: CGFloat = 2.0

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                var x: CGFloat = 0
                while x < width {
                    let relativeX: CGFloat = width == 0 ? 0 : (x / width)
                    let phase: Double = Double(relativeX) * .pi * 2.0 + time * layerSpeed
                    let sine: CGFloat = CGFloat(sin(phase))
                    let envelope: CGFloat = CGFloat(sin(Double(relativeX) * .pi))
                    let y: CGFloat = midY + sine * amplitude * envelope * (animating ? 1.0 : 0.6)
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += step
                }

                // Break up style construction
                let startColor: Color = .teal.opacity(0.7 / Double(layer + 1))
                let endColor: Color = .cyan.opacity((0.7 / Double(layer + 1)) * 0.5)
                let gradient = Gradient(colors: [startColor, endColor])
                let startPoint: CGPoint = .zero
                let endPoint: CGPoint = CGPoint(x: width, y: height)

                let lineWidth: Double = max(0.5, 4.0 - Double(layer))

                context.stroke(
                    path,
                    with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint),
                    lineWidth: lineWidth
                )
            }
        }
    }
}

// MARK: - Enhanced Components

private struct StatusCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        GlassCard(tint: color.opacity(0.15), padding: 16) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title2)
                    .glow(color: color, radius: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct FeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.teal)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .shimmer()
    }
}

private struct AnimatedScoreRow: View {
    let icon: String
    let title: String
    let targetWidth: CGFloat
    let color: Color
    let delay: CGFloat
    let animate: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animate ? geo.size.width * targetWidth : 0, height: 8)
                        .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(delay), value: animate)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct ToolkitCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        GlassCard(cornerRadius: 20, tint: color.opacity(0.15), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                    .glow(color: color, radius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .offset(y: isVisible ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isVisible)
    }
}

private struct CurriculumPhaseRow: View {
    let week: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard(cornerRadius: 18, tint: color.opacity(0.1), padding: 16) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                    .glow(color: color, radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(week)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundStyle(color)
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}

private struct CompactProgressRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        GlassCard(cornerRadius: 16, tint: color.opacity(0.1), padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 15)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isVisible)
    }
}

private struct MiniContributionGraph: View {
    private let columns = 14
    private let rows = 3

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Consistency", systemImage: "chart.dots.scatter")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                    Spacer()
                }

                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { col in
                        VStack(spacing: 4) {
                            ForEach(0..<rows, id: \.self) { row in
                                let intensity = sampleIntensity(col: col, row: row)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AppColors.contributionColor(intensity: intensity))
                                    .frame(width: 18, height: 18)
                                    .shimmer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func sampleIntensity(col: Int, row: Int) -> Double {
        let seed = col * 3 + row
        let base = Double(col) / Double(columns)
        let noise = sin(Double(seed) * 1.5) * 0.4
        return max(0.1, min(1, base * 0.7 + noise + 0.2))
    }
}

private struct PrivacyBadge: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.teal)
            }
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Animation Extensions

extension Animation {
    static func expoOut(duration: Double = 1.0) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }
}
