# Profiling runbook: baseline (`AsyncImage`) vs image pipeline

Run the same procedure twice: once on the `baseline-asyncimage` tag, and again after the image
pipeline lands. Change one thing between runs: how images are loaded.

## 0. Before you start

| Item | Setting |
|---|---|
| Baseline | Check out the `baseline-asyncimage` tag (or `main` at that commit). |
| Device | A physical iPhone, the same one for both runs. Hitches are not meaningful on the simulator. |
| Scheme | The shared `Resplash` scheme passes `-ProfilingHUD` on its **Profile** action only, so Product → Profile (⌘I) shows the HUD and a normal Run (⌘R) does not. |
| Build | Product → Profile (⌘I). It builds **Release**. `Resplash/Config/Secrets.xcconfig` must be present. |
| Conditions | Low Power Mode off, same Wi-Fi, other apps closed, auto-lock off, device cool. |
| API quota | About 500 photos is about 17 list requests (30 per page). The demo limit is believed to be 50 requests per hour (confirm in the Unsplash dashboard), so do at most two runs per hour. Image downloads come from the CDN and do not count. |
| Trace files | Save `.trace` files outside version control (`*.trace` is gitignored). Only the results table is committed, in the README. |

### The HUD

With `-ProfilingHUD` (set by the scheme's Profile action) a small overlay appears at the top left of the Library:

- `Loaded N/500`: photos loaded so far.
- `Photo K/100`: 1-based position of the photo whose cell most recently appeared, roughly where the
  scroll is.

Each line turns green with a ✓ when it reaches its milestone, and a haptic fires at that moment so you
can watch Instruments instead of the phone. The photo line is live, so it goes grey again if you scroll
back above 100. Loading is in pages of 30, so `Loaded` crosses 500 at 510.

Without the argument (a normal Run) nothing is shown. The HUD is not observable by the grid, so it does not add view
updates to the numbers being measured.

## 1. The scroll script (identical every run)

1. **Cold start.** Delete the app, reinstall via Profile, wait for the first page.
2. **Phase A, forward.** Scroll down at a steady pace until `Loaded` shows ✓ (about 17 pages).
3. **Phase B, back to top.** Scroll back up to the top. This tests whether images come back without
   reloading.
4. **Phase C, pager.** Scroll down until `Photo` shows ✓ (photo 100), open that photo, swipe 10 pages
   forward, then close. This tests the grid flicker on return and the pager's own loading.
5. **Warm run (optional).** Relaunch without deleting and repeat phase A. This shows the on-disk cache
   effect.

## 2. Instruments passes

One trace per template, each running the full script.

| Template | Record | Where to find it |
|---|---|---|
| **Network** (HTTP Traffic) | Total image requests, unique URLs, **duplicate count** (target 0) | Group requests by URL and compare total with unique. |
| **Allocations** | **Persistent Bytes** at the end of A, B and C (use *Mark Generation* after each phase); note ImageIO and CG raster rows | Statistics view. |
| **Animation Hitches** | Hitch count and hitch time ratio (ms per second) per phase | Phase A matters most. |
| **Time Profiler** | % of main-thread time in image decoding (ImageIO, CGImageSource) | Select the main thread, invert the call tree, hide system libraries. |
| **SwiftUI** | `PhotoGridCell` body updates per page load | The SwiftUI instrument's view body updates, filtered by cell type. |

## 3. Results

One column per run.

| Metric | Baseline (cold) | Baseline (warm) | Pipeline (cold) | Pipeline (warm) |
|---|---|---|---|---|
| Image requests / unique / duplicates | | | | |
| Persistent bytes after A / B / C | | | | |
| Hitch count (A) / hitch ratio | | | | |
| Main-thread decode % | | | | |
| Cell body updates per page | | | | |

## 4. Also note, whatever the numbers say

- **Variance.** With the quota you may only get one cold run per configuration. Say so rather than
  implying a statistical result.
- **Pager flicker.** Does the grid image visibly reload when the pager closes? It is not a number, but
  it is the clearest before and after.
- **`URLCache`.** `AsyncImage` has no cache of its own; it relies on `URLCache.shared` (small default
  limits) and decodes each time. If the baseline shows it doing more than expected, record that.
- **Anything surprising.**
