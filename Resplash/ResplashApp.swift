import SwiftUI

@main
struct ResplashApp: App {
    
    /// Composition root: the only place that knows concrete types. `nil` when no access key is configured.
    private let repository: PhotoRepository? = (try? Config()).map {
        UnsplashPhotoRepository(api: UnsplashAPI(accessKey: $0.unsplashAccessKey))
    }

    private let imageLoader = ImageLoader.makeLive()

    var body: some Scene {
        WindowGroup {
            if let repository {
                LibraryView(repository: repository, imagePrefetcher: imageLoader)
                    .environment(\.imageLoader, imageLoader)
            } else {
                MissingConfigView()
            }
        }
    }
}
