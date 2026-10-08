import SwiftUI

/// Full-screen error for a failed first page.
struct LibraryErrorView: View {
    let failure: PhotoListFailure
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: failure.systemImage)
                .font(.largeTitle)
            Text(failure.title)
                .font(.headline)
            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
