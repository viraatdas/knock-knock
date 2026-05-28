import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case transport(Error)
    case decoding(Error)
    case unauthorized
    case server(code: String, message: String, retryAfter: Int?)
    case http(status: Int)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .transport(let e): return e.localizedDescription
        case .decoding: return "Couldn't read the server response."
        case .unauthorized: return "Your session expired. Please sign in again."
        case .server(_, let message, _): return message
        case .http(let status): return "Request failed (\(status))."
        case .notAuthenticated: return "Not signed in."
        }
    }
}
