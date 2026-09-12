import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case transport(Error)
    case decoding(Error)
    case unauthorized
    case server(code: String, message: String, retryAfter: Int?, status: Int)
    case http(status: Int)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That didn't work. Try again."
        case .transport(let e): return e.localizedDescription
        case .decoding: return "Couldn't read the server response."
        case .unauthorized: return "Your session expired. Sign in again."
        case .server(_, let message, _, _): return message
        case .http(let status): return "Request failed (\(status))."
        case .notAuthenticated: return "Not signed in."
        }
    }

    /// The server-supplied error code, when there is one (e.g. "session_closed",
    /// "profile_incomplete", "location_required", "date_in_progress").
    var code: String? {
        guard case .server(let code, _, _, _) = self else { return nil }
        return code
    }

    var status: Int? {
        switch self {
        case .server(_, _, _, let status): return status
        case .http(let status): return status
        case .unauthorized: return 401
        default: return nil
        }
    }

    /// A transient failure worth a same-request retry (network blip / 5xx).
    var isRetryable: Bool {
        switch self {
        case .transport, .decoding:
            return true
        case .http(let status):
            return status < 0 || status >= 500
        case .server(_, _, _, let status):
            return status >= 500
        default:
            return false
        }
    }
}
