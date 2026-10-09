import ImageIO
import UIKit

nonisolated enum ImageDownsampler {

    /// Decodes `data` no larger than `maxPixelSize` on its longest edge. ImageIO decodes straight to the
    /// target size instead of decoding the full image and shrinking it, and `ShouldCacheImmediately`
    /// does that work now, on the calling thread, rather than lazily on the main thread at first draw.
    @concurrent
    static func image(from data: Data, maxPixelSize: Int) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        // ImageIO scales thumbnails up to the limit as well as down, so cap it at the image's own size.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? maxPixelSize
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? maxPixelSize
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, max(width, height)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}
