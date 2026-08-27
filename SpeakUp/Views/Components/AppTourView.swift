import SwiftUI

// MARK: - Steps

/// One-shot guided layout walkthrough. Runs the first time the user lands on
/// Today after finishing onboarding: three stops on Today, one per remaining
/// tab, ending on the Session Defaults row so the user knows where their
/// recording preset lives. Each stop is a coach line, not a feature essay.
///
/// The overlay owns the whole screen while active (including the tab bar), so
/// the tour drives tab selection itself and the user can't wander mid-tour.
/// Skip is always one tap away.
enum AppTourStep: Int, CaseIterable {
    case record
    case stats
    case tools
    case library
    case history
    case learn
    case presets

    var tab: AppTab {
        switch self {
        case .record, .stats, .tools: return .today
        case .library: return .library
        case .history: return .history
        case .learn: return .learn
        case .presets: return .settings
        }
    }

    /// The on-screen element this stop spotlights. Nil means the surface
    /// itself is the subject: no cutout, bubble sits above the tab bar.
    var anchorID: AppTourAnchorID? {
        switch self {
        case .record: return .todayPrompt
        case .stats: return .todayStats
        case .tools: return .todayTools
        case .presets: return .settingsPresets
        case .library, .history, .learn: return nil
        }
    }

    var title: String {
        switch self {
        case .record: return "Today"
        case .stats: return "Where you stand"
        case .tools: return "Prep tools"
        case .library: return "The Library"
        case .history: return "History"
        case .learn: return "Learning Path"
        case .presets: return "Your recording preset"
        }
    }

    var message: String {
        switch self {
        case .record:
            return "A fresh prompt every day. Tap a start button, talk, get scored. One rep a day moves the line."
        case .stats:
            return "Streak up top, rings for sessions and scores. Tap the rings for full charts."
        case .tools:
            return "Warm-ups open the voice, drills fix one weakness, calm settles nerves, and the wheel surprises you with a prompt. Customize which blocks show on Today anytime."
        case .library:
            return "Prompts and Stories are what you speak. Tools are how you prep — warm-ups, drills, read-aloud, calm."
        case .history:
            return "Every take and score, your baseline included. This is where the line climbs."
        case .learn:
            return "A week-by-week curriculum when you want structure. Free drills stay under Library → Tools."
        case .presets:
            return "Session Defaults holds recording length, countdown, and live feedback. Set it up the way you like."
        }
    }

    var next: AppTourStep? { AppTourStep(rawValue: rawValue + 1) }
}

/// Elements a tour stop can spotlight. Views register their frames with
/// `.tourAnchor(_:)`; only the active step's anchor is ever read.
enum AppTourAnchorID: String {
    case todayPrompt
    case todayStats
    case todayTools
    case settingsPresets
}

// MARK: - Model

/// Shared between ContentView (which mounts the overlay and switches tabs)
/// and the anchored views (which report their frames). Frames are in global
/// coordinates; the overlay converts into its own space when drawing.
@MainActor
@Observable
final class AppTourModel {
    var activeStep: AppTourStep?
    var frames: [AppTourAnchorID: CGRect] = [:]

    func begin() {
        activeStep = .record
    }
}

/// Explicit key rather than `@Entry`: the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and this is the environment-key
/// shape already proven against it (see `View+Glass.swift`).
private struct AppTourKey: EnvironmentKey {
    static let defaultValue: AppTourModel? = nil
}

extension EnvironmentValues {
    /// Nil everywhere the tour isn't wired (previews, widget target), so
    /// `.tourAnchor` degrades to a no-op instead of crashing.
    var appTour: AppTourModel? {
        get { self[AppTourKey.self] }
        set { self[AppTourKey.self] = newValue }
    }
}

// MARK: - Anchor reporting

extension View {
    /// Marks this view as a tour spotlight target. Reports the frame through
    /// `onGeometryChange` rather than anchor preferences so the geometry
    /// survives the UIKit-backed TabView boundary.
    func tourAnchor(_ id: AppTourAnchorID) -> some View {
        modifier(TourAnchorReporter(id: id))
    }
}

private struct TourAnchorReporter: ViewModifier {
    let id: AppTourAnchorID
    @Environment(\.appTour) private var tour

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            tour?.frames[id] = frame
        }
    }
}

// MARK: - Overlay

/// Dimmed layer with a rounded cutout over the active step's target and a
/// glass coach bubble. Tap anywhere (or Next) advances; Skip ends the tour.
struct AppTourOverlay: View {
    let tour: AppTourModel
    /// `completed` is false when the user skipped partway.
    let onFinish: (_ completed: Bool) -> Void

    var body: some View {
        if let step = tour.activeStep {
            GeometryReader { proxy in
                let spotlight = spotlightRect(for: step, in: proxy)

                ZStack {
                    dimLayer(cutout: spotlight)
                        .contentShape(Rectangle())
                        .onTapGesture { advance(from: step) }

                    if let spotlight {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 1.5)
                            .frame(width: spotlight.width, height: spotlight.height)
                            .position(x: spotlight.midX, y: spotlight.midY)
                            .allowsHitTesting(false)
                    }

                    bubble(for: step)
                        .padding(.horizontal, 24)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: bubbleAlignment(for: spotlight, in: proxy)
                        )
                        .padding(bubblePadding(for: spotlight, in: proxy))
                }
            }
            // The reader, not the dim layer, is what escapes the safe area.
            // Insetting only the fill would leave the cutout computed in one
            // coordinate space and drawn in another, sliding the highlight off
            // the element by the top inset.
            .ignoresSafeArea()
            .motion(AppMotion.settle, value: step)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .onChange(of: step, initial: true) { _, newStep in
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(newStep.title). \(newStep.message)"
                )
            }
        }
    }

    // MARK: Layout

    /// Target frame in overlay space, padded out so the highlight breathes.
    /// Nil for tab stops and while a just-mounted tab hasn't reported yet
    /// (the bubble falls back to the tab-bar position for a frame or two).
    ///
    /// Also nil when the target has scrolled mostly out of view: a cutout
    /// drawn off-screen reads as "the whole screen went dark for no reason",
    /// so the step degrades to a plain bubble instead.
    private func spotlightRect(for step: AppTourStep, in proxy: GeometryProxy) -> CGRect? {
        guard let id = step.anchorID, let global = tour.frames[id] else { return nil }
        let origin = proxy.frame(in: .global).origin
        let local = global
            .offsetBy(dx: -origin.x, dy: -origin.y)
            .insetBy(dx: -8, dy: -8)

        let visible = local.intersection(CGRect(origin: .zero, size: proxy.size))
        guard !visible.isNull, visible.height >= local.height * 0.6 else { return nil }
        return local
    }

    private func dimLayer(cutout: CGRect?) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.6))
            .mask {
                ZStack {
                    Rectangle()
                    if let cutout {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .frame(width: cutout.width, height: cutout.height)
                            .position(x: cutout.midX, y: cutout.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
    }

    private func bubbleAlignment(for spotlight: CGRect?, in proxy: GeometryProxy) -> Alignment {
        guard let spotlight else { return .bottom }
        return spotlight.midY < proxy.size.height / 2 ? .top : .bottom
    }

    private func bubblePadding(for spotlight: CGRect?, in proxy: GeometryProxy) -> EdgeInsets {
        guard let spotlight else {
            // Tab stops: sit just above the tab bar the copy is pointing at.
            return EdgeInsets(top: 0, leading: 0, bottom: 84, trailing: 0)
        }
        if spotlight.midY < proxy.size.height / 2 {
            return EdgeInsets(top: max(spotlight.maxY + 14, 0), leading: 0, bottom: 0, trailing: 0)
        }
        return EdgeInsets(top: 0, leading: 0, bottom: max(proxy.size.height - spotlight.minY + 14, 0), trailing: 0)
    }

    // MARK: Bubble

    private func bubble(for step: AppTourStep) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(step.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    stepDots(current: step)

                    Spacer(minLength: 0)

                    Button("Skip tour") {
                        Haptics.light()
                        onFinish(false)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)

                    GlassButton(
                        title: step.next == nil ? "Done" : "Next",
                        icon: step.next == nil ? "checkmark" : "arrow.right",
                        iconPosition: .right,
                        style: .primary,
                        size: .small
                    ) {
                        advance(from: step)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepDots(current: AppTourStep) -> some View {
        HStack(spacing: 5) {
            ForEach(AppTourStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == current ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func advance(from step: AppTourStep) {
        Haptics.light()
        if let next = step.next {
            tour.activeStep = next
        } else {
            onFinish(true)
        }
    }
}
