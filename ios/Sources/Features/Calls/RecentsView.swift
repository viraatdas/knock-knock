import SwiftUI

@MainActor
final class RecentsViewModel: ObservableObject {
    @Published var calls: [Call] = []
    @Published var isLoading = false
    @Published var nextCursor: String?

    private let api = APIClient.shared
    private var currentUserId: String?
    private var contactsByUserId: [String: Contact] = [:]

    func load(currentUserId: String?) async {
        self.currentUserId = currentUserId
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.calls()
            calls = resp.calls
            nextCursor = resp.nextCursor
        } catch {
            if Config.useMockData { calls = MockData.calls }
        }
        do {
            let contacts = try await api.contacts()
            var byUserId: [String: Contact] = [:]
            for contact in contacts {
                guard let userId = contact.contactUserId else { continue }
                byUserId[userId] = byUserId[userId] ?? contact
            }
            contactsByUserId = byUserId
        } catch {
            contactsByUserId = [:]
        }
    }

    func displayName(for call: Call) -> String {
        guard let other = otherParticipant(for: call) else { return "Slide" }
        return displayName(for: other)
    }

    func subtitle(for call: Call) -> (text: String, isMissed: Bool) {
        let meId = currentUserId ?? MockData.me.id
        let outgoing = call.createdBy == meId
        switch call.status {
        case .missed:
            return ("Missed", true)
        case .declined:
            return (outgoing ? "Declined" : "Declined", true)
        case .ringing:
            return ("Ringing", false)
        default:
            let dir = outgoing ? "Outgoing" : "Incoming"
            if let s = call.startedAt, let e = call.endedAt {
                let mins = max(1, Int(e.timeIntervalSince(s) / 60))
                return ("\(dir) · \(mins)m", false)
            }
            return (dir, false)
        }
    }

    func userFor(call: Call) -> User {
        guard let other = otherParticipant(for: call) else {
            return User(id: call.createdBy, phone: "", displayName: "Slide",
                        avatarUrl: nil, createdAt: nil, lastSeenAt: nil)
        }
        if let contact = contactsByUserId[other.userId], let user = contact.slideUser {
            return user
        }
        let name = displayName(for: other)
        return User(id: other.userId, phone: other.phone ?? "", displayName: name, avatarUrl: other.avatarUrl,
                    createdAt: nil, lastSeenAt: nil)
    }

    private func otherParticipant(for call: Call) -> CallParticipant? {
        let meId = currentUserId ?? MockData.me.id
        if let other = call.participants.first(where: { $0.userId != meId }) {
            return other
        }
        if let createdBy = call.participants.first(where: { $0.userId == call.createdBy }) {
            return createdBy
        }
        return call.participants.first
    }

    private func displayName(for participant: CallParticipant) -> String {
        if let contact = contactsByUserId[participant.userId] {
            let name = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let name = participant.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           name.localizedCaseInsensitiveCompare("unknown") != .orderedSame,
           name.localizedCaseInsensitiveCompare("someone") != .orderedSame {
            return name
        }
        if let phone = participant.phone, !phone.isEmpty { return phone }
        if Config.useMockData, let name = MockData.names[participant.userId] { return name }
        return "Slide"
    }
}

struct RecentsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = RecentsViewModel()
    @State private var showDial = false

    var body: some View {
        VStack(spacing: 0) {
            WordmarkBar {
                Button {
                    showDial = true
                } label: {
                    Image(systemName: "circle.grid.3x3")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.Color.text)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Open callpad")
            }
            HairlineDivider()

            if vm.calls.isEmpty && !vm.isLoading {
                EmptyStateView(message: "No calls yet", systemImage: "phone")
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Space.sm) {
                        ForEach(vm.calls) { call in
                            let user = vm.userFor(call: call)
                            RecentCallCard(name: vm.displayName(for: call),
                                           subtitle: vm.subtitle(for: call),
                                           isVideo: call.videoEnabled ?? true) {
                                appState.startKnockCall(to: user, video: call.videoEnabled ?? true)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
        .background(Theme.Color.bg)
        .task { await vm.load(currentUserId: appState.currentUser?.id) }
        .sheet(isPresented: $showDial) {
            DialView()
                .environmentObject(appState)
        }
    }
}

struct RecentCallCard: View {
    let name: String
    let subtitle: (text: String, isMissed: Bool)
    var isVideo: Bool
    let onTapCall: () -> Void

    var body: some View {
        Button(action: onTapCall) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    AvatarCircle(name: name, size: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.text)
                            .lineLimit(1)
                        Text(subtitle.text)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(subtitle.isMissed ? Theme.Color.danger
                                                               : Theme.Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Theme.Space.sm)

                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: isVideo ? "video" : "phone")
                            .font(.system(size: 13, weight: .light))
                        Text(isVideo ? "Video" : "Audio")
                            .font(Theme.Font.caption)
                    }
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, Theme.Space.sm)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(Theme.Color.bgGrouped)
                            .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
                    )
                }

                HStack(spacing: Theme.Space.sm) {
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Text("tap")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Color.onAccent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap to call")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.text)
                        Text("Repeats the last \(isVideo ? "video" : "audio") call")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }

                    Spacer()
                }
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Color.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Tap to call \(name)")
    }
}
