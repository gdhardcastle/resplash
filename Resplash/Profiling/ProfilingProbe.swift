import Combine
import OSLog
import SwiftUI

/// Opt-in measurement aid for Instruments runs: launch with `-ProfilingHUD`, which the scheme's
/// Profile action passes. Off by default, so normal builds never show it.
///
/// The probe is deliberately not an `ObservableObject`. Grid cells report into it from `onAppear`, and
/// observing it from the screen would re-render the views being measured. Only the small HUD view
/// subscribes, through `updates`.
///
/// It also marks the same moments in the Instruments trace as Points of Interest signposts, so a
/// recording shows exactly when each page landed and when 100 / 500 were reached, without having to
/// click anything while recording.
@MainActor
final class ProfilingProbe {
    struct Snapshot: Equatable {
        /// Photos loaded so far.
        var loaded = 0
        /// 1-based position of the photo whose cell most recently appeared: roughly where the scroll is.
        var latest = 0

        func crossedLoadedMilestone(from old: Snapshot) -> Bool {
            old.loaded < ProfilingProbe.loadedMilestone && loaded >= ProfilingProbe.loadedMilestone
        }

        func crossedPhotoMilestone(from old: Snapshot) -> Bool {
            old.latest < ProfilingProbe.photoMilestone && latest >= ProfilingProbe.photoMilestone
        }
    }

    /// Positions the runbook cares about.
    static let loadedMilestone = 500
    static let photoMilestone = 100

    let updates = PassthroughSubject<Snapshot, Never>()

    private var snapshot = Snapshot()
    private var indexByID: [Photo.ID: Int] = [:]

    /// Shows up on the Points of Interest track in Instruments.
    private let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "com.georgehardcastle.Resplash", category: .pointsOfInterest)
    )

    private init() {
        // Proof in the trace that the launch argument reached the app.
        signposter.emitEvent("Profiling HUD enabled")
    }

    // MARK: Pager markers
    //
    // Intervals rather than points, so each phase is a bar on the Points of Interest track whose range
    // can be selected for Animation Hitches, Time Profiler and the SwiftUI instrument:
    //   "Pager open"    from tapping a photo until the pager has fully gone,
    //   "Pager opening" the grid-to-pager flight,
    //   "Pager closing" the pager-to-grid flight.
    // Each ends at most once, so closing mid-flight or reopening quickly leaves nothing dangling.

    private var openInterval: OSSignpostIntervalState?
    private var openingInterval: OSSignpostIntervalState?
    private var closingInterval: OSSignpostIntervalState?

    func pagerWillOpen() {
        endAllPagerIntervals()
        openInterval = signposter.beginInterval("Pager open")
        openingInterval = signposter.beginInterval("Pager opening")
    }

    /// The opening flight has landed.
    func pagerDidFinishOpening() {
        if let state = openingInterval {
            signposter.endInterval("Pager opening", state)
            openingInterval = nil
        }
    }

    func pagerWillClose() {
        pagerDidFinishOpening()
        guard closingInterval == nil else { return }
        closingInterval = signposter.beginInterval("Pager closing")
    }

    /// The grid was brought in line with the page the pager paused on.
    func gridDidSync() {
        signposter.emitEvent("Grid synced")
    }

    /// The closing flight has landed and the pager is gone.
    func pagerDidClose() {
        if let state = closingInterval {
            signposter.endInterval("Pager closing", state)
            closingInterval = nil
        }
        if let state = openInterval {
            signposter.endInterval("Pager open", state)
            openInterval = nil
        }
    }

    private func endAllPagerIntervals() {
        pagerDidFinishOpening()
        pagerDidClose()
    }

    private static let flag = "-ProfilingHUD"

    /// The HUD is on when the launch arguments contain `-ProfilingHUD`. The match is deliberately loose
    /// because launchers tokenise differently: Xcode's Run splits `-ProfilingHUD YES` in two, while a
    /// profiling launch may hand it over as one argument with a space in it. `-ProfilingHUD YES`
    /// through `UserDefaults` still works too, for `simctl launch`.
    static func makeIfEnabled() -> ProfilingProbe? {
        let isEnabled = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix(flag) }
            || UserDefaults.standard.bool(forKey: "ProfilingHUD")
        return isEnabled ? ProfilingProbe() : nil
    }

    func cellAppeared(_ photo: Photo, in photos: [Photo]) {
        // Rebuilt once per page, then each appearance is a dictionary lookup.
        if photos.count != indexByID.count {
            indexByID = Dictionary(
                photos.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        var next = snapshot
        next.loaded = photos.count
        if let index = indexByID[photo.id] { next.latest = index + 1 }
        guard next != snapshot else { return }
        let previous = snapshot
        snapshot = next

        // Pages land in batches, so a change in `loaded` is the first appearance after a page arrived.
        if next.loaded != previous.loaded {
            signposter.emitEvent("Page loaded", "\(next.loaded) photos")
        }
        if next.crossedLoadedMilestone(from: previous) {
            signposter.emitEvent("Milestone: 500 loaded", "\(next.loaded) photos")
        }
        if next.crossedPhotoMilestone(from: previous) {
            signposter.emitEvent("Milestone: photo 100 reached")
        }
        updates.send(next)
    }
}

private struct ProfilingProbeKey: EnvironmentKey {
    static let defaultValue: ProfilingProbe? = nil
}

extension EnvironmentValues {
    var profilingProbe: ProfilingProbe? {
        get { self[ProfilingProbeKey.self] }
        set { self[ProfilingProbeKey.self] = newValue }
    }
}
