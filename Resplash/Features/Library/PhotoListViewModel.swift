import Combine
import Foundation

/// Drives a paginated photo grid for one `PhotoSource` (the list feed or a search).
@MainActor
final class PhotoListViewModel: ObservableObject {
    
    enum State: Equatable {
        case idle
        case loadingFirstPage
        case loaded
        /// Only a first-page failure replaces the whole screen.
        case failed(PhotoListFailure)
    }

    enum Footer: Equatable {
        case hidden
        case loading
        case failed(PhotoListFailure)
    }

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var footer: Footer = .hidden

    /// Upper bound on consecutive fetches when a page contains only photos we already have.
    private static let maxPagesPerLoad = 3

    private var source: PhotoSource
    private let repository: PhotoRepository
    private let perPage: Int
    private let prefetchThreshold: Int

    private var nextPage: Int? = 1
    private var loadedIDs = Set<String>()
    /// Non-nil while a fetch is in flight; doubles as the guard against duplicate triggers.
    private var loadTask: Task<Void, Never>?
    /// Bumped whenever results are discarded so a response from before the reset can never land in the new list.
    private var generation = 0

    init(source: PhotoSource, repository: PhotoRepository, perPage: Int = 30, prefetchThreshold: Int = 6) {
        self.source = source
        self.repository = repository
        self.perPage = perPage
        self.prefetchThreshold = prefetchThreshold
    }

    func loadFirstPageIfNeeded() {
        guard state == .idle else { return }
        startLoadingNextPage()
    }

    /// Discards everything and starts again from page 1 (retry after a first-page failure, pull to refresh).
    func reload() {
        discardResults()
        startLoadingNextPage()
    }

    /// Switches to a different source (a new search query) and loads it from page 1.
    /// Anything still in flight for the old source is dropped.
    func changeSource(_ newSource: PhotoSource) {
        guard newSource != source else { return }
        source = newSource
        reload()
    }

    /// Back to a pristine, idle state with nothing loaded and no request made. Used when a search is cleared.
    func reset() {
        source = .search("")
        discardResults()
    }

    private func discardResults() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        photos = []
        loadedIDs = []
        nextPage = 1
        footer = .hidden
        state = .idle
    }

    /// Called as each cell appears; loads the next page once the user is near the end.
    func photoDidAppear(_ photo: Photo) {
        guard state == .loaded, nextPage != nil, footer == .hidden else { return }
        // suffix is O(threshold), not O(n).
        guard photos.suffix(prefetchThreshold).contains(where: { $0.id == photo.id }) else { return }
        startLoadingNextPage()
    }

    func retryLoadMore() {
        guard case .failed = footer else { return }
        startLoadingNextPage()
    }

    /// Awaits any in-flight load. Lets tests wait deterministically.
    func settled() async {
        await loadTask?.value
    }

    private func startLoadingNextPage() {
        guard loadTask == nil, let page = nextPage else { return }
        let isFirstPage = photos.isEmpty
        if isFirstPage {
            state = .loadingFirstPage
        } else {
            footer = .loading
        }
        let generation = generation
        loadTask = Task { [weak self] in
            await self?.load(page: page, isFirstPage: isFirstPage, generation: generation)
        }
    }

    private func load(page: Int, isFirstPage: Bool, generation: Int) async {
        do {
            var page = page
            for _ in 0..<Self.maxPagesPerLoad {
                let result = try await repository.photos(for: source, page: page, perPage: perPage)
                // Cancelled responses can still arrive; discard anything from a previous generation.
                guard !Task.isCancelled, generation == self.generation else { return }

                let fresh = result.items.filter { loadedIDs.insert($0.id).inserted }
                photos.append(contentsOf: fresh)
                nextPage = result.nextPage

                // Pages can overlap. If nothing new landed no cell will appear to trigger the next
                // load, so keep going.
                guard fresh.isEmpty, let next = result.nextPage else { break }
                page = next
            }
            state = .loaded
            footer = .hidden
        } catch {
            guard generation == self.generation else { return }
            // Cancelled requests surface as errors, so check the task rather than the error type.
            if Task.isCancelled {
                state = isFirstPage ? .idle : state
                footer = .hidden
            } else if isFirstPage {
                state = .failed(PhotoListFailure(error))
            } else {
                footer = .failed(PhotoListFailure(error))
            }
        }
        loadTask = nil
    }
}
