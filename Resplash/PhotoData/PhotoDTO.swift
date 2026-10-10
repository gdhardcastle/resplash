import Foundation

nonisolated struct PhotoDTO: Decodable, Sendable {
    struct URLs: Decodable, Sendable {
        let small: URL
        let regular: URL
    }

    struct User: Decodable, Sendable {
        struct Links: Decodable, Sendable {
            let html: URL?
        }
        let name: String
        let links: Links?
    }

    let id: String
    let width: Int
    let height: Int
    let color: String?
    let description: String?
    let altDescription: String?
    let urls: URLs
    let user: User

    private enum CodingKeys: String, CodingKey {
        case id, width, height, color, description, urls, user
        case altDescription = "alt_description"
    }
}

nonisolated extension PhotoDTO {
    private static let fallbackColorHex = "#E0E0E0"

    func toDomain() -> Photo {
        Photo(
            id: id,
            caption: caption,
            width: width,
            height: height,
            colorHex: color ?? Self.fallbackColorHex,
            smallURL: urls.small,
            regularURL: urls.regular,
            photographer: Photographer(
                name: user.name,
                profileURL: user.links?.html.map(UnsplashAttribution.withReferral)
            )
        )
    }

    /// alt_description → description → "Photo by <name>".
    private var caption: String {
        for candidate in [altDescription, description] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return "Photo by \(user.name)"
    }
}

nonisolated struct SearchResponseDTO: Decodable, Sendable {
    let totalPages: Int
    let results: [PhotoDTO]

    private enum CodingKeys: String, CodingKey {
        case totalPages = "total_pages"
        case results
    }
}
