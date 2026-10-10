import Foundation
import OSLog

/// How each image request was served, counted for measurement. Every count is also written to the
/// Instruments trace as a Points of Interest event, so a recording shows when each happened and the
/// totals between two milestones can be read off it.
nonisolated final class ImagePipelineStats: @unchecked Sendable {

    enum Outcome: CaseIterable {
        /// A request found its decoded image already in memory.
        case memoryHit
        /// A request joined a download or load that was already running.
        case joined
        /// A load was answered from the disk cache.
        case diskHit
        /// A load went to the network.
        case download
        /// An image was decoded.
        case decode
        /// A load was cancelled because the last request waiting for it went away.
        case cancelledLoad
        /// A load failed for a reason other than cancellation.
        case failure
        /// A prefetch started a load that was not already cached or running.
        case prefetchStarted
    }

    private let lock = NSLock()
    private var counts: [Outcome: Int] = [:]

    private let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "com.georgehardcastle.Resplash", category: .pointsOfInterest)
    )

    func record(_ outcome: Outcome) {
        lock.withLock { counts[outcome, default: 0] += 1 }
        switch outcome {
        case .memoryHit: signposter.emitEvent("Image memory hit")
        case .joined: signposter.emitEvent("Image joined")
        case .diskHit: signposter.emitEvent("Image disk hit")
        case .download: signposter.emitEvent("Image download started")
        case .decode: signposter.emitEvent("Image decoded")
        case .cancelledLoad: signposter.emitEvent("Image load cancelled")
        case .failure: signposter.emitEvent("Image load failed")
        case .prefetchStarted: signposter.emitEvent("Image prefetch started")
        }
    }

    func count(_ outcome: Outcome) -> Int {
        lock.withLock { counts[outcome, default: 0] }
    }
}
