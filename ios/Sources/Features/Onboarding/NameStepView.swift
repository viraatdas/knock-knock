import SwiftUI
import PhotosUI

struct NameStepView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("What's your name?")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("This is how friends will see you.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.xxl)

            // Optional avatar.
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let avatarData, let ui = UIImage(data: avatarData) {
                            Image(uiImage: ui)
                                .resizable().scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                        } else {
                            ZStack {
                                Circle().fill(Theme.Color.bgGrouped)
                                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                                Image(systemName: "camera")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            .frame(width: 88, height: 88)
                        }
                    }
                }
                Spacer()
            }

            UnderlineField(placeholder: "Name", text: $name,
                           contentType: .name,
                           autocapitalization: .words,
                           submitLabel: .done) { save() }
                .focused($focused)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            Spacer()

            PrimaryButton(title: "Continue",
                          isLoading: isSaving,
                          isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                save()
            }
            .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onAppear { focused = true }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    avatarData = data
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isSaving = true
        Task {
            var avatarUrl: String?
            if let avatarData {
                avatarUrl = try? await appState.api.uploadAvatar(avatarData)
            }
            do {
                let user = try await appState.api.updateMe(displayName: trimmed, avatarUrl: avatarUrl)
                await MainActor.run {
                    isSaving = false
                    appState.didCompleteName(user: user)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    if Config.useMockData {
                        var u = appState.currentUser ?? MockData.me
                        u.displayName = trimmed
                        appState.didCompleteName(user: u)
                    } else {
                        errorMessage = (error as? APIError)?.errorDescription ?? "Couldn't save. Try again."
                    }
                }
            }
        }
    }
}
