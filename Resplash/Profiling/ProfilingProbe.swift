import Combine
import SwiftUI

/// Opt-in measurement aid for Instruments runs: launch with `-ProfilingHUD`, which the scheme's
/// Profile action passes. Off by default, so normal builds never show it.
///
/// The probe is deliberately not an `ObservableObject`. Grid cells report into it from `onAppear`, and
/// observing it from the screen would re-render the views being measured. Only the small HUD view
/// subscribes, through `updates`.
@MainActor
final class ProfilingProbe {
    struct Snapshot: Equatable {
        /// Photos loaded so far.
        var loaded = 0
        /// 1-based position of the photo whose cell most recently appeared: roughly where the scroll is.
        var latest = 0
    }

    /// Positions the runbook cares about.
    static let loadedMilestone = 500
    static let photoMilestone = 100

    let updates = PassthroughSubject<Snapshot, Never>()

    private var snapshot = Snapshot()
    private var indexByID: [Photo.ID: Int] = [:]

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
        snapshot = next
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
