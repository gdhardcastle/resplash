import SwiftUI

struct LibraryView: View {
    static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    @ObservedObject var viewModel: PhotoListViewModel

    var body: some View {
        content
            .onAppear { viewModel.loadFirstPageIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loadingFirstPage:
            LibrarySkeletonView()
        case .failed(let failure):
            LibraryErrorView(failure: failure, retry: viewModel.reload)
        case .loaded where viewModel.photos.isEmpty:
            Text("No photos")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                ForEach(viewModel.photos) { photo in
                    PhotoGridCell(photo: photo)
                        .equatable()
                        .onAppear { viewModel.photoDidAppear(photo) }
                }
            }
            .padding(.horizontal, 12)

            LibraryFooterView(footer: viewModel.footer, retry: viewModel.retryLoadMore)
        }
    }
}
