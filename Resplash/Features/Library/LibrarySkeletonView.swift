import SwiftUI

/// Placeholder columns shown while the first page loads.
struct LibrarySkeletonView: View {
    private static let columns: [[Double]] = [
        [1.5, 0.75, 1.0, 1.3],
        [0.8, 1.2, 1.5, 0.9],
    ]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: LibraryView.columnSpacing) {
                ForEach(Array(Self.columns.enumerated()), id: \.offset) { _, ratios in
                    VStack(spacing: LibraryView.rowSpacing) {
                        ForEach(Array(ratios.enumerated()), id: \.offset) { _, ratio in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .aspectRatio(ratio, contentMode: .fit)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
        }
        .disabled(true)
        .accessibilityLabel("Loading photos")
    }
}
