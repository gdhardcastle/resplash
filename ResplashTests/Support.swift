import Foundation
@testable import Resplash

/// Scripted `HTTPClient` that records requests and returns a canned response.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private let handler: Handler
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        return try handler(request)
    }

    static func responding(
        status: Int = 200,
        body: String = "[]",
        headers: [String: String] = [:]
    ) -> StubHTTPClient {
        StubHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }
}

enum Fixtures {
    static func photoJSON(
        id: String = "abc",
        altDescription: String? = "a mountain",
        description: String? = "Mountain at dawn",
        color: String? = "#112233"
    ) -> String {
        func field(_ name: String, _ value: String?) -> String {
            value.map { "\"\(name)\": \"\($0)\"," } ?? "\"\(name)\": null,"
        }
        return """
        {
          "id": "\(id)",
          "width": 4000,
          "height": 3000,
          \(field("color", color))
          \(field("alt_description", altDescription))
          \(field("description", description))
          "urls": {"small": "https://images.unsplash.com/\(id)-small", "regular": "https://images.unsplash.com/\(id)-regular"},
          "user": {"name": "Jane Doe", "links": {"html": "https://unsplash.com/@jane"}}
        }
        """
    }

    static func searchJSON(totalPages: Int, photos: [String]) -> String {
        "{\"total\": 100, \"total_pages\": \(totalPages), \"results\": [\(photos.joined(separator: ","))]}"
    }
}

extension Photo {
    static func stub(_ id: String) -> Photo {
        Photo(
            id: id,
            caption: "Photo \(id)",
            width: 400,
            height: 300,
            colorHex: "#808080",
            smallURL: URL(string: "https://example.com/\(id)-small")!,
            regularURL: URL(string: "https://example.com/\(id)-regular")!,
            photographer: Photographer(name: "Jane", profileURL: nil)
        )
    }
}

/// Scripted `PhotoRepository`. The handler may suspend, so tests can hold a request in flight.
final class MockPhotoRepository: PhotoRepository, @unchecked Sendable {
    typealias Handler = @Sendable (PhotoSource, Int) async throws -> Page<Photo>

    private let handler: Handler
    private let lock = NSLock()
    private var _requestedPages: [Int] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requestedPages: [Int] {
        lock.withLock { _requestedPages }
    }

    func photos(for source: PhotoSource, page: Int, perPage: Int) async throws -> Page<Photo> {
        lock.withLock { _requestedPages.append(page) }
        return try await handler(source, page)
    }
}

/// Lets a test hold a mock request open and release it later.
actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Records what a view model asked to be prefetched.
final class RecordingPrefetcher: ImagePrefetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[ImageRequest]] = []

    /// One entry per `prefetch` call, in order.
    var calls: [[ImageRequest]] { lock.withLock { _calls } }

    func prefetch(_ requests: [ImageRequest]) {
        lock.withLock { _calls.append(requests) }
    }
}
