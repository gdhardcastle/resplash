import SwiftUI

@main
struct ResplashApp: App {
    private let config = Result { try Config() }

    var body: some Scene {
        WindowGroup {
            switch config {
            case .success:
                RootView()
            case .failure:
                MissingConfigView()
            }
        }
    }
}
