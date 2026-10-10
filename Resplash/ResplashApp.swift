import SwiftUI

@main
struct ResplashApp: App {
    
    /// Composition root: the only place that knows concrete types. `nil` when no access key is configured.
    private let repository: PhotoRepository? = PerfMode.isEnabled
        ? PerfMode.makeRepository()
        : (try? Config()).map { UnsplashPhotoRepository(api: UnsplashAPI(accessKey: $0.unsplashAccessKey)) }

    private let imageLoader = PerfMode.makeLoader()

    var body: some Scene {
        WindowGroup {
            if let repository {
                LibraryView(repository: repository)
                    .environment(\.imageLoader, imageLoader)
                    .overlay(alignment: .bottomLeading) {
                        if PerfMode.isEnabled { PerfStatsLabel(stats: imageLoader.stats) }
                    }
            } else {
                MissingConfigView()
            }
        }
    }
}
