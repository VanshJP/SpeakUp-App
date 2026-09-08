import UIKit

/// One place that puts a rendered card into the system share sheet.
/// Both share surfaces — the score card and the Then-vs-Now card — need the
@MainActor
enum SharePresenter {
    @discardableResult
    static func present(
        image: UIImage,
        cardType: String,
        trigger: String,
        message: String? = nil,
        onShared: (() -> Void)? = nil
    ) -> Bool {
        guard let root = rootViewController else { return false }

        guard canPresent(from: root) else { return false }

        var items: [Any] = [image]
        if let message, !message.isEmpty {
            items.append(message)
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let popover = activity.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        activity.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in
                AnalyticsService.shared.log(.shareCompleted(cardType: cardType, trigger: trigger))
                onShared?()
            }
        }

        root.present(activity, animated: true)
        return true
    }

    static func present(url: URL) {
        guard let root = rootViewController else { return }
        guard canPresent(from: root) else { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popover = activity.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        root.present(activity, animated: true)
    }

    private static func canPresent(from root: UIViewController) -> Bool {
        if root is UIActivityViewController { return false }
        if root.presentedViewController != nil { return false }
        return true
    }

    private static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return nil }
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
