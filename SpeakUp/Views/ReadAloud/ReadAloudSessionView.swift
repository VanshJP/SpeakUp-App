import SwiftUI

struct ReadAloudSessionView: View {
    @Bindable var viewModel: ReadAloudViewModel
    let passage: ReadAloudPassage
    @Environment(\.dismiss) private var dismiss
    @State private var showingResult = false

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 0) {
                // Top bar
                topBar

                // Progress bar
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Passage text with word highlighting
                ScrollViewReader { proxy in
                    ScrollView {
                        passageText
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                    }
                    .onChange(of: viewModel.currentWordIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("word_\(max(0, newIndex - 3))", anchor: .center)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.startSession(passage: passage)
        }
        .onDisappear {
            if viewModel.sessionState == .listening {
                viewModel.stopSession()
            }
        }
        .onChange(of: viewModel.sessionState) { _, newState in
            if newState == .finished {
                showingResult = true
            }
        }
        .fullScreenCover(isPresented: $showingResult) {
            if let result = viewModel.result {
                ReadAloudResultView(result: result, onRetry: {
                    showingResult = false
                    Task { await viewModel.retryPassage() }
                }, onDone: {
                    showingResult = false
                    viewModel.reset()
                    dismiss()
                })
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.reset()
                dismiss()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.warning()
                viewModel.stopSession()
                viewModel.reset()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(.ultraThinMaterial)
                    }
            }

            Spacer()

            // Timer
            Text(viewModel.formattedElapsedTime)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                }

            Spacer()

            // Accuracy badge
            HStack(spacing: 4) {
                Circle()
                    .fill(accuracyColor)
                    .frame(width: 8, height: 8)
                Text("\(Int(viewModel.accuracyPercentage))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.teal, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * viewModel.progressPercentage)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.progressPercentage)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Passage Text

    private var passageText: some View {
        let words = passage.words
        let states = viewModel.wordStates

        return WrappingHStack(alignment: .leading, spacing: 6, lineSpacing: 12) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: 22, weight: wordWeight(for: index), design: .default))
                    .foregroundStyle(wordColor(for: index, state: index < states.count ? states[index] : .upcoming))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                    .background {
                        if index < states.count && states[index] == .current {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.teal.opacity(0.2))
                        }
                    }
                    .id("word_\(index)")
            }
        }
    }

    private func wordWeight(for index: Int) -> Font.Weight {
        let states = viewModel.wordStates
        guard index < states.count else { return .regular }
        return states[index] == .current ? .bold : .regular
    }

    private func wordColor(for index: Int, state: WordMatchState) -> Color {
        switch state {
        case .upcoming: return .white.opacity(0.4)
        case .current: return .white
        case .matched: return .green
        case .mismatched: return .red
        case .skipped: return .orange
        }
    }

    private var accuracyColor: Color {
        let acc = viewModel.accuracyPercentage
        if acc >= 80 { return .green }
        if acc >= 60 { return .yellow }
        return .red
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Mic indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isListening ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(viewModel.isListening ? "Listening..." : "Not listening")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Stop button
            Button {
                Haptics.medium()
                viewModel.stopSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.body.weight(.semibold))
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.teal, .cyan.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
    }
}

// MARK: - Wrapping HStack (Flow Layout)

struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
