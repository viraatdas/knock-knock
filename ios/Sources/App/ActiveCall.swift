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

    @Published var status: Status
    @Published var callId: String?
    @Published var session: CallSession?

    init(direction: Direction, remoteName: String, remotePhone: String,
         remoteUserId: String?, isVideo: Bool, status: Status) {
        self.direction = direction
        self.remoteName = remoteName
        self.remotePhone = remotePhone
        self.remoteUserId = remoteUserId
        self.isVideo = isVideo
        self.status = status
    }
}
