import Foundation
import Testing
@testable import Resplash

struct PhotoDTOMappingTests {
    private func map(altDescription: String?, description: String?, color: String? = "#112233") throws -> Photo {
        let json = Fixtures.photoJSON(altDescription: altDescription, description: description, color: color)
        let dto = try JSONDecoder().decode(PhotoDTO.self, from: Data(json.utf8))
        return dto.toDomain()
    }

    @Test func prefersAltDescription() throws {
        #expect(try map(altDescription: "alt", description: "desc").caption == "alt")
    }

    @Test func fallsBackToDescription() throws {
        #expect(try map(altDescription: nil, description: "desc").caption == "desc")
        #expect(try map(altDescription: "  ", description: "desc").caption == "desc")
    }

    @Test func fallsBackToPlaceholder() throws {
        #expect(try map(altDescription: nil, description: nil).caption == "Photo by Jane Doe")
        #expect(try map(altDescription: "", description: "   ").caption == "Photo by Jane Doe")
    }

    @Test func mapsFieldsAndAspectRatio() throws {
        let photo = try map(altDescription: "alt", description: nil)
        #expect(photo.id == "abc")
        #expect(photo.colorHex == "#112233")
        #expect(photo.aspectRatio == 4.0 / 3.0)
        #expect(photo.smallURL.absoluteString == "https://images.unsplash.com/abc-small")
        #expect(photo.regularURL.absoluteString == "https://images.unsplash.com/abc-regular")
    }

    @Test func missingColorUsesFallback() throws {
        #expect(try map(altDescription: "alt", description: nil, color: nil).colorHex == "#E0E0E0")
    }

    @Test func attributionLinkCarriesReferral() throws {
        let url = try #require(try map(altDescription: "alt", description: nil).photographer.profileURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "unsplash.com")
        #expect(items.contains(URLQueryItem(name: "utm_source", value: "Resplash")))
        #expect(items.contains(URLQueryItem(name: "utm_medium", value: "referral")))
    }
}
