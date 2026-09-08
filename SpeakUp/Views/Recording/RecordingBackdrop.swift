import SwiftUI

// MARK: - Recording Backdrop

/// The session background menu — Recording Look, painted behind the prepare
/// countdown and the take itself, so the look a speaker picked does not vanish
/// the moment they start talking.
nonisolated enum RecordingBackdrop: Int, Codable, CaseIterable, Identifiable, Sendable {
    case base = 0
    case aurora = 1
    case hyperspace = 2
    case nebula = 3
    case ember = 4
    case void = 5
    case tide = 6
    case dusk = 7
    case signal = 8
    case noir = 9

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .aurora: return "Aurora"
        case .hyperspace: return "Hyperspace"
        case .nebula: return "Nebula"
        case .ember: return "Ember"
        case .void: return "Void"
        case .tide: return "Tide"
        case .dusk: return "Dusk"
        case .signal: return "Signal"
        case .noir: return "Noir"
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
        case .tide: return .tide
        case .dusk: return .dusk
        case .signal: return .signal
        case .noir: return .noir
        }
    }

    var subtitle: String { look.summary }
}

// MARK: - View

/// Full-bleed session canvas. Every look is a still — because every look
/// normalises against the view's diagonal, the 76pt picker tile, the preview
/// card and the live session all show the same composition at different scales.
struct RecordingBackdropView: View {
    var backdrop: RecordingBackdrop = .base
    /// Unused — every look is a still. Kept so thumbnail call sites do not churn.
    var animated: Bool = true
    var fillsSafeArea: Bool = true

    var body: some View {
        let canvas = CanvasLookView(
            look: backdrop.look,
            mood: .session,
            tone: .recording
        )
        .overlay { readability }

        if fillsSafeArea {
            canvas.ignoresSafeArea()
        } else {
            canvas
        }
    }

    @ViewBuilder
    private var readability: some View {
        if backdrop != .base {
            let wash = LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.40), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.42),
                    .init(color: .black.opacity(0.10), location: 0.60),
                    .init(color: .black.opacity(0.46), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if fillsSafeArea {
                wash.ignoresSafeArea()
            } else {
                wash
            }
        }
    }
}
