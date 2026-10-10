import Foundation
import OSLog
import SwiftUI

/// Counts what the scenario needs to compare: how often each view's `body` ran, and what the grid was
/// showing. The image loader's own outcome counts are read from `ImagePipelineStats`.
nonisolated final class PerfCounters: @unchecked Sendable {

    static let shared = PerfCounters()

    private let lock = NSLock()
    private var values: [String: Int] = [:]
    private var hasMarkedScrollDown = false

    /// Phase boundaries as Points of Interest events, so a trace shows where each phase starts and ends
    /// without anyone judging it by eye. Phase 1 ends when 300 photos are loaded, the scenario's target.
    private static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "com.georgehardcastle.Resplash", category: .pointsOfInterest)
    )
    private static let scrollDownTarget = 300

    static func markPhase(_ name: StaticString) {
        guard PerfMode.isEnabled else { return }
        signposter.emitEvent(name)
    }
    private var requestedImageURLs: [URL: Int] = [:]

    /// Call from a view's `body`. Does nothing outside the scenario.
    static func bodyEvaluated(_ view: String) {
        guard PerfMode.isEnabled else { return }
        shared.lock.withLock { shared.values["body.\(view)", default: 0] += 1 }
    }

    func set(_ key: String, _ value: Int) {
        guard PerfMode.isEnabled else { return }
        let reachedTarget = lock.withLock {
            values[key] = value
            guard key == "photosLoaded", value >= Self.scrollDownTarget, !hasMarkedScrollDown else { return false }
            hasMarkedScrollDown = true
            return true
        }
        if reachedTarget { Self.markPhase("Phase 1 ends, phase 2 starts: 300 photos loaded") }
    }

    /// A request that left the device for an image (counted for `AsyncImage` only: the loader counts its own).
    func recordImageRequest(_ url: URL) {
        lock.withLock { requestedImageURLs[url, default: 0] += 1 }
    }

    /// `key=value` tokens: the counters, the image requests, and the loader's outcomes.
    func snapshot(stats: ImagePipelineStats) -> String {
        var tokens = lock.withLock {
            values.map { "\($0.key)=\($0.value)" }
                + ["asyncimage.requests=\(requestedImageURLs.values.reduce(0, +))",
                   "asyncimage.uniqueURLs=\(requestedImageURLs.count)"]
        }
        tokens += ImagePipelineStats.Outcome.allCases.map { "loader.\($0)=\(stats.count($0))" }
        return tokens.sorted().joined(separator: " ")
    }
}
