import SwiftUI

/// Shown instead of crashing when no Unsplash Access Key was supplied at build time.
struct MissingConfigView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.largeTitle)
            Text("Unsplash Access Key missing")
                .font(.headline)
            Text("Copy Resplash/Config/Secrets.example.xcconfig to Resplash/Config/Secrets.xcconfig, add your key, then rebuild. See the README for details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    MissingConfigView()
}
