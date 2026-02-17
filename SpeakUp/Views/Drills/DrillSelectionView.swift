import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingSession = false
    @State private var showingCountdown = false
    @State private var selectedDrillMode: DrillMode?

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
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
        }
    }
}
