import SwiftUI

/// Placeholder grid shown while the first page loads.
struct LibrarySkeletonView: View {
    private static let ratios: [Double] = [1.5, 0.8, 1.0, 1.3, 0.75, 1.2, 1.0, 1.5]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: LibraryView.columns, spacing: 16) {
                ForEach(Array(Self.ratios.enumerated()), id: \.offset) { _, ratio in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .aspectRatio(ratio, contentMode: .fit)
                }
            }
            .padding(.horizontal, 12)
        }
        .disabled(true)
        .accessibilityLabel("Loading photos")
    }
}
