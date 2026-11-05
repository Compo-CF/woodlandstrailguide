#!/bin/bash
# Capture App Store screenshots from the simulator (run on the Mac).
#
#   scripts/screenshots.sh setup          boot the sim, build, install, seed coverage
#   scripts/screenshots.sh shot <name>    capture the current screen
#   scripts/screenshots.sh list           show what has been captured
#
# ASC's 6.9" slot wants 1206 x 2622, which is iPhone 16 Pro's native size, so
# `simctl io screenshot` output needs no resizing. Shots land in build/shots/.
#
# setup seeds scripts/screenshot_coverage.json into the app's Documents as
# coverage.json: the coverage map is the feature these screenshots exist to
# show, and a fresh simulator has walked nothing, so without it the headline
# screen photographs as an empty map.
set -euo pipefail

DEVICE="${DEVICE:-iPhone 16 Pro}"
BUNDLE="com.compofelice.WoodlandsTrailGuide"
SCHEME="WoodlandsTrailGuide"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SHOTS="$REPO/build/shots"
EXPECTED_W=1206
EXPECTED_H=2622

fail() { echo "FAILED: $*" >&2; exit 1; }

cmd_setup() {
    xcrun simctl list devices available | grep -q "$DEVICE (" \
        || fail "no simulator named '$DEVICE'. List them with: xcrun simctl list devices available
                 Then re-run with: DEVICE='iPhone 16 Pro Max' scripts/screenshots.sh setup"

    echo "==> Booting $DEVICE"
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    open -a Simulator
    xcrun simctl bootstatus booted -b

    echo "==> Building for the simulator"
    cd "$REPO"
    command -v xcodegen >/dev/null || fail "xcodegen not on PATH. export PATH=\"\$HOME/bin:\$PATH\""
    xcodegen generate
    xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE" \
        -derivedDataPath build/sim -quiet build \
        || fail "simulator build"

    APP="$REPO/build/sim/Build/Products/Debug-iphonesimulator/$SCHEME.app"
    [ -d "$APP" ] || fail "no .app at $APP"

    echo "==> Installing and seeding coverage"
    xcrun simctl install booted "$APP"
    # Launch once so the data container exists, then seed and relaunch --
    # CoverageStore reads coverage.json in init, so seeding a running app
    # would not be picked up.
    xcrun simctl launch booted "$BUNDLE" >/dev/null
    sleep 3
    CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE" data)"
    cp "$REPO/scripts/screenshot_coverage.json" "$CONTAINER/Documents/coverage.json"
    xcrun simctl terminate booted "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch booted "$BUNDLE" >/dev/null

    mkdir -p "$SHOTS"
    cat <<'TIP'

==> Ready.

Set the location before capturing, or the map opens empty:
  Simulator > Features > Location > Custom Location
  Latitude 30.1658   Longitude -95.4613

Then drive the app by hand and capture each screen:
  scripts/screenshots.sh shot 01-your-woodlands
  scripts/screenshots.sh shot 02-coverage-on-map
  scripts/screenshots.sh shot 03-plan-a-walk
  scripts/screenshots.sh shot 04-turn-by-turn
  scripts/screenshots.sh shot 05-amenities
  scripts/screenshots.sh shot 06-trip-stats
TIP
}

cmd_shot() {
    [ $# -ge 1 ] || fail "usage: scripts/screenshots.sh shot <name>"
    mkdir -p "$SHOTS"
    OUT="$SHOTS/$1.png"
    xcrun simctl io booted screenshot "$OUT" >/dev/null 2>&1 || fail "capture (is a simulator booted?)"
    W=$(sips -g pixelWidth  "$OUT" | awk '/pixelWidth/{print $2}')
    H=$(sips -g pixelHeight "$OUT" | awk '/pixelHeight/{print $2}')
    if [ "$W" != "$EXPECTED_W" ] || [ "$H" != "$EXPECTED_H" ]; then
        echo "  WARNING: ${W}x${H}, but ASC's 6.9\" slot wants ${EXPECTED_W}x${EXPECTED_H}."
        echo "           Wrong simulator? Re-run setup with DEVICE='iPhone 16 Pro'."
    fi
    echo "  $1.png  ${W}x${H}"
}

cmd_list() {
    [ -d "$SHOTS" ] || { echo "nothing captured yet"; return; }
    for f in "$SHOTS"/*.png; do
        [ -e "$f" ] || { echo "nothing captured yet"; return; }
        echo "  $(basename "$f")  $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')"
    done
}

case "${1:-}" in
    setup) shift; cmd_setup "$@" ;;
    shot)  shift; cmd_shot "$@" ;;
    list)  shift; cmd_list "$@" ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
esac
