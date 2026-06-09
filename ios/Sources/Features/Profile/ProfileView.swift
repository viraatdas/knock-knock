import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showEdit = false
    @State private var showKnockSound = false
    @State private var showPrivacy = false
    @State private var showAbout = false

    private var user: User { appState.currentUser ?? MockData.me }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Large avatar + name.
                VStack(spacing: Theme.Space.md) {
                    AvatarCircle(name: user.displayName,
                                 imageURL: user.avatarUrl.flatMap(URL.init(string:)),
                                 size: 104)
                        .padding(.top, Theme.Space.xl)
                    VStack(spacing: Theme.Space.xxs) {
                        Text(user.displayName ?? "Add your name")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Color.text)
                        Text(user.phone)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Text("Edit")
                            .font(Theme.Font.buttonSmall)
                            .foregroundStyle(Theme.Color.text)
                            .padding(.horizontal, Theme.Space.lg)
                            .padding(.vertical, Theme.Space.xs)
                            .overlay(
                                Capsule().stroke(Theme.Color.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Space.xl)

                // Minimal settings list with hairline dividers.
                VStack(spacing: 0) {
                    HairlineDivider()
                    SettingsRow(icon: "bell", title: "Notifications") { openNotificationSettings() }
                    HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                    SettingsRow(icon: "hand.tap", title: "Knock sound") { showKnockSound = true }
                    HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                    SettingsRow(icon: "lock", title: "Privacy") { showPrivacy = true }
                    HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                    SettingsRow(icon: "info.circle", title: "About") { showAbout = true }
                    HairlineDivider()
                }
                .padding(.top, Theme.Space.md)

                // Log out in subtle red.
                Button {
                    appState.logout()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 18, weight: .light))
                        Text("Log out")
                            .font(Theme.Font.body)
                        Spacer()
                    }
                    .foregroundStyle(Theme.Color.danger)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, Theme.Space.xl)

                Text("Knock Knock \(Config.appVersion)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, Theme.Space.lg)
            }
        }
        .background(Theme.Color.bg)
        .sheet(isPresented: $showEdit) {
            EditProfileSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showKnockSound) {
            KnockSoundSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
                .presentationDetents([.medium, .large])
        }
    }

    /// Deep-link straight to this app's notification settings.
    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Knock sound

/// Pick what knocks sound (and feel) like. Tapping a row previews it live.
private struct KnockSoundSheet: View {
    @State private var selection = KnockSound.current

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Knock sound")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                Text("What your door is made of. Tap one to try it.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.xl)

            VStack(spacing: 0) {
                HairlineDivider()
                ForEach(KnockSound.allCases, id: \.self) { sound in
                    Button {
                        selection = sound
                        KnockSound.current = sound
                        KnockHaptics.shared.knock()   // live preview
                    } label: {
                        HStack {
                            Text(sound.title)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Color.text)
                            Spacer()
                            if selection == sound {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                        .padding(.vertical, Theme.Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    HairlineDivider()
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.bg)
    }
}

// MARK: - Privacy

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Privacy")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.text)
                .padding(.top, Theme.Space.xl)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                privacyPoint(icon: "phone",
                             title: "Your number is your account",
                             detail: "We use your phone number to sign you in and let friends find you. No usernames, no passwords, no email.")
                privacyPoint(icon: "person.2",
                             title: "Contacts stay yours",
                             detail: "Contacts are matched only to show you who's already on Knock Knock. They're never sold or used for ads.")
                privacyPoint(icon: "lock",
                             title: "Calls are encrypted in transit",
                             detail: "Audio and video travel over encrypted WebRTC (DTLS-SRTP). We don't record calls.")
                privacyPoint(icon: "eye.slash",
                             title: "No ads, no tracking",
                             detail: "There are no third-party trackers and we don't track you across other apps.")
            }

            Spacer()

            PrimaryButton(title: "Manage permissions in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.bg)
    }

    private func privacyPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.text)
                Text(detail)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - About

private struct AboutSheet: View {
    /// The joke plays out line by line, with a knock per line.
    @State private var jokeStep = 0
    private let joke = ["Knock knock.", "Who's there?", "Your people."]

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Wordmark(size: 34)
                .padding(.top, Theme.Space.xxl)

            Text("Video calls you'll actually want to make.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Space.xs) {
                ForEach(0..<jokeStep, id: \.self) { i in
                    Text(joke[i])
                        .font(i == 2 ? Theme.Font.title3 : Theme.Font.callout)
                        .foregroundStyle(i == 2 ? Theme.Color.accent : Theme.Color.text)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(minHeight: 88)
            .padding(.top, Theme.Space.md)

            Spacer()

            // Open source: the whole app lives on GitHub — stars and issues welcome.
            Button {
                if let url = URL(string: "https://github.com/viraatdas/knock-knock") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 13, weight: .medium))
                    Text("Knock Knock is open source")
                        .font(Theme.Font.buttonSmall)
                }
                .foregroundStyle(Theme.Color.text)
                .padding(.horizontal, Theme.Space.md)
                .frame(height: 40)
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                if let url = URL(string: "https://github.com/viraatdas/knock-knock/issues/new") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Found a bug? File an issue →")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .underline()
            }
            .buttonStyle(PressableButtonStyle())

            VStack(spacing: Theme.Space.xxs) {
                Text("Knock Knock \(Config.appVersion)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("© 2026 Viraat Das")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.bg)
        .onAppear { playJoke() }
    }

    private func playJoke() {
        jokeStep = 0
        Task { @MainActor in
            for step in 1...joke.count {
                try? await Task.sleep(nanoseconds: step == 1 ? 400_000_000 : 900_000_000)
                if step == 1 || step == 3 { KnockHaptics.shared.knock() }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { jokeStep = step }
            }
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Color.text)
                    .frame(width: 24)
                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.xl) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let avatarData, let ui = UIImage(data: avatarData) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                    } else {
                        AvatarCircle(name: name.isEmpty ? appState.currentUser?.displayName : name,
                                     size: 96)
                    }
                }
                .padding(.top, Theme.Space.lg)

                UnderlineField(placeholder: "Name", text: $name,
                               contentType: .name, autocapitalization: .words)
                    .padding(.horizontal, Theme.Space.lg)

                Spacer()

                PrimaryButton(title: "Save", isLoading: isSaving,
                              isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    save()
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
            }
            .background(Theme.Color.bg)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Color.text)
                }
            }
            .onAppear { name = appState.currentUser?.displayName ?? "" }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        isSaving = true
        Task {
            var avatarUrl: String?
            if let avatarData {
                avatarUrl = try? await appState.api.uploadAvatar(avatarData)
            }
            do {
                let user = try await appState.api.updateMe(displayName: trimmed, avatarUrl: avatarUrl)
                await MainActor.run {
                    appState.currentUser = user
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    if Config.useMockData {
                        var u = appState.currentUser ?? MockData.me
                        u.displayName = trimmed
                        appState.currentUser = u
                    }
                    isSaving = false
                    dismiss()
                }
            }
        }
    }
}
