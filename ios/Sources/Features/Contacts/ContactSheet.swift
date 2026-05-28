import SwiftUI

struct ContactSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let contact: Contact

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer().frame(height: Theme.Space.lg)

            AvatarCircle(name: contact.displayName, size: 96)

            VStack(spacing: Theme.Space.xs) {
                Text(contact.displayName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.text)
                Text(formatted(contact.phone))
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                if !contact.onSlide {
                    Text("Not on Slide yet")
                        .uppercaseLabel()
                        .padding(.top, Theme.Space.xs)
                }
            }

            if contact.onSlide {
                // Two big thin-outlined circular actions.
                HStack(spacing: Theme.Space.xxl) {
                    VStack(spacing: Theme.Space.xs) {
                        CircleActionButton(systemImage: "phone", diameter: 72) {
                            start(video: false)
                        }
                        Text("Audio").uppercaseLabel()
                    }
                    VStack(spacing: Theme.Space.xs) {
                        CircleActionButton(systemImage: "video", diameter: 72) {
                            start(video: true)
                        }
                        Text("Video").uppercaseLabel()
                    }
                }
                .padding(.top, Theme.Space.md)
            } else {
                PrimaryButton(title: "Invite to Slide") {
                    let text = "Let's talk on Slide."
                    if let url = URL(string: "sms:\(contact.phone)&body=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.bg)
    }

    private func start(video: Bool) {
        appState.startCall(to: MockData.userForContact(contact), video: video)
        dismiss()
    }

    private func formatted(_ phone: String) -> String {
        phone.isEmpty ? "" : phone
    }
}
