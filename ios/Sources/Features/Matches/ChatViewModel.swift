import Foundation
import SwiftUI

/// Thin per-chat helper around `AppState`'s message store (the real source
/// of truth — see `AppState.messagesByMatch`), so `ChatView` doesn't poke
/// AppState internals directly. Init: `ChatViewModel(matchId: String)`.
@MainActor
final class ChatViewModel: ObservableObject {
    let matchId: String
    @Published var draft: String = ""
    @Published var isLoadingOlder = false
    /// Starts `true` only as a placeholder until `onAppear` seeds the real
    /// value from `AppState.hasMoreOlderByMatch` (itself the server's
    /// `MessagesPage.hasMore`). Re-opening a chat whose history was already
    /// fully loaded — and, per SPEC's five-minute-date/short-conversation
    /// shape, usually short enough to have exhausted `hasMore` already —
    /// must not re-arm the "there's more to page in" flag, or the top
    /// sentinel fires a pointless `loadOlder` on first appear and its
    /// completion later yanks the scroll position away from the bottom.
    @Published var hasMoreOlder = true

    init(matchId: String) {
        self.matchId = matchId
    }

    func onAppear(appState: AppState) async {
        appState.setActiveChatMatchId(matchId)
        await appState.loadMessages(matchId: matchId)
        hasMoreOlder = appState.hasMoreOlderByMatch[matchId] ?? true
        await appState.markRead(matchId: matchId)
    }

    func onDisappear(appState: AppState) {
        if appState.activeChatMatchId == matchId {
            appState.setActiveChatMatchId(nil)
        }
    }

    /// Pages older messages in when the user scrolls to the top. A failed
    /// request (nil) leaves `hasMoreOlder` as-is so the next scroll-to-top
    /// retries, instead of a network hiccup permanently reading as "reached
    /// the start of history".
    func loadOlder(appState: AppState) async {
        guard !isLoadingOlder, hasMoreOlder else { return }
        isLoadingOlder = true
        if let hasMore = await appState.loadOlderMessages(matchId: matchId) {
            hasMoreOlder = hasMore
        }
        isLoadingOlder = false
    }

    func send(appState: AppState) {
        let body = draft
        draft = ""
        Task { await appState.sendMessage(matchId: matchId, body: body) }
    }
}
