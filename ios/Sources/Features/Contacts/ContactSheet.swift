import SwiftUI

struct ContactSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let contact: Contact
    @State private var showKnockPad = false
    /// Invoked when the user taps "Invite to Slide". The presenter handles the
    /// actual SMS / share-sheet composer.
    var onInvite: () -> Void = {}

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer().frame(height: Theme.Space.lg)

            AvatarCircle(name: contact.displayName,
                         imageURL: contact.avatarUrl.flatMap(URL.init(string:)),
                         size: 96)

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
                // Three big thin-outlined circular actions: Knock, Audio, Video.
                HStack(spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.xs) {
                        KnockCircleButton(diameter: 72) {
                            showKnockPad = true
                        }
                        Text("Knock").uppercaseLabel()
                    }
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
                    dismiss()
                    onInvite()
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.bg)
        .sheet(isPresented: $showKnockPad) {
            KnockPad(user: MockData.userForContact(contact))
                .environmentObject(appState)
        }
    }

    private func start(video: Bool) {
        appState.startCall(to: MockData.userForContact(contact), video: video)
        dismiss()
    }

    private func formatted(_ phone: String) -> String {
        phone.isEmpty ? "" : phone
    }
}

/// A thin-outlined circular ✊ button matching CircleActionButton's footprint,
/// but rendering the knock emoji instead of an SF Symbol.
private struct KnockCircleButton: View {
    var diameter: CGFloat = 72
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.Color.bg)
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
                Text("✊")
                    .font(.system(size: diameter * 0.42))
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(PressableButtonStyle())
    }
}
