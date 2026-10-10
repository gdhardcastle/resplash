#!/bin/bash
# Records one Instruments trace of the scenario.
#
#   docs/perf/profile.sh <device id> <loader|baseline> "<template>" [output dir]
#
# Templates: "Time Profiler", "Allocations", "Animation Hitches", "SwiftUI".
# The UI test drives the app and Instruments records it; the recording stops when the app exits.
# Builds Release, so the figures are of the shipped code, not the debug build.
set -euo pipefail

DEVICE=${1:?device id (xcrun xctrace list devices)}
MODE=${2:?loader or baseline}
TEMPLATE=${3:?template name}
OUT=${4:-perf-traces}

case "$MODE" in
  loader) TEST_CLASS=ImageLoaderScenarioTests ;;
  baseline) TEST_CLASS=AsyncImageBaselineScenarioTests ;;
  *) echo "mode must be loader or baseline" >&2; exit 1 ;;
esac

# The Animation Hitches and SwiftUI templates do not include Points of Interest, which is where the app
# marks the phase boundaries, so add it to them.
EXTRA_INSTRUMENTS=()
case "$TEMPLATE" in
  "Animation Hitches"|"SwiftUI") EXTRA_INSTRUMENTS=(--instrument "Points of Interest") ;;
esac

mkdir -p "$OUT"
TRACE="$OUT/$MODE-$(echo "$TEMPLATE" | tr ' ' '-').trace"
rm -rf "$TRACE"

COMMON=(-project Resplash.xcodeproj -scheme Resplash -configuration Release -destination "id=$DEVICE"
        -parallel-testing-enabled NO "-only-testing:ResplashUITests/$TEST_CLASS" ENABLE_TESTABILITY=YES)
APP_ARGS=(-perf -perf-cold)
[ "$MODE" = baseline ] && APP_ARGS+=(-perf-baseline)

IS_PHYSICAL=false
if xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -q physical; then IS_PHYSICAL=true; fi

if $IS_PHYSICAL; then
  # xctrace cannot attach to an app on a device, only launch it. So: build and install, start the test
  # (which waits for the app), then have xctrace launch the app with its arguments and record it. The
  # test drives that app and ends it, which ends the recording.
  echo "Building..."
  xcodebuild build-for-testing "${COMMON[@]}" > "$OUT/$MODE.build.log" 2>&1
  TEST_RUNNER_PERF_ATTACH=1 xcodebuild test-without-building "${COMMON[@]}" > "$OUT/$MODE.xcodebuild.log" 2>&1 &
  XCODEBUILD=$!

  echo "Waiting for the test runner to start on the device..."
  for _ in $(seq 1 300); do
    xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null | grep -q ResplashUITests-Runner && break
    kill -0 "$XCODEBUILD" 2>/dev/null || { echo "xcodebuild exited early: see $OUT/$MODE.xcodebuild.log" >&2; exit 1; }
    sleep 1
  done

  echo "Recording..."
  xcrun xctrace record --template "$TEMPLATE" ${EXTRA_INSTRUMENTS[@]+"${EXTRA_INSTRUMENTS[@]}"} --device "$DEVICE" --time-limit 6m \
    --output "$TRACE" --no-prompt --launch -- com.georgehardcastle.Resplash "${APP_ARGS[@]}" \
    > "$OUT/$MODE.xctrace.log" 2>&1 || true
else
  # A simulator lets xctrace attach to the app by name once the test has launched it.
  xcodebuild test "${COMMON[@]}" > "$OUT/$MODE.xcodebuild.log" 2>&1 &
  XCODEBUILD=$!
  echo "Waiting for the app to launch (the build comes first)..."
  for _ in $(seq 1 900); do
    if xcrun xctrace record --template "$TEMPLATE" ${EXTRA_INSTRUMENTS[@]+"${EXTRA_INSTRUMENTS[@]}"} --device "$DEVICE" --attach Resplash \
        --time-limit 6m --output "$TRACE" --no-prompt >> "$OUT/$MODE.xctrace.log" 2>&1; then
      break
    fi
    kill -0 "$XCODEBUILD" 2>/dev/null || { echo "xcodebuild exited before the app was recorded" >&2; break; }
    sleep 1
  done
fi

wait "$XCODEBUILD" || true
grep -aE "Test Case.*(passed|failed)|^PERF|^  [123] |^  total" "$OUT/$MODE.xcodebuild.log" || true
if [ -d "$TRACE" ]; then echo "Trace: $TRACE"; else echo "No trace was recorded: see $OUT/$MODE.xctrace.log" >&2; exit 1; fi
