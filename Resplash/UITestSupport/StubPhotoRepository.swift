import Foundation

/// Launching with `-ui-testing` swaps the Unsplash repository for this one, so the UI tests need no
/// network and no access key and always see the same photos. Selected in `ResplashApp`, the composition
/// root, and nowhere else.
nonisolated enum UITestSupport {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ui-testing")
}

/// A fixed single page of photos. Search matches on the caption, like the real thing would on keywords.
nonisolated struct StubPhotoRepository: PhotoRepository {

    private struct Entry {
        let caption: String
        let photographer: String
        let width: Int
        let height: Int
        let colorHex: String
    }

    private static let entries = [
        Entry(caption: "A snow-capped mountain at sunrise", photographer: "Alex Rivera", width: 4000, height: 3000, colorHex: "#7A8FA6"),
        Entry(caption: "A red bicycle leaning on a blue wall", photographer: "Sam Okafor", width: 3000, height: 4000, colorHex: "#B5483A"),
        Entry(caption: "Waves breaking on a rocky coast", photographer: "Mira Chen", width: 4000, height: 2667, colorHex: "#3E6B7E"),
        Entry(caption: "A lighthouse above a rough sea", photographer: "Jon Beck", width: 3000, height: 4500, colorHex: "#5C6F7B"),
        Entry(caption: "Steam rising from a cup of coffee", photographer: "Priya Nair", width: 4000, height: 4000, colorHex: "#8B6B4A"),
        Entry(caption: "A forest path covered in autumn leaves", photographer: "Luca Romano", width: 3200, height: 4800, colorHex: "#A66A2E"),
        Entry(caption: "City lights reflected in a rainy street", photographer: "Hana Sato", width: 4800, height: 3200, colorHex: "#2F3A55"),
        Entry(caption: "A field of lavender under a cloudy sky", photographer: "Omar Haddad", width: 4000, height: 3000, colorHex: "#7C6CA8"),
    ]

    func photos(for source: PhotoSource, page: Int, perPage: Int) async throws -> Page<Photo> {
        guard page == 1 else { return Page(items: [], nextPage: nil) }
        let matching: [(offset: Int, element: Entry)]
        switch source {
        case .list:
            matching = Array(Self.entries.enumerated())
        case .search(let query):
            matching = Self.entries.enumerated().filter {
                $0.element.caption.localizedCaseInsensitiveContains(query)
            }
        }
        return Page(items: matching.map { photo(id: $0.offset, entry: $0.element) }, nextPage: nil)
    }

    /// Image URLs use the reserved `.invalid` domain, which never resolves: the grid shows its colour
    /// placeholders and failure icon, and the tests never depend on an image arriving.
    private func photo(id: Int, entry: Entry) -> Photo {
        Photo(
            id: "stub-\(id)",
            caption: entry.caption,
            width: entry.width,
            height: entry.height,
            colorHex: entry.colorHex,
            smallURL: URL(string: "https://images.invalid/stub-\(id)-small")!,
            regularURL: URL(string: "https://images.invalid/stub-\(id)-regular")!,
            photographer: Photographer(name: entry.photographer, profileURL: nil)
        )
    }
}
