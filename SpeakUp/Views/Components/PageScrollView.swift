import SwiftUI

/// A vertical page scroller that cannot scroll sideways.
/// They do not stop it growing the other way: if any child measures wider than
/// fixed-width frame, or ordinary content at an accessibility text size — the
/// because a scroll view scrolls on any axis where content exceeds bounds.
struct PageScrollView<Content: View>: View {
    var showsIndicators: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(showsIndicators ? .automatic : .hidden)
    }
}
