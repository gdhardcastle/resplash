# Resplash

An iOS 16+ SwiftUI image gallery backed by the Unsplash API: endless Editorial feed, full-screen viewer and search.

## Setup

1. Create an app at <https://unsplash.com/oauth/applications> and copy its **Access Key**.
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and paste the key.
3. Open `Resplash.xcodeproj` and run.

`Secrets.xcconfig` is gitignored. The key flows `xcconfig → Info.plist (UnsplashAccessKey) → Config`. Without a key the app shows an in-app message instead of crashing.

## Architecture

_TODO (step 10)_

## Assumptions and limitations

_TODO (step 10)_

## Profiling results

_TODO (step 7)_
