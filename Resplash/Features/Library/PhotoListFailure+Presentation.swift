extension PhotoListFailure {
    var title: String {
        switch self {
        case .rateLimited: "Rate limit reached"
        case .unauthorized: "Access key rejected"
        case .offline: "You're offline"
        case .generic: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .rateLimited: "Unsplash limits how many requests an app can make per hour. Try again later."
        case .unauthorized: "Check the Unsplash Access Key in Config/Secrets.xcconfig."
        case .offline: "Check your connection and try again."
        case .generic: "Please try again."
        }
    }

    var systemImage: String {
        switch self {
        case .rateLimited: "hourglass"
        case .unauthorized: "key.slash"
        case .offline: "wifi.slash"
        case .generic: "exclamationmark.triangle"
        }
    }
}
