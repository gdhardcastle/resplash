import SwiftUI

/// The counters as one line of text over the app, so the UI test can read them. It never takes touches.
struct PerfStatsLabel: View {

    let stats: ImagePipelineStats
    @State private var text = ""

    var body: some View {
        Text(text)
            .font(.system(size: 6, design: .monospaced))
            .foregroundStyle(.white)
            .background(.black.opacity(0.6))
            .allowsHitTesting(false)
            .accessibilityIdentifier("perf.stats")
            .task {
                while !Task.isCancelled {
                    text = PerfCounters.shared.snapshot(stats: stats)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
    }
}
