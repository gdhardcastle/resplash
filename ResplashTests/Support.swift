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
