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

### Not yet measured

- [ ] **Network:** total image requests, unique URLs, duplicate count (to confirm the repeat-decoding
  reading above). The Network instrument has been crashing; to be retried with a launched recording.
- [ ] Values at each milestone (select 0 s to the signpost in Instruments and read Statistics).
- [ ] Animation Hitches and hitch time ratio.
- [ ] Time Profiler: share of main-thread time spent decoding.
- [ ] SwiftUI instrument: `PhotoGridCell` body updates per page.
- [ ] Warm run (relaunch without deleting the app).
- [ ] Pager phase, with its own marker.

## Pipeline

To be recorded after step 6, with the same procedure and the same columns.
