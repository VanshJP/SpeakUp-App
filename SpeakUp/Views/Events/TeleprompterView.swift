import MediaPlayer
import SwiftUI

private enum TeleprompterWorkflowMode: String, CaseIterable, Identifiable {
    case liveRehearsal
    case prerecordAutoScroll
    case externalDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveRehearsal: return "Live"
        case .prerecordAutoScroll: return "Pre-Record"
        case .externalDisplay: return "External"
        }
    }

    var subtitle: String {
        switch self {
        case .liveRehearsal: return "Manual + auto-scroll rehearsal"
        case .prerecordAutoScroll: return "Auto-scroll, then jump into recording"
        case .externalDisplay: return "Mirror to another display for recording"
        }
    }
}

struct TeleprompterView: View {
    let scriptText: String
    var speed: Double = 1.0
    var fontSize: Double = 24.0
    var onStartRecording: (() -> Void)?
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
    @State private var nowPlaying = TeleprompterNowPlayingController.shared
    @State private var workflowMode: TeleprompterWorkflowMode = .prerecordAutoScroll
    @State private var prerecordCountdown = 0

    private let basePixelsPerSecond: CGFloat = 30

    init(
        scriptText: String,
        speed: Double = 1.0,
        fontSize: Double = 24.0,
        onStartRecording: (() -> Void)? = nil,
        onSettingsChanged: ((Double, Double) -> Void)? = nil
    ) {
        self.scriptText = scriptText
        self.speed = speed
        self.fontSize = fontSize
        self.onStartRecording = onStartRecording
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

    private var progress: Double {
        guard maxScroll > 0 else { return 0 }
        return max(0, min(1, Double(scrollOffset / maxScroll)))
    }

    private var estimatedDuration: TimeInterval {
        guard adjustedSpeed > 0 else { return 0 }
        return TimeInterval(maxScroll / (CGFloat(adjustedSpeed) * basePixelsPerSecond))
    }

    private var elapsedEstimate: TimeInterval {
        estimatedDuration * progress
    }

    private var speedDescriptor: String {
        switch adjustedSpeed {
        case ..<0.85: return "Slow and steady"
        case 0.85..<1.2: return "Natural pace"
        case 1.2..<1.7: return "Presentation pace"
        default: return "Fast rehearsal"
        }
    }

    private var estimatedWordsPerMinute: Int {
        Int((110 * adjustedSpeed).rounded())
    }

    private var nowPlayingTitle: String {
        let snippet = scriptText
            .split(separator: " ")
            .prefix(8)
            .joined(separator: " ")
        return snippet.isEmpty ? "Teleprompter Session" : snippet + "..."
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

            if prerecordCountdown > 0 {
                countdownOverlay
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
        .onAppear {
            nowPlaying.onTogglePlayPause = {
                Task { @MainActor in
                    toggleScrolling()
                }
            }
            nowPlaying.onRestart = {
                Task { @MainActor in
                    resetTeleprompter()
                }
            }
            updateNowPlayingOverlay()
        }
        .onChange(of: isScrolling) { _, _ in
            updateNowPlayingOverlay()
        }
        .onChange(of: scrollOffset) { _, _ in
            updateNowPlayingOverlay()
        }
        .onChange(of: adjustedSpeed) { _, _ in
            updateNowPlayingOverlay()
        }
        .onChange(of: workflowMode) { _, _ in
            updateNowPlayingOverlay()
        }
        .onDisappear {
            onSettingsChanged?(adjustedSpeed, adjustedFontSize)
            nowPlaying.clear()
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

                Text("Teleprompter • \(workflowMode.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Reset button
                GlassIconButton(icon: "arrow.counterclockwise") {
                    Haptics.light()
                    resetTeleprompter()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            workflowModePicker
                .padding(.horizontal, 20)
                .padding(.top, 10)

            Spacer()

            // Bottom controls
            VStack(spacing: 16) {
                if workflowMode == .externalDisplay {
                    externalDisplayHelp
                } else {
                    // Play/Pause button
                    Button {
                        if workflowMode == .prerecordAutoScroll && !isScrolling {
                            startPrerecordCountdown()
                        } else {
                            toggleScrolling()
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
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Scroll Speed", systemImage: "speedometer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(estimatedWordsPerMinute) wpm • \(String(format: "%.2fx", adjustedSpeed))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $adjustedSpeed, in: 0.5...3.0, step: 0.05)
                        .tint(AppColors.primary)

                    HStack(spacing: 8) {
                        ForEach([0.8, 1.0, 1.25, 1.5], id: \.self) { preset in
                            Button {
                                adjustedSpeed = preset
                                Haptics.selection()
                            } label: {
                                Text(String(format: "%.2fx", preset))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(abs(adjustedSpeed - preset) < 0.01 ? .white : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background {
                                        Capsule()
                                            .fill(abs(adjustedSpeed - preset) < 0.01 ? AppColors.primary.opacity(0.45) : Color.white.opacity(0.08))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                // Font size control
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Text Size", systemImage: "textformat.size")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(adjustedFontSize)) pt")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $adjustedFontSize, in: 16...48, step: 2)
                        .tint(AppColors.primary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speedDescriptor)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(formatTime(elapsedEstimate)) elapsed • \(formatTime(max(0, estimatedDuration - elapsedEstimate))) left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Overlay active", systemImage: "rectangle.stack.badge.play")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                }

                if workflowMode != .liveRehearsal {
                    GlassButton(title: "Start Recording", icon: "mic.fill", style: .primary, fullWidth: true) {
                        Haptics.heavy()
                        onStartRecording?()
                    }
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

    private var workflowModePicker: some View {
        HStack(spacing: 8) {
            ForEach(TeleprompterWorkflowMode.allCases) { mode in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        workflowMode = mode
                        if mode == .externalDisplay {
                            isScrolling = false
                        }
                    }
                } label: {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(workflowMode == mode ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(workflowMode == mode ? AppColors.primary.opacity(0.55) : Color.white.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var externalDisplayHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("External Display Mode", systemImage: "display.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text("Use AirPlay or wired mirroring to place the script on another display. Keep this teleprompter visible there, then tap Start Recording to capture audio on your phone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
                }
        }
    }

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Recording starts soon")
                    .font(.headline)
                Text("\(prerecordCountdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primary)
            }
            .foregroundStyle(.white)
        }
        .transition(.opacity)
    }

    private func toggleScrolling() {
        guard workflowMode != .externalDisplay else { return }
        Haptics.medium()
        isScrolling.toggle()
        if !isScrolling {
            lastTime = nil
        }
    }

    private func startPrerecordCountdown() {
        guard prerecordCountdown == 0 else { return }
        Haptics.medium()
        isScrolling = false
        lastTime = nil

        Task { @MainActor in
            for remaining in stride(from: 3, through: 1, by: -1) {
                prerecordCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            prerecordCountdown = 0
            isScrolling = true
        }
    }

    private func resetTeleprompter() {
        isScrolling = false
        lastTime = nil
        withAnimation(.spring(response: 0.3)) {
            scrollOffset = 0
        }
    }

    private func updateNowPlayingOverlay() {
        nowPlaying.update(
            title: nowPlayingTitle,
            subtitle: "Teleprompter • \(workflowMode.title) • \(speedDescriptor)",
            elapsed: elapsedEstimate,
            duration: max(estimatedDuration, 1),
            speed: adjustedSpeed,
            isPlaying: isScrolling
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let mins = whole / 60
        let secs = whole % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
private final class TeleprompterNowPlayingController {
    static let shared = TeleprompterNowPlayingController()

    var onTogglePlayPause: (() -> Void)?
    var onRestart: (() -> Void)?

    private var didConfigureCommands = false

    private init() {}

    func update(
        title: String,
        subtitle: String,
        elapsed: TimeInterval,
        duration: TimeInterval,
        speed: Double,
        isPlaying: Bool
    ) {
        configureRemoteCommandsIfNeeded()

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = subtitle
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        onTogglePlayPause = nil
        onRestart = nil
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !didConfigureCommands else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        didConfigureCommands = true
    }
}
