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
        ZStack {
            TabView(selection: $viewModel.currentPage) {
                welcomePage.tag(0)
                analysisPage.tag(1)
                practiceToolkitPage.tag(2)
                curriculumPage.tag(3)
                trackProgressPage.tag(4)
                micPermissionPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentPage)

            VStack {
                Spacer()
                bottomControls
            }
        }
        .appBackground(.subtle)
        .onAppear {
            viewModel.checkMicPermission()
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 6) {
                ForEach(0..<viewModel.totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == viewModel.currentPage ? Color.teal : Color.white.opacity(0.2))
                        .frame(
                            width: index == viewModel.currentPage ? 24 : 8,
                            height: 8
                        )
                        .animation(.spring(response: 0.3), value: viewModel.currentPage)
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
        }
        .padding(.bottom, 50)
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

    /// Consistent page structure: hero area (fixed position) → title/subtitle (same Y) → detail content → bottom space
    private func onboardingPage<Hero: View, Detail: View>(
        title: String,
        subtitle: String,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero area — fixed height so title always starts at same Y
                hero()
                    .frame(height: OnboardingLayout.heroHeight)
                    .padding(.top, OnboardingLayout.heroTopPadding)

                // Title + subtitle — always at the same vertical position
                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.top, OnboardingLayout.heroToTitleSpacing)

                // Detail content below title
                detail()
                    .padding(.top, OnboardingLayout.titleToContentSpacing)

                Spacer(minLength: OnboardingLayout.bottomPadding)
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        onboardingPage(
            title: "Welcome to SpeakUp",
            subtitle: "Your personal speech coach.\nRecord, analyze, and master the art of speaking."
        ) {
            WaveformHeroView()
        } detail: {
            HStack(spacing: 8) {
                FeaturePill(icon: "waveform", text: "Analyze")
                FeaturePill(icon: "flame.fill", text: "Practice")
                FeaturePill(icon: "chart.line.uptrend.xyaxis", text: "Improve")
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 2: Smart Analysis

    private var analysisPage: some View {
        onboardingPage(
            title: "Deep Speech Analysis",
            subtitle: "Every session is scored across four dimensions so you know exactly where to focus."
        ) {
            // Animated score ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 110, height: 110)

                Circle()
                    .trim(from: 0, to: viewModel.scoreAnimationTriggered ? 0.82 : 0)
                    .stroke(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: viewModel.scoreAnimationTriggered)

                VStack(spacing: 2) {
                    Text(viewModel.scoreAnimationTriggered ? "82" : "--")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("score")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        } detail: {
            // Metric bars — matches RecordingDetailView subscores
            VStack(spacing: 10) {
                AnimatedScoreRow(icon: "waveform", title: "Clarity", targetWidth: 0.85, color: .blue, delay: 0.3, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "speedometer", title: "Pace", targetWidth: 0.72, color: .green, delay: 0.5, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "text.badge.minus", title: "Filler Usage", targetWidth: 0.90, color: .orange, delay: 0.7, animate: viewModel.scoreAnimationTriggered)
                AnimatedScoreRow(icon: "pause.circle", title: "Pause Quality", targetWidth: 0.78, color: .purple, delay: 0.9, animate: viewModel.scoreAnimationTriggered)
            }
            .padding(.horizontal, 8)
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 1 {
                viewModel.triggerScoreAnimation()
            }
        }
    }

    // MARK: - Page 3: Practice Toolkit

    private var practiceToolkitPage: some View {
        onboardingPage(
            title: "Your Practice Toolkit",
            subtitle: "Everything you need to warm up, practice, and build real confidence."
        ) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.teal.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(.teal)
            }
        } detail: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ToolkitCard(
                        icon: "wind",
                        title: "Warm-Ups",
                        subtitle: "Breathing, tongue twisters, vocal exercises",
                        color: .cyan,
                        isVisible: viewModel.toolsRevealed >= 1
                    )
                    ToolkitCard(
                        icon: "bolt.circle",
                        title: "Quick Drills",
                        subtitle: "Filler elimination, pace control, impromptu",
                        color: .orange,
                        isVisible: viewModel.toolsRevealed >= 2
                    )
                }

                HStack(spacing: 12) {
                    ToolkitCard(
                        icon: "leaf",
                        title: "Confidence",
                        subtitle: "Calming, visualization, affirmations",
                        color: .green,
                        isVisible: viewModel.toolsRevealed >= 3
                    )
                    ToolkitCard(
                        icon: "bubble.left.and.text.bubble.right.fill",
                        title: "Prompts",
                        subtitle: "Hundreds of topics across 7 categories",
                        color: .purple,
                        isVisible: viewModel.toolsRevealed >= 4
                    )
                }
            }
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 2 {
                viewModel.revealTools()
            }
        }
    }

    // MARK: - Page 4: Curriculum

    private var curriculumPage: some View {
        onboardingPage(
            title: "Structured Learning Path",
            subtitle: "Follow a week-by-week curriculum designed to build your skills progressively."
        ) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "map.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
            }
        } detail: {
            VStack(spacing: 10) {
                CurriculumPhaseRow(
                    week: "Weeks 1–2",
                    title: "Foundation",
                    subtitle: "Pacing, breathing, reducing fillers",
                    icon: "1.circle.fill",
                    color: .green
                )
                CurriculumPhaseRow(
                    week: "Weeks 3–4",
                    title: "Building Skills",
                    subtitle: "Structure, vocabulary, pausing",
                    icon: "2.circle.fill",
                    color: .blue
                )
                CurriculumPhaseRow(
                    week: "Weeks 5+",
                    title: "Advanced",
                    subtitle: "Persuasion, improvisation, mastery",
                    icon: "3.circle.fill",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Page 5: Track Progress

    private var trackProgressPage: some View {
        onboardingPage(
            title: "Track Your Growth",
            subtitle: "Streaks, achievements, goals, and detailed analytics."
        ) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }
        } detail: {
            VStack(spacing: 10) {
                CompactProgressRow(
                    icon: "flame.fill",
                    title: "Daily Streaks",
                    subtitle: "Track consistency with milestones",
                    color: .orange,
                    isVisible: viewModel.progressItemsRevealed >= 1
                )
                CompactProgressRow(
                    icon: "trophy.fill",
                    title: "12 Achievements",
                    subtitle: "Unlock badges as you improve",
                    color: .yellow,
                    isVisible: viewModel.progressItemsRevealed >= 2
                )

                MiniContributionGraph()
                    .padding(.top, 2)
                    .opacity(viewModel.progressItemsRevealed >= 2 ? 1 : 0)
                    .offset(y: viewModel.progressItemsRevealed >= 2 ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15), value: viewModel.progressItemsRevealed)
            }
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if newValue == 4 {
                viewModel.revealProgressItems()
            }
        }
    }

    // MARK: - Page 6: Mic Permission

    private var micPermissionPage: some View {
        onboardingPage(
            title: viewModel.hasMicPermission ? "You're All Set!" : "One Last Thing",
            subtitle: viewModel.hasMicPermission
                ? "SpeakUp can now record and analyze your speech. Let's start practicing!"
                : "SpeakUp needs microphone access to record and analyze your speech."
        ) {
            Image(systemName: viewModel.hasMicPermission ? "mic.circle.fill" : "mic.circle")
                .font(.system(size: 72))
                .foregroundStyle(viewModel.hasMicPermission ? .green : .teal)
        } detail: {
            if !viewModel.hasMicPermission {
                VStack(spacing: 14) {
                    GlassButton(
                        title: "Enable Microphone",
                        icon: "mic.fill",
                        style: .primary,
                        size: .large,
                        isLoading: viewModel.isRequestingPermission
                    ) {
                        Haptics.medium()
                        Task {
                            await viewModel.requestMicPermission()
                        }
                    }

                    HStack(spacing: 20) {
                        PrivacyBadge(icon: "iphone", text: "On-device")
                        PrivacyBadge(icon: "lock.shield.fill", text: "Private")
                        PrivacyBadge(icon: "waveform", text: "Local AI")
                    }
                }
            } else {
                GlassCard(tint: AppColors.glassTintSuccess, padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All processing happens on your device")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text("No data leaves your iPhone — ever.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Waveform Hero Animation

private struct WaveformHeroView: View {
    @State private var animating = false

    private let barCount = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.teal.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 90
                    )
                )

            ForEach(0..<barCount, id: \.self) { i in
                WaveformBar(index: i, total: barCount, animating: animating)
            }

            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.teal)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let total: Int
    let animating: Bool

    private var angle: Double {
        Double(index) / Double(total) * 360
    }

    private var baseHeight: CGFloat {
        let phase = sin(Double(index) * 0.8) * 0.5 + 0.5
        return 12 + CGFloat(phase) * 20
    }

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.teal.opacity(0.8), .cyan.opacity(0.4)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: animating ? baseHeight * 1.4 : baseHeight * 0.6)
            .offset(y: -52)
            .rotationEffect(.degrees(angle))
            .animation(
                .easeInOut(duration: 0.8 + Double(index % 5) * 0.2)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.05),
                value: animating
            )
    }
}

// MARK: - Feature Pill

private struct FeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                }
        }
        .clipShape(Capsule())
    }
}

// MARK: - Animated Score Row

private struct AnimatedScoreRow: View {
    let icon: String
    let title: String
    let targetWidth: CGFloat
    let color: Color
    let delay: CGFloat
    let animate: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animate ? geo.size.width * targetWidth : 0, height: 6)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay), value: animate)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Toolkit Card (2x2 grid)

private struct ToolkitCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        GlassCard(cornerRadius: 16, tint: color.opacity(0.12), padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 16)
    }
}

// MARK: - Curriculum Phase Row

private struct CurriculumPhaseRow: View {
    let week: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard(cornerRadius: 14, tint: color.opacity(0.1), padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(week)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

// MARK: - Compact Progress Row

private struct CompactProgressRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        GlassCard(cornerRadius: 12, tint: color.opacity(0.08), padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
    }
}

// MARK: - Mini Contribution Graph

private struct MiniContributionGraph: View {
    private let columns = 14
    private let rows = 3

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.dots.scatter")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Activity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { col in
                        VStack(spacing: 3) {
                            ForEach(0..<rows, id: \.self) { row in
                                let intensity = sampleIntensity(col: col, row: row)
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(AppColors.contributionColor(intensity: intensity))
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sampleIntensity(col: Int, row: Int) -> Double {
        let seed = col * 3 + row
        let base = Double(col) / Double(columns)
        let noise = sin(Double(seed) * 2.1) * 0.3
        let value = base * 0.8 + noise
        return max(0, min(1, value))
    }
}

// MARK: - Privacy Badge

private struct PrivacyBadge: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.teal)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
