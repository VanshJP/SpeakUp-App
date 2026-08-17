import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingSession = false
    @State private var showingCountdown = false
    @State private var selectedDrillMode: DrillMode?

    var sourceStory: Story?
    /// Arms a specific drill on open — used when a session's weakest subscore
    /// routes the user straight to the drill that targets it.
    var initialMode: DrillMode?

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                PageScrollView {
                    VStack(spacing: 20) {
                        if let story = sourceStory {
                            sourceStoryBanner(story)
                                .padding(.horizontal)
                        }

                        Text("Choose a drill to sharpen a specific skill.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(DrillMode.allCases) { mode in
                                Button {
                                    selectedDrillMode = mode
                                    showingCountdown = true
                                } label: {
                                    GlassCard {
                                        VStack(spacing: 12) {
                                            Image(systemName: mode.icon)
                                                .font(.largeTitle)
                                                .foregroundStyle(mode.color)

                                            Text(mode.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)

                                            Text(mode.description)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)

                                            Text("\(mode.defaultDurationSeconds)s")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(mode.color)
                                        }
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingSession) {
                DrillSessionView(viewModel: viewModel)
            }
            .overlay {
                if showingCountdown {
                    CountdownOverlayView(
                        prompt: nil,
                        duration: .thirty,
                        countdownDuration: userSettings.first?.countdownDuration ?? 15,
                        countdownStyle: CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown,
                        look: CountdownLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring,
                        backdrop: CountdownBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base,
                        onComplete: {
                            showingCountdown = false
                            if let mode = selectedDrillMode {
                                viewModel.startDrill(mode: mode)
                                showingSession = true
                            }
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
