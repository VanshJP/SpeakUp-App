import SwiftUI

// MARK: - Recording Backdrop

/// The session background menu — Recording Look, painted behind the prepare
/// countdown and the take itself, so the look a speaker picked does not vanish
/// the moment they start talking.
///
/// A thin persisted list over the shared `CanvasLook` catalogue, exactly like
/// `AppCanvas`. It is not a second theme system and it owns no art: Aurora and
/// Ember here are the same painters the app canvas uses, turned up to
/// `.session` intensity.
///
/// Raw values are the SwiftData payload; do not reorder existing cases.
/// `nonisolated` so settings tests and any off-main decode of the stored Int
/// do not hop the MainActor.
nonisolated enum RecordingBackdrop: Int, Codable, CaseIterable, Identifiable, Sendable {
    case base = 0
    case aurora = 1
    case hyperspace = 2
    case nebula = 3
    case ember = 4
    case void = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .aurora: return "Aurora"
        case .hyperspace: return "Hyperspace"
        case .nebula: return "Nebula"
        case .ember: return "Ember"
        case .void: return "Void"
        }
    }

    /// The art this entry paints. `base` is always Classic at recording tone —
    /// never the user's app-wide canvas. Recording Look owns session mood
    /// separately from Settings → Appearance.
    var look: CanvasLook {
        switch self {
        case .base: return .classic
        case .aurora: return .aurora
        case .hyperspace: return .hyperspace
        case .nebula: return .nebula
        case .ember: return .ember
        case .void: return .void
        }
    }

    var subtitle: String { look.summary }
}

// MARK: - View

/// Full-bleed session canvas. `animated: false` freezes a frame for
/// thumbnails — and because every look normalises against the view's diagonal,
/// the 76pt picker tile, the preview card and the live session all show the
/// same composition at different scales.
struct RecordingBackdropView: View {
    var backdrop: RecordingBackdrop = .base
    var animated: Bool = true

    var body: some View {
        CanvasLookView(
            look: backdrop.look,
            mood: .session,
            tone: .recording,
            animated: animated
        )
        .overlay { readability }
    }

    /// Keeps white countdown type readable on a busy canvas. Base is already
    /// dark enough at recording tone, and a second wash over it just muddies
    /// the navy.
    @ViewBuilder
    private var readability: some View {
        if backdrop != .base {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.40), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.42),
                    .init(color: .black.opacity(0.10), location: 0.60),
                    .init(color: .black.opacity(0.46), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
