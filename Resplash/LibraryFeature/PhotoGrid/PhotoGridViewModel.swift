import Combine
import Foundation

/// View model for one photo grid: loads a single `PhotoSource` a page at a time and publishes what
/// the grid should show.
///
/// It owns the paging mechanics (which page is next, de-duplication, the in-flight guard, stale
/// responses) but knows nothing about search queries or screens; a different source means a
/// different view model.
@MainActor
final class PhotoGridViewModel: ObservableObject {

    /// Everything the grid can be showing. Photos only exist inside `.loaded`, so there is no way to
    /// hold photos while loading, or a next-page status while the first page has failed.
    enum State: Equatable {
        case idle
        case loadingFirstPage
        /// The photos loaded so far, plus the status of the page after them.
        case loaded(photos: [Photo], nextPage: NextPageStatus)
        /// Only a first-page failure replaces the whole screen.
        case failed(PhotoRepositoryError)
    }

    /// Progress of loading the page after the ones already shown.
    enum NextPageStatus: Equatable {
        case idle
        case loading
        case failed(PhotoRepositoryError)
    }

    @Published private(set) var state: State = .idle

    /// The photos loaded so far; empty in every state except `.loaded`.
    var photos: [Photo] {
        guard case .loaded(let photos, _) = state else { return [] }
        return photos
    }

    /// Upper bound on consecutive fetches when a page contains only photos we already have.
    private static let maxPagesPerLoad = 3
    /// The next page to request; `nil` once the source is exhausted.
    private var nextPageNumber: Int? = 1
    /// Non-nil while a fetch is in flight; doubles as the guard against duplicate triggers.
    private var loadTask: Task<Void, Never>?
    /// Bumped whenever results are discarded so a response from before the reset can never land in the new list.
    private var generation = 0
    
    let source: PhotoSource
    private let repository: PhotoRepository
    private let prefetcher: ImagePrefetching
    private let perPage: Int
    private let prefetchThreshold: Int

    init(
        source: PhotoSource,
        repository: PhotoRepository,
        prefetcher: ImagePrefetching,
        perPage: Int = 30,
        prefetchThreshold: Int = 6
    ) {
        self.source = source
        self.repository = repository
        self.prefetcher = prefetcher
        self.perPage = perPage
        self.prefetchThreshold = prefetchThreshold
    }

    func loadFirstPageIfNeeded() {
        guard state == .idle else { return }
        startLoadingNextPage()
    }

    /// Discards everything and starts again from page 1 (retry after a first-page failure).
    func reload() {
        cancel()
        nextPageNumber = 1
        state = .idle
        startLoadingNextPage()
    }

    /// Abandons any in-flight request. Used when this view model is being replaced.
    func cancel() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
    }

    /// Called as each cell appears; loads the next page once the user is near the end.
    func photoDidAppear(_ photo: Photo) {
        guard case .loaded(let photos, .idle) = state, nextPageNumber != nil else { return }
        // suffix is O(threshold), not O(n).
        guard photos.suffix(prefetchThreshold).contains(where: { $0.id == photo.id }) else { return }
        startLoadingNextPage()
    }

    /// How many photos ahead of the one that just appeared to start loading thumbnails for.
    private static let thumbnailPrefetchDistance = 8

    /// There is no prefetch API for SwiftUI lazy stacks, so each appearing cell asks for the thumbnails
    /// of the photos after it. Each call replaces the last window, so fast scrolling cancels what it passed.
    func prefetchThumbnails(after photo: Photo) {
        let photos = photos
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let ahead = photos[(index + 1)...].prefix(Self.thumbnailPrefetchDistance)
        prefetcher.prefetch(ahead.map(\.thumbnailRequest))
    }

    /// The pager's own pages load their images; this gets the ones two away on either side ready.
    func prefetchFullScreenImages(around id: Photo.ID) {
        let photos = photos
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let wanted = [index - 2, index + 2].filter(photos.indices.contains).map { photos[$0].fullScreenRequest }
        prefetcher.prefetch(wanted)
    }

    func retryLoadMore() {
        guard case .loaded(_, .failed) = state else { return }
        startLoadingNextPage()
    }

    /// Awaits any in-flight load. Lets tests wait deterministically.
    func settled() async {
        await loadTask?.value
    }

    private func startLoadingNextPage() {
        guard loadTask == nil, let page = nextPageNumber else { return }

        let existing: [Photo]
        switch state {
        case .idle, .failed:
            existing = []
            state = .loadingFirstPage
        case .loaded(let photos, _):
            existing = photos
            state = .loaded(photos: photos, nextPage: .loading)
        case .loadingFirstPage:
            return
        }

        let generation = generation
        loadTask = Task { [weak self] in
            await self?.load(page: page, after: existing, generation: generation)
        }
    }

    private func load(page: Int, after existing: [Photo], generation: Int) async {
        let isFirstPage = existing.isEmpty
        do {
            var page = page
            var photos = existing
            var knownIDs = Set(existing.map(\.id))
            for _ in 0..<Self.maxPagesPerLoad {
                let result = try await repository.photos(for: source, page: page, perPage: perPage)
                // Cancelled responses can still arrive; discard anything from a previous generation.
                guard !Task.isCancelled, generation == self.generation else { return }

                let fresh = result.items.filter { knownIDs.insert($0.id).inserted }
                photos.append(contentsOf: fresh)
                nextPageNumber = result.nextPage

                // Pages can overlap. If nothing new landed no cell will appear to trigger the next
                // load, so keep going.
                guard fresh.isEmpty, let next = result.nextPage else { break }
                page = next
            }
            state = .loaded(photos: photos, nextPage: .idle)
        } catch {
            guard generation == self.generation else { return }
            // Cancelled requests surface as errors, so check the task rather than the error type.
            if Task.isCancelled {
                state = isFirstPage ? .idle : .loaded(photos: existing, nextPage: .idle)
            } else if isFirstPage {
                state = .failed(Self.failure(from: error))
            } else {
                state = .loaded(photos: existing, nextPage: .failed(Self.failure(from: error)))
            }
        }
        loadTask = nil
    }

    /// The repository contract only throws `PhotoRepositoryError`; anything else is a bug and is shown
    /// as a generic failure.
    private static func failure(from error: Error) -> PhotoRepositoryError {
        (error as? PhotoRepositoryError) ?? .invalidResponse
    }
}
