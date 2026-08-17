import Photos
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share surface for a scored session: pick which card leaves the app, see
/// it before it does, then save, copy, or send it.
///
/// This replaced a confirmation dialog with two buttons and a paragraph
/// explaining what each one would reveal. Nobody reads a paragraph about what a
/// picture contains when the picture can be shown instead — and the preview is
/// the privacy control, because the prompt is either visibly on the card or it
/// is not.
struct ShareCardSheet: View {
    let recording: Recording
    /// Fires on any completed outbound action, not just the system sheet —
    /// saving to Photos is the same intent by a different route.
    var onShared: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    /// The challenge card is the default — it is the one that travels, because
    /// it carries a link a friend can tap. Turning it off falls back to the
    /// scores-only card.
    @State private var includePrompt = true
    /// Keyed by variant *and* theme — switching either one is a different card.
    @State private var rendered: [String: UIImage] = [:]
    @State private var confirmation: String?
    /// A card needs a score. Reached by opening the sheet on a session that was
    /// saved but never analyzed — without this the preview spins forever and
    /// the buttons do nothing.
    @State private var unavailable = false

    /// Which card gets rendered. Kept as a type rather than a bare flag because
    /// it keys the render cache and names the card in analytics.
    ///
    /// `nonisolated` because it is a pure value type nested in a MainActor
    /// view — see `docs/AGENT_GOTCHAS.md`.
    nonisolated enum Variant: String, Hashable, Identifiable {
        case scores
        case challenge

        var id: String { rawValue }

        var includesPromptText: Bool { self == .challenge }

        var cardType: String {
            includesPromptText ? "score_card_with_prompt" : "score_card"
        }
    }

    /// The challenge card only exists when there is something to challenge with.
    private var challengeAvailable: Bool {
        ScoreCardRenderer.promptCaption(for: recording) != nil
    }

    private var variant: Variant {
        challengeAvailable && includePrompt ? .challenge : .scores
    }

    private var theme: ScoreCardTheme {
        ScoreCardTheme(rawValue: userSettings.first?.shareCardTheme ?? 0) ?? .midnight
    }

    private var renderKey: String { "\(variant.rawValue)_\(theme.rawValue)" }

    var body: some View {
        VStack(spacing: 0) {
            header

            preview
                .frame(maxHeight: .infinity)

            if !unavailable {
                themeStrip.padding(.bottom, 14)
            }

            if challengeAvailable && !unavailable {
                promptToggle.padding(.bottom, 18)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground { AppBackground(style: .subtle) }
        .task(id: renderKey) { await renderIfNeeded(variant) }
        .overlay(alignment: .bottom) {
            if let confirmation {
                Text(confirmation)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5)
                    }
                    .padding(.bottom, 130)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.slide, value: confirmation)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                Text("Share")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                HStack {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 34, height: 34)
                            .background {
                                Circle().fill(Color.white.opacity(0.06))
                                Circle().stroke(AppColors.cardStroke, lineWidth: 0.5)
                            }
                    }
                    .accessibilityLabel("Close")

                    Spacer()
                }
            }

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// One line saying what is on the card in front of them. This is the whole
    /// text budget of the screen — the card says the rest.
    private var subtitle: String {
        switch variant {
        case .scores:
            return "Your scores only. No prompt, no transcript."
        case .challenge:
            return recording.prompt != nil
                ? "Your scores, the prompt, and a link your friend can tap."
                : "Your scores and your story's title."
        }
    }

    // MARK: - Cards

    private var preview: some View {
        Group {
            if let image = rendered[renderKey] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    // The card is dark on a dark canvas, so the standard
                    // `cardStroke` hairline vanishes. A brighter rim lit from
                    // the top, a deep drop shadow, and a faint ambient glow are
                    // what separate the preview from the sheet behind it.
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.28),
                                        .white.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.65), radius: 30, y: 18)
                    .shadow(color: .white.opacity(0.05), radius: 18)
                    .accessibilityLabel("Share card preview")
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColors.surfaceLift)
                    .overlay {
                        if unavailable {
                            Text("This session hasn't been scored yet.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(24)
                        } else {
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    }
                    .aspectRatio(0.62, contentMode: .fit)
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 18)
    }

    /// Filter-strip picker: the swatch is the actual backdrop the card uses,
    /// so no second render is needed to show what you are choosing.
    private var themeStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ScoreCardTheme.allCases) { option in
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 6) {
                            // Drawn at card scale then shrunk, so the swatch
                            // shows the real gradient rather than one corner
                            // of it — the orbs are sized in absolute points.
                            option.background
                                .frame(width: 400, height: 400)
                                .scaleEffect(0.13)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            option == theme ? Color.white.opacity(0.9) : AppColors.cardStroke,
                                            lineWidth: option == theme ? 2 : 0.5
                                        )
                                }

                            Text(option.displayName)
                                .font(.caption2.weight(option == theme ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(option == theme ? 0.9 : 0.45))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(option == theme ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func select(_ option: ScoreCardTheme) {
        guard option != theme, let settings = userSettings.first else { return }
        Haptics.selection()
        settings.shareCardTheme = option.rawValue
        try? modelContext.save()
    }

    private var promptToggle: some View {
        Toggle(isOn: $includePrompt) {
            Text(recording.prompt != nil ? "Include prompt and link" : "Include story title")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .tint(AppColors.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.cardStroke, lineWidth: 0.5)
        }
        .padding(.horizontal, 20)
        .onChange(of: includePrompt) { _, _ in Haptics.selection() }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        if unavailable {
            GlassButton(title: "Done", style: .secondary) { dismiss() }
                .padding(.bottom, 28)
        } else {
            HStack(spacing: 4) {
                ShareAction(icon: "square.and.arrow.down", label: "Save\nimage") {
                    withImage { image in Task { await saveToPhotos(image) } }
                }
                ShareAction(icon: "doc.on.doc", label: "Copy\nimage") {
                    withImage(copyToPasteboard)
                }
                ShareAction(icon: "square.and.arrow.up", label: "Share", prominent: true) {
                    withImage(presentSystemSheet)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    /// Every action needs the rendered card. Rendering is fast enough to do
    /// inline on the rare miss (a tap landing before `.task` finished) rather
    /// than disabling the buttons until it lands.
    private func withImage(_ body: (UIImage) -> Void) {
        guard let image = rendered[renderKey] ?? render(variant) else { return }
        rendered[renderKey] = image
        body(image)
    }

    private func saveToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            confirm("Allow photo access in Settings to save")
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Haptics.success()
        confirm("Saved to Photos")
        report(trigger: "recording_detail_save")
    }

    /// One pasteboard item carrying both representations, so a destination that
    /// wants the picture gets the picture and one that wants text gets the link.
    private func copyToPasteboard(_ image: UIImage) {
        var item: [String: Any] = [:]
        if let png = image.pngData() {
            item[UTType.png.identifier] = png
        }
        item[UTType.utf8PlainText.identifier] = caption()
        UIPasteboard.general.setItems([item])
        Haptics.success()
        confirm("Copied")
        report(trigger: "recording_detail_copy")
    }

    private func presentSystemSheet(_ image: UIImage) {
        Haptics.medium()
        SharePresenter.present(
            image: image,
            cardType: variant.cardType,
            trigger: "recording_detail",
            message: caption()
        ) {
            onShared?()
        }
    }

    private func report(trigger: String) {
        AnalyticsService.shared.log(
            .shareCompleted(cardType: variant.cardType, trigger: trigger)
        )
        onShared?()
    }

    private func confirm(_ text: String) {
        confirmation = text
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if confirmation == text { confirmation = nil }
        }
    }

    // MARK: - Rendering

    /// Yields first so the sheet finishes animating in before `ImageRenderer`
    /// takes the main thread for a frame or two.
    private func renderIfNeeded(_ option: Variant) async {
        let key = renderKey
        guard rendered[key] == nil else { return }
        await Task.yield()
        if let image = render(option) {
            rendered[key] = image
        } else {
            unavailable = true
        }
    }

    private func render(_ option: Variant) -> UIImage? {
        ScoreCardRenderer.render(
            recording: recording,
            includePromptText: option.includesPromptText,
            theme: theme
        )
    }

    // MARK: - Caption

    /// The text that travels with the card. Only the challenge card carries a
    /// prompt or a link; the scores card is a number and nothing else.
    private func caption() -> String {
        let score = recording.analysis?.speechScore.overall
        guard variant.includesPromptText else {
            return SharedPromptLink.message(
                score: score,
                verdict: score.map { AppColors.scoreVerdict(for: $0) },
                promptText: nil,
                url: nil
            )
        }

        let url: URL?
        let promptText: String?
        if let prompt = recording.prompt {
            url = SharedPromptLink.shareURL(for: SharedPromptPayload(
                promptID: prompt.id,
                text: prompt.text,
                category: prompt.category,
                difficulty: prompt.difficulty.rawValue,
                beatScore: score,
                source: SharedPromptLink.shareSource
            ))
            promptText = prompt.text
        } else {
            // The story title is on the card, but a friend cannot open someone
            // else's story. Send them into a fresh session instead.
            url = SharedPromptLink.shareURL(
                for: SharedPromptPayload(source: SharedPromptLink.shareSource)
            )
            promptText = recording.storyTitle
        }

        return SharedPromptLink.message(
            score: score,
            verdict: score.map { AppColors.scoreVerdict(for: $0) },
            promptText: promptText,
            url: url
        )
    }
}

// MARK: - Action Button

private struct ShareAction: View {
    let icon: String
    let label: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(prominent ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white)
                    .frame(width: 58, height: 58)
                    .background {
                        Circle().fill(prominent ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
                        Circle().stroke(AppColors.cardStroke, lineWidth: prominent ? 0 : 0.5)
                    }

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.replacingOccurrences(of: "\n", with: " "))
    }
}
