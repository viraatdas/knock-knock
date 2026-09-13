import Foundation

/// Sample data so the UI renders fully in the simulator without a live backend.
/// Only used when `Config.useMockData` is true (DEBUG by default), and to seed
/// `-scene <name>` screenshot launches (see AppState.bootstrap).
enum MockData {
    static let me = MeView(
        id: "u_me", phone: "+14155550123", displayName: "Alex Rivera",
        birthdate: "1996-04-02", age: 30, gender: .nonbinary,
        interestedIn: [.woman, .man, .nonbinary], ageMin: 24, ageMax: 38,
        bio: "Cook elaborate breakfasts. Bad at small talk, good at big talk.",
        hasPhoto: false, photoUrl: nil, photoUpdatedAt: nil,
        profileComplete: true, hasLocation: true, isReviewAccount: false,
        createdAt: Date(timeIntervalSinceNow: -86_400 * 90), lastSeenAt: Date())

    /// A fresh, not-yet-onboarded version of `me` for the profile-setup scenes.
    static let meIncomplete = MeView(
        id: "u_me", phone: "+14155550123", displayName: nil,
        birthdate: nil, age: nil, gender: nil, interestedIn: [],
        ageMin: 18, ageMax: 99, bio: "",
        hasPhoto: false, photoUrl: nil, photoUpdatedAt: nil,
        profileComplete: false, hasLocation: false, isReviewAccount: false,
        createdAt: Date(), lastSeenAt: Date())

    /// Six believable profiles, ages 24-34.
    static let profiles: [PublicProfile] = [
        PublicProfile(id: "u_maya", displayName: "Maya", age: 29, gender: .woman,
                      bio: "Runs a pottery studio on weekends. Terrible at karaoke, does it anyway.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 4),
        PublicProfile(id: "u_daniel", displayName: "Daniel", age: 31, gender: .man,
                      bio: "Backpacked through Patagonia and still hasn't shut up about it.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 9),
        PublicProfile(id: "u_priya", displayName: "Priya", age: 27, gender: .woman,
                      bio: "Product designer by day, terrible at Mario Kart by night.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 2),
        PublicProfile(id: "u_marcus", displayName: "Marcus", age: 33, gender: .man,
                      bio: "Slow runner, fast reader. Will talk your ear off about sci-fi.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 15),
        PublicProfile(id: "u_sam", displayName: "Sam", age: 28, gender: .nonbinary,
                      bio: "Coffee, long walks, bad puns.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 6),
        PublicProfile(id: "u_grace", displayName: "Grace", age: 34, gender: .woman,
                      bio: "Grows tomatoes on a fire escape. Ask about the tomatoes.",
                      hasPhoto: false, photoUrl: nil, distanceMiles: 11)
    ]

    static func profile(_ id: String) -> PublicProfile {
        profiles.first { $0.id == id } ?? profiles[0]
    }

    /// What the server actually sends as `DateSession.partner`: the id and
    /// nothing else. Dates are anonymous; the real card only arrives inside
    /// a `MatchSummary` after a mutual yes.
    static func anonymousPartner(id: String) -> PublicProfile {
        PublicProfile(id: id, displayName: "", age: nil, gender: nil, bio: "",
                      hasPhoto: false, photoUrl: nil, distanceMiles: nil)
    }

    /// A date in progress, 1:48 elapsed of 5:00 (matches the SPEC's "3:12 left" scene).
    /// `partner` is redacted down to its id before it goes in, mirroring the
    /// wire contract; the id still picks the stand-in remote feed in
    /// `MockVideoPlaceholder`.
    static func dateSession(with partner: PublicProfile = profiles[0],
                            secondsLeft: TimeInterval = 192) -> DateSession {
        DateSession(id: "d_mock", roomId: "room_mock", sfuUrl: "wss://sfu.example/mock",
                   joinToken: "mock-token",
                   startedAt: Date(timeIntervalSinceNow: -(300 - secondsLeft)),
                   endsAt: Date(timeIntervalSinceNow: secondsLeft),
                   dateSeconds: 300, partner: anonymousPartner(id: partner.id))
    }

    /// 10-message transcript for the first match, with Maya.
    static let transcript: [Message] = {
        let base = Date(timeIntervalSinceNow: -3600)
        func m(_ i: Int, _ sender: String, _ body: String, _ offset: TimeInterval) -> Message {
            Message(id: "msg\(i)", matchId: "m1", senderId: sender, body: body,
                   createdAt: base.addingTimeInterval(offset))
        }
        return [
            m(1, "u_me", "Hey! That was fun.", 0),
            m(2, "u_maya", "Same! You had me at the pottery joke.", 40),
            m(3, "u_me", "I have more where that came from.", 90),
            m(4, "u_maya", "Careful, I might hold you to that.", 140),
            m(5, "u_me", "What are you up to tonight?", 400),
            m(6, "u_maya", "Just got back from the studio, cleaning clay off everything.", 460),
            m(7, "u_me", "Sounds messier than my night.", 520),
            m(8, "u_maya", "It always is. Worth it though.", 580),
            m(9, "u_me", "Want to grab coffee this week?", 900),
            m(10, "u_maya", "Sounds great, can't wait!", 960)
        ]
    }()

    static let matches: [MatchSummary] = [
        MatchSummary(id: "m1", partner: profiles[0],
                     createdAt: Date(timeIntervalSinceNow: -3600 * 2),
                     lastMessage: LastMessage(id: "msg10", senderId: "u_maya",
                                              body: "Sounds great, can't wait!",
                                              createdAt: Date(timeIntervalSinceNow: -600)),
                     unreadCount: 2),
        MatchSummary(id: "m2", partner: profiles[2],
                     createdAt: Date(timeIntervalSinceNow: -86_400),
                     lastMessage: nil, unreadCount: 0),
        MatchSummary(id: "m3", partner: profiles[4],
                     createdAt: Date(timeIntervalSinceNow: -86_400 * 3),
                     lastMessage: LastMessage(id: "msgX", senderId: "u_me",
                                              body: "Careful, I have more.",
                                              createdAt: Date(timeIntervalSinceNow: -86_400 * 2)),
                     unreadCount: 0)
    ]

    static let datesToday: [DateHistoryEntry] = [
        DateHistoryEntry(id: "d1", partner: profiles[0],
                         startedAt: Date(timeIntervalSinceNow: -3600 * 3),
                         endedAt: Date(timeIntervalSinceNow: -3600 * 3 + 300),
                         myDecision: true, matched: true),
        DateHistoryEntry(id: "d2", partner: profiles[1],
                         startedAt: Date(timeIntervalSinceNow: -3600 * 2),
                         endedAt: Date(timeIntervalSinceNow: -3600 * 2 + 300),
                         myDecision: false, matched: false)
    ]

    static let sessionOpen = SessionWindow(
        isOpen: true, opensAt: Date(timeIntervalSinceNow: -1800),
        closesAt: Date(timeIntervalSinceNow: 2460),
        sessionDate: ISO8601DateFormatter().string(from: Date()).prefix(10).description,
        serverTime: Date(), timezone: "America/Los_Angeles",
        dateSeconds: 300, radiusMiles: 75)

    static let sessionClosed = SessionWindow(
        isOpen: false, opensAt: Date(timeIntervalSinceNow: 3600 * 2 + 60 * 14),
        closesAt: Date(timeIntervalSinceNow: 3600 * 3 + 60 * 14),
        sessionDate: ISO8601DateFormatter().string(from: Date()).prefix(10).description,
        serverTime: Date(), timezone: "America/Los_Angeles",
        dateSeconds: 300, radiusMiles: 75)
}
