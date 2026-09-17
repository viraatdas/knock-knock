import SwiftUI

/// Safety actions for a match/partner (SPEC §2.3 ChatView toolbar menu:
/// Unmatch, Report, Block; also presented from DecisionView right after any
/// date, matched or not — abuse during the date itself must be reportable
/// even when the two never match). Init: `SafetySheet(partner:matchId:
/// dateId:onHandled:)` — `matchId` nil hides Unmatch; `onHandled` fires
/// after Unmatch/Block so a presenting view that wants to pop (ChatView) can.
/// Every action confirms before it runs; Report also collects an optional
/// details note before it submits.
struct SafetySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let partner: PublicProfile
    var matchId: String?
    var dateId: String?
    var onHandled: () -> Void = {}

    @State private var showReportReasons = false
    @State private var confirmUnmatch = false
    @State private var confirmBlock = false
    @State private var reportReason: ReportReason?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HairlineDivider()
                if matchId != nil {
                    row("Unmatch", tint: Theme.Color.warm) { confirmUnmatch = true }
                    HairlineDivider()
                }
                row("Report \(partner.displayName)", tint: Theme.Color.text) {
                    showReportReasons = true
                }
                HairlineDivider()
                row("Block \(partner.displayName)", tint: Theme.Color.warm) { confirmBlock = true }
                HairlineDivider()
                Spacer()
            }
            .background(Theme.Color.bg)
            .navigationTitle("Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Unmatch with \(partner.displayName)?", isPresented: $confirmUnmatch,
                                titleVisibility: .visible) {
                Button("Unmatch", role: .destructive) {
                    guard let matchId else { return }
                    Task {
                        await appState.unmatch(matchId: matchId)
                        onHandled()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll both lose this chat. This can't be undone.")
            }
            .confirmationDialog("Block \(partner.displayName)?", isPresented: $confirmBlock,
                                titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Task {
                        await appState.block(userId: partner.id)
                        onHandled()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They won't be able to see or match with you again. This ends any match you have now.")
            }
            .confirmationDialog("Report \(partner.displayName)", isPresented: $showReportReasons) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.label) { reportReason = reason }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We'll look into it. This won't tell them you reported them.")
            }
            .sheet(item: $reportReason) { reason in
                ReportDetailsView(reasonLabel: reason.label) { details in
                    Task {
                        await appState.report(userId: partner.id, reason: reason, details: details,
                                              dateId: dateId, matchId: matchId)
                    }
                }
            }
        }
    }

    private func row(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.Font.body).foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Second step of Report: an optional note, then a final confirm ("Submit
/// report") so reporting is never a single accidental tap.
private struct ReportDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let reasonLabel: String
    let onSubmit: (String) -> Void

    @State private var details = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(reasonLabel)
                    .font(Theme.Font.title3)
                    .foregroundStyle(Theme.Color.text)
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Text("Anything else? Optional.").uppercaseLabel()
                        Spacer()
                        Text("\(details.count)/1000")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    TextField("What happened", text: $details, axis: .vertical)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(4...8)
                        .onChange(of: details) { _, v in
                            if v.count > 1000 { details = String(v.prefix(1000)) }
                        }
                }
                Spacer()
                PrimaryButton(title: "Submit report") {
                    onSubmit(details.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .padding(Theme.Space.lg)
            .background(Theme.Color.bg)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
