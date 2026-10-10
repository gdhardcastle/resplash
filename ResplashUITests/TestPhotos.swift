import Foundation

/// The photos the UI tests run against, handed to the app as JSON in the Unsplash list format (see
/// `InjectedPhotoRepository`). Image URLs use the reserved `.invalid` domain, which never resolves: the
/// grid shows its colour placeholders and the tests never depend on an image arriving.
enum TestPhotos {

    struct Photo {
        let caption: String
        let photographer: String
        let width: Int
        let height: Int
        let color: String
    }

    static let mountain = Photo(caption: "A snow-capped mountain at sunrise", photographer: "Alex Rivera", width: 4000, height: 3000, color: "#7A8FA6")
    static let bicycle = Photo(caption: "A red bicycle leaning on a blue wall", photographer: "Sam Okafor", width: 3000, height: 4000, color: "#B5483A")
    static let coast = Photo(caption: "Waves breaking on a rocky coast", photographer: "Mira Chen", width: 4000, height: 2667, color: "#3E6B7E")
    static let lighthouse = Photo(caption: "A lighthouse above a rough sea", photographer: "Jon Beck", width: 3000, height: 4500, color: "#5C6F7B")
    static let coffee = Photo(caption: "Steam rising from a cup of coffee", photographer: "Priya Nair", width: 4000, height: 4000, color: "#8B6B4A")
    static let forest = Photo(caption: "A forest path covered in autumn leaves", photographer: "Luca Romano", width: 3200, height: 4800, color: "#A66A2E")
    static let city = Photo(caption: "City lights reflected in a rainy street", photographer: "Hana Sato", width: 4800, height: 3200, color: "#2F3A55")
    static let lavender = Photo(caption: "A field of lavender under a cloudy sky", photographer: "Omar Haddad", width: 4000, height: 3000, color: "#7C6CA8")

    /// In the order the grid shows them.
    static let all = [mountain, bicycle, coast, lighthouse, coffee, forest, city, lavender]

    /// `all` as the API would return them.
    static var json: String {
        let objects: [[String: Any]] = all.enumerated().map { index, photo in
            [
                "id": "test-\(index)",
                "width": photo.width,
                "height": photo.height,
                "color": photo.color,
                "alt_description": photo.caption,
                "description": NSNull(),
                "urls": [
                    "small": "https://images.invalid/test-\(index)-small",
                    "regular": "https://images.invalid/test-\(index)-regular",
                ],
                "user": ["name": photo.photographer, "links": ["html": NSNull()]],
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: objects)
        return String(decoding: data, as: UTF8.self)
    }
}
