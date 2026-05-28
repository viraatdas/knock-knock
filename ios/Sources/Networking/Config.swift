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
        return URL(string: "http://localhost:8080/v1")!
    }

    /// Whether to use the mocked CallService (real WebRTC requires a device to
    /// verify). Defaults to `true` so screens render in the simulator.
    static var useMockCallService: Bool {
        if let raw = ProcessInfo.processInfo.environment["SLIDE_USE_REAL_WEBRTC"] {
            return !(raw == "1" || raw.lowercased() == "true")
        }
        return true
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
}
