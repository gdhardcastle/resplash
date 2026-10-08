import SwiftUI

/// Composes the Library screen with the detail carousel that opens over it.
struct RootView: View {
    @StateObject private var library: LibraryViewModel
    @StateObject private var hero = HeroTransition()
    @Namespace private var listNamespace
    @Namespace private var searchNamespace

    init(repository: PhotoRepository) {
        _library = StateObject(wrappedValue: LibraryViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            LibraryView(
                viewModel: library,
                hero: hero,
                listNamespace: listNamespace,
                searchNamespace: searchNamespace
            )

            // Sits above the navigation stack so the carousel covers the nav bar too.
            if let id = hero.selectedID, let viewModel = library.activeViewModel {
                DetailOverlay(
                    viewModel: viewModel,
                    hero: hero,
                    namespace: library.isSearching ? searchNamespace : listNamespace,
                    fallbackID: id
                )
                // No fade on the way in: the photo must be visible at the cell's position immediately.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(1)
            }
        }
    }
}

/// Observes the active grid view model so the carousel sees pages as they load, without the carousel
/// itself depending on Library types.
private struct DetailOverlay: View {
    @ObservedObject var viewModel: PhotoGridViewModel
    @ObservedObject var hero: HeroTransition
    let namespace: Namespace.ID
    let fallbackID: Photo.ID

    var body: some View {
        DetailPagerView(
            photos: viewModel.photos,
            selection: Binding(get: { hero.selectedID ?? fallbackID }, set: { hero.selectedID = $0 }),
            namespace: namespace,
            isHeroActive: hero.isActive,
            onPhotoShown: viewModel.photoDidAppear,
            onDismiss: hero.dismiss
        )
    }
}
