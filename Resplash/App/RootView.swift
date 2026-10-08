import SwiftUI

struct RootView: View {
    private static let heroDuration = 0.4
    private static let heroAnimation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: heroDuration)
    private static let searchDebounce = Duration.milliseconds(350)

    /// Two long-lived view models: clearing the search returns to the feed instantly, with its scroll
    /// position intact and no extra API calls.
    @StateObject private var feed: PhotoListViewModel
    @StateObject private var search: PhotoListViewModel
    /// One namespace per grid, so a photo that appears in both can never clash in the hero transition.
    @Namespace private var feedNamespace
    @Namespace private var searchNamespace

    @State private var query = ""
    /// Owns the grid ↔ carousel hand-off. `nil` means the grid is showing.
    @State private var selectedID: Photo.ID?
    /// True only while the selected photo is flying between grid and carousel.
    @State private var isHeroActive = false
    @State private var heroTask: Task<Void, Never>?

    init(repository: PhotoRepository) {
        _feed = StateObject(wrappedValue: PhotoListViewModel(source: .list, repository: repository))
        _search = StateObject(wrappedValue: PhotoListViewModel(source: .search(""), repository: repository))
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    private var activeViewModel: PhotoListViewModel {
        isSearching ? search : feed
    }

    private var activeNamespace: Namespace.ID {
        isSearching ? searchNamespace : feedNamespace
    }

    var body: some View {
        ZStack {
            NavigationStack {
                // Both grids stay alive and cross-fade, which is what keeps the feed's scroll position.
                ZStack {
                    library(feed, namespace: feedNamespace, isActive: !isSearching, emptyMessage: "No photos")
                    library(search, namespace: searchNamespace, isActive: isSearching, emptyMessage: "No results for “\(trimmedQuery)”")
                }
                .animation(.easeInOut(duration: 0.2), value: isSearching)
                .navigationTitle("Library")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
            }

            // Sits above the navigation stack so the carousel covers the nav bar too.
            if let id = selectedID {
                DetailPagerView(
                    photos: activeViewModel.photos,
                    selection: Binding(get: { selectedID ?? id }, set: { selectedID = $0 }),
                    namespace: activeNamespace,
                    isHeroActive: isHeroActive,
                    onPhotoShown: activeViewModel.photoDidAppear,
                    onDismiss: dismissDetail
                )
                // No fade on the way in: the photo must be visible at the cell's position immediately.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(1)
            }
        }
        .task { feed.loadFirstPageIfNeeded() }
        .task(id: trimmedQuery) { await runSearch(for: trimmedQuery) }
    }

    private func library(
        _ viewModel: PhotoListViewModel,
        namespace: Namespace.ID,
        isActive: Bool,
        emptyMessage: String
    ) -> some View {
        LibraryView(
            viewModel: viewModel,
            namespace: namespace,
            selectedID: isActive ? selectedID : nil,
            emptyMessage: emptyMessage,
            onSelect: showDetail
        )
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
    }

    /// Debounced: `.task(id:)` cancels this as soon as the query changes, so only a pause in typing
    /// reaches the API.
    private func runSearch(for query: String) async {
        guard !query.isEmpty else {
            search.reset()
            return
        }
        try? await Task.sleep(for: Self.searchDebounce)
        guard !Task.isCancelled else { return }
        search.changeSource(.search(query))
    }

    private func showDetail(_ photo: Photo) {
        UIApplication.dismissKeyboard()
        heroTask?.cancel()
        isHeroActive = true
        withAnimation(Self.heroAnimation) { selectedID = photo.id }
        // Once the flight lands, detach the page from the grid so paging can't trigger another one.
        heroTask = Task {
            try? await Task.sleep(for: .seconds(Self.heroDuration + 0.1))
            guard !Task.isCancelled else { return }
            isHeroActive = false
        }
    }

    private func dismissDetail() {
        heroTask?.cancel()
        heroTask = Task {
            // Rejoin the hero id first, in its own update, so the flight back has a matching pair.
            isHeroActive = true
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(Self.heroAnimation) { selectedID = nil }
        }
    }
}
