import SwiftUI

struct DrillSessionView: View {
    var viewModel: DrillViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 24) {
                // Top bar
                HStack {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Spacer()

                    if let mode = viewModel.selectedMode {
                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Spacer()
                    Spacer().frame(width: 44)
                }
                .padding(.top, 50)

                if viewModel.isComplete, let result = viewModel.result {
                    DrillResultView(result: result) {
                        if let mode = viewModel.selectedMode {
                            viewModel.startDrill(mode: mode)
                        }
                    } onDone: {
                        dismiss()
                    }
                } else {
                    drillContent
                }
            }
            .padding()
        }
    }

    private var drillContent: some View {
        VStack(spacing: 32) {
            Spacer()

            // Mode-specific display
            if let mode = viewModel.selectedMode {
                switch mode {
                case .fillerElimination:
                    fillerDisplay
                case .paceControl:
                    paceDisplay
                case .pausePractice:
                    pauseDisplay
                case .impromptuSprint:
                    impromptuDisplay
                }
            }

            // Timer
            Text("\(viewModel.timeRemaining)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: viewModel.timeRemaining)

            // Progress ring
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        viewModel.selectedMode?.color ?? .teal,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: viewModel.progress)
            }
            .frame(width: 120, height: 120)

            Spacer()

            // Stop button
            Button {
                viewModel.finishDrill()
            } label: {
                Text("Stop")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 52)
                    .background(Capsule().fill(.red.opacity(0.8)))
            }
            .padding(.bottom, 40)
        }
    }

    private var fillerDisplay: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.liveFillerCount)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.liveFillerCount == 0 ? .green : .orange)

            Text("fillers detected")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var paceDisplay: some View {
        VStack(spacing: 8) {
            Text("\(Int(viewModel.liveWPM))")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.liveWPM >= 130 && viewModel.liveWPM <= 170 ? .green : .red)

            Text("WPM")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            Text("Target: 130-170")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var pauseDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Pause at the markers")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var impromptuDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Speak now!")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}
