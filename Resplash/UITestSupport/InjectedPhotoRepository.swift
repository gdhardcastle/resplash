import Foundation

/// Serves the photos a UI test hands to the app, instead of calling the API.
///
/// Launching with `-ui-testing` and a `UITEST_PHOTOS` environment variable holding a JSON array in the
/// Unsplash list format makes `ResplashApp` use this repository. The test owns the data, so no fixture
/// lives in the app, and the photos go through the real `PhotoDTO` mapper. One page; search matches the
/// caption.
nonisolated struct InjectedPhotoRepository: PhotoRepository {

    static let launchArgument = "-ui-testing"
    static let environmentKey = "UITEST_PHOTOS"

    private let photos: [Photo]

    init(json: String) throws {
        let dtos = try JSONDecoder().decode([PhotoDTO].self, from: Data(json.utf8))
        photos = dtos.map { $0.toDomain() }
    }

    /// `nil` unless the app was launched for UI testing. A launch that asks for it but supplies unusable
    /// photos stops, so a test never silently runs against something else.
    static func fromLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> InjectedPhotoRepository? {
        guard arguments.contains(launchArgument) else { return nil }
        guard let json = environment[environmentKey], let repository = try? InjectedPhotoRepository(json: json) else {
            preconditionFailure("\(launchArgument) needs \(environmentKey) to hold a JSON array of photos")
        }
        return repository
    }

    func photos(for source: PhotoSource, page: Int, perPage: Int) async throws -> Page<Photo> {
        guard page == 1 else { return Page(items: [], nextPage: nil) }
        switch source {
        case .list:
            return Page(items: photos, nextPage: nil)
        case .search(let query):
            let matches = photos.filter { $0.caption.localizedCaseInsensitiveContains(query) }
            return Page(items: matches, nextPage: nil)
        }
    }
}
