/// Splits photos into columns for a masonry grid: each photo goes into whichever column is currently
/// shortest. Assignment is greedy and in order, so appending photos never moves existing ones.
nonisolated enum MasonryLayout {
    static let columnCount = 2

    /// Caption plus spacing under each image, as a fraction of the column width (two lines of caption
    /// text at roughly 183pt wide).
    private static let captionAllowance = 0.22

    static func columns(for photos: [Photo], count: Int = columnCount) -> [[Photo]] {
        var columns = Array(repeating: [Photo](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for photo in photos {
            // First shortest column wins ties, keeping the layout deterministic.
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(photo)
            heights[target] += 1 / photo.aspectRatio + captionAllowance
        }
        return columns
    }
}
