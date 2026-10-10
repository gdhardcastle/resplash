import Foundation

/// Counts the image requests `AsyncImage` makes, which it cannot report itself. A request answered by
/// `URLCache.shared` is not counted: it never reaches the network. Registered only for the baseline.
nonisolated final class ImageRequestCountingProtocol: URLProtocol, @unchecked Sendable {

    private static let handledKey = "ImageRequestCountingProtocol.handled"
    private var forwardedTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: handledKey, in: request) == nil && request.url?.host == "images.unsplash.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url, URLCache.shared.cachedResponse(for: request) == nil {
            PerfCounters.shared.recordImageRequest(url)
        }
        let forwarded = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: forwarded)
        forwardedTask = URLSession.shared.dataTask(with: forwarded as URLRequest) { [self] data, response, error in
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        }
        forwardedTask?.resume()
    }

    override func stopLoading() { forwardedTask?.cancel() }
}
