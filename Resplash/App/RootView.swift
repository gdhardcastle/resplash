import SwiftUI

struct RootView: View {
    @StateObject private var feed: PhotoListViewModel

    init(repository: PhotoRepository) {
        _feed = StateObject(wrappedValue: PhotoListViewModel(source: .list, repository: repository))
    }

    var body: some View {
        NavigationStack {
            LibraryView(viewModel: feed)
                .navigationTitle("Library")
        }
    }
}
