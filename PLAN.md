# iOS Tech Challenge: Plan and Execution Order

Context file for Claude Code. It captures the challenge brief, the architecture decisions made so far, and the execution order. Use it as the source of truth when working through individual steps.

---

## 1. Challenge brief (summary)

**Goal:** Build an iOS image gallery app using the Unsplash API: an endless-scroll grid of the Editorial feed, a full-screen image view, and search.

**Logistics**
- Duration: 48-72 hours (early submission possible).
- Submission: zip or GitHub repo link, plus **one Loom recording (max 3 minutes, in English)** showing the working solution and explaining the main technical choices, with a focus on the code. Mention assumptions and limitations.
- Do not use "BeReal" or "Voodoo" names in public repositories.

**Technical requirements**
- Swift and SwiftUI (UIKit allowed only if justified).
- Minimum iOS version: **iOS 16**.
- Data source: Unsplash API. Images must be fetched from the API, not bundled.
- The Unsplash Access Key must be supplied through local configuration or another environment-specific mechanism (no hardcoding).
- External libraries allowed only if they don't implement the core feature. Justify choices. If using an image-loading library, explain what it provides and how it is configured.

**Required features**
1. **Main feed:** 2 or 3 column grid. Each cell shows the image and a short description (`alt_description`, falling back to `description`, then to a sensible placeholder). Endless scroll. Smooth, no stutter or visible loading delays.
2. **Full screen view:** tap an image to view it full screen, with a beautiful way back to the gallery.
3. **Search:** search photos. Results use the same grid and endless scroll. Transition between Editorial and search results should be intuitive and seamless.

**Evaluation criteria**
- *Architecture and code quality:* clear structure, separation of concerns, readability.
- *User experience:* scroll smoothness, responsiveness, elegant loading states.
- *Performance:* behaviour after scrolling several hundred images, efficient image loading with no duplicated work, avoiding unnecessary SwiftUI view updates, **profiling with Instruments (CPU and memory)**.

**Bonus (not required)**
- Advanced image pipeline: prefetching, request cancellation, request deduplication, memory-aware and/or disk caching. Document the design and measure impact with Instruments. A library's default behaviour alone does not count.
- Unit and/or UI tests.
- Offline mode: persist metadata and cached images, with graceful network error handling.
- Advanced animations between grid and full screen.

---

## 2. Architecture

**Pattern:** Feature-based MVVM with a repository layer, inspired by Clean Architecture's dependency rule but **without a use-case layer** (there is no business logic to justify one; it would be a one-line pass-through).

**Dependency direction:** everything points toward **Domain**.

```
Views --> ViewModels --> Domain (Photo, PhotoRepository protocol) <-- Data (UnsplashPhotoRepository, API, DTOs, caches)
 presentation (outer)        centre                                     infrastructure (outer)
```

- Domain depends on nothing.
- Presentation (views, view models) depends on Domain.
- Data (networking, DTOs, persistence) depends on Domain: the concrete repository implements the protocol and maps DTOs into `Photo`.
- Only the composition root knows concrete types.

**Suggested structure**

```
App/                  entry point, composition root
Domain/               Photo, Page<T>, PhotoSource, PhotoRepository (protocol)
Data/
  Networking/         HTTPClient, Endpoint, UnsplashAPI, DTOs, mapper
  Persistence/        (optional) offline store
  ImagePipeline/      ImageLoader (actor), memory cache, disk cache, downsampler
Core/Config/          Config (key lookup)
Features/
  Gallery/            GalleryView, PhotoGridCell, PhotoListViewModel
  Search/             search UI, reuses the grid
  Detail/             FullScreenView, transition code
```

Optional extra signal: split into local Swift packages (`Domain`, `Networking`, `ImagePipeline`, `Features`) so the compiler enforces the layering.

---

## 3. Key decisions

### Unsplash key handling
- Gitignored `Secrets.xcconfig` with `UNSPLASH_ACCESS_KEY = ...`, plus a committed `Secrets.example.xcconfig` with a placeholder.
- Set as the base configuration for Debug and Release. Info.plist key `UnsplashAccessKey = $(UNSPLASH_ACCESS_KEY)`. Read via a small `Config` type.
- Missing key shows a friendly in-app error pointing to the README (not a crash). A Keychain entry screen is optional, only if time allows.
- Send as `Authorization: Client-ID <key>` header, not a query parameter.
- Prefer a GitHub link plus the example file over a zip. If zipping, decide deliberately whether the key is included (and revoke afterwards if so).
- Never commit the key to git history; regenerate if it happens.
- Loom point: a key shipped in an app bundle is never truly secret. In production, proxy through a backend.

### State management (iOS 16)
- `@Observable` is iOS 17+, so it is **not available**. Use `ObservableObject` + `@Published`.
- View models are `@MainActor`, owned with `@StateObject` (not `@ObservedObject`). Async/await rather than Combine pipelines.
- State enum: `idle`, `loadingFirstPage`, `loaded`, `failed`.
- Keep view models small and scoped. Cells take value-type inputs (small `Equatable` views), not the view model, so one `@Published` change doesn't re-render every cell.
- Skip TCA (too heavy to defend in 3 minutes) and swift-perception (extra surface area).
- Loom one-liner: "I used `ObservableObject` because `@Observable` requires iOS 17; on a newer target I'd migrate for finer-grained updates."

### Feed and search view model
- One `PhotoListViewModel` class parameterised by `enum PhotoSource { case editorial; case search(String) }`.
- **Two instances**: a persistent feed VM and a search VM. The view shows `query.isEmpty ? feedVM : searchVM`. Clearing search switches back instantly, keeps scroll position and saves API calls.
- Pagination safeguards:
  - Generation token plus `Task.isCancelled` checks so stale responses never land in a newer list.
  - `loadTask == nil` as the in-flight guard (lazy grid `onAppear` fires repeatedly).
  - Dedupe by photo ID when appending (pages can overlap).
  - Prefetch threshold check with `photos.suffix(threshold)` (O(threshold), not O(n)).
  - Footer error with retry for failed later pages. Only a first-page failure gets a full-screen error.
  - Cancelled requests throw `URLError.cancelled`, so check `Task.isCancelled` rather than the error type.
  - End of feed: search responses include `total_pages`. The editorial list may not, so treat a short or empty page as the end (verify against the docs).
- Search debounce (~350ms) lives in the view via `.task(id: query)` with `Task.sleep`, cancelled automatically on change.
- Fallback mapping (`alt_description` -> `description` -> placeholder) happens in the DTO-to-domain mapper, not in the view. `Photo` is `Identifiable`, `Equatable`, `Sendable` with a stable ID.

### Layout stability
- Reserve aspect ratio from `width`/`height`.
- Use the photo `color` (or `blur_hash`) as an instant placeholder.

### Full-screen view
- `matchedGeometryEffect` with a shared namespace and an overlay (not a `NavigationLink` push). The iOS 18 zoom transition is not available on iOS 16. This doubles as the advanced animations bonus.
- Show the already-cached grid image instantly, then swap in the `regular` size once loaded.
- Include photographer attribution with a link (Unsplash API guidelines, verify the exact requirements).

### Image pipeline (the main differentiator)
- `actor ImageLoader` behind a protocol.
- Request/cache key: `ImageRequest { url, maxPixelSize }`.
- Use `urls.small` (~400px) for grid cells and `urls.regular` (~1080px) for full screen. Never download `full`/`raw` and shrink locally.
- Lookup order: `NSCache` (set `totalCostLimit`, cost = width x height x 4) -> in-flight dictionary (dedup) -> disk cache (file store keyed by URL hash, LRU eviction) -> network (write encoded bytes to disk) -> ImageIO downsampling (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceShouldCacheImmediately: true`) so decoding happens off the main thread.
- **Ref-counted cancellation:** several cells may await the same download, so one cell cancelling must not kill it. Track `waiters` per in-flight entry and cancel the underlying task only when the count reaches 0. Test this explicitly.
- Cell integration: `.task(id: request)` gives cancel-on-scroll-away for free.
- Memory gotcha to verify in Allocations: lazy grids on iOS 16 may keep views alive off-screen. If each cell holds a decoded `UIImage` in `@State`, it bypasses the `NSCache` budget. Mitigate by nil-ing state in `onDisappear` and reloading from the memory cache.
- Prefetching: no SwiftUI prefetch API on iOS 16. When cell `i` appears, prefetch `i+1...i+8` as cancellable low-priority tasks. (UIKit `UICollectionView` prefetching is the alternative, but would need justification.)

### Offline mode (optional)
- Persistence sits behind the repository so view models never know whether data came from network or disk.
- SwiftData is iOS 17+, so use Core Data or a simple JSON file of the first few pages, plus the disk image cache.

### Testing
- Mock repository and mock image loader make these cheap to test: pagination, search cancellation and stale-response handling, mapper fallbacks, and ref-counted cancellation in the loader.

---

## 4. Risks and constraints

- **Rate limit:** demo-tier keys are limited (believed to be 50 requests/hour; confirm in the Unsplash dashboard). Debounce search, dedupe requests, cache responses, and show a clear rate-limit error state (403) rather than a blank screen. Repeated debug runs burn through the quota quickly.
- **Loom is 3 minutes max.** Cover: architecture and dependency direction, why `ObservableObject`, the image pipeline and measured impact, assumptions and limitations (key handling, rate limits, no use-case layer).

---

## 5. Execution order

1. **Project setup:** repo, `.gitignore`, xcconfig and `Config`, folder or package structure, README skeleton.
2. **Domain and networking:** `Photo`, `PhotoRepository`, DTOs, mapper, HTTP client, Unsplash endpoints (editorial list and search), error and rate-limit handling.
3. **Feed view model and grid:** pagination logic, 2-column grid, aspect-ratio placeholders, loading, error and empty states. Use plain `AsyncImage` for now, which doubles as the **baseline for profiling**.
4. **Full-screen view:** matched-geometry transition, dismiss gesture, attribution.
5. **Search:** second view model instance, `.searchable` with debounce, feed-to-search switching.
6. **Image pipeline:** `ImageLoader` actor, memory then disk cache, dedup, ref-counted cancellation, downsampling, prefetching. Swap it in for `AsyncImage`.
7. **Profiling:** Instruments passes at ~500 images, before vs after, recorded in a table for the README:
   - Network: duplicate request count (target zero).
   - Allocations: persistent bytes, with and without downsampling.
   - Animation Hitches / Time Profiler: hitch counts and main-thread decode time.
   - SwiftUI instrument: cell `body` evaluations per page load.
8. **Tests:** view model pagination, stale-search handling, mapper fallbacks, loader ref-counted cancellation.
9. **Offline mode (only if time allows):** persist early pages behind the repository, reuse the disk image cache.
10. **Wrap-up:** README (setup, architecture, assumptions and limitations, measurements), then the Loom.

### Time guardrails
- Steps 1-5 produce a complete, submittable app. Protect them first.
- Step 6 is the biggest differentiator. Don't leave it until the last hours.
- If time gets tight, cut offline mode first, then test breadth. **Never cut profiling or the README.**
- Draft the Loom outline as you go so recording is quick.

---

## 6. Open items to verify against Unsplash docs
- Current demo-tier rate limit.
- Whether the editorial list endpoint exposes total pages or needs an empty-page end check.
- Exact attribution requirements for displaying photos.
- Which `urls.*` sizes best fit grid cells on 2x and 3x devices.
