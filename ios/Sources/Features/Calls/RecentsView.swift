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

    /// One card per person: keep only the most recent call for each other-party,
    /// so calling the same person repeatedly shows a single tile (FaceTime-style).
    /// `calls` is already newest-first from the API.
    var dedupedCalls: [Call] {
        var seen = Set<String>()
        var out: [Call] = []
        for call in calls {
            let key = otherParticipant(for: call)?.userId ?? call.id
            if seen.insert(key).inserted { out.append(call) }
        }
        return out
    }

    func displayName(for call: Call) -> String {
        guard let other = otherParticipant(for: call) else { return "Knock Knock" }
        return displayName(for: other)
    }

    /// Compact relative date for the grid card, e.g. "6/2/26".
    func dateLabel(for call: Call) -> String {
        let when = call.startedAt ?? call.createdAt
        guard let when else { return "" }
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f.string(from: when)
    }

    /// Direction arrow + Video/Audio, e.g. "↗ Video" (outgoing) / "↙ Video".
    func directionLabel(for call: Call) -> String {
        let meId = currentUserId ?? MockData.me.id
        let outgoing = call.createdBy == meId
        let arrow = outgoing ? "↗" : "↙"
        let kind = (call.videoEnabled ?? true) ? "Video" : "Audio"
        return "\(arrow) \(kind)"
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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.md),
                                        GridItem(.flexible(), spacing: Theme.Space.md)],
                              spacing: Theme.Space.md) {
                        ForEach(vm.dedupedCalls) { call in
                            let user = vm.userFor(call: call)
                            RecentGridCard(
                                name: vm.displayName(for: call),
                                photoURL: user.avatarUrl.flatMap(URL.init(string:)),
                                direction: vm.directionLabel(for: call),
                                date: vm.dateLabel(for: call),
                                isVideo: call.videoEnabled ?? true,
                                isMissed: vm.subtitle(for: call).isMissed
                            ) {
                                appState.startKnockCall(to: user, video: call.videoEnabled ?? true)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
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

/// FaceTime-style grid tile: a tall rounded card filled with the person's photo
/// (or a warm initials backdrop), name top-left, direction + date bottom-left,
/// and a video glyph in the bottom-right. The whole card taps to call.
struct RecentGridCard: View {
    let name: String
    let photoURL: URL?
    let direction: String
    let date: String
    var isVideo: Bool
    var isMissed: Bool
    let onTapCall: () -> Void

    var body: some View {
        Button(action: onTapCall) {
            ZStack {
                // Photo fill, or a warm tinted backdrop with big initials.
                if let photoURL {
                    AsyncImage(url: photoURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        initialsBackdrop
                    }
                } else {
                    initialsBackdrop
                }

                // Bottom scrim so text is legible over any photo.
                LinearGradient(
                    colors: [.clear, .clear, Theme.Color.text.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading) {
                    Text(name)
                        .font(Theme.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(direction)
                                .foregroundStyle(isMissed ? Theme.Color.danger : .white)
                            Text(date)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .font(Theme.Font.caption)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)

                        Spacer()

                        // Corner video glyph (visual affordance, not a label).
                        Image(systemName: isVideo ? "video.fill" : "phone.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.Color.text.opacity(0.35)))
                    }
                }
                .padding(Theme.Space.md)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Call \(name)")
    }

    private var initialsBackdrop: some View {
        ZStack {
            Theme.Color.bgGrouped
            AvatarCircle(name: name, size: 96)
        }
    }
}
