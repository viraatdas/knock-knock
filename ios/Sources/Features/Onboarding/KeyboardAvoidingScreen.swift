import SwiftUI

/// Wraps a step's content so it scrolls out from under the keyboard instead
/// of clipping, while keeping the normal onboarding/profile-setup look on a
/// screen with room to spare: a trailing `Spacer()` inside `content` still
/// expands to fill the available height (header up top, primary button
/// pinned near the bottom) when nothing is covering it. Used by the
/// screens in Onboarding/ProfileSetup that show a keyboard (phone, code,
/// name, bio).
struct KeyboardAvoidingScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
