import Foundation

/// The sizes the screens ask for. Unsplash's `small` is 400px wide and `regular` 1080px: close to what a
/// grid column (~550px at 3x) and the full-screen view (~1200px) need, so the limits are a cap, not a resize.
extension Photo {
    var thumbnailRequest: ImageRequest {
        ImageRequest(url: smallURL, maxPixelSize: 600)
    }

    var fullScreenRequest: ImageRequest {
        ImageRequest(url: regularURL, maxPixelSize: 1200)
    }
}
