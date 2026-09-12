import SwiftUI
import UIKit
import Foundation

/// One chat (SPEC §2.3 "Chat"). Init: `ChatView(matchId: String)`. Pushed
/// from `MatchesView`'s NavigationStack. Reads
/// `AppState.messagesByMatch[matchId]` (loaded via `AppState.loadMessages`)
/// and the `MatchSummary` from `AppState.matches` for the partner header.
/// Marks read on appear and on each incoming message while visible; incoming
/// messages arrive live through AppState's WebSocket handling while
/// `activeChatMatchId == matchId`.
struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ChatViewModel
    @State private var showSafety = false
    @State private var revealedTimestampIds: Set<String> = []
    @FocusState private var composerFocused: Bool
    /// Set once the deferred scroll-to-bottom in the body's `onAppear` (or,
    /// for a chat whose history hadn't loaded yet on first render, the
    /// first `onChange(of: messages.last?.id)`) actually lands. Gates
    /// `topAnchor`'s pagination trigger so a cached/instant history load —
    /// where `messages` is already non-empty at scroll offset 0 on the very
    /// first render — can't fire `loadOlder` and race the still-pending
    /// scroll-to-bottom, which used to yank the view back up once that
    /// pagination resolved.
    @State private var didCompleteInitialScroll = false

    init(matchId: String) {
        _vm = StateObject(wrappedValue: ChatViewModel(matchId: matchId))
    }

    private var match: MatchSummary? {
        appState.matches.first { $0.id == vm.matchId }
    }

    private var messages: [ChatMessage] {
        appState.messagesByMatch[vm.matchId] ?? []
    }

    /// Bubbles cap at 78% of the screen width (SPEC §2.3). The app is
    /// portrait-only (SPEC §2.1), so the screen width is a stable basis.
    private var maxBubbleWidth: CGFloat {
        UIScreen.main.bounds.width * 0.78
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    topAnchor(proxy: proxy)
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard let last = messages.last else { return }
                // Dispatched to the next runloop turn: on first appear the
                // ScrollView hasn't measured its content yet, so scrolling
                // synchronously here can land short of the true bottom and
                // leave the newest bubble half hidden under the composer.
                DispatchQueue.main.async {
                    proxy.scrollTo(last.id, anchor: .bottom)
                    didCompleteInitialScroll = true
                }
            }
            // Keyed on the *last message's id*, not the count: paging older
            // messages in at the top also changes the count, but leaves the
            // last id alone, so that doesn't yank the scroll position back
            // down to the bottom.
            .onChange(of: messages.last?.id) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(Theme.Motion.standard) { proxy.scrollTo(last.id, anchor: .bottom) }
                didCompleteInitialScroll = true
                if last.message.senderId != appState.me?.id {
                    Task { await appState.markRead(matchId: vm.matchId) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                HairlineDivider()
                composer
            }
            .background(Theme.Color.bg)
        }
        .background(Theme.Color.bg)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        // The floating tab bar has no business showing behind an open chat —
        // hide it here the way a pushed screen normally would.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSafety = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.Color.text)
                }
            }
        }
        .sheet(isPresented: $showSafety) {
            if let partner = match?.partner {
                SafetySheet(partner: partner, matchId: vm.matchId, onHandled: { dismiss() })
                    .environmentObject(appState)
            }
        }
        .overlay(alignment: .top) {
            if appState.matchEndedToastMatchId == vm.matchId {
                MatchEndedToast {
                    appState.matchEndedToastMatchId = nil
                    dismiss()
                }
                .padding(.top, Theme.Space.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.standard, value: appState.matchEndedToastMatchId)
        .task { await vm.onAppear(appState: appState) }
        .onDisappear { vm.onDisappear(appState: appState) }
        .onChange(of: appState.matchEndedToastMatchId) { _, newValue in
            guard newValue == vm.matchId else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard appState.matchEndedToastMatchId == vm.matchId else { return }
                appState.matchEndedToastMatchId = nil
                dismiss()
            }
        }
    }

    private var titleText: String {
        guard let partner = match?.partner else { return "Chat" }
        if let age = partner.age { return "\(partner.displayName) \u{00b7} \(age)" }
        return partner.displayName
    }

    // MARK: - Rows: day separators, grouped spacing, sparse timestamps

    private enum Row: Identifiable {
        case day(id: String, label: String)
        case message(ChatMessage, tightTop: Bool, showTimestamp: Bool)

        var id: String {
            switch self {
            case .day(let id, _): return id
            case .message(let message, _, _): return message.id
            }
        }
    }

    /// Consecutive bubbles from the same sender within a minute sit tight;
    /// a timestamp shows automatically only on the first message of the day
    /// or after a 10-minute-plus gap (SPEC: "timestamps on long-press or
    /// every ~10 min gap"). Long-press reveals one on any bubble on demand.
    private var rows: [Row] {
        var result: [Row] = []
        var previous: ChatMessage?
        for message in messages {
            let sameDay = previous.map {
                Calendar.current.isDate($0.message.createdAt, inSameDayAs: message.message.createdAt)
            } ?? false
            if !sameDay {
                result.append(.day(id: "day-\(message.id)", label: dayLabel(message.message.createdAt)))
            }
            let gap = message.message.createdAt.timeIntervalSince(previous?.message.createdAt ?? .distantPast)
            let tightTop = sameDay && previous?.message.senderId == message.message.senderId && gap < 60
            let showTimestamp = !sameDay || gap >= 600
            result.append(.message(message, tightTop: tightTop, showTimestamp: showTimestamp))
            previous = message
        }
        return result
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .day(_, let label):
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xs)
                .frame(maxWidth: .infinity)
        case .message(let message, let tightTop, let showTimestamp):
            VStack(spacing: 2) {
                if showTimestamp || revealedTimestampIds.contains(message.id) {
                    Text(timeLabel(message.message.createdAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .padding(.bottom, 2)
                }
                ChatBubble(message: message, maxWidth: maxBubbleWidth,
                          isMine: message.message.senderId == appState.me?.id,
                          onRetry: {
                    Task { await appState.retryMessage(matchId: vm.matchId, tempId: message.id) }
                }, onLongPress: {
                    Haptics.select()
                    withAnimation(Theme.Motion.fast) {
                        if !revealedTimestampIds.insert(message.id).inserted {
                            revealedTimestampIds.remove(message.id)
                        }
                    }
                })
            }
            .padding(.top, tightTop ? Theme.Space.xxs : Theme.Space.sm)
        }
    }

    /// An invisible sentinel above the first message. Scrolling it into view
    /// pages older messages in via the "before" cursor, then jumps back to
    /// the message that used to be first so the view doesn't lurch — the
    /// newly loaded history appears above without moving what's on screen.
    private func topAnchor(proxy: ScrollViewProxy) -> some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                guard didCompleteInitialScroll,
                      vm.hasMoreOlder, !vm.isLoadingOlder, !messages.isEmpty else { return }
                let anchorId = messages.first?.id
                Task {
                    await vm.loadOlder(appState: appState)
                    guard let anchorId else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { proxy.scrollTo(anchorId, anchor: .top) }
                    }
                }
            }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        formatter.dateFormat = sameYear ? "MMMM d" : "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.sm) {
            TextField("Message", text: $vm.draft, axis: .vertical)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.Color.bgGrouped, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))

            Button {
                // AppState.sendMessage fires Haptics.tap() + SoundEffects.play(.message)
                // itself once the optimistic bubble is appended; doing it again here
                // would double the buzz on every send.
                vm.send(appState: appState)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Theme.Color.hairline : Theme.Color.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Space.md)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let maxWidth: CGFloat
    let isMine: Bool
    let onRetry: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.message.body)
                    .font(Theme.Font.body)
                    .foregroundStyle(isMine ? Theme.Color.onAccent : Theme.Color.text)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium)
                            .fill(isMine ? Theme.Color.bubbleMine : Theme.Color.bubbleTheirs)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium)
                            .stroke(isMine ? Color.clear : Theme.Color.hairline,
                                   lineWidth: Theme.hairlineWidth)
                    )
                    // Long-press only the bubble itself, not the retry link
                    // below it, so retrying a failed send still works.
                    .onLongPressGesture(minimumDuration: 0.3, perform: onLongPress)
                if message.status == .failed {
                    Button("Failed \u{00b7} Retry", action: onRetry)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.warm)
                } else if message.status == .pending {
                    Text("Sending\u{2026}")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .frame(maxWidth: maxWidth, alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}

/// "This match ended." (SPEC §2.3: "match_removed while open → dismiss with
/// a toast"). Auto-dismisses the chat a couple seconds after showing itself;
/// tapping it dismisses right away.
private struct MatchEndedToast: View {
    let onTap: () -> Void
    var body: some View {
        Text("This match ended.")
            .font(Theme.Font.footnote)
            .foregroundStyle(Theme.Color.onAccent)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Color.accent, in: Capsule())
            .onTapGesture(perform: onTap)
    }
}
