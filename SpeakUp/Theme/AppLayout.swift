import SwiftUI

/// Shared page rhythm for the five root tabs. Without one owner, Today padded
/// 16, Learn padded 20, Library/History used system default, and the stack
/// read as five different apps when you flipped tabs.
enum AppLayout {
    /// Horizontal inset for every root tab's scroll content.
    static let pageHorizontal: CGFloat = 16

    /// Bottom breathing room above the tab bar (and Library's FAB).
    static let pageBottom: CGFloat = 16

    /// Gap between major chapters (Today modules, Learn path, Progress).
    static let chapterSpacing: CGFloat = 20

    /// Gap for denser list hubs (Library, History recordings, Settings).
    static let listSpacing: CGFloat = 16

    /// Minimum touch target. Visible chrome may be smaller; expand with
    /// `.frame` + `.contentShape` so the hit box still meets this size.
    static let minHitTarget: CGFloat = 44
}

extension View {
    /// Standard horizontal + bottom inset for a root tab's scroll column.
    func pageContentInsets() -> some View {
        self
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.bottom, AppLayout.pageBottom)
    }
}
