import OSLog
import UIKit

nonisolated protocol ImageLoading: Sendable {
    /// The decoded image if it is already in memory. Synchronous, so a view can draw it on its first frame.
    /// `countingAsHit` is for a view asking because it needs the image, not for one redrawing what it has:
    /// `body` can run many times for a single request.
    func cachedImage(for request: ImageRequest, countingAsHit: Bool) -> UIImage?
    func image(for request: ImageRequest) async throws -> UIImage
    /// Quietly loads these ahead of need. Each call replaces the previous window: requests no longer in
    /// it are cancelled, so scrolling fast doesn't leave a queue of downloads nobody will see.
    func prefetch(_ requests: [ImageRequest])
}

extension ImageLoading {
    nonisolated func cachedImage(for request: ImageRequest) -> UIImage? {
        cachedImage(for: request, countingAsHit: false)
    }
}

nonisolated enum ImageLoadError: Error {
    case badStatus(Int)
    case undecodable
}

/// Memory cache, then in-flight downloads, then disk cache, then network, in that order.
///
/// - Duplicate requests join one download rather than starting another.
/// - Cancellation is reference-counted: a cell scrolling away only cancels the download once no other
///   cell is still waiting on it.
/// - Decoding is downsampled and happens off the main thread, and the actor never blocks on it.
actor ImageLoader: ImageLoading {

    private struct InFlight {
        let id = UUID()
        let task: Task<UIImage, Error>
        var waiters = 1
    }

    private let http: HTTPClient
    private let memory: MemoryImageCache
    private let disk: DiskImageCache
    private var inFlight: [ImageRequest: InFlight] = [:]
    private var prefetching: [ImageRequest: Task<Void, Never>] = [:]

    nonisolated let stats = ImagePipelineStats()

    /// Marks each download as an interval carrying its URL, so duplicates are countable per URL.
    private let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "com.georgehardcastle.Resplash", category: .pointsOfInterest)
    )

    init(http: HTTPClient, memory: MemoryImageCache, disk: DiskImageCache) {
        self.http = http
        self.memory = memory
        self.disk = disk
    }

    /// The app's loader. Its session has no `URLCache`: the loader's own disk cache is the only one,
    /// so each image isn't stored twice.
    static func makeLive() -> ImageLoader {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ImageLoader(
            http: URLSessionHTTPClient(session: URLSession(configuration: configuration)),
            memory: MemoryImageCache(totalCostLimit: 100_000_000),
            disk: DiskImageCache(directory: caches.appendingPathComponent("Images"))
        )
    }

    // MARK: ImageLoading

    nonisolated func cachedImage(for request: ImageRequest, countingAsHit: Bool) -> UIImage? {
        let image = memory.image(for: request)
        if image != nil, countingAsHit { stats.record(.memoryHit) }
        return image
    }

    func image(for request: ImageRequest) async throws -> UIImage {
        try await image(for: request, isPrefetch: false)
    }

    /// A prefetch is not a request for the screen, so it does not count as a hit or a join: the loads it
    /// causes still show up as disk hits, downloads and decodes.
    private func image(for request: ImageRequest, isPrefetch: Bool) async throws -> UIImage {
        if let cached = memory.image(for: request) {
            if !isPrefetch { stats.record(.memoryHit) }
            return cached
        }

        let (id, task) = join(request, isPrefetch: isPrefetch)
        defer { finish(request, id: id) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(request, id: id) }
        }
    }

    nonisolated func prefetch(_ requests: [ImageRequest]) {
        Task { await updatePrefetch(requests) }
    }

    // MARK: In-flight bookkeeping

    private func join(_ request: ImageRequest, isPrefetch: Bool) -> (id: UUID, task: Task<UIImage, Error>) {
        if var existing = inFlight[request] {
            if !isPrefetch { stats.record(.joined) }
            existing.waiters += 1
            inFlight[request] = existing
            return (existing.id, existing.task)
        }
        if isPrefetch { stats.record(.prefetchStarted) }
        let entry = InFlight(task: Task { try await self.load(request) })
        inFlight[request] = entry
        return (entry.id, entry.task)
    }

    /// One waiter gave up. The download is cancelled only when it was the last, and removed at once so a
    /// later request starts afresh instead of joining a cancelled task.
    private func leave(_ request: ImageRequest, id: UUID) {
        guard var entry = inFlight[request], entry.id == id else { return }
        entry.waiters -= 1
        if entry.waiters == 0 {
            stats.record(.cancelledLoad)
            entry.task.cancel()
            inFlight[request] = nil
        } else {
            inFlight[request] = entry
        }
    }

    /// Clears a finished entry. Compares ids so a slow waiter can't remove a newer download of the same request.
    private func finish(_ request: ImageRequest, id: UUID) {
        if inFlight[request]?.id == id { inFlight[request] = nil }
    }

    // MARK: Loading

    private func load(_ request: ImageRequest) async throws -> UIImage {
        do {
            return try await loadUncounted(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            stats.record(.failure)
            throw error
        }
    }

    private func loadUncounted(_ request: ImageRequest) async throws -> UIImage {
        if let data = await disk.data(for: request.url) {
            if let image = await decode(data, for: request) {
                stats.record(.diskHit)
                return image
            }
            // A truncated or corrupt file would otherwise fail forever.
            await disk.remove(request.url)
        }

        let data = try await download(request.url)
        try Task.checkCancellation()
        guard let image = await decode(data, for: request) else {
            throw ImageLoadError.undecodable
        }
        await disk.store(data, for: request.url)
        return image
    }

    /// Decodes, downsampled and off the main thread, and puts the result in the memory cache.
    private func decode(_ data: Data, for request: ImageRequest) async -> UIImage? {
        guard let image = await ImageDownsampler.image(from: data, maxPixelSize: request.maxPixelSize) else {
            return nil
        }
        stats.record(.decode)
        memory.insert(image, for: request)
        return image
    }

    private func download(_ url: URL) async throws -> Data {
        stats.record(.download)
        let interval = signposter.beginInterval("Image download", "\(url.absoluteString, privacy: .public)")
        defer { signposter.endInterval("Image download", interval) }

        let (data, response) = try await http.send(URLRequest(url: url))
        guard (200..<300).contains(response.statusCode) else {
            throw ImageLoadError.badStatus(response.statusCode)
        }
        return data
    }

    // MARK: Prefetching

    private func updatePrefetch(_ requests: [ImageRequest]) {
        let wanted = Set(requests)
        for (request, task) in prefetching where !wanted.contains(request) {
            task.cancel()
            prefetching[request] = nil
        }
        for request in requests where prefetching[request] == nil && memory.image(for: request) == nil {
            prefetching[request] = Task(priority: .utility) {
                _ = try? await self.image(for: request, isPrefetch: true)
                self.prefetchDidFinish(request)
            }
        }
    }

    private func prefetchDidFinish(_ request: ImageRequest) {
        prefetching[request] = nil
    }
}
