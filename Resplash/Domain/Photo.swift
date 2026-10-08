import Foundation

nonisolated struct Photo: Identifiable, Equatable, Sendable {
    
    let id: String
    let caption: String
    let width: Int
    let height: Int
    /// Dominant colour as `#RRGGBB`, used as an instant placeholder.
    let colorHex: String
    /// ~400px wide, for grid cells.
    let smallURL: URL
    /// ~1080px wide, for the full-screen view.
    let regularURL: URL
    let photographer: Photographer

    var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 1
    }
}

nonisolated struct Photographer: Equatable, Sendable {
    let name: String
    let profileURL: URL?
}
