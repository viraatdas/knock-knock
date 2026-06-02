import Foundation
import Combine

/// Observable state for the call currently presented (incoming or in-call).
@MainActor
final class ActiveCall: ObservableObject, Identifiable {
    enum Direction { case incoming, outgoing }
    enum Status { case ringing, dialing, connecting, active, failed, ended }

    let id = UUID()
    /// Stable UUID for CallKit.
    let uuid = UUID()

    let direction: Direction
    let remoteName: String
    let remotePhone: String
    let remoteUserId: String?
    let isVideo: Bool

    /// Whether this is a group call (more than one other participant).
    let isGroup: Bool
    /// Display names of the invited group members (excludes self). For 1:1 this
    /// is just `[remoteName]`.
    let memberNames: [String]

    @Published var status: Status
    @Published var callId: String?
    @Published var session: CallSession?

    init(direction: Direction, remoteName: String, remotePhone: String,
         remoteUserId: String?, isVideo: Bool, status: Status,
         isGroup: Bool = false, memberNames: [String] = []) {
        self.direction = direction
        self.remoteName = remoteName
        self.remotePhone = remotePhone
        self.remoteUserId = remoteUserId
        self.isVideo = isVideo
        self.status = status
        self.isGroup = isGroup
        self.memberNames = memberNames.isEmpty ? [remoteName] : memberNames
    }
}
