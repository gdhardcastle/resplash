import SwiftUI

struct LibraryView: View {
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 16

    @ObservedObject var viewModel: PhotoListViewModel
    let namespace: Namespace.ID
    /// The photo currently shown in the detail carousel, if any. Read-only: the Library never owns selection.
    let selectedID: Photo.ID?
    /// Shown when a load succeeds but returns nothing.
    let emptyMessage: String
    let onSelect: (Photo) -> Void

    var body: some View {
        switch viewModel.state {
        case .idle, .loadingFirstPage:
            LibrarySkeletonView()
        case .failed(let failure):
            LibraryErrorView(failure: failure, retry: viewModel.reload)
        case .loaded where viewModel.photos.isEmpty:
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(Array(MasonryLayout.columns(for: viewModel.photos).enumerated()), id: \.offset) { _, column in
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

                LibraryFooterView(footer: viewModel.footer, retry: viewModel.retryLoadMore)
            }
            // Keep the grid in step with the carousel so dismissing lands on the right cell.
            .onChange(of: selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}
