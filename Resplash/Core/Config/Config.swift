import Foundation

/// Reads environment-specific values injected at build time via xcconfig → Info.plist.
nonisolated struct Config: Sendable {
    enum Error: Swift.Error, Equatable {
        case missingAccessKey
    }

    /// Info.plist key holding the access key. Must match `Config/Info.plist`.
    static let accessKeyInfoPlistKey = "UnsplashAccessKey"

    let unsplashAccessKey: String

    /// Throws `missingAccessKey` when the key is absent, empty or still the example placeholder.
    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) throws {
        let raw = infoDictionary[Self.accessKeyInfoPlistKey] as? String
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty, key != "YOUR_UNSPLASH_ACCESS_KEY", !key.hasPrefix("$(") else {
            throw Error.missingAccessKey
        }
        unsplashAccessKey = key
    }
}
