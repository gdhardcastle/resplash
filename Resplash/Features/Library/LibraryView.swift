import SwiftUI

/// The Library screen: the browsable list with search on top.
struct LibraryView: View {
    
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var hero: HeroTransition
    
    /// One namespace per grid, so a photo that appears in both can never clash in the hero transition.
    let listNamespace: Namespace.ID
    let searchNamespace: Namespace.ID

    var body: some View {
        NavigationStack {
            // Both grids stay alive and cross-fade, which is what keeps the list's scroll position.
            ZStack {
                PhotoGridView(
                    viewModel: viewModel.list,
                    namespace: listNamespace,
                    selectedID: viewModel.isSearching ? nil : hero.selectedID,
                    emptyMessage: "No photos",
                    onSelect: select
                )
                .opacity(viewModel.isSearching ? 0 : 1)
                .allowsHitTesting(!viewModel.isSearching)
                .accessibilityHidden(viewModel.isSearching)

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
        .task { viewModel.start() }
    }

    @ViewBuilder
    private var searchGrid: some View {
        if let results = viewModel.searchResults {
            PhotoGridView(
                viewModel: results,
                namespace: searchNamespace,
                selectedID: hero.selectedID,
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
        hero.present(photo)
    }
}
