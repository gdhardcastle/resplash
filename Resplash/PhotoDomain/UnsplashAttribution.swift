import Foundation

/// What Unsplash's API guidelines ask of the credit line: the photographer's name linking to their
/// profile and "Unsplash" linking to unsplash.com, both carrying the app's name as `utm_source`.
nonisolated enum UnsplashAttribution {

    static let homepage = withReferral(URL(string: "https://unsplash.com/")!)

    /// Adds `utm_source` and `utm_medium` to a link back to Unsplash, keeping any query it already has.
    static func withReferral(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "utm_source", value: "Resplash"),
            URLQueryItem(name: "utm_medium", value: "referral"),
        ]
        return components.url ?? url
    }
}
