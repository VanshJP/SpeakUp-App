import SwiftUI
import SwiftData

struct FirstRecordingSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }

    @State private var selectedDuration: RecordingDuration = .sixty
    @State private var selectedTimerBehavior: Int = 0
    @State private var countdownSeconds: Int = 10
    @State private var showFullSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        quickSettingsSection
                        fullSettingsButton
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Welcome!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.teal)
                }
            }
            .navigationDestination(isPresented: $showFullSettings) {
                SettingsView()
            }
            .onAppear {
                if let settings {
                    selectedDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
                    selectedTimerBehavior = settings.timerEndBehavior
                    countdownSeconds = settings.countdownDuration
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.12), .cyan.opacity(0.06)],
            padding: 20
        ) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Great first recording!")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("Customize your session defaults so every future recording feels just right.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var quickSettingsSection: some View {
        VStack(spacing: 14) {
            GlassSectionHeader("Quick Setup", icon: "slider.horizontal.3")

            GlassCard {
                VStack(spacing: 16) {
                    // Default Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Default Duration", systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            ForEach(RecordingDuration.allCases) { duration in
                                selectionTile(
                                    text: duration.displayName,
                                    isSelected: selectedDuration == duration
                                ) {
                                    Haptics.light()
                                    selectedDuration = duration
                                }
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    // Timer End Behavior
                    VStack(alignment: .leading, spacing: 8) {
                        Label("When Timer Ends", systemImage: "timer")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            timerBehaviorOption(
                                title: "Save & Stop",
                                icon: "stop.circle",
                                value: 0
                            )
                            timerBehaviorOption(
                                title: "Keep Going",
                                icon: "play.circle",
                                value: 1
                            )
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    // Countdown Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Countdown: \(countdownSeconds)s", systemImage: "hourglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            ForEach([3, 5, 10, 15], id: \.self) { seconds in
                                selectionTile(
                                    text: "\(seconds)s",
                                    isSelected: countdownSeconds == seconds
                                ) {
                                    Haptics.light()
                                    countdownSeconds = seconds
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func timerBehaviorOption(title: String, icon: String, value: Int) -> some View {
        Button {
            Haptics.light()
            selectedTimerBehavior = value
        } label: {
            let isSelected = selectedTimerBehavior == value
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.primary.opacity(0.5) : .clear)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.primary.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func selectionTile(text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AppColors.primary.opacity(0.5) : .clear)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppColors.primary.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private var fullSettingsButton: some View {
        GlassButton(
            title: "All Settings",
            icon: "gearshape",
            style: .secondary,
            fullWidth: true
        ) {
            Haptics.medium()
            showFullSettings = true
        }
    }

    // MARK: - Save

    private func saveSettings() {
        guard let settings else { return }
        settings.defaultDuration = selectedDuration.rawValue
        settings.timerEndBehavior = selectedTimerBehavior
        settings.countdownDuration = countdownSeconds
        try? modelContext.save()
        Haptics.success()
    }
}
