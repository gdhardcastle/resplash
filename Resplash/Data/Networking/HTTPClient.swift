import Foundation

nonisolated protocol HTTPClient: Sendable {
    /// Returns the raw response for any HTTP status; callers interpret status codes.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }
}
