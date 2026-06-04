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
        // Release/TestFlight: the live AWS backend (App Runner).
        return URL(string: "https://nck3w7ufbz.us-east-1.awsapprunner.com/v1")!
        #endif
    }

    /// Whether to use the mocked CallService (real WebRTC requires a device to
    /// verify). Defaults to `true` so screens render in the simulator.
    static var useMockCallService: Bool {
        if let raw = ProcessInfo.processInfo.environment["SLIDE_USE_REAL_WEBRTC"] {
            return !(raw == "1" || raw.lowercased() == "true")
        }
        #if DEBUG
        // Simulator can't do real capture; default to the mock for screens.
        return true
        #else
        // Release/TestFlight on a real device: use real WebRTC so calls (and
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
}
