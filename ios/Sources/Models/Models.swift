import Foundation

// MARK: - Models (camelCase JSON, matching AGENTS.md)

struct User: Codable, Identifiable, Hashable {
    let id: String
    let phone: String
    var displayName: String?
    var avatarUrl: String?
    var createdAt: Date?
    var lastSeenAt: Date?
}

struct Device: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let pushToken: String
    let platform: String      // ios | android
    let appVersion: String
    var updatedAt: Date?
}

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let ownerUserId: String
    var contactUserId: String?
    let phone: String
    var displayName: String
    /// The matched Slide user's avatar (on-Slide contacts only).
    var avatarUrl: String? = nil

    var onSlide: Bool { contactUserId != nil }

    var slideUser: User? {
        guard let contactUserId, !contactUserId.isEmpty else { return nil }
        return User(id: contactUserId,
                    phone: phone,
                    displayName: displayName,
                    avatarUrl: avatarUrl,
                    createdAt: nil,
                    lastSeenAt: nil)
    }
}

/// Result row from POST /contacts/sync.
struct ContactSyncResult: Codable, Hashable {
    let phone: String
    var displayName: String?
    var userId: String?
    let onSlide: Bool
}

enum CallType: String, Codable, Hashable {
    case oneToOne = "one_to_one"
    case group
}

enum CallStatus: String, Codable, Hashable {
    case ringing, active, ended, missed, declined
}

enum ParticipantState: String, Codable, Hashable {
    case invited, ringing, joined, left, declined
}

struct CallParticipant: Codable, Hashable {
    let userId: String
    let state: ParticipantState
    var joinedAt: Date?
    var leftAt: Date?
    var displayName: String? = nil
    var phone: String? = nil
    var avatarUrl: String? = nil
}

struct Call: Codable, Identifiable, Hashable {
    let id: String
    let roomId: String
    var sfuNodeId: String?
    let type: CallType
    let createdBy: String
    var status: CallStatus
    var startedAt: Date?
    var endedAt: Date?
    var createdAt: Date?
    var participants: [CallParticipant]
}

struct IceServer: Codable, Hashable {
    let urls: [String]
    var username: String?
    var credential: String?
}

// MARK: - Auth payloads

struct VerifyOtpResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let isNewUser: Bool
    let user: User
}

struct RefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct RequestOtpResponse: Codable {
    /// In dev the backend echoes the code so we can autofill it.
    var devCode: String?
}

// MARK: - Calls control plane

/// Returned by POST /calls and POST /calls/:id/accept.
struct CallSession: Codable {
    let call: Call
    let joinToken: String
    let sfuUrl: String
    let iceServers: [IceServer]
}

struct CallListResponse: Codable {
    let calls: [Call]
    var nextCursor: String?
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
