import SwiftUI
import UIKit

// MARK: - Wordmark

/// The "Slide" wordmark — always thin (300), tracking +0.04em.
struct Wordmark: View {
    var size: CGFloat = 24
    var body: some View {
        Text("Knock Knock").wordmarkStyle(size)
    }
}

// MARK: - Hairline divider (1px instead of cards-with-shadows)

struct HairlineDivider: View {
    var leadingInset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Theme.Color.hairline)
            .frame(height: Theme.hairlineWidth)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Primary button (filled black, full width)

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Theme.Color.onAccent)
                } else {
                    Text(title)
                        .font(Theme.Font.button)
                }
            }
            .foregroundStyle(Theme.Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Color.accent)
            )
            .opacity(isEnabled && !isLoading ? 1 : 0.35)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Secondary / text button

struct TextLinkButton: View {
    let title: String
    var color: Color = Theme.Color.text
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.buttonSmall)
                .foregroundStyle(color)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Pressable style — subtle, fast feedback

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
            // Light haptic the moment the press registers — app-wide tap feel.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

// MARK: - Underline text field (thin underline, big digits optional)

struct UnderlineField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var bigDigits: Bool = false
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            TextField(placeholder, text: $text)
                .font(bigDigits ? Theme.Font.bigDigits : Theme.Font.body)
                .foregroundStyle(Theme.Color.text)
                .tint(Theme.Color.accent)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(keyboard == .phonePad || keyboard == .numberPad)
                .submitLabel(submitLabel)
                .focused($focused)
                .onSubmit { onSubmit?() }

            Rectangle()
                .fill(focused ? Theme.Color.text : Theme.Color.hairline)
                .frame(height: Theme.hairlineWidth)
                .animation(Theme.Motion.standard, value: focused)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Search field (thin underline, pinned)

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField(placeholder, text: $text)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                    .tint(Theme.Color.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Color.hairline)
                    }
                }
            }
            Rectangle()
                .fill(focused ? Theme.Color.text : Theme.Color.hairline)
                .frame(height: Theme.hairlineWidth)
                .animation(Theme.Motion.standard, value: focused)
        }
    }
}

// MARK: - Avatar circle (image or initials)

struct AvatarCircle: View {
    let name: String?
    var imageURL: URL? = nil
    var size: CGFloat = 44
    var background: Color = Theme.Color.bgGrouped
    var foreground: Color = Theme.Color.text

    private var initials: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
                .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .regular))
            .foregroundStyle(foreground)
    }
}

// MARK: - Circular thin-outlined action button (call sheet, in-call chrome)

struct CircleActionButton: View {
    let systemImage: String
    var diameter: CGFloat = 64
    var filled: Bool = false
    var tint: Color = Theme.Color.text
    var strokeColor: Color = Theme.Color.hairline
    var background: Color = Theme.Color.bg
    /// Icon color when `filled` — must contrast with `tint` (e.g. dark icon on
    /// a white-filled button over video chrome).
    var filledIconColor: Color = Theme.Color.onAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? tint : background)
                    .overlay(
                        Circle().stroke(filled ? Color.clear : strokeColor,
                                        lineWidth: Theme.hairlineWidth)
                    )
                Image(systemName: systemImage)
                    .font(.system(size: diameter * 0.34, weight: .light))
                    .foregroundStyle(filled ? filledIconColor : tint)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Loading / empty states

struct EmptyStateView: View {
    let message: String
    var systemImage: String? = nil
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.Color.hairline)
            }
            Text(message)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chip (multi-select pill: gender, show-me, etc.)

struct Chip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.buttonSmall)
                .foregroundStyle(isSelected ? Theme.Color.onAccent : Theme.Color.text)
                .padding(.horizontal, Theme.Space.md)
                .frame(minHeight: 44)
                .background(Capsule().fill(isSelected ? Theme.Color.accent : Theme.Color.bg))
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Theme.Color.hairline,
                                     lineWidth: Theme.hairlineWidth)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - CountdownRing (date timer, 5:00 -> 0:00)

struct CountdownRing: View {
    /// 1.0 (just started) -> 0.0 (time's up).
    let progress: Double
    var lineWidth: CGFloat = 4
    var color: Color = Theme.Color.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Color.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.standard, value: progress)
        }
    }
}

// MARK: - PhotoAvatar (bearer-authed photo fetch, in-memory cache, initials fallback)

/// Small in-memory cache for `GET /users/:id/photo` bytes. There is no public
/// photo URL — every fetch needs the bearer token — so PhotoAvatar goes
/// through this instead of AsyncImage.
@MainActor
final class PhotoCache {
    static let shared = PhotoCache()
    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func cached(for userId: String) -> UIImage? { cache[userId] }

    func load(for userId: String) async -> UIImage? {
        if let cached = cache[userId] { return cached }
        if let existing = inFlight[userId] { return await existing.value }
        let task = Task<UIImage?, Never> {
            guard let data = try? await APIClient.shared.photoData(for: userId),
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        inFlight[userId] = task
        let image = await task.value
        inFlight[userId] = nil
        if let image { cache[userId] = image }
        return image
    }
}

/// A date partner's/match's photo, loaded via `PhotoCache`. Falls back to
/// initials immediately (no spinner) while the fetch is in flight.
struct PhotoAvatar: View {
    let profile: PublicProfile?
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Color.bgGrouped)
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: Theme.hairlineWidth))
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .regular))
                    .foregroundStyle(Theme.Color.text)
            }
        }
        .frame(width: size, height: size)
        .task(id: profile?.id) {
            guard let profile else { image = nil; return }
            #if DEBUG
            // Screenshot seam: `-mockPhotosDir` stands in real-looking faces
            // for MockData's fixed profiles, independent of `hasPhoto` (mock
            // profiles are all seeded with `hasPhoto: false`).
            if let mock = MockPhotoAvatars.image(for: profile.id) { image = mock; return }
            #endif
            guard profile.hasPhoto else { image = nil; return }
            image = PhotoCache.shared.cached(for: profile.id)
            if image == nil {
                image = await PhotoCache.shared.load(for: profile.id)
            }
        }
    }

    private var initials: String {
        guard let name = profile?.displayName,
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
}

// MARK: - Image resizing (profile photo upload prep)

extension UIImage {
    /// Downscale to at most `maxDimension` on the long edge and re-encode as
    /// JPEG at `quality`. Used before `PUT /me/photo` (SPEC: "max 1024px JPEG
    /// q0.8"); a no-op re-encode if the image is already small enough.
    func resizedJPEGData(maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else { return jpegData(compressionQuality: quality) }
        let scale = maxDimension / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Top bar with wordmark + trailing action

struct WordmarkBar<Trailing: View>: View {
    var size: CGFloat = 26
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Wordmark(size: size)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
    }
}
