import SwiftUI
import UserNotifications
import CoreLocation
import AVFoundation

/// Profile tab (SPEC §2.3 "Profile tab"). Reads `AppState.me`. The primary
/// action wired here is "Log out" (`AppState.logout()`); "Edit profile" opens
/// `EditProfileView` and "Delete account" confirms then calls
/// `AppState.deleteAccount()`.
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var locationService = LocationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showEdit = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined

    private var me: MeView { appState.me ?? MockData.me }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: Theme.Space.md) {
                        PhotoAvatar(profile: profileForAvatar, size: 104)
                            .padding(.top, Theme.Space.xl)
                        VStack(spacing: Theme.Space.xxs) {
                            HStack(spacing: Theme.Space.xs) {
                                Text(me.displayName ?? "Add your name")
                                    .font(Theme.Font.title)
                                    .foregroundStyle(Theme.Color.text)
                                if let age = me.age {
                                    Text("\(age)")
                                        .font(Theme.Font.title2)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                }
                            }
                            if !me.bio.isEmpty {
                                Text(me.bio)
                                    .font(Theme.Font.callout)
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Theme.Space.xl)
                            }
                        }
                        Button { showEdit = true } label: {
                            Text("Edit profile")
                                .font(Theme.Font.buttonSmall)
                                .foregroundStyle(Theme.Color.text)
                                .padding(.horizontal, Theme.Space.lg)
                                .padding(.vertical, Theme.Space.xs)
                                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Space.xl)

                    VStack(spacing: 0) {
                        HairlineDivider()
                        SettingsRow(icon: "bell", title: "Notifications", trailing: notificationStatusLabel) {
                            openSettings()
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "location", title: "Location", trailing: locationStatusLabel) {
                            openSettings()
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "video", title: "Camera", trailing: cameraStatusLabel) {
                            openSettings()
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "mic", title: "Microphone", trailing: microphoneStatusLabel) {
                            openSettings()
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "lock", title: "Privacy policy") {
                            open("https://slide.viraat.dev/privacy")
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "doc.text", title: "Terms") {
                            open("https://slide.viraat.dev/terms")
                        }
                        HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                        SettingsRow(icon: "info.circle", title: "About", trailing: Config.appVersion) {
                            showAbout = true
                        }
                        HairlineDivider()
                    }
                    .padding(.top, Theme.Space.md)
                    .task {
                        await refreshNotificationStatus()
                        refreshMediaStatus()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        // Camera/mic (like location) can only change from the
                        // system Settings screen, so re-read on every return
                        // to the foreground — not just the initial `.task`.
                        if phase == .active {
                            Task { await refreshNotificationStatus() }
                            refreshMediaStatus()
                        }
                    }

                    Button { appState.logout() } label: {
                        HStack {
                            Image(systemName: "arrow.right.square")
                                .font(.system(size: 18, weight: .light))
                            Text("Log out")
                                .font(Theme.Font.body)
                            Spacer()
                        }
                        .foregroundStyle(Theme.Color.warm)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.md)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.top, Theme.Space.xl)

                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Text("Delete account")
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.top, Theme.Space.md)

                    Text("Knock Knock \(Config.appVersion)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .padding(.top, Theme.Space.lg)
                        // Extra clearance so this doesn't sit under the
                        // floating tab bar at the very bottom of the scroll.
                        .padding(.bottom, Theme.Space.xxxl)
                }
            }
            .background(Theme.Color.bg)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showEdit) {
            EditProfileView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await appState.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your profile, matches and messages. It can't be undone.")
        }
    }

    private var profileForAvatar: PublicProfile {
        PublicProfile(id: me.id, displayName: me.displayName ?? "", age: me.age,
                      gender: me.gender, bio: me.bio, hasPhoto: me.hasPhoto,
                      photoUrl: me.photoUrl, distanceMiles: nil)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.authorizationStatus()
    }

    /// Camera/mic authorization is a plain synchronous read (unlike
    /// notifications), so this needs no `await`.
    private func refreshMediaStatus() {
        cameraStatus = MediaPermissions.cameraStatus
        microphoneStatus = MediaPermissions.microphoneStatus
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        default: return "Not set"
        }
    }

    private var locationStatusLabel: String {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return "On"
        case .denied, .restricted: return "Off"
        default: return "Not set"
        }
    }

    private var cameraStatusLabel: String { mediaStatusLabel(cameraStatus) }
    private var microphoneStatusLabel: String { mediaStatusLabel(microphoneStatus) }

    private func mediaStatusLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "On"
        case .denied, .restricted: return "Off"
        default: return "Not set"
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    var showsChevron: Bool = true
    /// `nil` renders a static, non-interactive row (e.g. "About").
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(PressableButtonStyle())
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.Color.text)
                .frame(width: 24)
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .contentShape(Rectangle())
    }
}
