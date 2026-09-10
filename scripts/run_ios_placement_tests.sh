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
# `PaidRouteRowTests` (8) plus, since v1.32, `StumbledWordsFlowTests` (1) and
# `StoreScreenshotTests` (1) — the two orphans that need no second destination.
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

# 4. There must be a live, unlocked GUI session. XCUITest drives a real window server; measured
#    2026-08-30, with the display asleep the suite builds cleanly, touches the .xctest bundle and
#    then does NOTHING at 0% CPU — four consecutive runs, always the same point — while `simctl`
#    reports the device booted throughout. It looks like a hang, not a failure.
#
#    The probe is `IOConsoleLocked`, which is the one STATE-2026-08-18 and CLAUDE.md both use and
#    which answers on this hardware. `pmset -g powerstate IODisplayWrangler` was tried first and
#    is WORTHLESS here: it prints "Internal failure: Failed to get power state information" on
#    Apple Silicon, so the grep matched nothing and the check silently passed. A precondition that
#    cannot fail is the thing this whole preamble exists to stop, so:
CONSOLE="$(ioreg -n Root -d1 -a 2>/dev/null | grep -A1 IOConsoleLocked | tail -1 | tr -d '[:space:]')"
case "$CONSOLE" in
  "<false/>") : ;;   # unlocked — proceed
  "<true/>")
    harness_error "the console is LOCKED. XCUITest needs a live window-server session: it builds,
  touches the .xctest bundle and then sits at 0% CPU with no diagnostic — measured, four runs in a
  row. Unlock the screen and re-run. (This is NOT the codesign keychain trap CLAUDE.md records,
  though the same lock causes both.)" ;;
  *)
    harness_error "could not read IOConsoleLocked (got '${CONSOLE:-nothing}'). Refusing rather
  than assuming: a precondition that cannot determine its answer must not report the good one.
  The first version of this check used \`pmset -g powerstate IODisplayWrangler\`, which fails on
  Apple Silicon and therefore passed every time." ;;
esac

echo "==> preconditions ok: $SIM_NAME ($SIM_UDID), exclusive, software keyboard, display awake"

caffeinate -d -i xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRideiOS \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -only-testing:NihongoRideiOSUITests/PaidRouteRowTests \
  -only-testing:NihongoRideiOSUITests/StumbledWordsFlowTests \
  -only-testing:NihongoRideiOSUITests/StoreScreenshotTests \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO
