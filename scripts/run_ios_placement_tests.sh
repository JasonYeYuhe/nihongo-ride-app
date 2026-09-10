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
# WHAT IT RUNS, and what it still does not (v1.32 §D5)
# ----------------------------------------------------
# TWO invocations, because the target holds suites about two different devices:
#   iPhone 17 Pro   PaidRouteRowTests (8) + StumbledWordsFlowTests (1)
#   iPad Pro 11"    TouchFlowTests (3) — App Review rejection 2.1(a), the touch-only path
# `StoreScreenshotTests` (1) is opt-in behind `--with-screenshots`: it skips by default, and a
# skip line in a gate's output reads like a test that ran.
#
# That is all 13 methods in the target. Before v1.32 §D5 the script ran 8 of them.
#
# `TouchFlowTests` (3) is still orphaned ON PURPOSE. Its own header says it needs an **iPad**
# simulator, and running it on the iPhone clone this script uses would defeat its purpose
# entirely: it reproduces App Review rejection 2.1(a) on the geometry where the keyboard failed to
# appear. That is a second `xcodebuild` invocation against a second destination, and it is the
# remaining piece of §D5.
#
# The two adopted here were not "never run" — the plan says so and it is wrong. They were GREEN on
# 2026-08-25 (`f311520`) and have had no runner since, so the drift window is 26 app-layer commits
# rather than six releases. Two real breakages were in that window and are fixed alongside this:
# an index into whichever segmented controls happen to be visible, and a query for a button INSIDE
# a button left over from when the mode row was a segmented control.
#
# NEVER pipe this. 0 = passed, 65 = a test failed, 2 = HARNESS ERROR (the machine, not the app).
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
# --- Which simulator, and why it is overridable -------------------------------
# 2026-09-05: this gate reported two failures -- including "an owner lost the road
# row entirely" -- that were not real. Another session on this machine was running
# its own XCUITests against the SAME device: there is exactly one simulator named
# "iPhone 17 Pro", and two UI-test runs on one device fight over the foreground.
# The failures vanished once the runs were separated.
#
# So the destination is overridable. But NOT with a different model: these tests
# assert hit areas and layout, so the screen size is part of the instrument, and
# quietly moving to an iPhone 17 Pro Max would be measuring something else. To
# isolate, clone the SAME device type under a private name:
#
#   xcrun simctl create NihongoRide-Placement "iPhone 17 Pro"
#   SIM_NAME=NihongoRide-Placement scripts/run_ios_placement_tests.sh
#
# The default stays "iPhone 17 Pro" so an unqualified run measures what it always
# measured.
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
echo "==> simulator destination: $SIM_NAME"

# --- The screenshot walk, on demand -------------------------------------------
#
# `StoreScreenshotTests` throws `XCTSkip` unless `NIHONGO_STORE_SHOTS` is set, so putting it in
# the default invocation buys a SKIP LINE and nothing else — and a skip line in a gate's output is
# worse than absence, because it reads like a test that ran. (`run_store_gates.sh` exists entirely
# because of that distinction.) So it is opt-in:
#
#   scripts/run_ios_placement_tests.sh --with-screenshots
#
# `TEST_RUNNER_` is the prefix `xcodebuild` strips when handing an environment variable to the
# XCUITest runner process, which is where the test's `ProcessInfo` reads it. Measured 2026-09-10:
# passing it as a command-line BUILD SETTING does not work — the test still skips. It has to be an
# environment variable of the xcodebuild process itself.
SHOT_TESTING=""
if [ "${1:-}" = "--with-screenshots" ]; then
  SHOT_TESTING="-only-testing:NihongoRideiOSUITests/StoreScreenshotTests"
  export TEST_RUNNER_NIHONGO_STORE_SHOTS=1
  echo "==> including the store screenshot walk (~76 s; attachments land in the .xcresult)"
fi

# --- Preconditions, ASSERTED rather than assumed (v1.32 §D5) ------------------
#
# Everything below was previously a property this script relied on and never checked. The
# distinction matters more here than almost anywhere else in the repo: when one of these is
# violated the suite does not error, it FAILS — with messages like "an owner lost the road row
# entirely", which is indistinguishable from the App Review 3.1.1 defect this gate exists to
# catch. That happened on 2026-09-05 and cost a real investigation.
#
# Convention borrowed from `launch_gate.sh`: exit 2 = HARNESS ERROR (the machine's fault),
# 65 = a test failed (the app's fault). They must never print the same number.
harness_error() { echo; echo "HARNESS ERROR: $1" >&2; exit 2; }

# 1. The device must exist, and it must be the model the assertions were calibrated on. A
#    destination that silently resolves to another model measures a different screen.
DEVICE_JSON="$(xcrun simctl list devices -j)"
SIM_UDID="$(printf '%s' "$DEVICE_JSON" | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d.get('name') == name and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
" "$SIM_NAME" 2>/dev/null || true)"
[ -n "$SIM_UDID" ] || harness_error "no available simulator named '$SIM_NAME'. Create one with:
    xcrun simctl create $SIM_NAME \"iPhone 17 Pro\""

# 2. NOBODY ELSE MAY BE DRIVING IT. This is the 2026-09-05 incident, and it is the one
#    precondition whose absence produces failures shaped exactly like real defects.
OTHER="$(pgrep -fl "xcodebuild.*$SIM_UDID" 2>/dev/null || true)"
if [ -z "$OTHER" ]; then
  # A run started by NAME rather than by udid will not match the pattern above, so also refuse
  # when any other xcodebuild test is running at all — several agent sessions share this machine
  # and only one of them can have the foreground.
  OTHER="$(pgrep -fl "xcodebuild.*NihongoRideiOS" 2>/dev/null | grep -v "^$$ " || true)"
fi
[ -z "$OTHER" ] || harness_error "another xcodebuild is already driving this simulator:
    $OTHER
  Two UI-test runs on one device fight over the foreground and produce failures that read like
  real defects — measured 2026-09-05. Wait, or clone the device:
    xcrun simctl create NihongoRide-Placement \"iPhone 17 Pro\"
    SIM_NAME=NihongoRide-Placement $0"

# 3. The SOFTWARE keyboard must be the one that appears. `TouchFlowTests` reproduces App Review
#    rejection 2.1(a) — "the keyboard never came up" — so a run with the hardware keyboard
#    connected asserts nothing and passes. The global preference is overridable PER DEVICE, so
#    both are checked; a missing key means the default, which is connected.
KB_GLOBAL="$(defaults read com.apple.iphonesimulator ConnectHardwareKeyboard 2>/dev/null || echo 1)"
[ "$KB_GLOBAL" = "0" ] || harness_error "the simulator's hardware keyboard is connected, so a
  software-keyboard assertion would pass without the software keyboard ever appearing. Turn it
  off (Simulator ▸ I/O ▸ Keyboard ▸ Connect Hardware Keyboard, or):
    defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false"

# 4. `caffeinate` must be present, because it — and NOT a human at the keyboard — is what makes
#    an unattended run work.
#
#    MEASURED 2026-09-10, and it refuted the check that used to be here. This script briefly
#    refused to start with the console locked, on the theory that XCUITest needs a live GUI
#    session. It does not. With `IOConsoleLocked = true` AND `CGDisplayIsAsleep = true` — screen
#    locked, display off, nobody at the machine — the full suite ran and passed: 10 tests, 1
#    skipped, 0 failures, 104 s.
#
#    So STATE-2026-08-18's stall entry is about DISPLAY SLEEP WITHOUT `caffeinate`, and its own
#    closing line already said so: *"`run_ios_placement_tests.sh` and `run_store_gates.sh` now hold
#    the display awake themselves, so the trap cannot recur through them."* The mitigation was
#    already in place and I re-derived the hazard as though it were not — the same conflation of
#    two nearby states (console lock vs display sleep) that CLAUDE.md warns about for signing.
#
#    A check that blocked every locked-screen run would have cost far more than it saved: an
#    agent-driven repo does most of its work with nobody at the keyboard. So what is asserted is
#    the thing that actually does the work.
command -v caffeinate > /dev/null 2>&1 || harness_error "caffeinate is not on PATH. It is what
  keeps this suite alive with the display asleep — measured 2026-08-30, four consecutive runs
  stalled at the build→test handoff at 0% CPU without it, with no diagnostic at all."
#    And the check has to be anchored, because the first version was not: it grepped this file
#    for a string that its own line contained, so deleting BOTH wrappers left it green. A checker
#    that cannot fail is worth less than no checker, because it is also believed. Both real
#    invocations start at column 0; this line does not, so `^` separates them — and the count is
#    asserted, so losing ONE of the two destinations is caught as well.
WRAPPED=$(grep -c '^caffeinate -d -i xcodebuild test' "${BASH_SOURCE[0]}")
[ "$WRAPPED" -eq 2 ] || harness_error "expected 2 xcodebuild invocations wrapped in
  \`caffeinate -d -i\`, found $WRAPPED. That wrapper is the only thing standing between an
  unattended run and a silent, indefinite stall — measured 2026-08-30."

echo "==> preconditions ok: $SIM_NAME ($SIM_UDID), exclusive, software keyboard, caffeinate present"

# TWO DESTINATIONS, because one of these suites is about a device this repo does not otherwise
# test on. `TouchFlowTests` reproduces App Review rejection 2.1(a) — "stuck on the first word
# screen" on a touch-only **iPad**, where the software keyboard never appeared — and its own
# header says so. Running it on the iPhone clone would defeat its purpose entirely, which is why
# it stayed orphaned rather than being folded into the invocation above.
#
# Overridable for the same reason `SIM_NAME` is, and pinned for a weaker one: these assert that
# things are TAPPABLE and that the keyboard appears, not where a hit region lands, so the exact
# iPad matters less here than the iPhone model does above. Pinned anyway, so a run reports which
# device answered.
IPAD_NAME="${IPAD_NAME:-iPad Pro 11-inch (M5)}"
IPAD_UDID="$(printf '%s' "$DEVICE_JSON" | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d.get('name') == name and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
" "$IPAD_NAME" 2>/dev/null || true)"
[ -n "$IPAD_UDID" ] || harness_error "no available simulator named '$IPAD_NAME'. TouchFlowTests
  needs an iPad — that is the geometry App Review rejected. Create one with:
    xcrun simctl create \"$IPAD_NAME\" \"$IPAD_NAME\""

echo "==> iPad destination: $IPAD_NAME ($IPAD_UDID)"

# Statuses are captured PER INVOCATION and combined at the end. No `&&` — it swallows the first
# failure — and no pipes, which replace the exit code of the command before them. Both traps are
# measured in this repo, the second on the gate that decides whether a release ships.
set +e
caffeinate -d -i xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRideiOS \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -only-testing:NihongoRideiOSUITests/PaidRouteRowTests \
  -only-testing:NihongoRideiOSUITests/StumbledWordsFlowTests \
  $SHOT_TESTING \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO
IPHONE_STATUS=$?

echo
echo "==> iPad suite (App Review 2.1(a): the touch-only path)"
caffeinate -d -i xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRideiOS \
  -destination "platform=iOS Simulator,name=$IPAD_NAME" \
  -only-testing:NihongoRideiOSUITests/TouchFlowTests \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO
IPAD_STATUS=$?
set -e

echo
echo "──────────────────────────────────────────────────────────────"
printf '  %-28s %s\n' "$SIM_NAME" "$([ "$IPHONE_STATUS" -eq 0 ] && echo ok || echo "FAILED (exit $IPHONE_STATUS)")"
printf '  %-28s %s\n' "$IPAD_NAME" "$([ "$IPAD_STATUS" -eq 0 ] && echo ok || echo "FAILED (exit $IPAD_STATUS)")"
# Report the FIRST non-zero rather than the last, so a passing second run cannot mask a failing
# first one — which is what a bare `exit $?` after two commands does.
if [ "$IPHONE_STATUS" -ne 0 ]; then exit "$IPHONE_STATUS"; fi
exit "$IPAD_STATUS"
