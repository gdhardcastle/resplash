import SwiftUI

enum RemoteImagePhase {
    case loading
    case loaded(Image)
    case failed
}

/// Draws an image from the environment's `ImageLoader`, in place of `AsyncImage`.
///
/// Unlike `AsyncImage` it draws a memory-cached image on its first frame, shares downloads, cancels
/// them when scrolled away, and retries a failure the next time it appears.
struct RemoteImage<Content: View>: View {

    private let request: ImageRequest
    private let content: (RemoteImagePhase) -> Content

    @Environment(\.imageLoader) private var loader
    @State private var loaded: UIImage?
    @State private var failed = false

    init(request: ImageRequest, @ViewBuilder content: @escaping (RemoteImagePhase) -> Content) {
        self.request = request
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: request) { await load() }
            // Holding the decoded image here would keep it alive outside the cache's memory budget.
            // It comes back from the cache, or the loader, when the view reappears.
            .onDisappear { loaded = nil }
    }

    private var phase: RemoteImagePhase {
        if let image = loaded ?? loader.cachedImage(for: request) { return .loaded(Image(uiImage: image)) }
        return failed ? .failed : .loading
    }

    private func load() async {
        failed = false
        guard loader.cachedImage(for: request, countingAsHit: true) == nil else { return }
        do {
            loaded = try await loader.image(for: request)
        } catch {
            // A cancelled load is the view going away, not a failure.
            failed = !Task.isCancelled
        }
    }
}

private struct ImageLoaderKey: EnvironmentKey {
    static let defaultValue: any ImageLoading = ImageLoader.makeLive()
}

extension EnvironmentValues {
    var imageLoader: any ImageLoading {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}
