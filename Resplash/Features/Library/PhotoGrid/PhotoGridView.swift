import SwiftUI

/// A masonry grid of one view model's photos, with its loading, error and empty states.
struct PhotoGridView: View {
    
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 16

    @ObservedObject var viewModel: PhotoGridViewModel
    
    let namespace: Namespace.ID
    /// The photo currently shown in the detail carousel, if any. Read-only: the grid never owns selection.
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
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(Array(columns(for: photos).enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: Self.rowSpacing) {
                            ForEach(column) { photo in
                                Button { onSelect(photo) } label: {
                                    PhotoGridCell(photo: photo, namespace: namespace, isSelected: selectedID == photo.id)
                                        .equatable()
                                }
                                .buttonStyle(.plain)
                                .onAppear { viewModel.photoDidAppear(photo) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)

                nextPageView(nextPage)
            }
            // Keep the grid in step with the carousel so dismissing lands on the right cell.
            .onChange(of: selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
    
    private func columns(for photos: [Photo], count: Int = 2) -> [[Photo]] {
        /// Caption plus spacing under each image, as a fraction of the column width (two lines of caption
        /// text at roughly 183pt wide).
        let captionAllowance = 0.22
        var columns = Array(repeating: [Photo](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for photo in photos {
            // First shortest column wins ties, keeping the layout deterministic.
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(photo)
            heights[target] += 1 / photo.aspectRatio + captionAllowance
        }
        return columns
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
