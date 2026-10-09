# Profiling results

Method and procedure: see [PROFILING.md](PROFILING.md). This file records what was measured.

## Baseline: plain `AsyncImage`

| | |
|---|---|
| Code | `main` at `1e6ab97`. Image loading is identical to the `baseline-asyncimage` tag (`4fb7c5a`); only the profiling HUD and signposts were added since. |
| Device | iPhone 13 Pro, iOS 26.7 |
| Tooling | Instruments 27.0 (27A266a), Allocations template with VM Tracker |
| Launch | Launched by Instruments from the `Resplash` scheme (Product → Profile, Release), with `-ProfilingHUD` |
| Run | One run, 52.6 s. On-disk `URLCache` state at the start was not recorded. |
| Trace file | `Allocations.trace`, kept outside the repository |

### What the session did (from the signposts)

| Time | Event |
|---|---|
| 2.2 s | `Profiling HUD enabled` |
| 2.7 s | First page, 30 photos |
| 11.7 s | Photo 100 reached (113 loaded) |
| 29.3 s | 500 loaded (504 photos after 18 pages) |
| 37.5 s, 49.3 s | Photo 100 crossed again (scrolled back up, then down) |

Pages do not add a flat 30: adjacent pages overlap and duplicates are dropped
(30 → 60 → 90 → 113 → 143 → 173 → 201 → 222 → 251 → 272 → 301 → 330 → 360 → 390 → 419 → 446 → 475 → 504).
The pager phase was not marked in this recording, so it is not known whether it was exercised.

### Allocations, whole run

These are totals for the whole 52.6 s recording, not values at a milestone.

| Metric | Value |
|---|---|
| Live memory at the end (heap + anonymous VM) | 30.0 MiB (86,281 live allocations) |
| of which heap | 13.4 MiB (86,202 live) |
| of which anonymous VM | 16.6 MiB (79 live) |
| Allocated over the run | 1,111.7 MiB |
| Freed over the run | 1,081.7 MiB |
| Allocation events | 8,876,085 |

### Image decoding

| Metric | Created over the run | Alive at the end |
|---|---|---|
| Image reads (`CGImageRead`) | **971** | 43 |
| IOSurface surfaces | 972 | 44 |
| IOSurface memory | 259.8 MiB | 11.2 MiB |

### VM Tracker (one snapshot, most likely the last)

| | |
|---|---|
| Total dirty | 78.8 MiB |
| Instruments' own overhead (`Performance Tool Data`) | 32.6 MiB, to be excluded |
| App's own dirty memory | about 46 MiB |
| Largest app regions | Malloc Small 17.6 MiB, IOSurface 11.2 MiB |

### Reading

- **Repeated decoding is likely.** 971 image reads against 504 loaded photos. If every photo were
  decoded once, the most a grid scroll needs, then at least 467 of the 971 are repeats, less however
  many came from the pager (not marked in this run, so unknown). This is inferred from counts, not
  shown per photo; the Network pass should confirm it with a per-URL request count.
- **Memory does not grow with the number of photos.** Only about 43 images are alive at the end,
  however many were scrolled past. The cost is churn (about 1.1 GiB allocated), not accumulation.
- **Expected effect of the pipeline.** "Persistent bytes" will probably go up, not down, because a
  memory cache keeps decoded images up to its limit. The metrics that should improve are decode count,
  allocated bytes, main-thread decode time and hitches. The README should frame it as a bounded memory
  trade for far fewer decodes.

### Network, from the Simulator (CFNetwork log, not Instruments)

The Network instrument kept crashing, so request counts were taken with
`scripts/count-image-requests.sh`-style CFNetwork diagnostics on an iPhone 18 Pro **Simulator**
(not the iPhone 13 Pro above), fresh install, one run, same `AsyncImage` code. Different device, so
compare the shape, not the absolute numbers, with the Allocations run.

| Step | Photos on screen | Image requests (cumulative) | From network | From `URLCache` |
|---|---|---|---|---|
| Launch (first page) | 1 to 7 visible | 7 | 7 | 0 |
| Scrolled down to photo 159 (171 loaded) | 159 | 159 | 159 | 0 |
| Scrolled back up to photo 76 | 76 | 296 | 163 | 133 |

- **Going down, one request per photo:** 159 requests for 159 photos, none repeated.
- **Coming back, 137 more requests for about 83 photos** (about 1.65 per photo). 133 of them were
  answered by `URLCache`, 4 went to the network. So the download is mostly not repeated, but the app
  asks again each time a cell reappears.
- **This supports the Allocations reading:** `URLCache` is absorbing the downloads, and the decoding is
  what repeats. The Instruments run showed 971 decodes for 504 photos.
- A relaunch without deleting the app was served entirely from `URLCache` (7 of 7 on the first page),
  so a cold run must start from a fresh install.

Caveats: Simulator, one run, and URLs are redacted in the log, so per-URL duplicates could not be
counted; the figures are request totals. The scroll steps were driven by hand-scripted swipes, so
"photos on screen" comes from the HUD, not a controlled script.

### Hitches, Time Profiler and SwiftUI, per phase (device)

| | |
|---|---|
| Device | iPhone 13 Pro, iOS 26.7, launched with `-ProfilingHUD` |
| Run | One run, 57.2 s: Animation Hitches with Time Profiler, SwiftUI and Points of Interest |
| Phases (from the signposts) | 500 loaded at 17.7 s (517 photos, 36 page loads). Pager #1 open 32.2 to 41.5 s, pager #2 open 45.1 to 54.6 s. Each pager has an opening flight (about 0.6 s), a paging period (about 8 s) and a closing flight (about 0.6 s). |

An earlier recording made without signposts showed the same pattern (3 hitches in the first 48 s, then 19 in a burst); this one explains it.

**Hitches**

| Phase | Seconds | Hitches | Total | Hitch time ratio | Worst |
|---|---|---|---|---|---|
| Grid (everything outside the pager) | 38.4 | 5 | 62.5 ms | **1.63 ms/s** | 16.7 ms |
| Pager opening (x2) | 1.2 | 0 | 0 | 0 | 0 |
| **Paging in the pager #1** | 8.1 | 17 | 545.9 ms | **67.4 ms/s** | 66.7 ms |
| **Paging in the pager #2** | 8.4 | 15 | 450.0 ms | **53.8 ms/s** | 75.0 ms |
| Pager closing (x2) | 1.2 | 1 | 16.7 ms | 13.9 ms/s | 16.7 ms |
| Whole run | 57.2 | 38 | 1075.1 ms | **18.8 ms/s** | 75.0 ms |

My recollection of Apple's guidance is under 5 ms/s good, 5 to 10 warning, over 10 critical. The grid is
well inside good. The open and close flights are clean. All of the damage is in paging, at five to
thirteen times the critical line, and it repeats in both pager sessions.

**Time Profiler (1 ms samples, share of main-thread samples with the pattern in the stack)**

| Phase | Main-thread CPU | Offscreen CPU rendering | `CGDrawingLayer` draw | SwiftUI graph update | Image decode | Text glyph drawing |
|---|---|---|---|---|---|---|
| Grid | 214 ms/s | 0.0% | 1.2% | 48.2% | 0.0% | 3.1% |
| Pager opening | 257 ms/s | 0.0% | 0.3% | 62.7% | 0.0% | 1.3% |
| **Paging** | 294 ms/s | **43.6%** | **46.2%** | 37.6% | 0.0% | 12.8% |
| Pager closing | 314 ms/s | 0.0% | 0.0% | 65.0% | 0.0% | 0.0% |

Image decoding never runs on the main thread. It is about half of all background-thread CPU (5.9 s in
this run), which fits `AsyncImage` decoding off the main thread.

**SwiftUI instrument**

- The main thread's time while paging is rendering, not body evaluation: all View Body Updates in the
  paging phases cost 395 ms in total, against 4.8 s of main-thread CPU.
- `PhotoPagerView` body updates: 210 while paging (48 ms in total). `PhotoGridView`, `MasonryColumns`
  and `LibraryView` each re-evaluate 22 times while paging, so the grid underneath the pager is being
  invalidated on page changes.
- `AnimatableAttribute<OpacityRendererEffect>` updates: 4,241 while paging, none worth listing in the
  grid. About 6,000 interpolated styled-text display lists while paging.
- **`PhotoGridCell` body updates: 91 recorded during the whole grid scroll.** I do not trust this count,
  because about 517 photos went by and every cell evaluates its body at least once when it appears. The
  instrument evidently did not record them all. It is not usable as the "cell body updates per page"
  baseline.

**Reading**

- **The hitches are not caused by image loading.** They occur only while swiping inside the pager, and
  decoding is off the main thread throughout. The image pipeline is therefore unlikely to move the
  hitch figures, and the README should not claim that it does.
- **The cause is CPU rendering in SwiftUI.** While paging, 44% of main-thread time is a
  `CGDrawingLayer` redrawing on the CPU: a transparency layer, a colour-matrix filter and text glyphs
  (`RB::DisplayList::Layer::make_cgimage` into `CGContextEndTransparencyLayer`).
- **Which view's layer that is has not been isolated.** Two candidates fit the data:
  1. The pager's chrome: a group `.opacity` over two `.ultraThinMaterial` backgrounds, with caption
     text that changes on every page.
  2. The grid underneath the pager: it is wrapped in an always-applied `.opacity`, and it is changed on
     every page flip (the selected cell flips, and the grid scrolls to it).
  Open and close change the selection once and stay clean, so a per-flip change fits both.

### Not yet measured

- [ ] Network instrument on the device (per-URL duplicates), if it can be made to stop crashing.
- [ ] Values at each milestone (select 0 s to the signpost in Instruments and read Statistics).
- [ ] A trustworthy `PhotoGridCell` body-update count (the SwiftUI instrument recorded 91 for the whole grid scroll, which cannot be complete).
- [ ] Warm run (relaunch without deleting the app).

## Pipeline

To be recorded after step 6, with the same procedure and the same columns.
