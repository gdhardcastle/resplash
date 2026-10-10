# Performance testing

One scenario, run the same way every time, looked at through four lenses. The harness that produces
these numbers is **not in `main`**: it lives on the `performance-profiling` branch, so the app on `main`
carries no measurement code. The branch also holds text summaries of every Instruments trace
(`docs/perf/results/`), because the traces themselves are 1 to 1.7 GB each.

## The scenario

Cold launch on a recorded feed (577 photos from the Editorial feed, recorded 2026-10-10), so every run
sees the same photos in the same order and nothing depends on the live feed or the demo key's request
limit. Image URLs are the real ones.

| Phase | What happens | Length on the device |
|---|---|---|
| 1 Scroll down | Flick down until 300 photos are loaded | about 77 s |
| 2 Scroll back | Flick up to about photo 100 | about 57 s |
| 3 Pager | Tap a photo, swipe through 20 pages, close | about 26 s |

The gestures are real touches from a UI test, not programmatic scrolling. Two modes were compared in the
same build:

- **Image loader:** the shipped `RemoteImage` and `ImageLoader`, with prefetching.
- **Baseline:** plain `AsyncImage`, with prefetching off.

The app marks the phase boundaries itself as Points of Interest events, so each phase is read between
two markers in the trace.

## Setup

iPhone 13 Pro, iOS 26.7, Release build, 2026-10-10. One recording of each Instruments template per
mode, made with `docs/perf/profile.sh` on the branch (Instruments launches the app, because it cannot
attach to a running one on a device).

## Results

### 1. Behaviour after several hundred images

Allocations, whole run, 307 photos loaded:

| | `AsyncImage` | Image loader |
|---|---|---|
| Live memory at the end | 47.6 MB | 141.7 MB |
| of which decoded image data | 19.0 MB (IOSurface) | 116.6 MB (CG Raster Data) |
| Allocated in total | 1.98 GB | 3.16 GB |

The loader's memory is bounded by its 100 MB decoded-image cache, not by how many photos were scrolled.
It holds about three times the baseline's live memory, by design. The total allocated is higher because
the loader decodes (and downsamples) images that the baseline lets the system draw.

### 2. Efficient loading, no duplicated work

Counters from the app, whole run, 316 distinct image URLs:

| | `AsyncImage` | Image loader |
|---|---|---|
| Network requests | 466 | 347 |
| Requests beyond one per URL | 150 (32% of requests) | 31 (9% of requests) |
| Phase 2: network requests | 147 | 0 (71 reads from disk) |
| Memory hits | none | 462 |

The loader's 31 repeats are loads that were cancelled by scrolling away and then asked for again (27
cancelled loads in the run). The baseline's repeats are mostly phase 2: images it had scrolled past were
not in `URLCache.shared`, so scrolling back asked for them again. (That cause is inferred, not isolated.)

A unit test covers the invariant directly: 500 photos, each asked for twice at once, through a memory
cache that holds about 40, then asked for again, make exactly 500 downloads.

### 3. Unnecessary SwiftUI view updates

`body` evaluations counted in the app, whole run:

| | `AsyncImage` | Image loader |
|---|---|---|
| `PhotoGridCell` (307 cells appeared) | 448 | 444 |
| `PhotoGridView` | 28 | 28 |
| `LibraryView` | 5 | 5 |
| `PhotoGridView` during phase 3 | 4 | 4 |
| `RemoteImage` | 494 | 637 |
| `PhotoPagerView` (20 swipes) | 324 | 324 |

The grid and library update identically in both modes: one cell body per appearance, the grid once per
page load, and the grid not at all while paging apart from opening and closing. The loader re-evaluates
the small `RemoteImage` leaf about 29% more, most likely because it publishes its own load state (not
isolated). `PhotoPagerView` runs about 16 times per swipe, most likely once per frame of the drag; it is
the largest count within the pager phase, though `PhotoGridCell` is larger over the whole run.

The Instruments SwiftUI template recorded no update events in either trace (every `swiftui-*` table was
empty), so these counters are the evidence for this focus.

### 4. CPU and smoothness in Instruments

Time Profiler, process CPU (main thread in brackets):

| Phase | `AsyncImage` | Image loader |
|---|---|---|
| 1 Scroll down | 26.4 s (22.5 s) | 25.9 s (21.8 s) |
| 2 Scroll back | 18.9 s (16.8 s) | 18.4 s (17.5 s) |
| 3 Pager | 6.1 s (4.7 s) | 6.1 s (4.5 s) |

CPU is the same. Nearly all main-thread time is in system frameworks (`libobjc`, `AttributeGraph`,
`libswiftCore`, `UIKitCore`); the app's own functions are under 0.5% of it.

Animation Hitches, hitches caused by the app:

| | `AsyncImage` | Image loader |
|---|---|---|
| Scrolling (phases 1 and 2), 130 to 133 s | 12 hitches, 175 ms, 1.3 ms/s, longest 83 ms | 26 hitches, 283 ms, 2.1 ms/s, longest 17 ms |
| Pager (phase 3) | 4 hitches, 42 ms, 1.5 ms/s | 1 hitch, 17 ms, 0.7 ms/s |

Both are far below the 5 ms/s that Apple rates as good. The two modes differ in which phase hitches more,
but with one run each that is not a finding.

## Limits of these results

- **One run per mode.** There is no spread on anything, counters included. A difference between modes
  smaller than a few tens of percent should not be read as real.
- **Memory disagrees between tools.** XCTest's physical-memory metric ordered the modes the other way
  (loader 36.6 MB at the end and 69.2 MB at the peak; baseline 55.6 and 60.9 MB). I have not explained
  this. The Allocations figures agree with the Xcode memory gauge, so I used those.
- **The Hitches traces lost the "phase 1 ends" marker**, so scroll down and scroll back are reported as
  one span there.
- **The recorded feed answers instantly** (a fixed 100 ms), so real paging latency is not exercised.
- **The harness is in the process it measures.** Its cost is a lock and a counter increment per `body`,
  visible in the Time Profiler at about 50 ms per phase.

## Repeating it

Check out `performance-profiling`. Then:

```bash
# counters and XCTest metrics, on a simulator or device
xcodebuild test -project Resplash.xcodeproj -scheme Resplash \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  -only-testing:ResplashUITests/ImageLoaderScenarioTests

# an Instruments trace, on a device (also: "Allocations", "Animation Hitches", "SwiftUI")
docs/perf/profile.sh <device id> loader   "Time Profiler"
docs/perf/profile.sh <device id> baseline "Time Profiler"
python3 -I docs/perf/analyze_trace.py perf-traces/loader-Time-Profiler.trace
```

The branch's `docs/perf/` has the scripts and `docs/perf/results/` the summaries behind every table
above.
