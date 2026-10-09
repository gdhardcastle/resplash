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

### Animation Hitches and Time Profiler (device, whole run)

| | |
|---|---|
| Device | iPhone 13 Pro, iOS 26.7, launched with `-ProfilingHUD` |
| Run | One run, 60.1 s, Animation Hitches template with Time Profiler (1 ms sampling) |
| Not in this trace | **Points of Interest signposts** (the template does not include them, so the phases cannot be isolated) and the **SwiftUI instrument** |

**Hitches**

| Window | Hitches | Total | Hitch time ratio | Worst |
|---|---|---|---|---|
| Whole run (60.1 s) | 22 | 495.9 ms | **8.25 ms/s** | 50.0 ms |
| 0 to 48 s | 3 | 37.5 ms | 0.78 ms/s | 12.5 ms |
| 48 to 58 s | 19 | 458.4 ms | 45.84 ms/s | 50.0 ms |

Almost all of the hitching is in one burst. The first 48 s, which must be the grid scrolling, had three
12.5 ms hitches. From 48 s there are 19, up to 50 ms. Instruments flags most of the burst as
"Potentially expensive app update(s)". My recollection of Apple's guidance is under 5 ms/s good, 5 to
10 warning, over 10 critical, which puts the whole run at warning and the burst well into critical.
The window boundary was read off the hitch timestamps, not from markers.

**Time Profiler (1 ms samples)**

| | Whole run | 0 to 48 s | 48 to 58 s |
|---|---|---|---|
| Main-thread CPU | 15.7 s (261 ms per second) | 13.0 s | 2.7 s |
| Main thread: image decode (ImageIO / JPEG frames in the stack) | 0.6% | 0.1% | 3.2% |
| Main thread: SwiftUI offscreen CPU rendering | 7.0% | 0.0% | **41.4%** |
| Main thread: SwiftUI graph update (`AG::`) | 53.5% | 55.7% | 43.3% |
| Background threads: image decode | 52.4% | 54.3% | 36.0% |

- **Image decoding is not on the main thread.** It is about 0.6% of main-thread samples. It happens on
  background threads (about 3.6 s of CPU, more than half of all background work), which fits `AsyncImage`
  decoding off the main thread. So the 971 decodes cost CPU and energy but are not what drops frames.
- **The hitch burst is SwiftUI's CPU renderer.** In that window 41% of main-thread samples are in
  `RB::DisplayList::Layer::make_cgimage` into `CGContextEndTransparencyLayer` and
  `RIPLayerBltImage`, with `argb32_image_mark_argb32` and vImage blends as the top self frames: offscreen
  layers being rasterised on the CPU. That is about 1.1 s of the window's 2.7 s.
- **What was happening at 48 s is not recorded.** My reading is that the burst is the pager (the end of
  the run's sequence, and a view with an opacity transition, materials and a scale effect), but this is
  an inference. It needs the `Pager open` intervals to confirm.

### Not yet measured

- [ ] Network instrument on the device (per-URL duplicates), if it can be made to stop crashing.
- [ ] Values at each milestone (select 0 s to the signpost in Instruments and read Statistics).
- [ ] SwiftUI instrument: `PhotoGridCell` body updates per page (was not in the hitches trace).
- [ ] Hitches and Time Profiler **per phase**: re-record with Points of Interest added so the pager can be isolated.
- [ ] Warm run (relaunch without deleting the app).
- [ ] Pager phase (now marked in the trace by the `Pager open` / `opening` / `closing` intervals).

## Pipeline

To be recorded after step 6, with the same procedure and the same columns.
