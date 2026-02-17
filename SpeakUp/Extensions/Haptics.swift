import UIKit

enum Haptics {
    // MARK: - Impact

    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// Light tap — filter chips, toggles, small UI interactions
    static func light() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    /// Medium tap — buttons, card taps, play/pause
    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }

    /// Heavy tap — countdown final seconds, recording stop, delete confirm
    static func heavy() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred()
    }

    // MARK: - Notification

    /// Success — recording saved, achievement unlocked, goal created
    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning — timer running low, approaching limit
    static func warning() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error — delete, cancel, destructive action
    static func error() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }

    // MARK: - Selection

    /// Selection change — picker value changes, scrubbing
    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }
}
