nonisolated protocol PhotoRepository: Sendable {
    /// Pages are 1-based. Throws `CancellationError` when the calling task is cancelled.
    func photos(for source: PhotoSource, page: Int, perPage: Int) async throws -> Page<Photo>
}

nonisolated enum PhotoRepositoryError: Error, Equatable, Sendable {
    /// The access key was rejected (HTTP 401).
    case unauthorized
    /// The hourly request quota is exhausted (HTTP 403 with no remaining requests).
    case rateLimited
    /// The device could not reach the server.
    case network
    case server(statusCode: Int)
    /// The response could not be decoded.
    case invalidResponse
}
