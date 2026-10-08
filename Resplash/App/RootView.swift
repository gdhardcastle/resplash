import SwiftUI

struct RootView: View {
    private static let heroDuration = 0.4
    private static let heroAnimation = Animation.timingCurve(0.25, 0.8, 0.25, 1, duration: heroDuration)

    @StateObject private var feed: PhotoListViewModel
    @Namespace private var heroNamespace
    /// Owns the grid ↔ carousel hand-off. `nil` means the grid is showing.
    @State private var selectedID: Photo.ID?
    /// True only while the selected photo is flying between grid and carousel.
    @State private var isHeroActive = false
    @State private var heroTask: Task<Void, Never>?

    init(repository: PhotoRepository) {
        _feed = StateObject(wrappedValue: PhotoListViewModel(source: .list, repository: repository))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                LibraryView(
                    viewModel: feed,
                    namespace: heroNamespace,
                    selectedID: selectedID,
                    onSelect: showDetail
                )
                .navigationTitle("Library")
            }

            // Sits above the navigation stack so the carousel covers the nav bar too.
            if let id = selectedID {
                DetailPagerView(
                    photos: feed.photos,
                    selection: Binding(get: { selectedID ?? id }, set: { selectedID = $0 }),
                    namespace: heroNamespace,
                    isHeroActive: isHeroActive,
                    onPhotoShown: feed.photoDidAppear,
                    onDismiss: dismissDetail
                )
                // No fade on the way in: the photo must be visible at the cell's position immediately.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(1)
            }
        }
    }

    private func showDetail(_ photo: Photo) {
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
