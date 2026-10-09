import SwiftUI

/// The Library screen: the same photos as a masonry grid or, once one is opened, a full-screen pager,
/// with search on top.
struct LibraryView: View {
    
    private static let heroDuration = 0.4
    private static let heroAnimation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: heroDuration)

    @StateObject private var viewModel: LibraryViewModel
    /// Only exists when launched with `-ProfilingHUD`; see `ProfilingProbe`.
    @State private var probe = ProfilingProbe.makeIfEnabled()

    /// The photo open in the pager. `nil` means the grid is showing.
    @State private var selectedID: Photo.ID?
    /// True only while the selected photo is flying between grid and pager. The pager's page only
    /// joins the shared hero id then; at rest it uses a throwaway id, so paging never makes a photo
    /// fly in from a grid cell.
    @State private var isHeroActive = false
    @State private var heroTask: Task<Void, Never>?

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
                    selection: Binding(get: { selectedID ?? id }, set: { selectedID = $0 }),
                    namespace: viewModel.isSearching ? searchNamespace : listNamespace,
                    isHeroActive: isHeroActive,
                    onDismiss: dismissPager
                )
                // No fade on the way in: the photo must be visible at the cell's position immediately.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(1)
            }
        }
        .environment(\.profilingProbe, probe)
        .overlay(alignment: .topLeading) {
            if let probe { ProfilingHUDView(probe: probe) }
        }
        .task { viewModel.start() }
    }
    
    private var listGrid: some View {
        PhotoGridView(
            viewModel: viewModel.listViewModel,
            namespace: listNamespace,
            selectedID: viewModel.isSearching ? nil : selectedID,
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
                emptyMessage: "No results for “\(viewModel.trimmedQuery)”",
                onSelect: select
            )
        } else {
            // Typed, but the debounce hasn't fired yet.
            PhotoGridSkeletonView()
        }
    }

    private func select(_ photo: Photo) {
        UIApplication.dismissKeyboard()
        heroTask?.cancel()
        isHeroActive = true
        probe?.pagerWillOpen()
        withAnimation(Self.heroAnimation) { selectedID = photo.id }
        // Once the flight lands, detach the page from the grid so paging can't trigger another one.
        heroTask = Task {
            try? await Task.sleep(for: .seconds(Self.heroDuration + 0.1))
            guard !Task.isCancelled else { return }
            isHeroActive = false
            probe?.pagerDidFinishOpening()
        }
    }

    private func dismissPager() {
        heroTask?.cancel()
        probe?.pagerWillClose()
        heroTask = Task {
            // Rejoin the hero id first, in its own update, so the flight back has a matching pair.
            isHeroActive = true
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(Self.heroAnimation) { selectedID = nil }
            // Profiling only: wait for the flight back to land so the marker covers all of it.
            if let probe {
                try? await Task.sleep(for: .seconds(Self.heroDuration + 0.1))
                guard !Task.isCancelled else { return }
                probe.pagerDidClose()
            }
        }
    }
}
