import UIKit

/// One place that puts a rendered card into the system share sheet.
///
/// Both share surfaces — the score card and the Then-vs-Now card — need the
/// same three things: a presenter, a completion that only counts a *finished*
/// share, and the advocacy event. Duplicating that meant one of them would
/// eventually stop logging.
@MainActor
enum SharePresenter {
    /// Presents `image` and reports the share once the user completes it.
    ///
    /// Returns false when no window is available to present from.
    @discardableResult
    static func present(
        image: UIImage,
        cardType: String,
        trigger: String,
        onShared: (() -> Void)? = nil
    ) -> Bool {
        guard let root = rootViewController else { return false }

        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)

        if let popover = activity.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        activity.completionWithItemsHandler = { _, completed, _, _ in
            // A dismissed sheet is not a share. Counting it would inflate the
            // one advocacy number the growth plan is steered by.
            guard completed else { return }
            Task { @MainActor in
                AnalyticsService.shared.log(.shareCompleted(cardType: cardType, trigger: trigger))
                onShared?()
            }
        }

        root.present(activity, animated: true)
        return true
    }

    private static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return nil }
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        return window?.rootViewController
    }
}
