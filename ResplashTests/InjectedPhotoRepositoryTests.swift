import Foundation
import Testing
@testable import Resplash

struct InjectedPhotoRepositoryTests {
    private func json(_ captions: [String]) -> String {
        let photos = captions.enumerated().map { index, caption in
            Fixtures.photoJSON(id: "p\(index)", altDescription: caption)
        }
        return "[\(photos.joined(separator: ","))]"
    }

    @Test func listReturnsTheInjectedPhotosThroughTheMapper() async throws {
        let repository = try InjectedPhotoRepository(json: json(["A mountain", "A beach"]))
        let page = try await repository.photos(for: .list, page: 1, perPage: 30)
        #expect(page.items.map(\.caption) == ["A mountain", "A beach"])
        #expect(page.nextPage == nil)
    }

    @Test func searchMatchesTheCaptionIgnoringCase() async throws {
        let repository = try InjectedPhotoRepository(json: json(["A Mountain", "A beach"]))
        let page = try await repository.photos(for: .search("mountain"), page: 1, perPage: 30)
        #expect(page.items.map(\.caption) == ["A Mountain"])
    }

    @Test func laterPagesAreEmpty() async throws {
        let repository = try InjectedPhotoRepository(json: json(["A mountain"]))
        let page = try await repository.photos(for: .list, page: 2, perPage: 30)
        #expect(page.items.isEmpty)
    }

    @Test func invalidJSONFailsToInitialise() {
        #expect(throws: (any Error).self) { try InjectedPhotoRepository(json: "not json") }
    }

    @Test func isOnlyUsedWhenTheLaunchArgumentIsPresent() {
        let environment = [InjectedPhotoRepository.environmentKey: "[]"]
        #expect(InjectedPhotoRepository.fromLaunch(arguments: [], environment: environment) == nil)
        #expect(InjectedPhotoRepository.fromLaunch(arguments: ["-ui-testing"], environment: environment) != nil)
    }
}
