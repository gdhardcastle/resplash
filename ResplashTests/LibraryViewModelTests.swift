import Foundation
import Testing
@testable import Resplash

@MainActor
struct LibraryViewModelTests {
    /// Echoes the query back as a single photo, so tests can see which search produced what.
    private func makeViewModel(
        gate: Gate? = nil
    ) -> (LibraryViewModel, MockPhotoRepository) {
        let repository = MockPhotoRepository { source, _ in
            switch source {
            case .list:
                return Page(items: [Photo.stub("list")], nextPage: nil)
            case .search(let query):
                if let gate, query == "cat" { await gate.wait() }
                return Page(items: [Photo.stub(query)], nextPage: nil)
            }
        }
        // Zero debounce: tasks still start only after the test yields, so back-to-back keystrokes
        // are cancelled before they run, exactly as a real debounce would drop them.
        return (LibraryViewModel(repository: repository, prefetcher: RecordingPrefetcher(), searchDebounce: .zero), repository)
    }

    @Test func startLoadsTheList() async {
        let (viewModel, repository) = makeViewModel()
        viewModel.start()
        await viewModel.listViewModel.settled()

        #expect(viewModel.listViewModel.photos.map(\.id) == ["list"])
        #expect(repository.requestedPages == [1])
        #expect(viewModel.isSearching == false)
        #expect(viewModel.activeViewModel === viewModel.listViewModel)
    }

    @Test func blankQueryDoesNotSearch() async {
        let (viewModel, repository) = makeViewModel()
        viewModel.query = "   "
        await viewModel.settled()

        #expect(viewModel.isSearching == false)
        #expect(viewModel.searchViewModel == nil)
        #expect(repository.requestedPages.isEmpty)
    }

    @Test func queryLoadsSearchResults() async {
        let (viewModel, _) = makeViewModel()
        viewModel.query = "  fox "
        #expect(viewModel.isSearching)
        #expect(viewModel.searchViewModel == nil) // still debouncing
        await viewModel.settled()

        #expect(viewModel.searchViewModel?.source == .search("fox"))
        #expect(viewModel.searchViewModel?.photos.map(\.id) == ["fox"])
        #expect(viewModel.activeViewModel === viewModel.searchViewModel)
    }

    @Test func rapidTypingOnlySearchesTheFinalQuery() async {
        let (viewModel, repository) = makeViewModel()
        viewModel.query = "f"
        viewModel.query = "fo"
        viewModel.query = "fox"
        await viewModel.settled()

        #expect(viewModel.searchViewModel?.photos.map(\.id) == ["fox"])
        #expect(repository.requestedPages == [1]) // one request, for "fox"
    }

    @Test func clearingTheQueryDropsResultsAndReturnsToTheList() async {
        let (viewModel, repository) = makeViewModel()
        viewModel.start()
        await viewModel.listViewModel.settled()
        viewModel.query = "fox"
        await viewModel.settled()
        let requestsBeforeClearing = repository.requestedPages.count

        viewModel.query = ""
        await viewModel.settled()

        #expect(viewModel.searchViewModel == nil)
        #expect(viewModel.isSearching == false)
        #expect(viewModel.activeViewModel === viewModel.listViewModel)
        #expect(viewModel.listViewModel.photos.map(\.id) == ["list"]) // untouched
        #expect(repository.requestedPages.count == requestsBeforeClearing) // clearing costs no request
    }

    @Test func requeryingTheSameTextKeepsTheExistingResults() async {
        let (viewModel, repository) = makeViewModel()
        viewModel.query = "fox"
        await viewModel.settled()
        let first = viewModel.searchViewModel

        viewModel.query = "fox "   // same query once trimmed
        await viewModel.settled()

        #expect(viewModel.searchViewModel === first)
        #expect(repository.requestedPages == [1])
    }

    @Test func aSlowEarlierSearchNeverReplacesALaterOne() async {
        let gate = Gate()
        let (viewModel, _) = makeViewModel(gate: gate)

        viewModel.query = "cat"
        // Let "cat" start and block inside the repository.
        await Task.yield()
        await Task.yield()

        viewModel.query = "dog"
        await viewModel.settled()

        await gate.open()                 // the "cat" request finally returns
        await Task.yield()
        await viewModel.settled()

        #expect(viewModel.searchViewModel?.source == .search("dog"))
        #expect(viewModel.searchViewModel?.photos.map(\.id) == ["dog"])
    }
}
