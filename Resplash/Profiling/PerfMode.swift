import Foundation

/// The switches for the performance scenario (see docs/PERFORMANCE.md). All are launch arguments, so a
/// normal launch is unaffected and none of this code runs.
nonisolated enum PerfMode {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// Serves a fixed, recorded feed instead of the API and exposes the counters on screen.
    static let isEnabled = arguments.contains("-perf")
    /// Draws images with `AsyncImage` instead of the image loader: the baseline.
    static let usesAsyncImage = isEnabled && arguments.contains("-perf-baseline")
    /// Empties the loader's disk cache at launch, so every run downloads everything.
    static let startsCold = isEnabled && arguments.contains("-perf-cold")

    /// The app's loader, with its disk cache emptied first when the scenario asks for a cold start.
    static func makeLoader() -> ImageLoader {
        if startsCold {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("Images"))
        }
        if usesAsyncImage { URLProtocol.registerClass(ImageRequestCountingProtocol.self) }
        return ImageLoader.makeLive()
    }

    /// The baseline is plain `AsyncImage`, which has no prefetching, so it gets a prefetcher that does nothing.
    static func prefetcher(for loader: ImageLoader) -> ImagePrefetching {
        usesAsyncImage ? NoPrefetching() : loader
    }

    /// The repository for the scenario: the real mapper and repository over a recorded feed.
    static func makeRepository() -> PhotoRepository {
        UnsplashPhotoRepository(api: UnsplashAPI(accessKey: "perf"), client: ReplayHTTPClient())
    }
}

nonisolated private struct NoPrefetching: ImagePrefetching {
    func prefetch(_ requests: [ImageRequest]) {}
}
