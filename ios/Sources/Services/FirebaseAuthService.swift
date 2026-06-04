import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore

/// Phone-number sign-in via Firebase. Firebase sends the SMS through Google's
/// carrier-approved infrastructure (no toll-free/10DLC registration), then we
/// exchange the resulting Firebase ID token for Slide session tokens at
/// POST /auth/firebase.
enum FirebaseAuthService {
    /// Call once at launch (from the AppDelegate) before any auth.
    static func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    /// Send an SMS code to `e164`. Returns an opaque verification id to pair with
    /// the code the user types.
    static func sendCode(toE164 e164: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
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
