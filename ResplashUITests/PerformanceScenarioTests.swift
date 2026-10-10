import XCTest

/// The performance scenario of docs/PERFORMANCE.md: one launch, three phases, real gestures.
///
/// 1. Scroll down until 300 photos are loaded.
/// 2. Scroll back up to about photo 100.
/// 3. Open a photo, swipe through 20 pages, and close.
///
/// XCTest's metrics cover the whole scenario. What the app's counters saw in each phase is printed on a
/// `PERF` line and attached to the test.
@MainActor
class PerformanceScenarioCase: XCTestCase {

    /// The two concrete classes below set this; the base class itself is not run.
    var usesAsyncImageBaseline: Bool { false }

    static let photosToScrollThrough = 300
    static let returnToPhoto = 100
    static let pagesToSwipe = 20
    /// Points per second. XCUITest's `.fast` is 750, which makes each gesture take over a second.
    static let flickVelocity = XCUIGestureVelocity(3000)

    let app = XCUIApplication()

    override class var defaultTestSuite: XCTestSuite {
        self == PerformanceScenarioCase.self ? XCTestSuite(name: "Abstract") : super.defaultTestSuite
    }

    /// Set (as `TEST_RUNNER_PERF_ATTACH=1`) by `docs/perf/profile.sh`, which has Instruments launch the
    /// app so it can record it. The test then drives that app instead of launching its own.
    private static let attachesToRunningApp = ProcessInfo.processInfo.environment["PERF_ATTACH"] == "1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        if Self.attachesToRunningApp {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 180), "The recorder did not launch the app")
        } else {
            app.launchArguments = ["-perf", "-perf-cold"] + (usesAsyncImageBaseline ? ["-perf-baseline"] : [])
            app.launch()
        }
        try waitUntil("the first page") { counters()["photosLoaded", default: 0] > 0 }
    }

    override func tearDown() {
        // Ending the app ends the recording.
        if Self.attachesToRunningApp { app.terminate() }
    }

    func testScenario() throws {
        var failure: Error?
        var phases: [(name: String, seconds: TimeInterval, delta: [String: Int])] = []
        var last = counters()
        var invocations = 0

        func phase(_ name: String, _ work: () throws -> Void) throws {
            let started = Date()
            try work()
            let now = counters()
            phases.append((name, Date().timeIntervalSince(started),
                           now.reduce(into: [:]) { $0[$1.key] = $1.value - last[$1.key, default: 0] }))
            last = now
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        var metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTMemoryMetric(application: app),
            XCTCPUMetric(application: app),
        ]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }

        // XCTest runs a measure block once more than `iterationCount` and measures only the last
        // run, so the first is skipped: the scenario can only be done once.
        measure(metrics: metrics, options: options) {
            invocations += 1
            guard invocations > 1 else { return }
            do {
                try phase("1 scrollDown") { try scrollDown() }
                try phase("2 scrollBack") { try scrollBack() }
                try phase("3 pager") { try pageThroughPager() }
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        XCTAssertEqual(invocations, 2, "XCTest ran the measure block an unexpected number of times")
        report(phases, total: last)
    }

    // MARK: Phases

    private func scrollDown() throws {
        // Reading the counters takes a while, so look every few swipes rather than every one.
        for _ in 0..<200 {
            if counters()["photosLoaded", default: 0] >= Self.photosToScrollThrough { return }
            for _ in 0..<2 { flick(up: true) }
        }
        XCTFail("Did not load \(Self.photosToScrollThrough) photos")
        throw ScenarioError.didNotFinish
    }

    private func scrollBack() throws {
        for _ in 0..<200 {
            if counters()["lastAppearedIndex", default: .max] <= Self.returnToPhoto { return }
            for _ in 0..<2 { flick(up: false) }
        }
        XCTFail("Did not scroll back to photo \(Self.returnToPhoto)")
        throw ScenarioError.didNotFinish
    }

    /// A drag across most of the screen's height, which then coasts: several screens per gesture.
    private func flick(up: Bool) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        let (from, to) = up ? (bottom, top) : (top, bottom)
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: Self.flickVelocity, thenHoldForDuration: 0)
    }

    private func pageThroughPager() throws {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "The pager did not open")
        for _ in 0..<Self.pagesToSwipe {
            app.swipeLeft(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.3)
        }
        close.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    // MARK: Reporting

    private func report(_ phases: [(name: String, seconds: TimeInterval, delta: [String: Int])], total: [String: Int]) {
        func line(_ values: [String: Int]) -> String {
            values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        var text = "PERF \(String(describing: type(of: self)))"
        for phase in phases {
            text += "\n  \(phase.name) (\(String(format: "%.1f", phase.seconds)) s): \(line(phase.delta))"
        }
        text += "\n  total: \(line(total))"
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "counters"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Reading the app

    /// The counters, as the app last published them. It republishes four times a second.
    private func counters() -> [String: Int] {
        Thread.sleep(forTimeInterval: 0.1)
        let label = app.staticTexts["perf.stats"].label
        return label.split(separator: " ").reduce(into: [:]) { result, token in
            let parts = token.split(separator: "=")
            if parts.count == 2, let value = Int(parts[1]) { result[String(parts[0])] = value }
        }
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for \(what)")
                throw ScenarioError.didNotFinish
            }
        }
    }

    private enum ScenarioError: Error { case didNotFinish }
}

/// The image loader, as shipped.
final class ImageLoaderScenarioTests: PerformanceScenarioCase {}

/// The baseline: the same scenario with `AsyncImage` drawing every image.
final class AsyncImageBaselineScenarioTests: PerformanceScenarioCase {
    override var usesAsyncImageBaseline: Bool { true }
}
