import SwiftUI

/// A vertical page scroller that cannot scroll sideways.
///
/// `ScrollView`'s axes decide which way content is allowed to grow *unbounded*.
/// They do not stop it growing the other way: if any child measures wider than
/// the viewport — a pill row pinned with `.fixedSize()`, a long unbroken word, a
/// fixed-width frame, or ordinary content at an accessibility text size — the
/// scroll view's content size grows with it and UIKit pans horizontally,
/// because a scroll view scrolls on any axis where content exceeds bounds.
/// The page ends up draggable sideways with everything cut off at the right.
///
/// Clamping the content to the container width makes the overflow clip instead.
/// It is a backstop, not a licence: a child that needs clamping is still a
/// layout bug, it just no longer takes the whole screen with it. Screens are
/// narrower than the design canvas on plenty of real devices — a 13 mini or SE
/// at 375pt, Display Zoom, and any of them at AX text sizes.
///
/// Use this for full-screen pages. Deliberately horizontal scrollers (chip
/// rows, card rails) stay as `ScrollView(.horizontal)`.
struct PageScrollView<Content: View>: View {
    var showsIndicators: Bool = true
    /// iOS 26's default *soft* top scroll-edge effect re-insets floating
    /// toolbar glass as content slides under the bar, so trailing icons bounce
    /// up and down. Pin it on screens with a hidden nav bar and trailing
    /// actions (`RecordingDetailView`).
    var pinTopEdge: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(showsIndicators ? .automatic : .hidden)
        .scrollEdgeEffectDisabled(pinTopEdge, for: .top)
    }
}
