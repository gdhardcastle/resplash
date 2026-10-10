import UIKit

/// Quietly loads images ahead of need. Each call replaces the previous window: requests no longer in it
/// are cancelled, so scrolling fast doesn't leave a queue of downloads nobody will see.
///
/// View models depend on this and nothing else of the image pipeline, so what to prefetch is decided
/// there, not in a view, and tests can record the requests.
nonisolated protocol ImagePrefetching: Sendable {
    func prefetch(_ requests: [ImageRequest])
}

/// What a view needs to draw a remote image. Declared here, not by the pipeline, so the views depend on
/// an abstraction and `ImageData` is only one way to provide it.
nonisolated protocol ImageLoading: ImagePrefetching {
    /// The decoded image if it is already in memory. Synchronous, so a view can draw it on its first frame.
    /// `countingAsHit` is for a view asking because it needs the image, not for one redrawing what it has:
    /// `body` can run many times for a single request.
    func cachedImage(for request: ImageRequest, countingAsHit: Bool) -> UIImage?
    func image(for request: ImageRequest) async throws -> UIImage
}

extension ImageLoading {
    nonisolated func cachedImage(for request: ImageRequest) -> UIImage? {
        cachedImage(for: request, countingAsHit: false)
    }
}
