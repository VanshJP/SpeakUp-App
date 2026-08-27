import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingSession = false
    @State private var showingCountdown = false
    @State private var selectedDrillMode: DrillMode?

    /// When true the grid is pushed onto a caller-owned `NavigationStack`
    /// (Library → Tools): no inner stack, and the sheet's ✕ gives way to the
    /// system back button.
    var isPushed: Bool = false

    var sourceStory: Story?
    /// Arms a specific drill on open — used when a session's weakest subscore
    /// routes the user straight to the drill that targets it.
    var initialMode: DrillMode?

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    private var content: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 20) {
                    // One line, not a banner card: the nav bar already names
                    // the page, so the header says what the tool gets you and
                    // gets out of the way. Copy comes from PracticeToolKind.
                    Text(PracticeToolKind.drills.outcome)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    if let story = sourceStory {
                        sourceStoryBanner(story)
                            .padding(.horizontal)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(DrillMode.allCases) { mode in
                            Button {
                                Haptics.medium()
                                // Impromptu picks its topic now so the prep
                                // countdown can show it — that window is the
                                // thinking time the format promises.
                                if mode == .impromptuSprint {
                                    viewModel.prepareImpromptuTopic()
                                }
                                selectedDrillMode = mode
                                showingCountdown = true
                            } label: {
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.title2.weight(.semibold))
                                            .foregroundStyle(mode.color)

                                        Text(mode.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        // Outcome first: what the drill fixes.
                                        Text(mode.outcome)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)

                                        // What the session shows while it
                                        // runs — the concrete promise that
                                        // makes the format legible.
                                        Label(mode.liveFeedback, systemImage: "waveform.path.ecg")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(mode.color)
                                            .lineLimit(1)

                                        // Duration + mechanic is the cost line.
                                        Text(mode.description)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(mode.color)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 176, maxHeight: 176, alignment: .topLeading)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Quick Drills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // The ✕ is a sheet affordance; a pushed page closes with Back.
            if !isPushed {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSession) {
            DrillSessionView(viewModel: viewModel)
        }
        .overlay {
            if showingCountdown, let mode = selectedDrillMode {
                CountdownOverlayView(
                    prompt: nil,
                    duration: .thirty,
                    countdownDuration: userSettings.first?.countdownDuration ?? 15,
                    countdownStyle: CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown,
                    look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring,
                    backdrop: RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base,
                    prepTitle: mode.title,
                    prepSubtitle: mode == .impromptuSprint ? viewModel.impromptuPrompt : mode.description,
                    onComplete: {
                        showingCountdown = false
                        viewModel.startDrill(mode: mode)
                        showingSession = true
                    },
                    onCancel: {
                        showingCountdown = false
                        selectedDrillMode = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingCountdown)
        .task {
            guard let initialMode else { return }
            selectedDrillMode = initialMode
            showingCountdown = true
        }
    }

    private func sourceStoryBanner(_ story: Story) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.categoryNeutralCool)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drilling from")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(story.title.isEmpty ? "Untitled story" : story.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            Text("Impromptu")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.categoryNeutralCool)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(AppColors.categoryNeutralCool.opacity(0.18))
                }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.categoryNeutralCool.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.categoryNeutralCool.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}
