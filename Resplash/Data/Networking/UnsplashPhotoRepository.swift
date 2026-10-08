import Foundation

nonisolated struct UnsplashPhotoRepository: PhotoRepository {
    private let api: UnsplashAPI
    private let client: HTTPClient

    init(api: UnsplashAPI, client: HTTPClient = URLSessionHTTPClient()) {
        self.api = api
        self.client = client
    }

    func photos(for source: PhotoSource, page: Int, perPage: Int) async throws -> Page<Photo> {
        switch source {
        case .list:
            return try await listPhotos(page: page, perPage: perPage)
        case .search(let query):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // A blank query would waste a request from a small hourly quota.
            guard !trimmed.isEmpty else { return Page(items: [], nextPage: nil) }
            return try await searchPhotos(query: trimmed, page: page, perPage: perPage)
        }
    }

    private func listPhotos(page: Int, perPage: Int) async throws -> Page<Photo> {
        let (data, response) = try await perform(api.listPhotos(page: page, perPage: perPage))
        let dtos = try decode([PhotoDTO].self, from: data)
        return Page(
            items: dtos.map { $0.toDomain() },
            nextPage: hasNextPage(response, itemCount: dtos.count, perPage: perPage) ? page + 1 : nil
        )
    }

    private func searchPhotos(query: String, page: Int, perPage: Int) async throws -> Page<Photo> {
        let (data, _) = try await perform(api.searchPhotos(query: query, page: page, perPage: perPage))
        let body = try decode(SearchResponseDTO.self, from: data)
        return Page(
            items: body.results.map { $0.toDomain() },
            nextPage: page < body.totalPages ? page + 1 : nil
        )
    }

    /// The list endpoint has no `total_pages`; Unsplash signals more pages with a `Link: rel="next"` header.
    /// Without that header, fall back to treating a short page as the end.
    private func hasNextPage(_ response: HTTPURLResponse, itemCount: Int, perPage: Int) -> Bool {
        if let link = response.value(forHTTPHeaderField: "Link") {
            return link.contains("rel=\"next\"")
        }
        return itemCount >= perPage
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch is URLError {
            throw PhotoRepositoryError.network
        }

        switch response.statusCode {
        case 200..<300:
            return (data, response)
        case 401:
            throw PhotoRepositoryError.unauthorized
        case 403 where response.value(forHTTPHeaderField: "X-Ratelimit-Remaining") == "0":
            throw PhotoRepositoryError.rateLimited
        default:
            throw PhotoRepositoryError.server(statusCode: response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PhotoRepositoryError.invalidResponse
        }
    }
}
