import Foundation
import Testing
import UIKit
@testable import Resplash

/// An `HTTPClient` whose responses wait on a gate, so a test can hold downloads in flight, add and
/// remove waiters, and see whether the download itself was cancelled.
private final class GatedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _isOpen = false
    private var _requests: [URL] = []
    private var _cancelled = 0
    private let status: Int
    private let body: Data

    init(status: Int = 200, body: Data = TestImages.png()) {
        self.status = status
        self.body = body
    }

    var requests: [URL] { lock.withLock { _requests } }
    var cancelledCount: Int { lock.withLock { _cancelled } }

    func open() { lock.withLock { _isOpen = true } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request.url!) }
        do {
            while !lock.withLock({ _isOpen }) {
                try await Task.sleep(for: .milliseconds(2))
            }
        } catch {
            lock.withLock { _cancelled += 1 }
            throw CancellationError()
        }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private enum TestImages {
    static func png(width: Int = 8, height: Int = 8) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }
}

private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
    for _ in 0..<1000 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

struct ImageLoaderTests {
    private let request = ImageRequest(url: URL(string: "https://example.com/a")!, maxPixelSize: 100)

    private func makeLoader(_ http: GatedHTTPClient, disk: URL? = nil) -> ImageLoader {
        let directory = disk ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ImageLoader(http: http, memory: MemoryImageCache(totalCostLimit: 10_000_000), disk: DiskImageCache(directory: directory))
    }

    @Test func concurrentRequestsShareOneDownload() async throws {
        let http = GatedHTTPClient()
        let loader = makeLoader(http)

        async let first = loader.image(for: request)
        async let second = loader.image(for: request)
        async let third = loader.image(for: request)
        await waitUntil { http.requests.count >= 1 }
        try await Task.sleep(for: .milliseconds(50))
        http.open()
        _ = try await (first, second, third)

        #expect(http.requests.count == 1)
        #expect(loader.stats.count(.download) == 1)
        #expect(loader.stats.count(.joined) == 2)
        #expect(loader.stats.count(.decode) == 1)
    }

    @Test func cancellingOneWaiterLeavesTheDownloadForTheOthers() async throws {
        let http = GatedHTTPClient()
        let loader = makeLoader(http)

        let leaving = Task { try await loader.image(for: request) }
        let staying = Task { try await loader.image(for: request) }
        await waitUntil { http.requests.count >= 1 }
        try await Task.sleep(for: .milliseconds(50))

        leaving.cancel()
        try await Task.sleep(for: .milliseconds(50))
        http.open()

        _ = try await staying.value
        #expect(http.requests.count == 1)
        #expect(http.cancelledCount == 0)
        #expect(loader.stats.count(.cancelledLoad) == 0)
    }

    @Test func cancellingTheLastWaiterCancelsTheDownload() async throws {
        let http = GatedHTTPClient()
        let loader = makeLoader(http)

        let only = Task { try await loader.image(for: request) }
        await waitUntil { http.requests.count >= 1 }
        only.cancel()
        await waitUntil { http.cancelledCount >= 1 }

        #expect(http.cancelledCount == 1)
        #expect(loader.stats.count(.cancelledLoad) == 1)
    }

    @Test func aRequestAfterACancellationStartsAFreshDownload() async throws {
        let http = GatedHTTPClient()
        let loader = makeLoader(http)

        let first = Task { try await loader.image(for: request) }
        await waitUntil { http.requests.count >= 1 }
        first.cancel()
        await waitUntil { http.cancelledCount >= 1 }

        http.open()
        _ = try await loader.image(for: request)
        #expect(http.requests.count == 2)
    }

    @Test func aLoadedImageIsServedFromMemory() async throws {
        let http = GatedHTTPClient()
        http.open()
        let loader = makeLoader(http)

        #expect(loader.cachedImage(for: request) == nil)
        _ = try await loader.image(for: request)
        _ = try await loader.image(for: request)

        #expect(loader.cachedImage(for: request) != nil)
        #expect(http.requests.count == 1)
        #expect(loader.stats.count(.download) == 1)
        #expect(loader.stats.count(.memoryHit) == 1)
    }

    @Test func aFreshLoaderReadsTheDiskCacheInsteadOfTheNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let http = GatedHTTPClient()
        http.open()
        _ = try await makeLoader(http, disk: directory).image(for: request)

        let laterHTTP = GatedHTTPClient()
        let later = makeLoader(laterHTTP, disk: directory)
        _ = try await later.image(for: request)

        #expect(laterHTTP.requests.isEmpty)
        #expect(later.stats.count(.diskHit) == 1)
        #expect(later.stats.count(.download) == 0)
    }

    @Test func aViewAskingForAnImageAlreadyInMemoryCountsAsAHitButADrawDoesNot() async throws {
        let http = GatedHTTPClient()
        http.open()
        let loader = makeLoader(http)
        _ = try await loader.image(for: request)

        _ = loader.cachedImage(for: request)
        _ = loader.cachedImage(for: request)
        #expect(loader.stats.count(.memoryHit) == 0)

        _ = loader.cachedImage(for: request, countingAsHit: true)
        #expect(loader.stats.count(.memoryHit) == 1)
    }

    @Test func aPrefetchIsNotCountedAsARequestForTheScreen() async throws {
        let http = GatedHTTPClient()
        http.open()
        let loader = makeLoader(http)

        loader.prefetch([request])
        await waitUntil { loader.cachedImage(for: request) != nil }
        loader.prefetch([request])
        try await Task.sleep(for: .milliseconds(50))

        #expect(loader.stats.count(.prefetchStarted) == 1)
        #expect(loader.stats.count(.memoryHit) == 0)
        #expect(loader.stats.count(.joined) == 0)
        #expect(loader.stats.count(.download) == 1)
    }

    /// The "no duplicated work" guarantee at the scale of the scenario: 500 photos, each asked for twice
    /// at once (the grid and the pager), through a memory cache far too small to hold them, then asked
    /// for again. Each URL must go to the network exactly once; the second pass is answered from disk.
    @Test func fiveHundredPhotosAskedForRepeatedlyAreDownloadedOnce() async throws {
        let http = GatedHTTPClient()
        http.open()
        // Holds about 40 of the 256-byte test images, so most of the second pass misses memory.
        let loader = ImageLoader(
            http: http,
            memory: MemoryImageCache(totalCostLimit: 10_000),
            disk: DiskImageCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        )
        let requests = (0..<500).map { ImageRequest(url: URL(string: "https://example.com/\($0)")!, maxPixelSize: 100) }

        for _ in 0..<2 {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    for _ in 0..<2 {
                        group.addTask { _ = try? await loader.image(for: request) }
                    }
                }
            }
        }

        #expect(http.requests.count == 500)
        #expect(Set(http.requests).count == 500)
        #expect(loader.stats.count(.download) == 500)
        #expect(loader.stats.count(.diskHit) > 0)
        #expect(loader.stats.count(.failure) == 0)
    }

    @Test func aBadStatusFailsAndCachesNothing() async throws {
        let http = GatedHTTPClient(status: 404)
        http.open()
        let loader = makeLoader(http)

        await #expect(throws: ImageLoadError.self) { try await loader.image(for: request) }
        #expect(loader.cachedImage(for: request) == nil)
        #expect(loader.stats.count(.failure) == 1)
    }

    @Test func prefetchingANewWindowCancelsTheOldOne() async throws {
        let http = GatedHTTPClient()
        let loader = makeLoader(http)
        let other = ImageRequest(url: URL(string: "https://example.com/b")!, maxPixelSize: 100)

        loader.prefetch([request])
        await waitUntil { http.requests.count >= 1 }
        loader.prefetch([other])
        await waitUntil { http.cancelledCount >= 1 }

        #expect(http.cancelledCount == 1)
        #expect(http.requests.contains(other.url))
        #expect(loader.stats.count(.prefetchStarted) == 2)
    }
}

struct ImageDownsamplerTests {
    @Test func shrinksALargeImageToTheLimit() async throws {
        let image = try #require(await ImageDownsampler.image(from: TestImages.png(width: 200, height: 100), maxPixelSize: 50))
        #expect(image.cgImage?.width == 50)
        #expect(image.cgImage?.height == 25)
    }

    @Test func neverUpscalesASmallImage() async throws {
        let image = try #require(await ImageDownsampler.image(from: TestImages.png(width: 20, height: 10), maxPixelSize: 500))
        #expect(image.cgImage?.width == 20)
    }

    @Test func rejectsDataThatIsNotAnImage() async {
        #expect(await ImageDownsampler.image(from: Data("nope".utf8), maxPixelSize: 100) == nil)
    }
}
