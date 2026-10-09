import SwiftUI

/// A masonry grid of one view model's photos, with its loading, error and empty states.
struct PhotoGridView: View {

    @ObservedObject var viewModel: PhotoGridViewModel
    @Environment(\.imageLoader) private var imageLoader
    
    let namespace: Namespace.ID
    /// The photo currently shown in the pager, if any. Read-only: the grid never owns selection.
    let selectedID: Photo.ID?
    /// How the Library scrolls this grid to the page the pager has reached.
    let scroller: GridScroller
    /// Shown when a load succeeds but returns nothing.
    let emptyMessage: String
    let onSelect: (Photo) -> Void

    var body: some View {
        switch viewModel.state {
        case .idle, .loadingFirstPage:
            PhotoGridSkeletonView()
        case .failed(let error):
            errorView(error)
        case .loaded(let photos, _) where photos.isEmpty:
            emptyView
        case .loaded(let photos, let nextPage):
            grid(photos: photos, nextPage: nextPage)
        }
    }

    private func grid(photos: [Photo], nextPage: PhotoGridViewModel.NextPageStatus) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                MasonryColumns(items: photos, relativeHeight: Self.relativeHeight(of:)) { photo in
                    Button { onSelect(photo) } label: {
                        PhotoGridCell(photo: photo, namespace: namespace, isSelected: selectedID == photo.id)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        viewModel.photoDidAppear(photo)
                        prefetchThumbnails(after: photo, in: photos)
                    }
                }

                nextPageView(nextPage)
            }
            .onAppear { scroller.scrollTo = { proxy.scrollTo($0) } }
        }
    }
    
    /// How many photos ahead of the one that just appeared to start loading.
    private static let prefetchDistance = 8

    /// There is no prefetch API for SwiftUI lazy stacks, so each appearing cell asks for the thumbnails
    /// of the photos after it. Each call replaces the last window, so fast scrolling cancels what it passed.
    private func prefetchThumbnails(after photo: Photo, in photos: [Photo]) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let ahead = photos[(index + 1)...].prefix(Self.prefetchDistance)
        imageLoader.prefetch(ahead.map(\.thumbnailRequest))
    }

    /// A cell's height relative to its width: the image at its aspect ratio, plus allowance for the
    /// two-line caption and spacing under it (roughly 0.22 of the column width at 183pt wide).
    private static func relativeHeight(of photo: Photo) -> Double {
        1 / photo.aspectRatio + 0.22
    }

    /// Full-screen error for a failed first page.
    private func errorView(_ error: PhotoRepositoryError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: error.systemImage)
                .font(.largeTitle)
            Text(error.title)
                .font(.headline)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: viewModel.reload)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown below the grid while the next page loads or after it fails; nothing otherwise.
    @ViewBuilder
    private func nextPageView(_ status: PhotoGridViewModel.NextPageStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().padding()
        case .failed(let error):
            VStack(spacing: 8) {
                Text(error.title).font(.subheadline)
                Button("Retry", action: viewModel.retryLoadMore)
            }
            .padding()
        }
    }
    
    private var emptyView: some View {
        Text(emptyMessage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
