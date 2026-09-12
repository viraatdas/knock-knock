import UserNotifications
import UIKit

/// Push permission + a local fallback reminder. The server pushes "doors are
/// open" at 7 PM (SPEC §1.11); this schedules the same message as a repeating
/// LOCAL notification at 18:59 PT so a lost/delayed push still gets someone
/// to the app on time.
enum NotificationService {
    private static let doorsOpenIdentifier = "doorsOpenLocal"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Fires at 18:59 America/Los_Angeles every day, regardless of the
    /// device's own time zone.
    static func scheduleDoorsOpenReminder() {
        var components = DateComponents()
        components.hour = 18
        components.minute = 59
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")

        let content = UNMutableNotificationContent()
        content.title = "Knock Knock"
        content.body = "Doors open in a minute."
        content.sound = .default
        // AppState.routeNotification(userInfo:) switches on "type" to decide
        // where a tap should land; without this a tapped doors-open reminder
        // did nothing.
        content.userInfo = ["type": "doors_open"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: doorsOpenIdentifier,
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelDoorsOpenReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [doorsOpenIdentifier])
    }
}
