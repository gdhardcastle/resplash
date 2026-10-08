import Foundation

/// Builds authenticated requests for the Unsplash endpoints the app uses.
nonisolated struct UnsplashAPI: Sendable {
    
    private static let baseURL = URL(string: "https://api.unsplash.com")!

    let accessKey: String

    /// `GET /photos` is Unsplash's Editorial feed.
    func editorialRequest(page: Int, perPage: Int) -> URLRequest {
        makeRequest(path: "photos", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ])
    }

    func searchRequest(query: String, page: Int, perPage: Int) -> URLRequest {
        makeRequest(path: "search/photos", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ])
    }

    private func makeRequest(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        return request
    }
}
