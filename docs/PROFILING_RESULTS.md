# Profiling results

Method and procedure: see [PROFILING.md](PROFILING.md). This file records what was measured.

Device: iPhone 13 Pro (iOS 26.7, ProMotion, so an 8.3 ms frame budget), Release build launched by
Instruments from the `Resplash` scheme with `-ProfilingHUD`, unless a section says Simulator. Traces are
kept outside the repository.

## Summary

### Paging in the pager, by code state

Same sequence each time: scroll to about 500 photos, open a photo, swipe through the pager, close, and
repeat. "Hitch time" is Instruments' hitch time ratio: milliseconds of hitch per second. My recollection
of Apple's guidance is under 5 good, 5 to 10 warning, over 10 critical.

| Recording | Code | Paging hitches | Hitch time | Worst | Main-thread CPU | Opening / closing hitches |
|---|---|---|---|---|---|---|
| Baseline | `AsyncImage` (`1e6ab97`) | 32 | 67.4 and 53.8 ms/s (two sessions) | 75 ms | 294 ms/s | 0 / 1 |
| Caption fix | Caption animation fixed (`e8dd9c6`) | 41 | 55.7 and 84.4 ms/s | 62 ms | 189 ms/s | 4 combined |
| 6 | Pager keeps its own page (`242cc75`) | 28 | 40.9 ms/s | 33 ms | 152 ms/s | 1 / 0 |
| 7 | Grid synced when idle (`15174c9`) | 13 | 35.1 ms/s | 33 ms | not read | 2 / 0 |
| 8 | Image loader replaces `AsyncImage` (`5fd474e`) | 11 | 24.4 ms/s | 25 ms | 144 ms/s | 0 / 0 |
| 9 | Grid scrolled without changing selection (`283ba01`) | **3** | **4.1 ms/s** | **25 ms** | 142 ms/s | **0 / 0** |

Runs 6 to 9 combine both pager sessions into one figure; the first two rows are per session as first
recorded. Runs 6 to 9 are your run numbers, in `Hitches Time Profiler & SwiftUI.trace` (its own numbers
for them are 3 to 6).

Caveats: one recording each, swipes done by hand, and the sessions differ in length (6.4 s to 9.5 s of
paging), so small steps are within noise. Run 6 to run 9 is the only change I would call a trend. The
grid-scroll phase was not re-measured after run 1.

### What has been established

- **CPU rendering while paging is gone.** The caption bar's text animated on every page change and was
  redrawn on the CPU (44% of main-thread time). One modifier fixed it. It was real but not the cause of
  the hitches.
- **Keeping the pager's page local to the pager removed the grid's work.** Grid-subtree updates while
  paging fell from about 3,380/s to 28/s, and hitch time from about 55 to 41 ms/s.
- **Idle sync fixed the closing stick.** Opening and closing are now clean in the trace. It costs updates
  during paging, below.
- **Every remaining paging hitch is Instruments' "Potentially expensive app update(s)".** Not image
  loading, decoding (always off the main thread) or GPU work.
- **The image loader moved the numbers, but the run does not isolate it.** Between runs 7 and 8 the loader
  is the only code change, but the sessions differ and there is no Allocations or Network recording for
  it yet, so no cache hit rate or duplicate count.
- **Scrolling the grid without touching state took paging under the warning line.** The idle sync was
  setting `selectedID`, which re-ran `LibraryView` and the grid. A `GridScroller` reference now scrolls the
  grid directly. Grid updates while paging fell from about 2,150/s to about 490/s, and paging hitches from
  11 to 3 (24.4 to 4.1 ms/s). Main-thread CPU barely changed (144 to 142 ms/s): the cost was concentrated in
  the frames where a sync landed, not spread across the session.

### Open

- **A sync can still cost a frame.** In run 9 one of the 3 paging hitches (25 ms at 10.42 s) lands 39 ms
  after a "Grid synced" signpost; the other two do not line up with one. The scroll itself still creates the
  cells that come into view.
- **The pager still updates about 3,060 views a second** while paging (`OpacityRendererEffect`,
  `_MatchedGeometryEffect`, `_ClipEffect`). Run 9 is already under the warning line, so reducing that is
  optional. The main thread is about 142 ms/s busy, 58% of it graph
  updates, 15% `body` evaluation, 15% Core Animation commit. Our own functions do not show by name in
  Release symbols.
- **A 37.5 ms hitch about 300 ms after the pager finished closing in run 8** was not seen in run 9
  (one 8 ms hitch outside the pager), so it may have been a one-off. Not investigated.
- **Failed grid images** (grey photo icon after scrolling back to about photo 100) were seen with
  `AsyncImage`. The loader retries a failed load when the cell reappears; not yet checked on the device.

## Baseline: plain `AsyncImage`

Code: `main` at `1e6ab97`, with image loading identical to the `baseline-asyncimage` tag (`4fb7c5a`). Tool:
Allocations with VM Tracker, one run of 52.6 s. The on-disk `URLCache` state at the start was not
recorded. The session: first page at 2.7 s, photo 100 reached at 11.7 s, 500 loaded at 29.3 s (504 photos
after 18 pages; pages overlap and duplicates are dropped), photo 100 crossed again at 37.5 s and 49.3 s.
The pager was not marked in this recording.

| Allocations, whole run | Value |
|---|---|
| Live memory at the end (heap + anonymous VM) | 30.0 MiB (86,281 live allocations) |
| Allocated / freed over the run | 1,111.7 MiB / 1,081.7 MiB |
| Allocation events | 8,876,085 |
| Image reads (`CGImageRead`): created / alive at the end | **971** / 43 |
| IOSurface memory: created / alive at the end | 259.8 MiB / 11.2 MiB |
| VM Tracker, app's own dirty memory (Instruments' 32.6 MiB overhead excluded) | about 46 MiB |

- **Repeated decoding is likely:** 971 image reads against 504 photos, so at least 467 are repeats, less
  whatever the pager did. Inferred from counts, not shown per photo.
- **Memory does not grow with the number of photos.** About 43 images are alive at the end. The cost is
  churn (about 1.1 GiB allocated), not accumulation.
- **Expected effect of a pipeline:** persistent bytes will probably rise, since a cache holds decoded images
  up to its limit. The metrics that should improve are decode count, allocated bytes and hitches.

**Network, from the Simulator** (CFNetwork log, not Instruments, which kept crashing; iPhone 18 Pro
Simulator, fresh install, one run, `AsyncImage`; compare shape, not absolute numbers). URLs are redacted
in the log, so per-URL duplicates could not be counted, only totals.

| Step | Image requests (cumulative) | From network | From `URLCache` |
|---|---|---|---|
| First page | 7 | 7 | 0 |
| Scrolled down to photo 159 | 159 | 159 | 0 |
| Scrolled back up to photo 76 | 296 | 163 | 133 |

Going down is one request per photo. Coming back is about 1.65 requests per photo, 133 of 137 answered by
`URLCache`: the download is mostly not repeated, but the app asks again each time a cell reappears, which
matches the repeated decoding. A relaunch without deleting the app was served entirely from `URLCache`, so
a cold run needs a fresh install.

## Allocations: `AsyncImage` against the image loader

Allocations with VM Tracker on the iPhone 13 Pro, Release, launched with `-ProfilingHUD`, in
`Allocations.trace`. Run 1 is the `AsyncImage` baseline above (52.6 s). Runs 2 and 3 are the loader at
`b77cc81`, **cold** (fresh install, 39.8 s) and **warm** (relaunch with the disk cache populated, 30.3 s).
Each run scrolled to about 500 photos and back to photo 100 by hand, so the pace differs: 500 loaded at 29.3 s,
16.9 s and 16.7 s. The pager was not opened.

| | `AsyncImage` (run 1) | Loader, cold (run 2) | Loader, warm (run 3) |
|---|---|---|---|
| App's own dirty memory at the end (VM Tracker, tool overhead excluded) | 46.2 MiB | 126.9 MiB | 143.9 MiB |
| Decoded image memory at the end | IOSurface 11.2 MiB | CG Raster Data 96.3 MiB | CG Raster Data 105.7 MiB |
| Image decodes (`CGImageRead` created) | 971 | not available | **935** |
| Live heap + anonymous VM (Statistics) | 30.0 MiB | not available | 125.7 MiB |
| Allocated over the run (Statistics) | 1,111.7 MiB | not available | 3,338.2 MiB |

**What I could not measure.** `xctrace` returns the same Allocations Statistics for every run in a trace
file. They match run 3 (its 105.7 MiB of CG Raster Data equals run 3's VM Tracker figure), so the cold run's
decode count and totals are unavailable until it is saved as the selected run. The VM Tracker data is per
run and its run 1 totals match the baseline section exactly. Downloads per URL are not in this trace at all:
the loader's `Image download` signposts are in the `ImagePipeline` category, which this template does not
record.

**Reading**

- **The decode count did not fall: 935 against 971.** For about 506 photos that is roughly 1.85 decodes
  each, the same shape as the baseline. A decoded thumbnail is about 0.7 MiB (652 MiB over 935 decodes), so
  the 100 MB cache holds about 140 of them. Scrolling to 500 and back to 100 passes about 400 photos that
  have already been evicted, and each is decoded again from the disk cache. This is inferred from the
  numbers, not measured as a hit rate.
- **Memory went up, as expected, and more than I guessed.** App memory is about 80 to 100 MiB higher
  (46 to 127 and 144 MiB), nearly all of it the decoded-image cache sitting at its limit. The baseline held
  about 43 images alive at the end; the loader holds about 150.
- **Total allocated bytes tripled, but are not comparable.** `AsyncImage` decodes appear as IOSurface; the
  loader's appear as four sizeable categories (ImageIO JPEG data 673 MiB, CG Image 653, CG Raster Data 652,
  CGSImageHandle 633) which look like the same decoded bytes seen at different layers, so adding them
  overstates it. Compare decode counts, not totals.
- **So the loader's gains are not in this table.** The hitch drop (run 6 to 9), duplicate downloads, request
  cancellation and the retry of a failed load are separate effects. What this run shows is that the memory
  cache is too small for a return trip of this length.

## Why paging hitched: the caption animation

**Baseline per phase** (57.2 s). Grid 1.63 ms/s over 38.4 s (5 hitches); pager opening clean;
**paging 67.4 and 53.8 ms/s** (17 and 15 hitches, worst 75 ms); closing 13.9 ms/s. Time Profiler while
paging: 43.6% of main-thread samples in offscreen CPU rendering and 46.2% in `CGDrawingLayer` drawing,
against about 0% in the grid. Image decoding never ran on the main thread. So the image pipeline was not
expected to fix the hitches, and the README should not claim that it does.

**Isolated on the Simulator, one change at a time** (`xctrace` Time Profiler, Release, iPhone 18 Pro
Simulator, same driven sequence: open the first photo, ten swipes, close; one recording per variant, so
differences under about 8 points are noise):

| Variant | Offscreen CPU render | Main-thread CPU |
|---|---|---|
| Control | 35.8% | 145 ms/s |
| Grid's selection frozen while paging | 43.6% | 148 ms/s |
| Chrome without group opacity or materials | 32.1% | 157 ms/s |
| Pages without clip, matched geometry, per-page opacity or scale | 38.8% | 153 ms/s |
| **Caption bar not animated** | **0.0%** | 101 ms/s |

The caption text changes on every page inside the paging `withAnimation`; SwiftUI interpolated the old and
new text each frame. The fix is `.transaction { $0.animation = nil }` on the caption bar. This test
measured CPU rendering only, so it says nothing about update spikes or the grid.

**Device re-measure after the fix** (62.0 s): CPU rendering 0.0% (was 43.6%), main-thread CPU
189 ms/s (was 294), but paging still 55.7 and 84.4 ms/s. 35 of 41 paging hitches were "Potentially
expensive app update(s)", with the main thread only about 38% busy in the hitch windows, so individual late
frames rather than overload. 245 gesture update groups cost 1,442 ms while paging, 24 of them 8 ms or
more. Each page flip changed the selection in `LibraryView`, which re-evaluated and scrolled the grid
underneath inside the frame that finished the swipe; that led to the pager owning its page (run 6).

## Run 8: with the image loader

Code `5fd474e` (loader, memory and disk caches, prefetching, `RemoteImage`), 20.4 s, two pager sessions.

| Phase | Seconds | Hitches | Hitch time | Worst |
|---|---|---|---|---|
| Pager opening | 1.1 | 0 | 0 | 0 |
| **Paging** | 7.9 | 11 | 24.4 ms/s | 25.0 ms |
| Pager closing | 1.2 | 0 | 0 | 0 |
| Outside the pager | n/a | 4 | 75 ms in total | n/a |

SwiftUI instrument while paging (76,479 updates, 9,725/s): pager subtree 27,995; grid 16,887 (about
2,100/s); other, mostly grid-cell `Button` and `ResolvedButtonStyle`, 27,589; both 4,008. The most updated
views in the pager are `OpacityRendererEffect` (6,419), `_MatchedGeometryEffect` (3,382) and `_ClipEffect`
(2,864). Main thread while paging is about 144 ms/s busy (run 6: 152).

## Run 9: grid scrolled without changing selection

Code `283ba01`, 22.5 s, two pager sessions.

| Phase | Seconds | Hitches | Hitch time | Worst |
|---|---|---|---|---|
| Pager opening | 1.1 | 0 | 0 | 0 |
| **Paging** | 10.0 | 3 | 4.1 ms/s | 25.0 ms |
| Pager closing | 1.2 | 0 | 0 | 0 |
| Outside the pager | n/a | 1 | 8 ms | 8 ms |

SwiftUI instrument while paging, against run 8: 79,681 updates (7,928/s, was 9,725/s). The grid's share
fell from 16,887 updates (about 2,150/s) to 4,881 (about 490/s), and grid-cell `Button` and
`ResolvedButtonStyle` no longer appear among the most updated views. The pager subtree is unchanged at
about 3,060 updates/s, and 1,345/s are classified as touching both the pager and the grid (not
investigated). Two of the three paging hitches are Instruments' "Potentially expensive app update(s)".

## Not yet measured

- [ ] The cold run's Allocations Statistics (decode count and totals): select run 2 in Instruments, save,
      and re-export.
- [ ] Cache hit rate and downloads per URL with the loader. The Allocations template cannot show them;
      the loader needs hit and miss counters, or its `ImagePipeline` signposts recorded.
- [ ] The grid scroll phase with the loader (hitches, update counts).
- [ ] Network instrument on the device, if it can be made to stop crashing.
- [ ] A trustworthy `PhotoGridCell` body-update count (the SwiftUI instrument recorded 91 for a whole grid
      scroll of about 517 photos, which cannot be complete).
- [ ] A warm run (relaunch without deleting the app), now that there is a disk cache.
