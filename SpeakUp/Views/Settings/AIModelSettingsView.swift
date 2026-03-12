import SwiftUI

struct AIModelSettingsView: View {
    @Environment(LLMService.self) private var llmService

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    appleIntelligenceCard
                    localModelCard
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

    // MARK: - Subviews

    private var appleIntelligenceCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 40, height: 40)
                    .background(.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.headline)
                    Text("Built-in on-device model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if llmService.appleIntelligenceAvailable {
                    Text("Active")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green))
                } else {
                    Text("Not Available")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
        }
    }

    // MARK: - Local Model Card

    private var localModelCard: some View {
        GlassCard(tint: .cyan.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                        .frame(width: 40, height: 40)
                        .background(.cyan.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local AI Model")
                            .font(.headline)
                        Text("\(LocalLLMService.modelDisplayName) • \(LocalLLMService.approximateModelSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    localModelStatusBadge
                }

                // Description
                if !llmService.appleIntelligenceAvailable {
                    Text("Download a compact on-device model to enable AI-powered coherence scoring and coaching tips on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Apple Intelligence is active. The local model is an optional backup if Apple Intelligence becomes unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Actions based on state
                localModelActions
            }
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
                .background(Capsule().fill(llmService.appleIntelligenceAvailable ? .orange : .green))
        case .loading:
            Text("Loading")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.blue))
        case .downloading:
            Text("Downloading")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.blue))
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
                .background(Capsule().fill(.red))
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
            GlassButton(title: "Download Model", icon: "arrow.down.circle", style: .primary, fullWidth: true) {
                Haptics.medium()
                Task { await llmService.setupLocalModel() }
            }

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(.cyan)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        llmService.localLLM.cancelDownload()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                }
            }

        case .downloaded:
            HStack(spacing: 12) {
                GlassButton(title: "Load Model", icon: "play.fill", style: .primary) {
                    Haptics.medium()
                    Task { await llmService.loadLocalModel() }
                }

                GlassButton(title: "Delete", icon: "trash", style: .danger) {
                    Haptics.warning()
                    llmService.deleteLocalModel()
                }
            }

            if let size = llmService.localLLM.modelFileSize {
                Text("Using \(size) of storage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.cyan)
                Text("Loading model into memory...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .ready:
            HStack(spacing: 12) {
                GlassButton(title: "Unload", icon: "stop.fill", style: .secondary) {
                    llmService.unloadLocalModel()
                }

                GlassButton(title: "Delete", icon: "trash", style: .danger) {
                    Haptics.warning()
                    llmService.deleteLocalModel()
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
                    .foregroundStyle(.red)

                GlassButton(title: "Retry", icon: "arrow.clockwise", style: .primary, fullWidth: true) {
                    Task { await llmService.setupLocalModel() }
                }
            }
        }
    }

    // MARK: - Features Card

    private var featuresCard: some View {
        GlassCard(tint: .purple.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("What does this power?", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    featureBullet(
                        icon: "brain",
                        text: "Smarter coherence scoring that understands meaning, not just keywords"
                    )
                    featureBullet(
                        icon: "sparkles",
                        text: "Personalized AI coaching tips based on your speech performance"
                    )
                }

                if !llmService.isAvailable {
                    Text("Download the local AI model above or use a device with Apple Intelligence to unlock these features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Privacy Card

    private var privacyCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("100% On-Device")
                        .font(.subheadline.weight(.medium))
                    Text("All AI processing happens privately on your device. No data is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func featureBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
