import SwiftUI

/// Small overlay for profiling runs. Each line turns green at its milestone, and a haptic marks the
/// moment it is crossed so you can keep your eyes on Instruments.
struct ProfilingHUDView: View {
    let probe: ProfilingProbe
    @State private var snapshot = ProfilingProbe.Snapshot()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line("Loaded", snapshot.loaded, milestone: ProfilingProbe.loadedMilestone)
            line("Photo", snapshot.latest, milestone: ProfilingProbe.photoMilestone)
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
        .allowsHitTesting(false)
        .onReceive(probe.updates) { next in
            if crossed(snapshot.loaded, next.loaded, ProfilingProbe.loadedMilestone)
                || crossed(snapshot.latest, next.latest, ProfilingProbe.photoMilestone) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            snapshot = next
        }
    }

    private func line(_ title: String, _ value: Int, milestone: Int) -> some View {
        Text("\(title) \(value)/\(milestone)\(value >= milestone ? " ✓" : "")")
            .foregroundStyle(value >= milestone ? Color.green : Color.primary)
    }

    private func crossed(_ old: Int, _ new: Int, _ milestone: Int) -> Bool {
        old < milestone && new >= milestone
    }
}
