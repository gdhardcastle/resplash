import Foundation
import Testing
@testable import Resplash

private func stubPhotos(_ range: ClosedRange<Int>) -> [Photo] {
    range.map { Photo.stub(String($0)) }
}

@MainActor
struct PhotoGridViewModelTests {
    private func makeViewModel(
        perPage: Int = 5,
        threshold: Int = 2,
        _ handler: @escaping MockPhotoRepository.Handler
    ) -> (PhotoGridViewModel, MockPhotoRepository) {
        let repository = MockPhotoRepository(handler)
        return (PhotoGridViewModel(source: .list, repository: repository, prefetcher: RecordingPrefetcher(), perPage: perPage, prefetchThreshold: threshold), repository)
    }

    /// One page of photos "1"…"20", loaded, with a prefetcher to inspect.
    private func loadedViewModel() async -> (PhotoGridViewModel, RecordingPrefetcher) {
        let prefetcher = RecordingPrefetcher()
        let repository = MockPhotoRepository { _, _ in Page(items: stubPhotos(1...20), nextPage: nil) }
        let viewModel = PhotoGridViewModel(source: .list, repository: repository, prefetcher: prefetcher, perPage: 20)
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        return (viewModel, prefetcher)
    }

    /// Three pages of five photos: 1…5, 6…10, 11…15.
    private func pagedHandler() -> MockPhotoRepository.Handler {
        { _, page in
            let start = (page - 1) * 5 + 1
            return Page(items: stubPhotos(start...start + 4), nextPage: page < 3 ? page + 1 : nil)
        }
    }

    @Test func firstLoadPopulatesPhotos() async {
        let (viewModel, _) = makeViewModel(pagedHandler())
        #expect(viewModel.state == .idle)

        viewModel.loadFirstPageIfNeeded()
        #expect(viewModel.state == .loadingFirstPage)
        await viewModel.settled()

        #expect(viewModel.isLoaded)
        #expect(viewModel.photos.map(\.id) == ["1", "2", "3", "4", "5"])
    }

    @Test func loadsNextPageOnlyNearTheEnd() async {
        let (viewModel, repository) = makeViewModel(pagedHandler())
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()

        viewModel.photoDidAppear(viewModel.photos[0])
        await viewModel.settled()
        #expect(repository.requestedPages == [1])

        viewModel.photoDidAppear(viewModel.photos[3]) // within the last 2
        await viewModel.settled()
        #expect(repository.requestedPages == [1, 2])
        #expect(viewModel.photos.count == 10)
    }

    @Test func repeatedTriggersWhileLoadingMakeOneRequest() async {
        let gate = Gate()
        let (viewModel, repository) = makeViewModel { _, page in
            if page == 2 { await gate.wait() }
            let start = (page - 1) * 5 + 1
            return Page(items: stubPhotos(start...start + 4), nextPage: page + 1)
        }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()

        let last = viewModel.photos[4]
        viewModel.photoDidAppear(last)
        viewModel.photoDidAppear(last)
        viewModel.photoDidAppear(viewModel.photos[3])
        #expect(viewModel.nextPageStatus == .loading)

        await gate.open()
        await viewModel.settled()
        #expect(repository.requestedPages == [1, 2])
    }

    @Test func stopsAtTheLastPage() async {
        let (viewModel, repository) = makeViewModel(pagedHandler())
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        for _ in 0..<2 {
            viewModel.photoDidAppear(viewModel.photos.last!)
            await viewModel.settled()
        }
        #expect(viewModel.photos.count == 15)

        viewModel.photoDidAppear(viewModel.photos.last!)
        await viewModel.settled()
        #expect(repository.requestedPages == [1, 2, 3])
    }

    @Test func overlappingPagesAreDeduplicated() async {
        let (viewModel, _) = makeViewModel { _, page in
            page == 1
                ? Page(items: stubPhotos(1...5), nextPage: 2)
                : Page(items: stubPhotos(4...8), nextPage: nil)
        }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        viewModel.photoDidAppear(viewModel.photos.last!)
        await viewModel.settled()

        #expect(viewModel.photos.map(\.id) == (1...8).map(String.init))
    }

    @Test func pageOfOnlyDuplicatesFetchesTheFollowingPage() async {
        let (viewModel, repository) = makeViewModel { _, page in
            switch page {
            case 1: Page(items: stubPhotos(1...5), nextPage: 2)
            case 2: Page(items: stubPhotos(1...5), nextPage: 3)
            default: Page(items: stubPhotos(6...10), nextPage: nil)
            }
        }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        viewModel.photoDidAppear(viewModel.photos.last!)
        await viewModel.settled()

        #expect(repository.requestedPages == [1, 2, 3])
        #expect(viewModel.photos.count == 10)
    }

    @Test func firstPageFailureThenRetry() async {
        let attempts = Counter()
        let (viewModel, _) = makeViewModel { _, _ in
            if await attempts.next() == 1 { throw PhotoRepositoryError.rateLimited }
            return Page(items: stubPhotos(1...5), nextPage: nil)
        }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        #expect(viewModel.state == .failed(.rateLimited))
        #expect(viewModel.photos.isEmpty)

        viewModel.reload()
        await viewModel.settled()
        #expect(viewModel.isLoaded)
        #expect(viewModel.photos.count == 5)
    }

    @Test func laterPageFailureKeepsPhotosAndShowsNextPageError() async {
        let (viewModel, repository) = makeViewModel { _, page in
            if page == 2 { throw PhotoRepositoryError.network }
            return Page(items: stubPhotos(1...5), nextPage: 2)
        }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        viewModel.photoDidAppear(viewModel.photos.last!)
        await viewModel.settled()

        #expect(viewModel.isLoaded)
        #expect(viewModel.photos.count == 5)
        #expect(viewModel.nextPageStatus == .failed(.network))

        // No automatic retry loop while the next-page error is showing.
        viewModel.photoDidAppear(viewModel.photos.last!)
        await viewModel.settled()
        #expect(repository.requestedPages == [1, 2])

        viewModel.retryLoadMore()
        await viewModel.settled()
        #expect(repository.requestedPages == [1, 2, 2])
    }

    @Test func staleResponseNeverLandsAfterReload() async {
        let gate = Gate()
        let calls = Counter()
        let (viewModel, _) = makeViewModel { _, _ in
            if await calls.next() == 1 {
                await gate.wait()
                return Page(items: [Photo.stub("stale")], nextPage: nil)
            }
            return Page(items: stubPhotos(1...5), nextPage: nil)
        }
        viewModel.loadFirstPageIfNeeded()
        viewModel.reload()
        await viewModel.settled()

        await gate.open() // the first (now stale) request finally returns
        await Task.yield()
        await viewModel.settled()

        #expect(viewModel.photos.map(\.id) == ["1", "2", "3", "4", "5"])
        #expect(viewModel.isLoaded)
    }

    @Test func reloadDropsThePreviousPhotosImmediately() async {
        let (viewModel, _) = makeViewModel(pagedHandler())
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        #expect(viewModel.photos.count == 5)

        viewModel.reload()
        // Photos live inside `.loaded`, so there is nothing left to show while the first page loads.
        #expect(viewModel.state == .loadingFirstPage)
        #expect(viewModel.photos.isEmpty)
        await viewModel.settled()
        #expect(viewModel.photos.count == 5)
    }

    @Test func emptyFirstPageIsLoadedWithNoPhotos() async {
        let (viewModel, _) = makeViewModel { _, _ in Page(items: [], nextPage: nil) }
        viewModel.loadFirstPageIfNeeded()
        await viewModel.settled()
        #expect(viewModel.isLoaded)
        #expect(viewModel.photos.isEmpty)
    }

    // MARK: Prefetching

    @Test func anAppearingPhotoPrefetchesThumbnailsOfTheNextEight() async {
        let (viewModel, prefetcher) = await loadedViewModel()
        viewModel.prefetchThumbnails(after: Photo.stub("3"))
        #expect(prefetcher.calls == [(4...11).map { Photo.stub(String($0)).thumbnailRequest }])
    }

    @Test func prefetchingNearTheEndAsksForWhatIsLeft() async {
        let (viewModel, prefetcher) = await loadedViewModel()
        viewModel.prefetchThumbnails(after: Photo.stub("18"))
        #expect(prefetcher.calls == [[Photo.stub("19").thumbnailRequest, Photo.stub("20").thumbnailRequest]])
    }

    @Test func aPhotoTheViewModelDoesNotHaveIsNotPrefetchedAround() async {
        let (viewModel, prefetcher) = await loadedViewModel()
        viewModel.prefetchThumbnails(after: Photo.stub("999"))
        viewModel.prefetchFullScreenImages(around: "999")
        #expect(prefetcher.calls.isEmpty)
    }

    @Test func thePagerPrefetchesFullScreenImagesTwoAwayEitherSide() async {
        let (viewModel, prefetcher) = await loadedViewModel()
        viewModel.prefetchFullScreenImages(around: "10")
        #expect(prefetcher.calls == [[Photo.stub("8").fullScreenRequest, Photo.stub("12").fullScreenRequest]])
    }

    @Test func thePagerPrefetchSkipsPagesThatDoNotExist() async {
        let (viewModel, prefetcher) = await loadedViewModel()
        viewModel.prefetchFullScreenImages(around: "1")
        #expect(prefetcher.calls == [[Photo.stub("3").fullScreenRequest]])
    }
}

actor Counter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private extension PhotoGridViewModel {
    var isLoaded: Bool {
        if case .loaded = state { true } else { false }
    }

    /// The next-page status, or `nil` unless the grid is `.loaded`.
    var nextPageStatus: NextPageStatus? {
        if case .loaded(_, let status) = state { status } else { nil }
    }
}
