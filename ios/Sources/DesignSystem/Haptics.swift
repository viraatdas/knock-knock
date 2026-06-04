import UIKit

/// Centralized haptic feedback. Haptics make the app feel responsive and
/// physical — used on taps, call lifecycle events, and success/error moments.
///
/// Generators are kept warm (`prepare()`) so the first tap isn't laggy. All
/// calls are no-ops on devices without a Taptic Engine, so this is safe to call
/// anywhere.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    /// Light tap — buttons, rows, toggles. The default "something happened" feel.
    static func tap() { light.impactOccurred(); light.prepare() }

    /// Selection change — pickers, segment changes, toggling a contact in a list.
    static func select() { selection.selectionChanged(); selection.prepare() }

    /// Medium — a meaningful action committed (place call, send, confirm).
    static func impact() { medium.impactOccurred(); medium.prepare() }

    /// Heavy — a big, decisive action (answer a call, end a call).
    static func strong() { heavy.impactOccurred(); heavy.prepare() }

    /// Soft — gentle, for subtle UI like a sheet settling or a chip removal.
    static func gentle() { soft.impactOccurred(); soft.prepare() }

    static func success() { notify.notificationOccurred(.success); notify.prepare() }
    static func warning() { notify.notificationOccurred(.warning); notify.prepare() }
    static func error() { notify.notificationOccurred(.error); notify.prepare() }

    /// Warm up the generators so the first real haptic fires without latency.
    static func prepareAll() {
        light.prepare(); medium.prepare(); heavy.prepare()
        soft.prepare(); rigid.prepare(); selection.prepare(); notify.prepare()
    }
}
