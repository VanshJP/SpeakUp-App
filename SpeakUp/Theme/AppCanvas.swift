import SwiftUI

// MARK: - App Canvas

/// The app-wide background menu — Settings → App Look, painted behind every
/// tab. A thin persisted list over the shared `CanvasLook` catalogue, which is
/// where the art lives; `RecordingBackdrop` is the other menu over the same
/// catalogue, so Aurora means the same Aurora on both screens.
///
/// Raw values are the SwiftData payload; do not reorder existing cases. Adding
/// a look this menu does not offer yet is one new case plus one line in `look`.
/// `nonisolated` so settings tests and off-main decode stay off the MainActor.
nonisolated enum AppCanvas: Int, Codable, CaseIterable, Identifiable, Sendable {
    case classic = 0
    case midnight = 1
    case mist = 2
    case aurora = 3
    case ember = 4
    case horizon = 5
    case prism = 6
    case depth = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .mist: return "Mist"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .horizon: return "Horizon"
        case .prism: return "Prism"
        case .depth: return "Depth"
        }
    }

    /// The art this entry paints.
    var look: CanvasLook {
        switch self {
        case .classic: return .classic
        case .midnight: return .midnight
        case .mist: return .mist
        case .aurora: return .aurora
        case .ember: return .ember
        case .horizon: return .horizon
        case .prism: return .prism
        case .depth: return .depth
        }
    }

    /// Comes from the catalogue, so the same look is described the same way
    /// wherever it is offered.
    var subtitle: String { look.summary }
}

// MARK: - Canvas View

/// Paints an `AppCanvas` in one `Canvas` pass at ambient intensity. See
/// `CanvasLook.paint` for why there is no `drawingGroup` and why every radius
/// is a fraction of the diagonal.
struct AppCanvasView: View {
    var canvas: AppCanvas = .classic
    var style: AppBackground.Style = .primary
    /// When false, freezes the canvas for thumbnails and Reduce Motion.
    var animated: Bool = true

    var body: some View {
        CanvasLookView(look: canvas.look, mood: .ambient, tone: style, animated: animated)
    }
}

// MARK: - Look View

/// The one view that runs a canvas clock. Both menus render through it, so the
/// pause rules, the frame budget and the freeze-for-thumbnails behaviour are
/// written once.
struct CanvasLookView: View {
    let look: CanvasLook
    let mood: CanvasMood
    var tone: AppBackground.Style = .primary
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let shouldAnimate = animated
            && look.isAnimated
            && !reduceMotion
            && scenePhase == .active

        TimelineView(.animation(minimumInterval: mood.frameInterval, paused: !shouldAnimate)) { context in
            // Absolute time, not time-since-appear: two backgrounds stacked by
            // a push stay in lockstep instead of one restarting from zero.
            let time = shouldAnimate ? context.date.timeIntervalSinceReferenceDate : 0

            Canvas(opaque: true) { graphics, size in
                look.paint(into: &graphics, size: size, mood: mood, tone: tone, time: time)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
