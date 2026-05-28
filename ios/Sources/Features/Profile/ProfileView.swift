import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showEdit = false

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
                    SettingsRow(icon: "bell", title: "Notifications") {}
                    HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                    SettingsRow(icon: "lock", title: "Privacy") {}
                    HairlineDivider(leadingInset: Theme.Space.lg + 24 + Theme.Space.md)
                    SettingsRow(icon: "info.circle", title: "About") {}
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

                Text("Slide \(Config.appVersion)")
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
