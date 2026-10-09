import SwiftUI

/// Lays items out in side-by-side columns, each item going into whichever column is currently
/// shortest. Placement is greedy and in order, so appending items never moves existing ones.
///
/// Shared by the photo grid and its loading skeleton so the two always line up.
struct MasonryColumns<Item: Identifiable, Cell: View>: View {
    
    let items: [Item]
    var columnCount = 2
    /// An item's height relative to the column width. Only used to decide which column is shortest.
    let relativeHeight: (Item) -> Double
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: 16) {
                    ForEach(column, content: cell)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    private var columns: [[Item]] {
        var columns = Array(repeating: [Item](), count: columnCount)
        var heights = Array(repeating: 0.0, count: columnCount)
        for item in items {
            // First shortest column wins ties, keeping the layout deterministic.
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(item)
            heights[target] += relativeHeight(item)
        }
        return columns
    }
}
