import Foundation

/// Sample data so the UI renders fully in the simulator without a live backend.
/// Only used when `Config.useMockData` is true (DEBUG by default).
enum MockData {
    static let me = User(
        id: "u_me",
        phone: "+14155550123",
        displayName: "Alex Rivera",
        avatarUrl: nil,
        createdAt: Date(timeIntervalSinceNow: -86_400 * 90),
        lastSeenAt: Date()
    )

    static let contacts: [Contact] = [
        c("Amelia Stone", "+14155550111", onSlide: true),
        c("Ben Carter", "+14155550112", onSlide: true),
        c("Caroline Diaz", "+14155550113", onSlide: false),
        c("Daniel Wu", "+14155550114", onSlide: true),
        c("Elena Marsh", "+14155550115", onSlide: false),
        c("Faisal Khan", "+14155550116", onSlide: true),
        c("Grace Lin", "+14155550117", onSlide: true),
        c("Henry Adams", "+14155550118", onSlide: false),
        c("Isla Moreno", "+14155550119", onSlide: true),
        c("Jonah Pratt", "+14155550120", onSlide: false),
        c("Karina Voss", "+14155550121", onSlide: true),
        c("Liam Foster", "+14155550122", onSlide: true)
    ]

    static func userForContact(_ contact: Contact) -> User {
        User(id: contact.contactUserId ?? "u_\(contact.phone)",
             phone: contact.phone,
             displayName: contact.displayName,
             avatarUrl: nil,
             createdAt: nil, lastSeenAt: nil)
    }

    static let calls: [Call] = [
        call(id: "c1", with: "u_amelia", status: .active, ago: 60 * 12, duration: 12 * 60,
             createdByMe: true),
        call(id: "c2", with: "u_ben", status: .missed, ago: 60 * 90, duration: 0,
             createdByMe: false),
        call(id: "c3", with: "u_daniel", status: .ended, ago: 60 * 60 * 5, duration: 3 * 60,
             createdByMe: false),
        call(id: "c4", with: "u_grace", status: .declined, ago: 60 * 60 * 26, duration: 0,
             createdByMe: true),
        call(id: "c5", with: "u_isla", status: .ended, ago: 60 * 60 * 50, duration: 42 * 60,
             createdByMe: true)
    ]

    /// Display names keyed by user id for the recents list.
    static let names: [String: String] = [
        "u_amelia": "Amelia Stone",
        "u_ben": "Ben Carter",
        "u_daniel": "Daniel Wu",
        "u_grace": "Grace Lin",
        "u_isla": "Isla Moreno"
    ]

    static func callSession(for user: User, video: Bool) -> CallSession {
        let call = Call(id: "mock_\(UUID().uuidString.prefix(6))",
                        roomId: "room_mock", sfuNodeId: "node_mock",
                        type: .oneToOne, createdBy: me.id, status: .active,
                        videoEnabled: video,
                        ringStyle: "call",
                        startedAt: Date(), endedAt: nil, createdAt: Date(),
                        participants: [
                            CallParticipant(userId: me.id, state: .joined, joinedAt: Date(), leftAt: nil),
                            CallParticipant(userId: user.id, state: .ringing, joinedAt: nil, leftAt: nil)
                        ])
        return CallSession(call: call, joinToken: "mock-token",
                           sfuUrl: "wss://sfu.example/mock",
                           iceServers: [IceServer(urls: ["stun:stun.l.google.com:19302"],
                                                  username: nil, credential: nil)])
    }

    static func incomingSession(callId: String, video: Bool) -> CallSession {
        let call = Call(id: callId, roomId: "room_mock", sfuNodeId: "node_mock",
                        type: .oneToOne, createdBy: "u_other", status: .active,
                        videoEnabled: video,
                        ringStyle: "call",
                        startedAt: Date(), endedAt: nil, createdAt: Date(), participants: [])
        return CallSession(call: call, joinToken: "mock-token",
                           sfuUrl: "wss://sfu.example/mock",
                           iceServers: [IceServer(urls: ["stun:stun.l.google.com:19302"],
                                                  username: nil, credential: nil)])
    }

    // MARK: helpers

    private static func c(_ name: String, _ phone: String, onSlide: Bool) -> Contact {
        Contact(id: "ct_\(phone)", ownerUserId: me.id,
                contactUserId: onSlide ? "u_\(phone)" : nil,
                phone: phone, displayName: name)
    }

    private static func call(id: String, with userId: String, status: CallStatus,
                             ago: TimeInterval, duration: TimeInterval,
                             createdByMe: Bool) -> Call {
        let start = Date(timeIntervalSinceNow: -ago)
        return Call(id: id, roomId: "room_\(id)", sfuNodeId: "node",
                    type: .oneToOne,
                    createdBy: createdByMe ? me.id : userId,
                    status: status,
                    videoEnabled: true,
                    ringStyle: "call",
                    startedAt: status == .missed || status == .declined ? nil : start,
                    endedAt: duration > 0 ? start.addingTimeInterval(duration) : nil,
                    createdAt: start,
                    participants: [
                        CallParticipant(userId: me.id, state: .joined, joinedAt: start, leftAt: nil),
                        CallParticipant(userId: userId, state: .joined, joinedAt: start, leftAt: nil)
                    ])
    }
}
