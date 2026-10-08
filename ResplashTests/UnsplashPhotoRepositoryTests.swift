import Foundation
import Testing
@testable import Resplash

struct UnsplashPhotoRepositoryTests {
    private func repository(_ client: StubHTTPClient) -> UnsplashPhotoRepository {
        UnsplashPhotoRepository(api: UnsplashAPI(accessKey: "KEY"), client: client)
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    // MARK: Requests

    @Test func editorialRequestIsAuthenticatedAndPaged() async throws {
        let client = StubHTTPClient.responding()
        _ = try await repository(client).photos(for: .editorial, page: 3, perPage: 20)

        let request = try #require(client.requests.first)
        #expect(request.url?.path == "/photos")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Client-ID KEY")
        #expect(request.url?.query?.contains("KEY") == false)
        #expect(queryValue("page", in: request) == "3")
        #expect(queryValue("per_page", in: request) == "20")
    }

    @Test func searchRequestCarriesTrimmedQuery() async throws {
        let client = StubHTTPClient.responding(body: Fixtures.searchJSON(totalPages: 1, photos: []))
        _ = try await repository(client).photos(for: .search("  red fox "), page: 1, perPage: 10)

        let request = try #require(client.requests.first)
        #expect(request.url?.path == "/search/photos")
        #expect(queryValue("query", in: request) == "red fox")
    }

    @Test func blankSearchMakesNoRequest() async throws {
        let client = StubHTTPClient.responding()
        let page = try await repository(client).photos(for: .search("   "), page: 1, perPage: 10)

        #expect(page == Page(items: [], nextPage: nil))
        #expect(client.requests.isEmpty)
    }

    // MARK: Pagination

    @Test func editorialNextPageFollowsLinkHeader() async throws {
        let body = "[\(Fixtures.photoJSON())]"
        let more = StubHTTPClient.responding(body: body, headers: ["Link": "<https://x?page=2>; rel=\"next\""])
        let last = StubHTTPClient.responding(body: body, headers: ["Link": "<https://x?page=1>; rel=\"prev\""])

        #expect(try await repository(more).photos(for: .editorial, page: 1, perPage: 10).nextPage == 2)
        #expect(try await repository(last).photos(for: .editorial, page: 5, perPage: 10).nextPage == nil)
    }

    @Test func editorialWithoutLinkHeaderTreatsShortPageAsEnd() async throws {
        let full = StubHTTPClient.responding(body: "[\(Fixtures.photoJSON(id: "a")),\(Fixtures.photoJSON(id: "b"))]")
        let short = StubHTTPClient.responding(body: "[\(Fixtures.photoJSON())]")

        #expect(try await repository(full).photos(for: .editorial, page: 1, perPage: 2).nextPage == 2)
        #expect(try await repository(short).photos(for: .editorial, page: 1, perPage: 2).nextPage == nil)
    }

    @Test func searchNextPageUsesTotalPages() async throws {
        let body = Fixtures.searchJSON(totalPages: 2, photos: [Fixtures.photoJSON()])
        let client = StubHTTPClient.responding(body: body)

        let first = try await repository(client).photos(for: .search("fox"), page: 1, perPage: 10)
        let second = try await repository(client).photos(for: .search("fox"), page: 2, perPage: 10)

        #expect(first.items.map(\.id) == ["abc"])
        #expect(first.nextPage == 2)
        #expect(second.nextPage == nil)
    }

    // MARK: Errors

    @Test(arguments: [
        (401, [:], PhotoRepositoryError.unauthorized),
        (403, ["X-Ratelimit-Remaining": "0"], .rateLimited),
        (403, [:], .server(statusCode: 403)),
        (500, [:], .server(statusCode: 500)),
    ] as [(Int, [String: String], PhotoRepositoryError)])
    func httpStatusMapsToDomainError(status: Int, headers: [String: String], expected: PhotoRepositoryError) async {
        let client = StubHTTPClient.responding(status: status, headers: headers)
        await #expect(throws: expected) {
            try await repository(client).photos(for: .editorial, page: 1, perPage: 10)
        }
    }

    @Test func malformedBodyIsInvalidResponse() async {
        let client = StubHTTPClient.responding(body: "{\"nope\": true}")
        await #expect(throws: PhotoRepositoryError.invalidResponse) {
            try await repository(client).photos(for: .editorial, page: 1, perPage: 10)
        }
    }

    @Test func transportFailureIsNetworkError() async {
        let client = StubHTTPClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: PhotoRepositoryError.network) {
            try await repository(client).photos(for: .editorial, page: 1, perPage: 10)
        }
    }

    @Test func cancellationPropagatesUnchanged() async {
        let client = StubHTTPClient { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            try await repository(client).photos(for: .editorial, page: 1, perPage: 10)
        }
    }
}
