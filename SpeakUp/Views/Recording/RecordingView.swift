import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RecordingViewModel()

    let prompt: Prompt?
    let duration: RecordingDuration
    let onComplete: (Recording) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Background
            audioBackground

            // Content Overlay
            VStack(spacing: 0) {
                // Top Bar
                topBar

                Spacer()

                // Center Content (Timer)
                centerContent

                Spacer()

                // Bottom Controls
                bottomControls
            }
            .padding()
        }
        .ignoresSafeArea()
        .task {
            viewModel.configure(
                with: modelContext,
                prompt: prompt,
                duration: duration
            )
            await viewModel.checkPermissions()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert("Permission Required", isPresented: $viewModel.showingPermissionAlert) {
            Button("Cancel") { onCancel() }
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(viewModel.permissionAlertMessage)
        }
    }

    // MARK: - Audio Background

    private var audioBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(white: 0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Show waveform during recording
            if viewModel.isRecording {
                AudioWaveformView(audioLevel: viewModel.audioLevel)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                // Close button
                Button {
                    if viewModel.isRecording {
                        viewModel.cancelRecording()
                    }
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }

                Spacer()

                // Duration badge
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(duration.displayName)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }

                Spacer()

                // Audio badge
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text("Audio")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }

            // Compact prompt card at top (during recording)
            if let prompt, viewModel.isRecording {
                compactPromptCard(prompt)
            }
        }
        .padding(.top, 50)
    }

    private func compactPromptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.category)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(prompt.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.8))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 24) {
            // Timer
            TimerView(
                remainingTime: viewModel.remainingTime,
                totalTime: TimeInterval(duration.seconds),
                progress: viewModel.progress,
                color: viewModel.timerColor,
                isRecording: viewModel.isRecording
            )

            // Voice activity indicator (during recording)
            if viewModel.isRecording {
                voiceActivityIndicator
            }

            // Prompt Card (if available) - show only before recording starts
            if let prompt, !viewModel.isRecording {
                promptCard(prompt)
            }
        }
    }

    private var voiceActivityIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.audioLevel > -40 ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.15), value: viewModel.audioLevel > -40)

            Text(viewModel.audioLevel > -40 ? "Speaking" : "Silent")
                .font(.caption.weight(.medium))
                .foregroundStyle(viewModel.audioLevel > -40 ? .white : .white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    private func promptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prompt.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(prompt.difficulty.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(AppColors.difficultyColor(prompt.difficulty).opacity(0.3))
                    }
                    .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))
            }

            Text(prompt.text)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 24) {
            // Recording status
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)

                    Text("Recording")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.red.opacity(0.3))
                }
            }

            // Record Button
            RecordButton(
                isRecording: viewModel.isRecording,
                onTap: {
                    Task {
                        if viewModel.isRecording {
                            if let recording = await viewModel.stopRecording() {
                                onComplete(recording)
                            }
                        } else {
                            await viewModel.startRecording()
                        }
                    }
                }
            )

            // Hint text
            if !viewModel.isRecording {
                Text("Tap to start recording")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("Tap to stop")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let audioLevel: Float
    private let barCount = 40

    // Store previous levels for smooth animation
    @State private var barHeights: [CGFloat] = Array(repeating: 0.1, count: 40)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                // Left half (mirrored)
                ForEach(0..<barCount/2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barGradient(for: index, isLeftSide: true))
                        .frame(width: barWidth(geometry: geometry))
                        .frame(height: barHeights[barCount/2 - 1 - index] * geometry.size.height)
                }
                // Right half
                ForEach(0..<barCount/2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barGradient(for: index, isLeftSide: false))
                        .frame(width: barWidth(geometry: geometry))
                        .frame(height: barHeights[barCount/2 + index] * geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 160)
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(level: newLevel)
        }
    }

    private func barWidth(geometry: GeometryProxy) -> CGFloat {
        (geometry.size.width - CGFloat(barCount - 1) * 3) / CGFloat(barCount)
    }

    private func barGradient(for index: Int, isLeftSide: Bool) -> LinearGradient {
        // Gradient fades from center outward
        let distanceFromCenter = isLeftSide ? CGFloat(barCount/2 - index) : CGFloat(index)
        let maxDistance = CGFloat(barCount/2)
        let opacity = 1.0 - (distanceFromCenter / maxDistance * 0.5)

        return LinearGradient(
            colors: [
                Color.teal.opacity(opacity),
                Color.cyan.opacity(opacity)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func updateBars(level: Float) {
        // Fix: Convert dB level (-60 to 0 range for speech) to normalized value (0 to 1)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))
        let baseHeight = CGFloat(normalizedLevel) * 0.8 + 0.1

        withAnimation(.easeOut(duration: 0.05)) {
            // Shift bars to the left and add new value at the end
            for i in 0..<(barCount - 1) {
                barHeights[i] = barHeights[i + 1]
            }
            // Add some randomness for visual interest
            let variation = CGFloat.random(in: 0.85...1.15)
            barHeights[barCount - 1] = min(1.0, baseHeight * variation)
        }
    }
}

#Preview {
    RecordingView(
        prompt: nil,
        duration: .sixty,
        onComplete: { _ in },
        onCancel: {}
    )
    .modelContainer(for: [Recording.self, Prompt.self], inMemory: true)
}
