#!/bin/bash
# Counts the app's image requests on a booted iOS Simulator, split into network loads and cache hits.
#
# Why this exists: Instruments' Network template can be unreliable, and AsyncImage's downloads bypass
# URLProtocol and URLCache.shared, so the app cannot count them itself. CFNetwork's own diagnostics log
# does see them, one entry per request with what the loader decided ("originload" = network, "use cached
# response" = URLCache).
#
# Usage: scripts/count-image-requests.sh [seconds]
#   Reinstalls nothing: delete the app first (xcrun simctl uninstall booted <bundle id>) for a cold run.
#   With no argument it runs until Ctrl-C, printing running totals every 2 s.
#
# Limits: Simulator only. URLs are redacted in the log, so it cannot say which URLs repeat, only how many
# requests there were and how each was served. Compare the count against photos seen on screen.
set -u

BUNDLE_ID="${BUNDLE_ID:-com.georgehardcastle.Resplash}"
DEVICE="${DEVICE:-booted}"
LIMIT="${1:-}"
LOG="$(mktemp -t image-requests)"

cleanup() {
    [ -n "${STREAM_PID:-}" ] && kill "$STREAM_PID" 2>/dev/null
    summary
    rm -f "$LOG"
}
summary() {
    local total cache network
    total=$(grep -c 'Request: https://images.unsplash.com' "$LOG")
    cache=$(grep -A3 'Request: https://images.unsplash.com' "$LOG" | grep -c 'use cached response')
    network=$(grep -A3 'Request: https://images.unsplash.com' "$LOG" | grep -c 'originload')
    printf 'image requests: %d   from cache: %d   from network: %d\n' "$total" "$cache" "$network"
}
trap 'cleanup; exit 0' INT TERM

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null
xcrun simctl spawn "$DEVICE" log stream --style compact --process Resplash >"$LOG" 2>&1 &
STREAM_PID=$!
sleep 2

SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3 xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -ProfilingHUD >/dev/null
echo "Launched. Scroll the app; totals update every 2 s. Ctrl-C to stop."

elapsed=0
while [ -z "$LIMIT" ] || [ "$elapsed" -lt "$LIMIT" ]; do
    sleep 2
    elapsed=$((elapsed + 2))
    printf '%3ds  ' "$elapsed"
    summary
done
cleanup
