/// What the grid shows for each failure. Lives with the grid rather than in Domain, which stays free
/// of UI strings.
extension PhotoRepositoryError {
    
    var title: String {
        switch self {
        case .rateLimited: "Rate limit reached"
        case .unauthorized: "Access key rejected"
        case .network: "You're offline"
        case .server, .invalidResponse: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .rateLimited: "Unsplash limits how many requests an app can make per hour. Try again later."
        case .unauthorized: "Check the Unsplash Access Key in Resplash/Config/Secrets.xcconfig."
        case .network: "Check your connection and try again."
        case .server, .invalidResponse: "Please try again."
        }
    }

    var systemImage: String {
        switch self {
        case .rateLimited: "hourglass"
        case .unauthorized: "key.slash"
        case .network: "wifi.slash"
        case .server, .invalidResponse: "exclamationmark.triangle"
        }
    }
}
