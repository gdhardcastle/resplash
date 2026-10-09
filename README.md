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

Measured with Instruments on an iPhone 13 Pro (120 Hz, Release build): Animation Hitches, Time Profiler, SwiftUI and Allocations. Each recording scrolled to about 500 photos, back to photo 100, then opened the pager and swiped through it. The plain-`AsyncImage` baseline is the same code before the image pipeline.

| | `AsyncImage` baseline | Final |
|---|---|---|
| Hitch time while paging in the pager | 67 and 54 ms/s (two sessions) | **4 ms/s** |
| Main-thread CPU rendering while paging | 44% of samples | **0%** |
| Hitch time scrolling the grid | 1.6 ms/s | not re-measured |
| Image decodes for 506 photos (scroll to 500 and back) | 971 | 869 cold, 894 warm |
| App memory at the end | 46 MiB | 134 to 139 MiB |
| Downloads, cold start | not counted on device | 563 for 494 URLs |
| Downloads, warm start (disk cache) | not counted on device | 0 |

What the profiling found, in the order it was fixed:

1. **The caption bar's text animated on every page change** and was drawn on the CPU. One modifier removed the CPU rendering; the hitches stayed.
2. **Every page flip re-evaluated the grid underneath the pager**, because the selection lived in the screen. Keeping the page inside the pager cut paging hitch time from 56 and 84 ms/s (two sessions) to 41.
3. **Syncing the grid by changing `@State` re-ran the whole screen.** Scrolling it directly through a small reference type took paging from 24 to 4 ms/s. Grid updates while paging fell from about 2,150 to 490 a second.
4. **The image loader** landed between a 35 and a 24 ms/s recording, but those runs differ in length, so its effect on hitches is not isolated. Decoding was already off the main thread. What it adds is de-duplication, cancellation, a disk cache and the counters.

The memory cache is bounded at 100 MB, about 140 thumbnails. The scroll back from 500 to 100 passes about 400, so roughly 60% of that trip is decoded again from disk. I chose bounded memory over fewer decodes: decoding is off the main thread and did not cause late frames, while memory growth risks the app being killed in the background.

## Tests

Unit tests cover the mapper and its fallbacks, the repository's error and rate-limit mapping, grid pagination and stale-response handling, search debounce, and the image loader (shared downloads, reference-counted cancellation, memory and disk hits, prefetch replacement, downsampling). The UI test target is Xcode's template and tests nothing.

## Assumptions and limitations

- **The access key ships in the app bundle, so it is not secret.** A production app would proxy through a backend.
- **Rate limit:** demo keys are limited per hour. The app shows a rate-limit state on a 403 with no remaining requests; that is covered by unit tests but not exercised against the live limit.
- **No offline mode.** Images are disk-cached, but the feed is not persisted, so a cold start without a network shows the error state.
- **Cancellation costs some downloads:** in the cold run 69 URLs were downloaded twice, about 12% extra, apparently loads cancelled and later requested again. The cause is not isolated.
- **Measurements are one recording per state on one device, with the scrolling done by hand.** Small differences are within noise; the paging figures are the only ones I would call a clear trend.
- **Attribution:** photographer links carry the Unsplash referral parameters; I have not checked the full attribution guidelines.
