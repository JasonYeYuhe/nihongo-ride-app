#!/usr/bin/env bash
#
# What `launch_gate.sh` reports for each bundle it can be handed.
#
# WHY THIS EXISTS
# ---------------
# v1.32 taught that gate the iOS bundle shape and then wired it into
# `build-appstore-ios.sh`, where it can now REFUSE A RELEASE. A gate on the release path that
# nobody has watched fail is the thing this repo keeps writing entries about, so it gets a
# self-test before it gets that authority.
#
# It builds nothing and needs no simulator: bundles are synthesised on disk, which is enough,
# because every branch under test reads the bundle's SHAPE and its signature — not its behaviour.
# The one branch that cannot be reached this way is the macOS launch itself, and it is skipped
# rather than faked.
#
# Exit 0 = every case classified correctly.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/launch_gate.sh"
ENTITLEMENTS="$HERE/../xcode/NihongoRide-iOS.entitlements"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/launch-gate-test.XXXXXX")"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

FAILURES=0
# Set when the ONE positive case — an entitled iOS bundle that must exit 0 — could not be built
# on this machine. Every other case expects a NON-zero exit, so without it the suite still passes
# while having proved only that the gate can say no. That is not a pass; it is no coverage, and
# `run_all_gates.sh` has a column for exactly that distinction. (v1.32 pre-submission review.)
NO_COVERAGE=0
check() {
    local name="$1" want="$2" app="$3" got
    "$GATE" "$app" > "$WORK/out.txt" 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        printf '  ok    %-50s -> %s\n' "$name" "$got"
    else
        printf '  FAIL  %-50s -> %s (want %s)\n' "$name" "$got" "$want"
        sed 's/^/          /' "$WORK/out.txt" | head -4
        FAILURES=$((FAILURES + 1))
    fi
}

# A minimal iOS bundle: Info.plist at the ROOT, executable beside it, widget under PlugIns.
make_ios_app() {
    local dir="$1" with_extension="$2"
    rm -rf "$dir"; mkdir -p "$dir"
    cp /bin/echo "$dir/Nihongo Ride"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string "Nihongo Ride"' \
        -c 'Add :CFBundleShortVersionString string 9.9' \
        -c 'Add :CFBundleVersion string 999' "$dir/Info.plist" > /dev/null
    if [ "$with_extension" = "yes" ]; then
        mkdir -p "$dir/PlugIns/NihongoRideWidget.appex"
    fi
}

echo "launch_gate.sh:"

# 1. Not a bundle at all — a harness fault, and it must not be confused with the app's.
mkdir -p "$WORK/not-an-app"
check "a directory with no Info.plist in either position" 2 "$WORK/not-an-app"
check "a path that does not exist"                        2 "$WORK/nope.app"

# 2. iOS, correctly shaped, WITHOUT the iCloud entitlement.
#
# This is the case worth having: it is not a harness problem, it is a launch crash for every
# customer. `CKContainer.init` traps without `com.apple.developer.icloud-services` — measured on
# the simulator 2026-09-10 with a paired control — and `AppModel.init` reaches that path on every
# un-isolated launch. So it must be 1 (FAIL), never 2 (harness).
make_ios_app "$WORK/NoEnt.app" yes
codesign -f -s - "$WORK/NoEnt.app" > /dev/null 2>&1
check "iOS bundle with NO iCloud entitlement" 1 "$WORK/NoEnt.app"

# 3. …and the paired control. Same bundle, entitlement added, and the gate must PASS it.
#    Without this the case above is satisfied by a gate that fails everything.
if [ -f "$ENTITLEMENTS" ]; then
    make_ios_app "$WORK/Ent.app" yes
    codesign -f -s - --entitlements "$ENTITLEMENTS" "$WORK/Ent.app" > /dev/null 2>&1
    if codesign -d --entitlements - --xml "$WORK/Ent.app" 2>/dev/null | grep -q icloud-services; then
        check "iOS bundle WITH the iCloud entitlement" 0 "$WORK/Ent.app"

        # 4. Entitled, but the widget extension is missing. A different failure from the app's own
        #    and nothing else in the repo looks for it.
        make_ios_app "$WORK/NoExt.app" no
        codesign -f -s - --entitlements "$ENTITLEMENTS" "$WORK/NoExt.app" > /dev/null 2>&1
        check "iOS bundle with the entitlement but no .appex" 1 "$WORK/NoExt.app"

        # 5. `icloud-services` present, CONTAINER WRONG. The services key alone does not say which
        #    container the app opens, and `CloudKitSyncController` opens exactly one by name — so a
        #    build signed for somebody else's container passes the services grep and finds nothing
        #    behind it at runtime. Without this case the container check added in v1.32 is
        #    satisfied by an entitlements file that happens to contain the right string.
        sed 's/iCloud\.com\.jasonye\.nihongoride/iCloud.com.example.wrong/g' \
            "$ENTITLEMENTS" > "$WORK/wrong-container.entitlements"
        if grep -q "iCloud.com.example.wrong" "$WORK/wrong-container.entitlements"; then
            make_ios_app "$WORK/WrongContainer.app" yes
            codesign -f -s - --entitlements "$WORK/wrong-container.entitlements" \
                "$WORK/WrongContainer.app" > /dev/null 2>&1
            check "iOS bundle entitled for the WRONG iCloud container" 1 "$WORK/WrongContainer.app"
        else
            echo "  SKIP  the entitlements file does not name the container by that string"
            NO_COVERAGE=1
        fi
    else
        echo "  SKIP  could not attach entitlements with an ad-hoc signature on this machine"
        echo "        — the PASS case is unverified here, which is stated rather than assumed"
        NO_COVERAGE=1
    fi
else
    echo "  SKIP  $ENTITLEMENTS not found"
    NO_COVERAGE=1
fi

# 5. macOS shape is RECOGNISED — routed to the macOS branch rather than the iOS one. The launch
#    itself is not exercised (it would run a binary for 16 s), so what is asserted is that the
#    shape decides the platform: an unsigned macOS bundle must be 2 (harness: no entitlement to
#    exercise the crash path) where the identical iOS one is 1 (a shipping defect).
MAC="$WORK/Mac.app/Contents"
mkdir -p "$MAC/MacOS"
cp /bin/echo "$MAC/MacOS/Nihongo Ride"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string "Nihongo Ride"' \
    -c 'Add :CFBundleShortVersionString string 9.9' \
    -c 'Add :CFBundleVersion string 999' "$MAC/Info.plist" > /dev/null
codesign -f -s - "$WORK/Mac.app" > /dev/null 2>&1
check "macOS bundle with no entitlement is a HARNESS error, not a FAIL" 2 "$WORK/Mac.app"

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "launch_gate classification: $FAILURES case(s) wrong"
    exit 1
fi
if [ "$NO_COVERAGE" -eq 1 ]; then
    echo "launch_gate classification: no case wrong, but the POSITIVE control did not run —"
    echo "  every case that DID run expects a non-zero exit, so nothing here proves the gate can pass."
    exit 3
fi
echo "launch_gate classification: all cases correct"
exit 0
