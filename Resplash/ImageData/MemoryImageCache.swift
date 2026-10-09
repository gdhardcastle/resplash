import UIKit

/// Decoded images, bounded by their size in memory rather than by count. `NSCache` is thread-safe and
/// evicts on memory warnings, so cells can read it synchronously from `body`.
nonisolated final class MemoryImageCache: @unchecked Sendable {

    private let cache = NSCache<NSString, UIImage>()

    init(totalCostLimit: Int) {
        cache.totalCostLimit = totalCostLimit
    }

    func image(for request: ImageRequest) -> UIImage? {
        cache.object(forKey: Self.key(for: request))
    }

    func insert(_ image: UIImage, for request: ImageRequest) {
        cache.setObject(image, forKey: Self.key(for: request), cost: Self.cost(of: image))
    }

    /// Decoded bytes: width × height × 4.
    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.width * cgImage.height * 4
    }

    private static func key(for request: ImageRequest) -> NSString {
        "\(request.maxPixelSize)|\(request.url.absoluteString)" as NSString
    }
}
