import SwiftUI

/// Tap a contact → their name, an Audio/Video slider, and a knock pad. You pick
/// the mode, then *knock* to place the call — knocking on their door is how you
/// reach them. Replaces the old three separate Knock / Audio / Video buttons.
struct ContactSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let contact: Contact
    /// Invoked when the user taps "Invite to Slide". The presenter handles the
    /// actual SMS / share-sheet composer.
    var onInvite: () -> Void = {}

    @State private var isVideo = true

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
                ModeSlider(isVideo: $isVideo)
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.top, Theme.Space.sm)

                KnockToCall { start(video: isVideo) }
                    .padding(.top, Theme.Space.lg)

                Text(isVideo ? "Knock to start a video call" : "Knock to start a call")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
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
    }

    private func start(video: Bool) {
        appState.startCall(to: MockData.userForContact(contact), video: video)
        dismiss()
    }

    private func formatted(_ phone: String) -> String {
        phone.isEmpty ? "" : phone
    }
}

/// Sliding Audio ↔ Video selector. The dark capsule glides under the active
/// segment; tapping either side switches (with a selection haptic).
private struct ModeSlider: View {
    @Binding var isVideo: Bool

    var body: some View {
        ZStack {
            Capsule().fill(Theme.Color.bgGrouped)
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.Color.text)
                    .frame(width: geo.size.width / 2 - 8, height: geo.size.height - 8)
                    .position(x: isVideo ? geo.size.width * 0.75 : geo.size.width * 0.25,
                              y: geo.size.height / 2)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isVideo)
            }
            HStack(spacing: 0) {
                segment("Audio", icon: "phone", selected: !isVideo) { set(false) }
                segment("Video", icon: "video", selected: isVideo) { set(true) }
            }
        }
        .frame(height: 48)
    }

    private func set(_ v: Bool) {
        guard v != isVideo else { return }
        Haptics.select()
        isVideo = v
    }

    private func segment(_ title: String, icon: String, selected: Bool,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(Theme.Font.callout)
            }
            .foregroundStyle(selected ? Theme.Color.bg : Theme.Color.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The knock pad: a large ✊ target that knocks (ripple + haptic) and then places
/// the call. Knocking on their door is the call-initiation gesture.
private struct KnockToCall: View {
    let action: () -> Void
    @State private var ripple = false

    var body: some View {
        Button {
            Haptics.strong()
            withAnimation(.easeOut(duration: 0.5)) { ripple = true }
            // Let the knock register, then ring them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { action() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.Color.text.opacity(0.3), lineWidth: 2)
                    .frame(width: 140, height: 140)
                    .scaleEffect(ripple ? 1.6 : 1)
                    .opacity(ripple ? 0 : 1)
                Circle()
                    .fill(Theme.Color.bg)
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
                    .frame(width: 140, height: 140)
                Text("✊").font(.system(size: 58))
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
