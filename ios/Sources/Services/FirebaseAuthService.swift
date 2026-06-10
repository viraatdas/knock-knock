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

    /// Call once at launch (from the AppDelegate) before any auth.
    static func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    /// Send an SMS code to `e164`. Returns an opaque verification id to pair with
    /// the code the user types.
    static func sendCode(toE164 e164: String) async throws -> String {
        // Give the APNs token a moment to arrive (cold launch → fast typer)
        // so verification happens silently. If it never comes (simulator, push
        // outage), proceed anyway — reCAPTCHA remains the fallback.
        let deadline = Date().addingTimeInterval(4)
        while await !apnsTokenReady, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return try await withCheckedThrowingContinuation { cont in
            PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil) { verificationID, error in
                if let error { cont.resume(throwing: error); return }
                guard let verificationID else {
                    cont.resume(throwing: AuthErrorShim.noVerificationID); return
                }
                cont.resume(returning: verificationID)
            }
        }
    }

    /// Verify `code` against `verificationID`, returning a Firebase ID token.
    static func verify(verificationID: String, code: String) async throws -> String {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID, verificationCode: code)
        let result = try await Auth.auth().signIn(with: credential)
        let token = try await result.user.getIDToken()
        return token
    }

    enum AuthErrorShim: LocalizedError {
        case noVerificationID
        var errorDescription: String? { "Could not start phone verification." }
    }
}
#endif
