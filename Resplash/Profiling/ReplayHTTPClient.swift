import Foundation

/// Answers the Unsplash list endpoint from `PerfFeed.json`: 20 pages of the Editorial feed recorded on
/// 2026-10-10. Every run then sees the same 577 photos, in the same order, whatever the live feed is
/// doing and without spending the demo key's hourly request limit. Image URLs are the real ones.
nonisolated struct ReplayHTTPClient: HTTPClient {

    private let pages: [Data]

    init() {
        let url = Bundle.main.url(forResource: "PerfFeed", withExtension: "json")!
        let feed = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        pages = (feed["pages"] as! [Any]).map { try! JSONSerialization.data(withJSONObject: $0) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // A fixed delay stands in for the network, so paging has the same rhythm every run.
        try await Task.sleep(for: .milliseconds(100))
        let url = request.url!
        let body: Data
        var headers: [String: String] = [:]
        if url.path == "/photos" {
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
            body = pages.indices.contains(page - 1) ? pages[page - 1] : Data("[]".utf8)
            // Recorded pages can hold fewer than 30 photos; the real API says whether there is a next page.
            if page < pages.count { headers["Link"] = "<https://api.unsplash.com/photos?page=\(page + 1)>; rel=\"next\"" }
        } else {
            body = Data(#"{"total":0,"total_pages":0,"results":[]}"#.utf8)
        }
        return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
    }
}
