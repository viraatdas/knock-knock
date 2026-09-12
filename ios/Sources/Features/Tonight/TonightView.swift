import SwiftUI
import UIKit
import UserNotifications

/// Tonight tab (SPEC §2.3 "Tonight tab"). Init: `TonightView()`. Reads
/// `AppState.sessionWindow`/`AppState.sessionClock` (kept fresh by AppState's
/// own 60s poll loop + on-appear/foreground refreshes) and
/// `AppState.datesToday`. The primary action, "Start a date", calls
/// `AppState.startLookingForDate()`; a `.waiting`/`.inDate`/etc DateFlow then
/// presents itself as a fullScreenCover from RootView automatically.
/// `profile_incomplete`/`location_required` from `/lobby/join` are already
/// routed by `AppState.handleLobbyError` (flips `phase` to `.profileSetup`),
/// so this view doesn't need to special-case them.
struct TonightView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        // TimelineView redraws once a second so the countdown text stays live
        // without this view owning its own Timer or observing SessionClock.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            // GeometryReader wraps (not sits inside) the ScrollView so `geo`
            // reports the actual space available above the tab bar — the
            // safe area the ScrollView itself respects — rather than the
            // raw screen height. Sizing the content to at least that with
            // `minHeight` lets the two Spacers below distribute the extra
            // room instead of collapsing everything to the top third with a
            // bare gap underneath (SPEC §4 names this tab as App Store
            // screenshot material); using the full raw screen height here
            // instead pushed `nags` low enough to render behind the floating
            // tab bar's glass material.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: Theme.Space.xl) {
                        Wordmark(size: 34).padding(.top, Theme.Space.xxl)

                        Spacer(minLength: Theme.Space.xl)

                        if let window = appState.sessionWindow {
                            if window.isOpen {
                                openContent(window)
                            } else {
                                closedContent(window)
                            }
                        } else {
                            ProgressView().tint(Theme.Color.accent).padding(.top, Theme.Space.xxl)
                        }

                        Spacer(minLength: Theme.Space.xl)

                        nags
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.xxl)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
            }
        }
        .background(Theme.Color.bg)
        .task {
            await appState.refreshSession()
            await appState.refreshDatesToday()
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
    }

    private func openContent(_ window: SessionWindow) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Doors are open")
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Color.text)
            Text(minutesLeftLabel(to: window.closesAt))
                .font(Theme.Font.displayLight(48))
                .foregroundStyle(Theme.Color.text)
            PrimaryButton(title: "Start a date") {
                Task { await appState.startLookingForDate() }
            }
        }
        .padding(.top, Theme.Space.xl)
    }

    private func closedContent(_ window: SessionWindow) -> some View {
        VStack(spacing: Theme.Space.md) {
            Text("Doors open in \(appState.sessionClock.countdown(to: window.opensAt))")
                .font(Theme.Font.displayLight(40))
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
            Text("Every day, 7 to 8 PM Pacific")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)

            if !appState.datesToday.isEmpty {
                let matched = appState.datesToday.filter(\.matched).count
                Text("\(appState.datesToday.count) date\(appState.datesToday.count == 1 ? "" : "s") tonight \u{00b7} \(matched) match\(matched == 1 ? "" : "es")")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, Theme.Space.md)
            }
        }
        .padding(.top, Theme.Space.xl)
    }

    /// "41 minutes left" style for the open state (whole minutes, spelled out,
    /// per SPEC §2.3 — distinct from the closed state's abbreviated "2h 14m").
    private func minutesLeftLabel(to target: Date) -> String {
        let remaining = appState.sessionClock.secondsRemaining(to: target)
        let totalMinutes = Int(remaining) / 60
        if totalMinutes < 1 { return "Less than a minute left" }
        return "\(totalMinutes) minute\(totalMinutes == 1 ? "" : "s") left"
    }

    @ViewBuilder
    private var nags: some View {
        VStack(spacing: Theme.Space.sm) {
            if appState.me?.hasLocation == false {
                NagRow(title: "Location is off. Turn it on to find dates nearby.",
                      action: locationActionLabel) {
                    Task { await handleLocationNagTap() }
                }
            }
            if notificationStatus == .denied || notificationStatus == .notDetermined {
                NagRow(title: "Notifications are off. Turn them on so you don't miss doors opening.",
                      action: notificationActionLabel) {
                    Task { await handleNotificationNagTap() }
                }
            }
        }
        .padding(.top, Theme.Space.lg)
    }

    // MARK: - Location nag

    private var locationActionLabel: String {
        switch appState.locationService.authorizationStatus {
        case .denied, .restricted: return "Open settings"
        default: return "Turn on"
        }
    }

    private func handleLocationNagTap() async {
        switch appState.locationService.authorizationStatus {
        case .denied, .restricted:
            openSystemSettings()
        case .notDetermined:
            appState.locationService.requestWhenInUseAuthorization()
        default:
            await appState.submitLocation()
        }
    }

    // MARK: - Notifications nag

    private var notificationActionLabel: String {
        notificationStatus == .denied ? "Open settings" : "Turn on"
    }

    private func handleNotificationNagTap() async {
        if notificationStatus == .denied {
            openSystemSettings()
            return
        }
        let granted = await NotificationService.requestAuthorization()
        if granted {
            NotificationService.registerForRemoteNotifications()
            NotificationService.scheduleDoorsOpenReminder()
        }
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.authorizationStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct NagRow: View {
    let title: String
    let action: String
    let onTap: () -> Void
    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Button(action: onTap) {
                Text(action)
                    .font(Theme.Font.buttonSmall)
                    .foregroundStyle(Theme.Color.text)
            }
        }
        .padding(Theme.Space.sm)
        .background(Theme.Color.bgGrouped, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}
