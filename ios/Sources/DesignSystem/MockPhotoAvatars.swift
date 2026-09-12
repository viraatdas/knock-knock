#if DEBUG
import UIKit
import Foundation

/// DEBUG-only seam for realistic screenshots: `-mockPhotosDir <absolute dir>`
/// points at a folder of face JPEGs (see `ios/tools/faces/`) that stand in
/// for MockData's profiles and the local self-view, so `-scene` screenshots
/// show real-looking photos instead of initials/placeholders. Same idea as
/// `-scene` itself — a launch-argument seam that only exists in DEBUG builds
/// (see `Array.sceneArgument`) — and is compiled out of Release entirely.
///
/// The faces are AI-generated, not real people.
enum MockPhotoAvatars {
    /// nil unless `-mockPhotosDir <dir>` was passed at launch.
    static let directory: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-mockPhotosDir"), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }()

    /// MockData's fixed profile ids -> a face file (without extension) in
    /// `directory`. "u_me" covers both the Profile tab's own avatar and the
    /// date screen's local self-view thumbnail.
    private static let fileByUserId: [String: String] = [
        "u_me": "self",
        "u_maya": "maya",
        "u_priya": "priya",
        "u_grace": "grace",
        "u_daniel": "ben",
        "u_marcus": "leo",
        "u_sam": "isla"
    ]

    private static var cache: [String: UIImage] = [:]

    /// The mapped face image for `userId`, or nil if no `-mockPhotosDir` was
    /// passed, the id isn't one of MockData's fixed profiles, or the file
    /// isn't there.
    static func image(for userId: String) -> UIImage? {
        guard let directory else { return nil }
        if let cached = cache[userId] { return cached }
        guard let file = fileByUserId[userId] else { return nil }
        let path = (directory as NSString).appendingPathComponent("\(file).jpg")
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache[userId] = image
        return image
    }
}
#endif
