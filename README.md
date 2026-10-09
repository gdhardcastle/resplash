# Resplash

An iOS 16+ SwiftUI photo library backed by the Unsplash API: an endless masonry grid of the Editorial feed, a full-screen pager with a hero transition, and search that reuses the same grid.

## Setup

1. Create an app at <https://unsplash.com/oauth/applications> and copy its **Access Key**.
2. `cp Resplash/Config/Secrets.example.xcconfig Resplash/Config/Secrets.xcconfig`, then open it from the `Config` folder in Xcode and paste the key.
3. Open `Resplash.xcodeproj` and run.

`Secrets.xcconfig` is gitignored. The key flows `xcconfig → Info.plist (UnsplashAccessKey) → Config`. Without a key the app shows an in-app message instead of crashing.

## Architecture

Feature-based MVVM with a repository, and no use-case layer: there is no business logic to put in one. Everything points toward `PhotoDomain`.

```
Views → ViewModels → PhotoDomain (Photo, PhotoRepository) ← PhotoData (API, DTOs, mapper)
                                                         ← ImageData  (image loader and caches)
```

| Folder | Contents |
|---|---|
| `PhotoDomain` | `Photo`, `Page`, `PhotoSource`, the `PhotoRepository` protocol. Depends on nothing. |
| `PhotoData`, `HTTPClient` | Unsplash endpoints, DTOs, the mapper (`alt_description` → `description` → placeholder), error and rate-limit mapping. |
| `ImageData`, `RemoteImage` | The image pipeline and the SwiftUI view that uses it. |
| `LibraryFeature` | The screen: grid, pager, search. |
| `Config` | Reads the access key. The composition root in `ResplashApp` is the only place that knows concrete types. |

- **State:** `ObservableObject` and `@Published`, because `@Observable` needs iOS 17. View models are `@MainActor`, with async/await.
- **One grid view model per source.** `PhotoGridViewModel` owns paging (state enum, generation token so a stale response never lands in a newer list, an in-flight guard, de-duplication by photo ID, a footer retry for failed later pages). `LibraryViewModel` keeps a list view model for the whole session and makes a fresh one per search, so clearing a search returns to the list instantly with its scroll position and no requests. Search is debounced by 350 ms.
- **Cells take values, not view models.** `PhotoGridCell` is `Equatable`, so one change does not re-render every cell. Layout is reserved from each photo's aspect ratio, with its dominant colour as the placeholder.
- **Hero transition.** `matchedGeometryEffect` between grid cell and pager page, in an overlay rather than a navigation push (the zoom transition needs iOS 18). The pager is hand-rolled rather than `TabView(.page)`, which ignores SwiftUI transactions and so cannot fly the selected photo in. It owns its current page, so paging does not re-evaluate the grid underneath; the grid is scrolled to the page after a pause, and its cell swaps its image only when the pager closes.

### Image pipeline

`ImageLoader` is an actor behind a protocol. A request looks in the decoded **memory cache** (`NSCache`, bounded by bytes), then joins any **download already in flight** for the same request, then reads the **disk cache** (files keyed by URL hash, least recently used evicted), then goes to the network. Images are decoded and downsampled with ImageIO off the main thread.

- **De-duplication:** requests for one image share one load.
- **Cancellation is reference-counted.** A cell scrolling away cancels the load only when no other request is waiting on it.
- **Prefetching:** the grid asks for the next 8 thumbnails as cells appear and the pager for the pages two away. Each call replaces the previous window and cancels loads that fell out of it.
- **No second cache:** the loader's session has no `URLCache`, so nothing is stored twice.
- **Counters:** `ImagePipelineStats` counts how each request was served (memory, joined, disk, download, decode, cancelled) and writes each as a Points of Interest event, so a recording shows the cache hit rate and downloads per URL.

## Performance

Measured with Instruments on an iPhone 13 Pro (120 Hz), Release build: scroll to about 500 photos, back to photo 100, then open the pager and swipe through it. **Baseline** is plain `AsyncImage`.

**Result:** paging hitch time fell from about 60 to 4 ms/s, decoded-image memory is capped, and each photo is downloaded once (except cancelled loads that restart), at the cost of about three times the baseline's memory.

| Criterion | Result | Evidence |
|---|---|---|
| After several hundred images | Decoded-image memory is capped by design; app memory was 134 and 139 MiB at the end of two runs of 506 photos (baseline 46 MiB) | Allocations and VM Tracker; cache limit 100 MB |
| Efficient loading, no duplicated work | Warm start downloads nothing; cold start about 1.14 downloads per photo; decodes 869 and 894 (baseline 971) | The loader's counters: 563 downloads for 494 URLs, the extra 12% being cancelled loads that restarted |
| Unnecessary SwiftUI updates | Grid updates while paging about 3,400/s before the pager owned its page, about 500/s now; paging hitch time 67 and 54 → 4 ms/s | SwiftUI instrument and Animation Hitches |
| CPU and memory in Instruments | CPU rendering while paging 44% → 0%; main-thread CPU while paging 294 → 142 ms/s | Time Profiler; Allocations and VM Tracker |

| Problem found | Fix | Effect |
|---|---|---|
| Caption text animated on every page and was drawn on the CPU | No animation on that bar | CPU rendering 44% → 0% |
| Every page flip re-evaluated the grid under the pager | The pager owns its current page | Hitch time 56 and 84 → 41 ms/s |
| Syncing the grid through `@State` re-ran the whole screen | Scroll it through a plain reference | 24 → 4 ms/s |

**Trade-off:** the 100 MB memory cache holds about 140 thumbnails, and the scroll back from 500 to 100 passes about 400, so roughly 60% of that trip is decoded again from disk. I chose bounded memory over fewer decodes: decoding is off the main thread and did not cause late frames, while memory growth risks the app being killed in the background.

**Not shown:** the loader's effect on hitches (it landed in a recording of a different length), and a Time Profiler comparison of the grid scroll. Each figure is from one recording, with the scrolling done by hand.

## Tests

Unit tests cover the mapper and its fallbacks, the repository's error and rate-limit mapping, grid pagination and stale-response handling, search debounce, and the image loader (shared downloads, reference-counted cancellation, memory and disk hits, prefetch replacement, downsampling). The UI test target is Xcode's template and tests nothing.

## Assumptions and limitations

- **The access key is kept out of git, but it is not secret.** `Secrets.xcconfig` is gitignored and not in the app target, but its value is substituted into `Info.plist` at build time, so it ships in the app bundle. A production app would proxy through a backend.
- **Rate limit:** demo keys are limited per hour. The app shows a rate-limit state on a 403 with no remaining requests; that is covered by unit tests but not exercised against the live limit.
- **No offline mode.** Images are disk-cached, but the feed is not persisted, so a cold start without a network shows the error state.
- **Cancellation costs some downloads:** in the cold run 69 URLs were downloaded twice, about 12% extra, apparently loads cancelled and later requested again. The cause is not isolated.
- **Measurements are one recording per state on one device, with the scrolling done by hand.** Small differences are within noise; the paging figures are the only ones I would call a clear trend.
- **Attribution:** photographer links carry the Unsplash referral parameters; I have not checked the full attribution guidelines.
