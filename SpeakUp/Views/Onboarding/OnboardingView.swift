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
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = OnboardingViewModel()
    var onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isSmallScreen = geometry.size.height < 700
            let heroHeight = isSmallScreen ? geometry.size.height * 0.18 : 160.0
            let topPadding = isSmallScreen ? geometry.size.height * 0.05 : 60.0

            ZStack {
                AppBackground(style: .subtle)
                    .ignoresSafeArea()

                TabView(selection: $viewModel.currentPage) {
                    welcomePage(heroHeight: heroHeight, topPadding: topPadding).tag(0)
                    analysisPage(heroHeight: heroHeight, topPadding: topPadding).tag(1)
                    aiSetupPage(heroHeight: heroHeight, topPadding: topPadding).tag(2)
                    practiceToolkitPage(heroHeight: heroHeight, topPadding: topPadding).tag(3)
                    curriculumPage(heroHeight: heroHeight, topPadding: topPadding).tag(4)
                    trackProgressPage(heroHeight: heroHeight, topPadding: topPadding).tag(5)
                    notificationPage(heroHeight: heroHeight, topPadding: topPadding).tag(6)
                    micPermissionPage(heroHeight: heroHeight, topPadding: topPadding).tag(7)
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
            // Page Indicators
            HStack(spacing: 8) {
                ForEach(0..<viewModel.totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == viewModel.currentPage ? Color.teal : Color.white.opacity(0.15))
                        .frame(
                            width: index == viewModel.currentPage ? 28 : 8,
                            height: 8
                        )
                        .animation(.easeInOut(duration: 0.25), value: viewModel.currentPage)
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

    private func onboardingPage<Hero: View, Detail: View>(
        pageIndex: Int,
        title: String,
        subtitle: String,
        heroHeight: CGFloat,
        topPadding: CGFloat,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero()
                    .frame(height: heroHeight)
                    .padding(.top, topPadding)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: heroHeight > 140 ? 32 : 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineSpacing(4)
                }
                .padding(.top, OnboardingLayout.heroToTitleSpacing)

                detail()
                    .padding(.top, OnboardingLayout.titleToContentSpacing)

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
            Image(systemName: "waveform")
                .font(.system(size: heroHeight * 0.35, weight: .bold))
                .foregroundStyle(.teal)
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
                // Score Ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: heroHeight * 0.75, height: heroHeight * 0.75)

                Circle()
                    .trim(from: 0, to: 0.82)
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

                VStack(spacing: 0) {
                    Text("82")
                        .font(.system(size: heroHeight * 0.25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("MASTER")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.5))
                        .kerning(1)
                }
            }
        } detail: {
            VStack(spacing: 12) {
                ScoreRow(icon: "waveform", title: "Clarity", width: 0.85, color: .blue)
                ScoreRow(icon: "speedometer", title: "Pace", width: 0.72, color: .green)
                ScoreRow(icon: "text.badge.minus", title: "Fillers", width: 0.90, color: .orange)
                ScoreRow(icon: "pause.circle", title: "Pausing", width: 0.78, color: .purple)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Page 3: AI Setup

    private func aiSetupPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 2,
            title: "Choose Your AI Mode",
            subtitle: "SpeakUp always works on-device. Extra AI quality is optional and transparent.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: llmService.appleIntelligenceAvailable ? "apple.intelligence" : "cpu")
                .font(.system(size: heroHeight * 0.38))
                .foregroundStyle(llmService.appleIntelligenceAvailable ? .purple : .teal)
        } detail: {
            VStack(spacing: 12) {
                aiModeStatusCard
                aiTransparencyCard
                if !llmService.appleIntelligenceAvailable {
                    aiLocalModelActionCard
                }
            }
        }
    }

    // MARK: - Page 4: Practice Toolkit

    private func practiceToolkitPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 3,
            title: "Practice Toolkit",
            subtitle: "Techniques for every scenario—from tongue twisters to impromptu speaking.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: "sparkles")
                .font(.system(size: heroHeight * 0.4))
                .foregroundStyle(.teal)
        } detail: {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ToolkitCard(icon: "wind", title: "Warm-Ups", subtitle: "Vocal & breathing", color: .cyan)
                    ToolkitCard(icon: "bolt.circle", title: "Drills", subtitle: "Active training", color: .orange)
                }
                HStack(spacing: 16) {
                    ToolkitCard(icon: "leaf", title: "Calm", subtitle: "Mental preparation", color: .green)
                    ToolkitCard(icon: "bubble.left.and.text.bubble.right", title: "Prompts", subtitle: "Topic library", color: .purple)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Page 5: Curriculum

    private func curriculumPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 4,
            title: "Expert Pathway",
            subtitle: "A structured curriculum built to transform your speaking in just 4 weeks.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: "map.fill")
                .font(.system(size: heroHeight * 0.35))
                .foregroundStyle(.blue)
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

    // MARK: - Page 6: Track Progress

    private func trackProgressPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 5,
            title: "Your Growth",
            subtitle: "Watch your confidence soar with detailed progress tracking and streaks.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: heroHeight * 0.35))
                .foregroundStyle(.green)
        } detail: {
            VStack(spacing: 12) {
                CompactProgressRow(
                    icon: "flame.fill",
                    title: "Daily Consistency",
                    subtitle: "Build a lasting practice habit",
                    color: .orange
                )
                MiniContributionGraph()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Page 7: Notifications

    private func notificationPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 6,
            title: viewModel.hasNotificationPermission ? "All Set!" : "Stay Inspired",
            subtitle: viewModel.hasNotificationPermission
                ? "We'll keep you motivated with timely practice reminders."
                : "Enable notifications for daily tips and practice reminders to keep your streak alive.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: viewModel.hasNotificationPermission ? "bell.badge.fill" : "bell.badge")
                .font(.system(size: heroHeight * 0.45))
                .foregroundStyle(viewModel.hasNotificationPermission ? .green : .orange)
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

    // MARK: - Page 8: Mic Permission

    private func micPermissionPage(heroHeight: CGFloat, topPadding: CGFloat) -> some View {
        onboardingPage(
            pageIndex: 7,
            title: viewModel.hasMicPermission ? "Ready to Go!" : "Voice Access",
            subtitle: viewModel.hasMicPermission
                ? "The stage is yours. Let's start your first practice session."
                : "We need microphone access to analyze your speech. Everything stays on your device.",
            heroHeight: heroHeight,
            topPadding: topPadding
        ) {
            Image(systemName: viewModel.hasMicPermission ? "mic.circle.fill" : "mic.circle")
                .font(.system(size: heroHeight * 0.5))
                .foregroundStyle(viewModel.hasMicPermission ? .green : .teal)
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
                    PrivacyBadge(icon: "wifi.slash", text: "Offline ")
                }
            }
        }
    }

    // MARK: - AI Setup Components

    private var aiModeStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: llmService.appleIntelligenceAvailable ? "apple.intelligence" : "cpu")
                        .font(.title3)
                        .foregroundStyle(llmService.appleIntelligenceAvailable ? .purple : .teal)
                    Text("Current AI Mode")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    OnboardingAIModeBadge(
                        text: aiModeLabel,
                        tint: aiModeTint
                    )
                }

                Text(aiModeDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aiTransparencyCard: some View {
        GlassCard(tint: .teal.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Why this matters", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                OnboardingAIBullet(text: "Core scoring works with zero AI downloads.")
                OnboardingAIBullet(text: "AI adds better semantic coherence and coaching quality.")
                OnboardingAIBullet(text: "All processing stays on your device—nothing is sent to servers.")
            }
        }
    }

    @ViewBuilder
    private var aiLocalModelActionCard: some View {
        GlassCard(tint: .cyan.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Optional local model")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(LocalLLMService.approximateModelSize)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                }

                Text("Download \(LocalLLMService.modelDisplayName) now to unlock stronger on-device AI on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                switch llmService.localLLM.modelState {
                case .ready:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Local model ready")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.cyan)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .tint(.cyan)
                        Text("Downloading \(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                case .downloaded:
                    GlassButton(
                        title: "Load Model",
                        icon: "play.fill",
                        style: .secondary,
                        size: .small,
                        fullWidth: true
                    ) {
                        Task { await llmService.loadLocalModel() }
                    }
                case .error(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        GlassButton(
                            title: "Retry Download",
                            icon: "arrow.clockwise",
                            style: .primary,
                            size: .small,
                            fullWidth: true
                        ) {
                            Task { await llmService.setupLocalModel() }
                        }
                    }
                case .notDownloaded:
                    GlassButton(
                        title: "Download Local AI",
                        icon: "arrow.down.circle",
                        style: .primary,
                        size: .small,
                        fullWidth: true
                    ) {
                        Task { await llmService.setupLocalModel() }
                    }
                }
            }
        }
    }

    private var aiModeLabel: String {
        if llmService.appleIntelligenceAvailable {
            return "Apple Intelligence"
        }
        if llmService.localLLM.isModelReady {
            return "Local LLM Active"
        }
        if llmService.localLLM.isModelDownloaded {
            return "Local LLM Installed"
        }
        return "Rule-Based + Core AI"
    }

    private var aiModeTint: Color {
        if llmService.appleIntelligenceAvailable {
            return .purple
        }
        if llmService.localLLM.isModelReady {
            return .green
        }
        if llmService.localLLM.isModelDownloaded {
            return .orange
        }
        return .teal
    }

    private var aiModeDescription: String {
        if llmService.appleIntelligenceAvailable {
            return "Apple Intelligence is available on this device and will be used for advanced coherence and coaching signals."
        }
        if llmService.localLLM.isModelReady {
            return "Your downloaded local model is active and will support enhanced scoring and coaching fully on-device."
        }
        if llmService.localLLM.isModelDownloaded {
            return "Your local model is downloaded. We’ll load it automatically when needed to save memory."
        }
        return "You can keep using core speech scoring now, then optionally add a local model later in Settings."
    }
}

// MARK: - Components

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

private struct OnboardingAIModeBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.9)))
    }
}

private struct OnboardingAIBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.teal)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
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
    }
}

private struct ScoreRow: View {
    let icon: String
    let title: String
    let width: CGFloat
    let color: Color

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
                        .frame(width: geo.size.width * width, height: 8)
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

    var body: some View {
        GlassCard(cornerRadius: 20, tint: color.opacity(0.15), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)

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
