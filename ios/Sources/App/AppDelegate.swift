import UIKit

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif

/// App delegate exists so Firebase Phone Auth can receive the silent APNs push /
/// URL-scheme callbacks it uses to confirm the device (anti-abuse) before
/// sending the SMS. No-ops cleanly when Firebase isn't bundled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth {
            FirebaseAuthService.configureIfNeeded()
        }
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseAuth)
        // Hand the APNs token to Firebase for phone-auth verification.
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        #endif
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification notification: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        #if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(notification) {
            completionHandler(.noData)
            return
        }
        #endif
        completionHandler(.newData)
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        #if canImport(FirebaseAuth)
        if Auth.auth().canHandle(url) { return true }
        #endif
        return false
    }
}
