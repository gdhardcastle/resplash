import Combine
import Foundation

/// Drives the Library screen: the browsable list, plus search on top of it.
///
/// The list view model lives for the whole session, so clearing the search returns to it instantly with
/// its scroll position and no extra requests. Search results get a fresh view model per query.
@MainActor
final class LibraryViewModel: ObservableObject {
    
    let listViewModel: PhotoGridViewModel
    @Published private(set) var searchViewModel: PhotoGridViewModel?
    
    @Published var query = "" {
        didSet { queryDidChange() }
    }
    
    private var searchTask: Task<Void, Never>?

    private let repository: PhotoRepository
    private let searchDebounce: Duration

    init(
        repository: PhotoRepository,
        searchDebounce: Duration = .milliseconds(350)
    ) {
        self.repository = repository
        self.searchDebounce = searchDebounce
        listViewModel = PhotoGridViewModel(source: .list, repository: repository)
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// The grid view model whose photos are currently on screen (and in the pager).
    var activeViewModel: PhotoGridViewModel? {
        isSearching ? searchViewModel : listViewModel
    }

    func start() {
        listViewModel.loadFirstPageIfNeeded()
    }

    /// Awaits the pending debounce and any load it started. Lets tests wait deterministically.
    func settled() async {
        await searchTask?.value
        await searchViewModel?.settled()
    }

    /// Debounced: every keystroke cancels the previous pending search, so only a pause in typing
    /// reaches the API.
    private func queryDidChange() {
        searchTask?.cancel()
        let query = trimmedQuery

        guard !query.isEmpty else {
            searchViewModel?.cancel()
            searchViewModel = nil
            return
        }
        // Back to the query that is already showing: nothing to do.
        guard searchViewModel?.source != .search(query) else { return }

        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            self?.startSearch(for: query)
        }
    }

    private func startSearch(for query: String) {
        searchViewModel?.cancel()
        let results = PhotoGridViewModel(source: .search(query), repository: repository)
        searchViewModel = results
        results.loadFirstPageIfNeeded()
    }
}
