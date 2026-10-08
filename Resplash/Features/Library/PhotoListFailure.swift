/// Presentation-level view of a failed load. Keeps views independent of repository error types.
enum PhotoListFailure: Equatable {
    case rateLimited
    case unauthorized
    case offline
    case generic

    init(_ error: Error) {
        switch error as? PhotoRepositoryError {
        case .rateLimited: self = .rateLimited
        case .unauthorized: self = .unauthorized
        case .network: self = .offline
        default: self = .generic
        }
    }
}
