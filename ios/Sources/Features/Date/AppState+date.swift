import Foundation

// MARK: - date hooks
//
// Small AppState additions the Date feature needs that weren't already on
// AppState. Kept in this extension (rather than editing App/AppState.swift)
// per the stage brief.
extension AppState {
    /// The Leave button on DateView, already confirmed. Tags the transition
    /// `endReason: "self_left"` (distinct from the "left" reason a partner's
    /// own `date_ended` uses) so DecisionView never shows "They left early"
    /// for a date you left yourself.
    func leaveDateFromSelf() async {
        guard case .inDate(let date) = dateFlow else { return }
        dateFlow = .deciding(date, endReason: "self_left")
        do { try await api.leaveDate(id: date.id) } catch {}
    }

    /// DateView's 20s connect timeout: the partner's track never showed up.
    /// Ends the date server-side same as any leave, but tags the reason so
    /// Decision shows "They didn't make it" instead of "They left early".
    func handleConnectTimeout(_ date: DateSession) {
        guard case .inDate(let current) = dateFlow, current.id == date.id else { return }
        dateFlow = .deciding(date, endReason: "no_show")
        Task { try? await self.api.leaveDate(id: date.id) }
    }
}
