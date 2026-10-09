# Resplash

An iOS 16+ SwiftUI photo library backed by the Unsplash API: endless feed (Unsplash Editorial), full-screen viewer and search.

## Setup

1. Create an app at <https://unsplash.com/oauth/applications> and copy its **Access Key**.
2. `cp Resplash/Config/Secrets.example.xcconfig Resplash/Config/Secrets.xcconfig`, then open it from the `Config` folder in Xcode and paste the key.
3. Open `Resplash.xcodeproj` and run.

`Secrets.xcconfig` is gitignored. The key flows `xcconfig → Info.plist (UnsplashAccessKey) → Config`. Without a key the app shows an in-app message instead of crashing.

## Architecture

_TODO (step 10)_

## Assumptions and limitations

_TODO (step 10)_

## Profiling results

_TODO (step 7)_
