import Foundation

/// What the loader is asked for, and the key for its caches and de-duplication: the same URL at two
/// sizes is two different decoded images.
nonisolated struct ImageRequest: Hashable, Sendable {
    let url: URL
    /// The longest edge, in pixels, the decoded image is downsampled to. Never upscales.
    let maxPixelSize: Int
}
