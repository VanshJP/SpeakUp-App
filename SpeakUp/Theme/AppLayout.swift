import SwiftUI

enum AppLayout {
    static let pageHorizontal: CGFloat = 16

    static let pageBottom: CGFloat = 16

    static let chapterSpacing: CGFloat = 20

    static let listSpacing: CGFloat = 16

    static let minHitTarget: CGFloat = 44
}

extension View {
    func pageContentInsets() -> some View {
        self
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.bottom, AppLayout.pageBottom)
    }
}
