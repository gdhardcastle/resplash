import SwiftUI

/// Shown below the grid while later pages load or after one fails.
struct LibraryFooterView: View {
    let footer: PhotoListViewModel.Footer
    let retry: () -> Void

    var body: some View {
        switch footer {
        case .hidden:
            EmptyView()
        case .loading:
            ProgressView().padding()
        case .failed(let failure):
            VStack(spacing: 8) {
                Text(failure.title).font(.subheadline)
                Button("Retry", action: retry)
            }
            .padding()
        }
    }
}
