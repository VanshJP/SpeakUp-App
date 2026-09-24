import SwiftUI
import SwiftData

struct AIModelSettingsView: View {
    @Environment(LLMService.self) private var llmService
    @Query private var settingsList: [UserSettings]
    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 20) {
                    if llmService.appleIntelligenceAvailable {
                        appleIntelligenceCard
                    }
                    localModelCard
                    dictationCard
                    featuresCard
                    privacyCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("AI Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Dictation Card

    private var dictationCard: some View {
        aiCard {
            HStack(spacing: 12) {
                cardHeader(
                    icon: "waveform",
                    tint: AppColors.primary,
                    title: "Auto-format Dictation",
                    subtitle: "Clean up punctuation, capitalization, and paragraphs when you dictate into a note."
                )

                Toggle("", isOn: Binding(
                    get: { settings?.autoFormatDictation ?? true },
                    set: { settings?.autoFormatDictation = $0 }
                ))
                .labelsHidden()
                .tint(AppColors.primary)
                .disabled(settings == nil || !llmService.isAvailable)
            }
        }
    }

    // MARK: - Card Chrome

    /// Every card on this page is one width, one padding and one header recipe.
    /// They used to differ on all three: the privacy card shrank to its text and
    /// sat narrower than the rest, icons came in three sizes (36pt square, 40pt
    /// square, a bare glyph), and titles in three weights.
    private func aiCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GlassCard(padding: 16) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cardHeader(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconChip(icon: icon, tint: tint, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Subviews

    private var appleIntelligenceCard: some View {
        aiCard {
            HStack(spacing: 12) {
                cardHeader(
                    icon: "cpu",
                    tint: AppColors.primary,
                    title: "Apple Intelligence",
                    subtitle: "Built-in on-device model"
                )

                Text("Active")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppColors.success))
            }
        }
    }

    // MARK: - Local Model Card

    private var localModelCard: some View {
        aiCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    cardHeader(
                        icon: "arrow.down.circle",
                        tint: AppColors.categoryBrandBright,
                        title: "Local AI Model",
                        subtitle: "\(llmService.localLLM.modelDisplayName) • \(llmService.localLLM.approximateModelSize)"
                    )

                    localModelStatusBadge
                }

                modelTierSection

                if !llmService.appleIntelligenceAvailable {
                    Text("Download a local model to enable on-device AI coherence scoring and coaching tips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Apple Intelligence is active. The local model is an optional backup if Apple Intelligence becomes unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if llmService.appleIntelligenceAvailable && llmService.localLLM.isModelReady {
                    preferLocalToggle
                }

                localModelActions
            }
        }
    }

    private var preferLocalToggle: some View {
        @Bindable var bindable = llmService
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use Local Model for AI Features")
                    .font(.subheadline.weight(.semibold))
                Text("Route coaching insights and coherence scoring through the on-device Gemma model instead of Apple Intelligence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $bindable.preferLocalLLM)
                .labelsHidden()
                .tint(AppColors.primary)
        }
    }

    @ViewBuilder
    private var modelTierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Model Tier")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if llmService.localLLM.selectedProfile != llmService.localLLM.recommendedProfile {
                    Text("Recommended: \(llmService.localLLM.recommendedProfile.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker(
                "Model Tier",
                selection: Binding(
                    get: { llmService.localLLM.selectedProfile },
                    set: { profile in
                        Haptics.selection()
                        llmService.localLLM.selectProfile(profile)
                    }
                )
            ) {
                ForEach(llmService.localLLM.availableProfiles) { profile in
                    Text("\(profile.displayName) • \(profile.approximateModelSize)")
                        .tag(profile)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var localModelStatusBadge: some View {
        switch llmService.localLLM.modelState {
        case .ready:
            Text(llmService.appleIntelligenceAvailable ? "Standby" : "Active")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(llmService.appleIntelligenceAvailable ? AppColors.warning : AppColors.success))
        case .loading:
            Text("Loading")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(AppColors.info))
        case .downloading:
            Text("Downloading")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(AppColors.info))
        case .downloaded:
            Text("Downloaded")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        case .error:
            Text("Error")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(AppColors.error))
        case .notDownloaded:
            Text("Not Installed")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
    }

    @ViewBuilder
    private var localModelActions: some View {
        switch llmService.localLLM.modelState {
        case .notDownloaded:
            GlassButton(title: "Download model", icon: "arrow.down.circle", style: .primary, fullWidth: true) {
                Haptics.medium()
                Task { await llmService.setupLocalModel() }
            }

        case .downloading:
            ModelDownloadProgress(localLLM: llmService.localLLM)

        case .downloaded:
            HStack(spacing: 10) {
                GlassButton(title: "Load model", icon: "play.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    Task { await llmService.localLLM.loadModel() }
                }

                GlassButton(title: "Delete", icon: "trash", style: .danger, fullWidth: true) {
                    Haptics.warning()
                    llmService.localLLM.deleteModel()
                }
            }

            if let size = llmService.localLLM.modelFileSize {
                Text("Using \(size) of storage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loading:
            HStack(spacing: 12) {
                VoiceLoader()
                    .foregroundStyle(AppColors.primary)
                Text("Loading model into memory...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .ready:
            HStack(spacing: 10) {
                GlassButton(title: "Unload", icon: "stop.fill", style: .secondary, fullWidth: true) {
                    llmService.localLLM.unloadModel()
                }

                GlassButton(title: "Delete", icon: "trash", style: .danger, fullWidth: true) {
                    Haptics.warning()
                    llmService.localLLM.deleteModel()
                }
            }

            if let size = llmService.localLLM.modelFileSize {
                Text("Using \(size) of storage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.error)

                GlassButton(title: "Retry", icon: "arrow.clockwise", style: .primary, fullWidth: true) {
                    Task { await llmService.setupLocalModel() }
                }
            }
        }
    }

    // MARK: - Features Card

    private var featuresCard: some View {
        aiCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(
                    icon: "sparkles",
                    tint: AppColors.primary,
                    title: "What does this power?",
                    subtitle: "Unlocked by an on-device model"
                )

                VStack(alignment: .leading, spacing: 8) {
                    featureBullet(
                        icon: "brain",
                        text: "Smarter coherence scoring that understands meaning, not just keywords"
                    )
                    featureBullet(
                        icon: "lightbulb",
                        text: "Personalized AI coaching tips based on your speech performance"
                    )
                }

                if !llmService.isAvailable {
                    Text("Download the local AI model above or use a device with Apple Intelligence to unlock these features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Privacy Card

    private var privacyCard: some View {
        aiCard {
            cardHeader(
                icon: "lock.shield",
                tint: AppColors.success,
                title: "100% On-Device",
                subtitle: "All AI processing happens privately on your device. No data is sent to any server."
            )
        }
    }

    private func featureBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppColors.primary)
                .frame(width: 40)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Download Progress

/// The only view that reads `downloadProgress`, so a download tick re-renders
/// this row and not the settings page around it.
private struct ModelDownloadProgress: View {
    let localLLM: LocalLLMService

    var body: some View {
        VStack(spacing: 8) {
            TakeWaveform(
                levels: TakeWaveform.track,
                mode: .filled(localLLM.downloadProgress),
                barWidth: 3
            )
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Download progress")
            .accessibilityValue("\(Int(localLLM.downloadProgress * 100)) percent")

            HStack {
                Text("\(Int(localLLM.downloadProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    localLLM.cancelDownload()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.error)
            }
        }
    }
}
