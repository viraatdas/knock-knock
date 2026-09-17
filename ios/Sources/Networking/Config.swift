import Foundation

/// App configuration. Base URL is overridable so the same binary can point at
/// localhost during development or the deployed backend in production.
enum Config {
    /// Default REST base URL. Override with the `SLIDE_API_BASE_URL`
    /// environment variable (handy in the simulator) or by editing here.
    static var apiBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["SLIDE_API_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        #if DEBUG
        // Simulator/dev default.
        return URL(string: "http://localhost:8080/v1")!
        #else
        // Release/TestFlight: slide-api on Fly. NOT App Runner — its Envoy
        // ingress 403s WebSocket upgrades, so /v1/ws (date/match signaling)
        // can't connect there. Fly serves WebSockets.
        return URL(string: "https://slide-api.fly.dev/v1")!
        #endif
    }

    /// Whether to use the mocked CallService (real LiveKit media requires a
    /// device to verify). Defaults to `true` so screens render in the simulator.
    static var useMockCallService: Bool {
        if let raw = ProcessInfo.processInfo.environment["SLIDE_USE_REAL_WEBRTC"] {
            return !(raw == "1" || raw.lowercased() == "true")
        }
        #if DEBUG
        // Simulator can't do real capture; default to the mock for screens.
        return true
        #else
        // Release/TestFlight on a real device: use real media so dates (and
        // audio routing) actually work.
        return false
        #endif
    }

    /// Whether to seed mock data so the UI is populated in the simulator even
    /// without a running backend. Defaults to true in DEBUG.
    static var useMockData: Bool {
        if let raw = ProcessInfo.processInfo.environment["SLIDE_USE_MOCK_DATA"] {
            return raw == "1" || raw.lowercased() == "true"
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    /// "1.1.0 (33)" — marketing version plus build number, for the About
    /// sheet (SPEC: show both, not just the short version Profile's row uses).
    static let fullVersion: String = {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty else { return appVersion }
        return "\(appVersion) (\(build))"
    }()

    /// Use Firebase Phone Auth for sign-in (real SMS via Google) when a
    /// GoogleService-Info.plist is bundled. Falls back to the backend OTP flow
    /// otherwise (simulator / before Firebase is configured). Only consulted
    /// when the server's `POST /auth/request-otp` response says
    /// `transport == "firebase"`.
    static var useFirebaseAuth: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Custom domain for Firebase Auth's reCAPTCHA/auth-handler web surface
    /// (`Auth.auth().customAuthDomain`), so that if a user ever sees it, it
    /// reads as our own domain instead of "<project>.firebaseapp.com". `nil`
    /// today — this needs a Firebase Hosting custom domain connected and
    /// allowlisted in the Firebase console first (see AGENTS.md's "Known
    /// follow-ups"); until that exists, leave this unset so
    /// `FirebaseAuthService.configureIfNeeded()` stays a no-op. Once the
    /// domain is live, either hardcode it here or keep reading the env var
    /// for staged rollout/testing.
    static var firebaseAuthCustomDomain: String? {
        ProcessInfo.processInfo.environment["FIREBASE_AUTH_CUSTOM_DOMAIN"]
    }

    /// Marketing site's legal pages (web/src/app/{terms,privacy}), linked from
    /// the onboarding consent step (Guideline 1.2) and Profile.
    static let termsURL = "https://slide.viraat.dev/terms"
    static let privacyURL = "https://slide.viraat.dev/privacy"
}
