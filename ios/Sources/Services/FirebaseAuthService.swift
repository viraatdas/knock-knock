import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore

/// Phone-number sign-in via Firebase. Firebase sends the SMS through Google's
/// carrier-approved infrastructure (no toll-free/10DLC registration), then we
/// exchange the resulting Firebase ID token for Slide session tokens at
/// POST /auth/firebase.
enum FirebaseAuthService {
    /// True once the APNs device token has been handed to Firebase (set by the
    /// AppDelegate). If phone verification starts before this, Firebase can't
    /// do its invisible silent-push device check and bounces the user through
    /// the ugly "verifying you're not a robot" reCAPTCHA web page instead.
    @MainActor static var apnsTokenReady = false

    /// True once `UIApplication.registerForRemoteNotifications()` has
    /// definitively failed (set by the AppDelegate's
    /// `didFailToRegisterForRemoteNotificationsWithError`) — simulator, no
    /// network, no valid APNs entitlement, etc. Lets `sendCode` stop waiting
    /// immediately instead of sitting out the full timeout on a device that
    /// can never get a token this launch.
    @MainActor static var apnsRegistrationFailed = false

    /// Call once at launch (from the AppDelegate) before any auth.
    static func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // No-op today: `Config.firebaseAuthCustomDomain` is nil until a
        // Firebase Hosting custom domain is connected and allowlisted in the
        // Firebase console (see Config.swift and AGENTS.md's "Known
        // follow-ups"). Once it exists, setting this repoints the reCAPTCHA/
        // auth-handler fallback page at our own domain instead of
        // "<project>.firebaseapp.com".
        if let domain = Config.firebaseAuthCustomDomain, !domain.isEmpty {
            Auth.auth().customAuthDomain = domain
        }
    }

    /// Send an SMS code to `e164`. Returns an opaque verification id to pair with
    /// the code the user types.
    static func sendCode(toE164 e164: String) async throws -> String {
        // Give the APNs token a moment to arrive (cold launch → fast typer)
        // so verification happens silently. If it never comes (real device
        // with a slow/dropped APNs registration, simulator, push outage),
        // proceed anyway — reCAPTCHA remains the fallback.
        //
        // 8s covers a slower cold-launch APNs round trip than before (was
        // 6s) without stalling the UI too long — Firebase's own internal
        // wait for this same token (AuthAPNSTokenManager, not publicly
        // configurable) is a fixed 5s, so this app-level wait is the only
        // lever we have to extend the silent-verification window past that.
        // We bail out early — instead of sitting out the full deadline — the
        // moment registration definitively fails, since waiting longer can't
        // help a device that will never get a token this launch.
        let deadline = Date().addingTimeInterval(8)
        while await !apnsTokenReady, await !apnsRegistrationFailed, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        do {
            return try await withCheckedThrowingContinuation { cont in
                PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil) { verificationID, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let verificationID else {
                        cont.resume(throwing: AuthErrorShim.noVerificationID); return
                    }
                    cont.resume(returning: verificationID)
                }
            }
        } catch {
            throw SendCodeError(underlying: error)
        }
    }

    /// Typed wrapper around a failed `sendCode` so callers can show/report the
    /// underlying Firebase error code without re-deriving it from `NSError`.
    struct SendCodeError: LocalizedError {
        /// The raw `NSError.code` (an `AuthErrorCode.Code` raw value when the
        /// error came from Firebase, e.g. 17010 for `.tooManyRequests`).
        let code: Int
        /// The short Firebase error name (e.g. "ERROR_TOO_MANY_REQUESTS"),
        /// read from `AuthErrorUserInfoNameKey` when Firebase set it.
        let codeName: String?
        let message: String

        init(underlying: Error) {
            let ns = underlying as NSError
            self.code = ns.code
            self.codeName = ns.userInfo[AuthErrorUserInfoNameKey] as? String
            self.message = ns.localizedDescription
        }

        var errorDescription: String? { message }
    }

    /// Verify `code` against `verificationID`, returning a Firebase ID token.
    /// Verify `code` against `verificationID` and return a Firebase ID token.
    ///
    /// This talks to Identity Toolkit directly instead of `Auth.signIn(with:)`.
    /// The SDK's sign-in persists a user in the keychain and fails the whole
    /// verification when the keychain does (restored devices, managed
    /// profiles, unsigned builds). We never need a Firebase user object: the
    /// ID token is exchanged once at `POST /auth/firebase` and the backend
    /// owns the session from there.
    static func verify(verificationID: String, code: String) async throws -> String {
        guard let apiKey = FirebaseApp.app()?.options.apiKey, !apiKey.isEmpty else {
            throw VerifyError(code: "NO_API_KEY", message: "Firebase isn't configured.")
        }
        var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The Firebase iOS API key is restricted to this bundle id.
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "sessionInfo": verificationID,
            "code": code,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if let idToken = object["idToken"] as? String, (200..<300).contains(status) {
            return idToken
        }
        let error = object["error"] as? [String: Any]
        let code = (error?["message"] as? String)?.components(separatedBy: " ").first ?? "HTTP_\(status)"
        throw VerifyError(code: code, message: userMessage(forIdentityToolkitCode: code))
    }

    /// Identity Toolkit error codes for `signInWithPhoneNumber`, in plain words.
    private static func userMessage(forIdentityToolkitCode code: String) -> String {
        switch code {
        case "INVALID_CODE": return "That code isn't right. Check the text and try again."
        case "SESSION_EXPIRED": return "That code expired. Tap Resend to get a new one."
        case "INVALID_SESSION_INFO", "MISSING_SESSION_INFO": return "Request a new code and try again."
        case "TOO_MANY_ATTEMPTS_TRY_LATER", "QUOTA_EXCEEDED": return "Too many tries. Wait a bit, then request a new code."
        default: return "We couldn't check that code. Try again in a minute."
        }
    }

    struct VerifyError: LocalizedError {
        let code: String
        let message: String
        var errorDescription: String? { message }
    }

    enum AuthErrorShim: LocalizedError {
        case noVerificationID
        var errorDescription: String? { "Could not start phone verification." }
    }
}
#endif
