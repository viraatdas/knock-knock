import SwiftUI

/// Tap a contact -> their name, a tap-to-reach action, and separate Audio/Video
/// call actions. Tap starts a call-style ring with tap presentation.
struct ContactSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let contact: Contact
    /// Invoked when the user taps "Invite to Slide". The presenter handles the
    /// actual SMS / share-sheet composer.
    var onInvite: () -> Void = {}

    @State private var isVideo = true

    private var user: User? { contact.slideUser }

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

                ContactTapButton { tap() }
                    .padding(.top, Theme.Space.lg)

                Text("Tap until they pick up.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)

                PrimaryButton(title: isVideo ? "Start video call" : "Start call") {
                    start(video: isVideo)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)
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
        guard let user else { return }
        appState.startCall(to: user, video: video)
        dismiss()
    }

    private func tap() {
        guard let user else { return }
        appState.startKnockCall(to: user, video: isVideo)
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
    @State private var dragX: CGFloat?
    @State private var previewIsVideo: Bool?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let selectedIsVideo = previewIsVideo ?? isVideo
            let thumbWidth = max(0, width / 2 - 8)
            let thumbX = dragX ?? (selectedIsVideo ? width * 0.75 : width * 0.25)

            ZStack {
                Capsule().fill(Theme.Color.bgGrouped)
                Capsule()
                    .fill(Theme.Color.text)
                    .frame(width: thumbWidth, height: height - 8)
                    .position(x: min(max(thumbX, width * 0.25), width * 0.75),
                              y: height / 2)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isVideo)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: dragX)

                HStack(spacing: 0) {
                    segment("Audio", icon: "phone", selected: !selectedIsVideo) { set(false) }
                    segment("Video", icon: "video", selected: selectedIsVideo) { set(true) }
                }
            }
            .gesture(slideGesture(width: width))
        }
        .frame(height: 48)
    }

    private func set(_ v: Bool) {
        guard v != isVideo else { return }
        Haptics.select()
        isVideo = v
    }

    private func slideGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(max(value.location.x, width * 0.25), width * 0.75)
                let v = value.location.x >= width / 2
                dragX = x
                if previewIsVideo != v {
                    previewIsVideo = v
                    Haptics.select()
                }
            }
            .onEnded { value in
                let v = value.location.x >= width / 2
                isVideo = v
                dragX = nil
                previewIsVideo = nil
            }
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

/// Large tap target that starts a call-style invitation.
private struct ContactTapButton: View {
    let action: () -> Void
    @State private var ripple = false

    var body: some View {
        Button {
            action()
            ripple = false
            withAnimation(.easeOut(duration: 0.5)) { ripple = true }
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
                Text("tap")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .accessibilityLabel("Tap")
        .accessibilityHint("Starts a tap call to this person")
        .buttonStyle(PressableButtonStyle())
    }
}
