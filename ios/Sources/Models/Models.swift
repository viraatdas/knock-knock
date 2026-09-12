import Foundation

// MARK: - Models (camelCase JSON, ISO-8601 with fractional seconds; see SPEC §1)

/// `woman` | `man` | `nonbinary`, used both for `gender` and `interestedIn`.
enum Gender: String, Codable, CaseIterable, Identifiable, Hashable {
    case woman, man, nonbinary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .woman: return "Woman"
        case .man: return "Man"
        case .nonbinary: return "Nonbinary"
        }
    }
}

/// `GET /v1/session` — the one place that knows whether doors are open.
struct SessionWindow: Codable, Hashable {
    let isOpen: Bool
    let opensAt: Date
    let closesAt: Date
    /// Local (America/Los_Angeles) calendar date of the window, "YYYY-MM-DD".
    let sessionDate: String
    let serverTime: Date
    let timezone: String
    let dateSeconds: Int
    let radiusMiles: Double
}

/// `GET /me` / `PATCH /me`.
struct MeView: Codable, Identifiable, Hashable {
    let id: String
    let phone: String
    var displayName: String?
    /// "YYYY-MM-DD", not decoded as a Date (no time component).
    var birthdate: String?
    var age: Int?
    var gender: Gender?
    var interestedIn: [Gender]
    var ageMin: Int
    var ageMax: Int
    var bio: String
    var hasPhoto: Bool
    var photoUrl: String?
    var photoUpdatedAt: Date?
    var profileComplete: Bool
    var hasLocation: Bool
    var isReviewAccount: Bool
    var createdAt: Date?
    var lastSeenAt: Date?
}

/// A profile as seen by someone else: a date partner, a match, a chat.
struct PublicProfile: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var age: Int?
    var gender: Gender?
    var bio: String
    var hasPhoto: Bool
    var photoUrl: String?
    /// Rounded integer miles; nil if either side has no location.
    var distanceMiles: Int?
}

/// The live date: my room, my token, my partner.
struct DateSession: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    let sfuUrl: String
    let joinToken: String
    let startedAt: Date
    let endsAt: Date
    let dateSeconds: Int
    let partner: PublicProfile
}

/// One row of `GET /dates/today`.
struct DateHistoryEntry: Codable, Identifiable, Hashable {
    let id: String
    let partner: PublicProfile
    let startedAt: Date
    var endedAt: Date?
    /// My own decision only; the partner's is never exposed until matched.
    var myDecision: Bool?
    var matched: Bool
}

struct LastMessage: Codable, Hashable {
    let id: String
    let senderId: String
    let body: String
    let createdAt: Date
}

/// One row of `GET /matches`.
struct MatchSummary: Codable, Identifiable, Hashable {
    let id: String
    var partner: PublicProfile
    let createdAt: Date
    var lastMessage: LastMessage?
    var unreadCount: Int
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let matchId: String
    let senderId: String
    var body: String
    let createdAt: Date
}

struct MessagesPage: Codable {
    let messages: [Message]
    let hasMore: Bool
}

/// `POST /lobby/join` / `POST /lobby/heartbeat`.
struct LobbyResponse: Codable {
    let status: String   // "waiting" | "matched"
    var date: DateSession?
}

/// `POST /dates/:id/decision`.
struct DecisionResponse: Codable {
    let status: String   // "waiting" | "matched" | "passed"
    var match: MatchSummary?
}

/// What a finished decision landed on — drives DecisionView's outcome screen.
enum DecisionResult: Equatable {
    case matched(MatchSummary)
    case waiting
    case passed
}

/// `POST /auth/request-otp`.
struct RequestOtpResponse: Codable {
    let status: String        // "sent"
    let transport: String     // "review" | "sms" | "firebase"
    /// Only present with `EXPOSE_DEV_OTP=true` (local/CI).
    var devCode: String?
}

// MARK: - Auth payloads

struct VerifyOtpResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let isNewUser: Bool
    let user: MeView
}

struct RefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

// MARK: - Safety

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case inappropriate, harassment, fake, underage, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inappropriate: return "Inappropriate content"
        case .harassment: return "Harassment"
        case .fake: return "Fake profile"
        case .underage: return "Underage"
        case .other: return "Something else"
        }
    }
}

// MARK: - Error envelope

struct APIErrorEnvelope: Codable {
    struct Body: Codable {
        let code: String
        let message: String
        var retryAfter: Int?
    }
    let error: Body
}
