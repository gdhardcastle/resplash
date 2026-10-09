import SwiftUI

/// The Library screen: the same photos as a masonry grid or, once one is opened, a full-screen pager,
/// with search on top.
struct LibraryView: View {
    
    private static let heroDuration = 0.4
    private static let heroAnimation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: heroDuration)

    @StateObject private var viewModel: LibraryViewModel

    /// The photo open in the pager. `nil` means the grid is showing. It is set when the pager opens
    /// and again when it is dismissed, but not on page flips: the pager keeps its own current page, so
    /// paging never re-evaluates the grid underneath.
    @State private var selectedID: Photo.ID?
    /// True only while the selected photo is flying between grid and pager. The pager's page only
    /// joins the shared hero id then; at rest it uses a throwaway id, so paging never makes a photo
    /// fly in from a grid cell.
    @State private var isHeroActive = false
    @State private var heroTask: Task<Void, Never>?
    /// Scrolls each grid to the pager's page. Reference types that views never read, so using them
    /// re-evaluates nothing.
    @State private var listScroller = GridScroller()
    @State private var searchScroller = GridScroller()

    /// One namespace per grid, so a photo that appears in both can never clash in the hero transition.
    @Namespace private var listNamespace
    @Namespace private var searchNamespace

    init(repository: PhotoRepository) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                // Both grids stay alive and cross-fade, which is what keeps the list's scroll position.
                ZStack {
                    listGrid
                    if viewModel.isSearching {
                        searchGrid.transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
                .navigationTitle("Library")
                .searchable(
                    text: $viewModel.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search photos"
                )
            }

            // Sits above the navigation stack so the pager covers the nav bar too.
            if let id = selectedID, let gridViewModel = viewModel.activeViewModel {
                PhotoPagerView(
                    viewModel: gridViewModel,
                    initialID: id,
                    namespace: viewModel.isSearching ? searchNamespace : listNamespace,
                    isHeroActive: isHeroActive,
                    onDismiss: dismissPager,
                    onSettle: syncGrid
                )
                // No fade on the way in: the photo must be visible at the cell's position immediately.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(1)
            }
        }
        .task { viewModel.start() }
    }
    
    private var listGrid: some View {
        PhotoGridView(
            viewModel: viewModel.listViewModel,
            namespace: listNamespace,
            selectedID: viewModel.isSearching ? nil : selectedID,
            scroller: listScroller,
            emptyMessage: "No photos",
            onSelect: select
        )
        .opacity(viewModel.isSearching ? 0 : 1)
        .allowsHitTesting(!viewModel.isSearching)
        .accessibilityHidden(viewModel.isSearching)
    }

    @ViewBuilder
    private var searchGrid: some View {
        if let results = viewModel.searchViewModel {
            PhotoGridView(
                viewModel: results,
                namespace: searchNamespace,
                selectedID: selectedID,
                scroller: searchScroller,
                emptyMessage: "No results for “\(viewModel.trimmedQuery)”",
                onSelect: select
            )
        } else {
            // Typed, but the debounce hasn't fired yet.
            PhotoGridSkeletonView()
        }
    }

    private var activeScroller: GridScroller {
        viewModel.isSearching ? searchScroller : listScroller
    }

    private func select(_ photo: Photo) {
        UIApplication.dismissKeyboard()
        activeScroller.reset(to: photo.id)
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

    /// Scrolls the grid to the page the user has paused on, so dismissing finds it already in place.
    /// Only the scroll position moves: `selectedID` is untouched, so no view body re-runs for it. The
    /// grid's cell only drops its image when the pager is dismissed.
    private func syncGrid(to id: Photo.ID) {
        guard selectedID != nil else { return }
        activeScroller.scroll(to: id)
    }

    /// `currentID` is the photo the pager is showing, which may differ from the one it opened on.
    /// Usually the grid is already there; if the user dismissed straight after a swipe it catches up now.
    private func dismissPager(at currentID: Photo.ID) {
        heroTask?.cancel()
        heroTask = Task {
            // Rejoin the hero id first, in its own update, so the flight back has a matching pair. The
            // grid's cell for the current photo drops its image now, before the flight back starts. The
            // grid is usually already scrolled there; if the user dismissed straight after a swipe, it
            // scrolls now.
            isHeroActive = true
            activeScroller.scroll(to: currentID)
            selectedID = currentID
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(Self.heroAnimation) { selectedID = nil }
        }
    }
}
