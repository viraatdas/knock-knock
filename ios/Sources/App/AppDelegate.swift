import UIKit
import UserNotifications

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif

/// No system call-management or VoIP-push framework anymore. This exists for: Firebase Phone Auth's
/// silent-APNs device check (falls back to reCAPTCHA without it), standard
/// alert-push registration (doors-open/match/message pushes), and routing a
/// tapped notification into AppState.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by SlideApp right after AppState is created. UIKit can deliver a
    /// notification tap before SwiftUI's own `.task` bootstrap has run, so
    /// this needs to exist as early as possible.
    weak var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth {
            FirebaseAuthService.configureIfNeeded()
        }
        #endif
        // Standard remote notifications: Firebase Phone Auth verifies the
        // device with a silent APNs push (falls back to the reCAPTCHA web
        // page without it), and the backend re-uses the same token to send
        // doors-open/match/message alert pushes ("apns" kind, no VoIP).
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth {
            Auth.auth().setAPNSToken(deviceToken, type: .unknown)
            // Unblocks FirebaseAuthService.sendCode, which waits briefly for
            // this so verification runs silently instead of via reCAPTCHA.
            Task { @MainActor in FirebaseAuthService.apnsTokenReady = true }
        }
        #endif
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Persisted independent of the session tokens so a later logout can
        // unregister it, and a same-device re-login can re-claim it without
        // waiting on the OS to call this back again.
        TokenStore.shared.devicePushToken = hex
        if TokenStore.shared.isAuthenticated {
            Task { try? await APIClient.shared.registerPushToken(hex) }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No APNs token (simulator, or push not provisioned). Firebase falls
        // back to reCAPTCHA, which needs the URL scheme set in project.yml.
        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth {
            // Unblocks FirebaseAuthService.sendCode's wait immediately
            // instead of it sitting out the full timeout on a device that
            // will never get a token this launch.
            Task { @MainActor in FirebaseAuthService.apnsRegistrationFailed = true }
        }
        #endif
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // No application(_:open:options:) here: under this app's SwiftUI
    // lifecycle (@main App + @UIApplicationDelegateAdaptor, no scene
    // delegate), UIKit never calls it. The reCAPTCHA URL callback is
    // forwarded to Firebase from SlideApp.swift's .onOpenURL instead, which
    // is the only handler SwiftUI actually invokes. Do not re-add a
    // look-alike method here; it would be dead code that misleads a future
    // reader into thinking URL handling is wired through AppDelegate.

    /// Firebase Phone Auth's silent-push device check arrives here as a
    /// standard remote notification (project.yml sets
    /// FirebaseAppDelegateProxyEnabled=false, so nothing forwards this
    /// automatically). Without this, Firebase never sees the silent push and
    /// every real sign-in falls through to reCAPTCHA, which needs the URL
    /// callback below to complete.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth, Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        #endif
        completionHandler(.noData)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground banner rules: suppress a message notification for the chat
    /// that's already open (the live WS already drives that screen); doors-
    /// open and match notifications always show.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String, type == "message",
           let matchId = userInfo["matchId"] as? String,
           matchId == appState?.activeChatMatchId {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// A tapped notification routes into AppState: message -> that chat,
    /// doors-open -> Tonight, match -> Matches.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor [weak self] in
            self?.appState?.routeNotification(userInfo: userInfo)
        }
        completionHandler()
    }
}
