import SwiftUI

@MainActor
final class RecentsViewModel: ObservableObject {
    @Published var calls: [Call] = []
    @Published var isLoading = false
    @Published var nextCursor: String?

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.calls()
            calls = resp.calls
            nextCursor = resp.nextCursor
        } catch {
            if Config.useMockData { calls = MockData.calls }
        }
    }

    func displayName(for call: Call) -> String {
        // Pick the participant who isn't me.
        let meId = MockData.me.id
        let other = call.participants.first(where: { $0.userId != meId })?.userId ?? call.createdBy
        return MockData.names[other] ?? "Unknown"
    }

    func subtitle(for call: Call) -> (text: String, isMissed: Bool) {
        let meId = MockData.me.id
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
        let meId = MockData.me.id
        let otherId = call.participants.first(where: { $0.userId != meId })?.userId ?? call.createdBy
        let name = MockData.names[otherId] ?? "Unknown"
        return User(id: otherId, phone: "", displayName: name, avatarUrl: nil,
                    createdAt: nil, lastSeenAt: nil)
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
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.Color.text)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("New call")
            }
            HairlineDivider()

            if vm.calls.isEmpty && !vm.isLoading {
                EmptyStateView(message: "No calls yet", systemImage: "phone")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.calls) { call in
                            CallRow(name: vm.displayName(for: call),
                                    subtitle: vm.subtitle(for: call),
                                    isVideo: false) {
                                appState.startCall(to: vm.userFor(call: call), video: false)
                            }
                            HairlineDivider(leadingInset: Theme.Space.lg + 44 + Theme.Space.md)
                        }
                    }
                    .padding(.top, Theme.Space.xs)
                }
            }
        }
        .background(Theme.Color.bg)
        .task { await vm.load() }
        .sheet(isPresented: $showDial) {
            DialView()
                .environmentObject(appState)
        }
    }
}

struct CallRow: View {
    let name: String
    let subtitle: (text: String, isMissed: Bool)
    var isVideo: Bool
    let onCallBack: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            AvatarCircle(name: name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                Text(subtitle.text)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(subtitle.isMissed ? Theme.Color.danger
                                                       : Theme.Color.textSecondary)
            }
            Spacer()
            Button(action: onCallBack) {
                Image(systemName: isVideo ? "video" : "phone")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Color.text)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Call back \(name)")
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .contentShape(Rectangle())
        // Tap anywhere on the row to call back, not just the phone icon.
        .onTapGesture { onCallBack() }
    }
}
