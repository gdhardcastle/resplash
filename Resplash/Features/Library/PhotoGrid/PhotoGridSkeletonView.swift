import SwiftUI

/// Placeholder columns shown while the first page loads.
struct PhotoGridSkeletonView: View {
    private struct Placeholder: Identifiable {
        let id: Int
        let aspectRatio: Double
    }

    private static let placeholders = [1.5, 0.8, 0.75, 1.2, 1.0, 1.5, 1.3, 0.9]
        .enumerated()
        .map { Placeholder(id: $0.offset, aspectRatio: $0.element) }

    var body: some View {
        ScrollView {
            MasonryColumns(items: Self.placeholders, relativeHeight: { 1 / $0.aspectRatio }) { placeholder in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(placeholder.aspectRatio, contentMode: .fit)
            }
        }
        .disabled(true)
        .accessibilityLabel("Loading photos")
    }
}
