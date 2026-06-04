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
        // Register for PushKit VoIP pushes so incoming calls/knocks ring via
        // CallKit even when the app is backgrounded, locked, or killed. iOS
        // launches the app into the background to deliver a VoIP push, so this
        // must be set up at launch.
        PushService.shared.start()

        // Register for STANDARD remote notifications too. Firebase Phone Auth
        // verifies the device with a silent APNs push; without this token it
        // falls back to a reCAPTCHA web page (which was erroring). VoIP/PushKit
        // tokens are separate and do NOT satisfy Firebase, so this is required.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseAuth)
        // Hand the APNs token to Firebase for phone-auth verification. On a
        // TestFlight/App Store build the token is production; .unknown lets
        // Firebase auto-detect the environment.
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        #endif
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No APNs token (e.g. simulator, or push not provisioned). Firebase will
        // fall back to the reCAPTCHA flow, which needs the URL scheme we set in
        // project.yml. Log so this is diagnosable but don't crash.
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
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
