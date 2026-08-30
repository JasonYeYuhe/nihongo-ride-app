#!/usr/bin/env bash
#
# Run the iOS placement UI tests (Tests/NihongoRideiOSUITests/PaidRouteRowTests).
#
# WHY THIS EXISTS AS A SCRIPT
# ---------------------------
# Because the tests were written, were correct, and were never run — and the one thing they
# guarded shipped broken. `testAnOwnedDeviceStillSeesTheRowAndStillHasRestore` asserts that an
# owner can still reach Restore Purchases (App Review 3.1.1); the first version of `RoadView`
# rendered the offer card — which contained the only Restore control — solely `if !entitled`.
# The test named the defect exactly and said nothing, because nothing invoked it.
#
# Proven to fire: reintroducing that arrangement in a copy makes this suite exit 65.
#
# Copies the tree first, for the reasons in `run_store_gates.sh`: `com.apple.provenance`, and
# `xcodebuild` hanging in-place whenever an agent worktree with its own Package.swift is left
# under `.claude/`.
#
# NEVER pipe this. 0 = passed, 65 = a test failed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nihongo-ios-placement.XXXXXX")"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

rsync -a \
  --exclude '.git' --exclude '.build' --exclude '/build' --exclude '.claude' --exclude '.swiftpm' \
  --exclude '/.venv-jp' --exclude '/.dictation-wav' \
  --exclude '/*.xcodeproj' --exclude '/NihongoRide-*' \
  "$REPO/" "$WORK/"

cd "$WORK"
xcodegen generate >/dev/null

# ⚠️ `caffeinate -d` is LOAD-BEARING, not politeness.
#
# MEASURED 2026-08-30: with the display asleep this suite stalls at exactly the build→test
# handoff — the build completes, the .xctest bundle is touched, and then nothing, at 0% CPU,
# indefinitely. FOUR consecutive runs, always the same point; `Simulator.app` never launches, and
# `xcrun simctl` reports the device booted the whole time. Holding the display awake for the
# duration was the ONLY change that made it run: 5 tests, 0 failures, first try.
#
# The distinction that matters, and the one that would cost a day to rediscover: the console was
# UNLOCKED every time (`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` → false). This is not the
# screen-lock trap CLAUDE.md records for notarization. It is DISPLAY SLEEP, and XCUITest needs a
# live window-server session because it drives a real GUI.
#
# `-i` also prevents idle system sleep for the run. Neither outlives the command.
caffeinate -d -i xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRideiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NihongoRideiOSUITests/PaidRouteRowTests \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO
