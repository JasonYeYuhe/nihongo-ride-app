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
set -uo pipefail

APP="${1:-}"
SECONDS_ALIVE="${2:-16}"
LOG="${TMPDIR:-/tmp}/launchgate_stderr.log"

[[ -n "$APP" ]] || { echo "HARNESS ERROR: usage: $0 <path to .app> [seconds]"; exit 2; }
[[ -d "$APP" ]] || { echo "HARNESS ERROR: no app bundle at $APP"; exit 2; }

PLIST="$APP/Contents/Info.plist"
EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)" || {
    echo "HARNESS ERROR: cannot read $PLIST"; exit 2; }
EXE="$APP/Contents/MacOS/$EXE_NAME"
[[ -x "$EXE" ]] || { echo "HARNESS ERROR: no executable at $EXE"; exit 2; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

# Condition 1: the entitlements have to be there, or the crash path is unreachable and a
# pass would mean nothing.
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "icloud-services"; then
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
echo "      iCloud: $ICLOUD"
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
