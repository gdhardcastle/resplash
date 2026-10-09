import SwiftUI

/// A masonry grid of one view model's photos, with its loading, error and empty states.
struct PhotoGridView: View {

    @ObservedObject var viewModel: PhotoGridViewModel
    @Environment(\.profilingProbe) private var probe
    
    let namespace: Namespace.ID
    /// The photo currently shown in the pager, if any. Read-only: the grid never owns selection.
    let selectedID: Photo.ID?
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
                        probe?.cellAppeared(photo, in: photos)
                    }
                }

                nextPageView(nextPage)
            }
            // Keep the grid in step with the pager so dismissing lands on the right cell.
            .onChange(of: selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
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
