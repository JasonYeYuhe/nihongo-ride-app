#!/usr/bin/env bash
# Release launch crash gate.
#
# macOS 1.4 was REJECTED by App Review for a launch crash — "Cannot await a call into
# CKSyncEngine from within a delegate callback" — that appeared ONLY in a signed build
# carrying the CloudKit entitlement, on a Mac signed into iCloud. A debug run, an
# unsigned build, and `swift test` all missed it, because none of them can reach the
# account-change path that trips it.
#
# So the gate has three conditions and none of them is optional:
#   1. the .app must come from the SIGNED ARCHIVE (it carries the entitlements),
#   2. the Mac must be signed into iCloud (that is what fires the signIn account change),
#   3. it must still be alive well past the point where 1.4 died — which was under two
#      seconds, with the fatal line on stderr.
#
# This existed only as prose in docs/V1.5-VERIFICATION.md §1 for seven releases. It is a
# script now because the one time it was run by hand from a shell here, a wrong path made
# it report the APP had crashed after one second when it was the harness that was broken —
# which is the failure mode a gate must never have. It now says "HARNESS ERROR" for its own
# faults and keeps "FAIL" for the app's.
#
#   scripts/launch_gate.sh "<archive>/Products/Applications/Nihongo Ride.app"
#
# It steals focus for ~20 seconds. Do not run it while somebody is using the machine.
#
# ── iOS (v1.32) ───────────────────────────────────────────────────────────────────────────────
#
# This script used to read `Contents/Info.plist` unconditionally, which is the macOS bundle shape.
# Handed an iOS artifact it said "HARNESS ERROR: cannot read …/Contents/Info.plist" — so **the
# artifact that ships to the iOS App Store had never been inspected by anything at all.** It now
# reads both shapes and runs every check that does not require executing the binary.
#
# **The runtime half cannot run on iOS from this machine, and that is measured, not assumed.**
# Launching an unsigned simulator build the way a CUSTOMER launches it — no `NIHONGO_UITEST`, so
# no isolation — kills it in about one second. Measured 2026-09-10 with a paired control: the same
# build launched WITH `NIHONGO_UITEST=1` survives, so the probe discriminates and the death is
# real. The simulator's own log gives the reason verbatim:
#
#     [com.apple.cloudkit.sim:CK] Significant issue at CKContainer.m:748: In order to use
#     CloudKit, your process must have a com.apple.developer.icloud-services entitlement.
#
# Which is `project.yml:447-450`'s recorded trap, on the platform it had only ever been recorded
# for the Mac test host. So an iOS launch gate on the simulator is **structurally impossible**: the
# path it exists to exercise needs the entitlement, and an unsigned simulator build cannot have a
# working one. The runtime half is a DEVICE errand.
#
# What runs here instead is condition 1, which is the one that would have caught the worst version
# of this: **an iOS release built without the iCloud entitlement traps on launch for every
# customer**, exactly as measured above, and nothing checked it.
set -uo pipefail

APP="${1:-}"
SECONDS_ALIVE="${2:-16}"
LOG="${TMPDIR:-/tmp}/launchgate_stderr.log"

[[ -n "$APP" ]] || { echo "HARNESS ERROR: usage: $0 <path to .app> [seconds]"; exit 2; }
[[ -d "$APP" ]] || { echo "HARNESS ERROR: no app bundle at $APP"; exit 2; }

# Which bundle shape is this? macOS nests everything under Contents/; iOS is flat. Deciding by
# what is THERE rather than by a flag, so a caller cannot tell the gate the wrong answer.
if [[ -f "$APP/Contents/Info.plist" ]]; then
    PLATFORM="macOS"
    PLIST="$APP/Contents/Info.plist"
elif [[ -f "$APP/Info.plist" ]]; then
    PLATFORM="iOS"
    PLIST="$APP/Info.plist"
else
    echo "HARNESS ERROR: $APP has no Info.plist in either the macOS (Contents/) or iOS (root)"
    echo "               position — it is not an app bundle."
    exit 2
fi

EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)" || {
    echo "HARNESS ERROR: cannot read $PLIST"; exit 2; }
if [[ "$PLATFORM" == "macOS" ]]; then
    EXE="$APP/Contents/MacOS/$EXE_NAME"
else
    EXE="$APP/$EXE_NAME"
fi
[[ -x "$EXE" ]] || { echo "HARNESS ERROR: no executable at $EXE"; exit 2; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

# Condition 1: the entitlements have to be there.
#
# On macOS a missing entitlement means the crash path is unreachable and a pass would mean
# nothing — a HARNESS problem. On iOS it is worse than that and it is not a harness problem at
# all: an iOS build shipped without `com.apple.developer.icloud-services` **traps in
# `CKContainer.init` on launch, for every customer**. Measured on the simulator 2026-09-10; the
# log line is quoted in this file's header. So the same missing entitlement is exit 2 on macOS
# and exit 1 — a FAILURE — on iOS.
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "icloud-services"; then
    if [[ "$PLATFORM" == "iOS" ]]; then
        echo "FAIL: this iOS build carries no com.apple.developer.icloud-services entitlement."
        echo "      That is not a gap in this gate — it is a launch crash for every customer:"
        echo "      CKContainer.init traps, measured, and AppModel.init reaches it on every"
        echo "      un-isolated launch. Do not ship this artifact."
        exit 1
    fi
    echo "HARNESS ERROR: this build has no CloudKit entitlement, so it cannot exercise the"
    echo "               path this gate exists for. Use the app from the signed archive."
    exit 2
fi

# Condition 2: iCloud. Not fatal to check loosely — but say so, because a pass on a
# signed-out Mac is a weaker claim than it looks.
if defaults read MobileMeAccounts Accounts >/dev/null 2>&1; then
    ICLOUD="signed in"
else
    ICLOUD="NOT SIGNED IN — a pass here does not exercise the account-change path"
fi

echo "gate: $VERSION ($BUILD)"
echo "      platform: $PLATFORM"
echo "      iCloud: $ICLOUD"

# iOS stops here, and says exactly what it did and did not do rather than printing PASS.
if [[ "$PLATFORM" == "iOS" ]]; then
    # The embedded widget extension is part of what launches. A missing or unsigned one is a
    # different failure from the app's own, and nothing else looks at it.
    EXTENSIONS="$(find "$APP/PlugIns" -maxdepth 1 -name "*.appex" 2>/dev/null | wc -l | tr -d ' ')"
    echo "      embedded app extensions: $EXTENSIONS"
    [[ "$EXTENSIONS" -ge 1 ]] || {
        echo "FAIL: no .appex under PlugIns/. The widget ships with this app; an artifact without"
        echo "      it is not the product, and the widget's own snapshot writer is what feeds the"
        echo "      home-screen view."
        exit 1
    }
    echo
    echo "CHECKED: bundle shape, executable, iCloud entitlement, embedded extension."
    echo "NOT CHECKED — and this is a real gap, not a formality: the app was never LAUNCHED."
    echo "  An iOS launch gate cannot run on this machine. An unsigned simulator build dies in"
    echo "  about a second on the un-isolated path (CKContainer.init traps without the"
    echo "  entitlement — measured 2026-09-10, with a paired control), and a signed build needs a"
    echo "  device. The runtime half is a DEVICE errand and is recorded as owner-only."
    exit 0
fi

echo "      launching $EXE"
: > "$LOG"
"$EXE" > "$LOG" 2>&1 &
PID=$!

for ((i = 1; i <= SECONDS_ALIVE; i++)); do
    sleep 1
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "FAIL: the app exited after ${i}s (1.4 died in under 2)"
        echo "--- stderr ---"
        tail -40 "$LOG"
        exit 1
    fi
done

echo "PASS: still running after ${SECONDS_ALIVE}s"
kill "$PID" 2>/dev/null
sleep 1
if [[ -s "$LOG" ]]; then
    echo "--- stderr produced while running (not a failure by itself) ---"
    tail -20 "$LOG"
fi
exit 0
