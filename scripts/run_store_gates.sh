#!/usr/bin/env bash
#
# Run the StoreKit purchase gates (Tests/NihongoRideMacTests) on macOS.
#
# WHY THIS COPIES THE TREE FIRST
# -------------------------------
# Two reasons, and the second one is a trap this project has now paid for twice in different
# costumes.
#
# 1. The same reason `build-appstore.sh` does it: files under `~/Documents` carry
#    `com.apple.provenance`, and codesign refuses to sign them.
#
# 2. **`xcodebuild` hangs in the working tree when an agent worktree is left under `.claude/`.**
#    Measured 2026-08-30: `xcodebuild -list -project NihongoRide.xcodeproj` timed out at 0% CPU
#    with SwiftPM.framework loaded and no package cache written, in-place; the identical project
#    generated in an rsync'd copy listed in seconds. The difference was
#    `.claude/worktrees/wf_e2240193-634-5` — a leftover full checkout from a v1.24 review fan-out,
#    **containing its own `Package.swift`**. A second Swift package nested inside the root
#    package's directory is what SwiftPM's xcodebuild integration stalls on.
#
#    STATE already warned that agent worktrees live inside the repo and the release build copies
#    them; the new half is that they also break `xcodebuild` outright, and that
#    `git worktree remove --force` and `git worktree prune` both HANG on such a worktree, so the
#    documented cleanup does not work. `rm -rf` does, slowly.
#
#    Copying is therefore not a workaround for one stale directory — it is how this gate stays
#    runnable no matter what an agent leaves behind.
#
# Exit codes: 0 all gates passed · 65 a gate failed · anything else, the harness broke.
# NEVER pipe this: a pipe replaces the exit code of the command before it, and this project has
# already shipped a release on an `xcodebuild … | tail` that reported 0 for a failed suite.
set -euo pipefail

# The classification is a FUNCTION so it can be exercised without running xcodebuild — see
# `scripts/test_run_store_gates.sh`, which sources this file and feeds it synthetic logs. A
# re-implementation of these rules in a test would be the shape v1.32 §D4 was about.
#
# ⚠️ ORDER MATTERS, and getting it wrong is the defect this block was rewritten to fix.
#
# The skip check used to run FIRST and unconditionally. So a run where the StoreKit gates skipped
# — which is every run today — AND another test in the same target genuinely FAILED exited 3,
# "no coverage": a real failure reported as a known, tolerated state. Every doc in this repo says
# to keep running this script and expect 3, so that failure would have been read as normal and
# walked past. A genuine failure must never be reportable as a documented non-result.
#
#   65  a gate genuinely failed        (xcodebuild's own code, taken from PIPESTATUS)
#    4  the harness could not start    (above)
#    3  the gates ran and SKIPPED, and nothing else failed — no coverage, not a pass
#    0  the gates ran and passed
classify_store_gates() {
  local status="$1" log="$2"
  if grep -q "with [0-9]* tests* skipped" "$log" \
     && ! grep -qE "Executed [0-9]+ tests?, with 0 tests? skipped" "$log"; then
    local skipped
    skipped=$(grep -oE "with [0-9]+ tests? skipped" "$log" | head -1)
    echo "  ⚠️  NO PURCHASE COVERAGE: $skipped. The StoreKit gates did not run — read the skip reason above." >&2
    echo "      (Other tests in this target may have passed. They say nothing about the purchase flow.)" >&2
    echo "      PLAN-STAGE1 §L's manual list is the only purchase coverage in that state." >&2
    # …but a genuine failure outranks the missing coverage. Both facts get printed; the EXIT CODE
    # reports the one that must not be walked past.
    if [ "$status" != "0" ]; then
      echo "      AND a test in this target FAILED (exit $status). That is the finding, not the skip." >&2
      echo "$status"
      return
    fi
    echo "3"
    return
  fi
  echo "$status"
}

# Sourced for testing rather than run: `test_run_store_gates.sh` sets this before sourcing.
# Sourced rather than run: `test_run_store_gates.sh` sets this, takes the function, and stops
# here — BEFORE the rsync, the xcodegen and the twenty-second xcodebuild below. The first version
# of this guard sat at the BOTTOM of the file, which guards nothing: sourcing would have run the
# whole gate first and then returned.
if [ -n "${RUN_STORE_GATES_SOURCE_ONLY:-}" ]; then return 0; fi


REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# A fresh directory per run, rather than one fixed path cleared at the top.
#
# The fixed path was the first version and it failed twice in a row with
# "Directory not empty": `rm -rf` races an earlier run's `xcodebuild`, which keeps writing to
# DerivedData/ModuleCache for a while after it is signalled. With `set -e` that aborts the whole
# gate — and a gate that fails for a reason having nothing to do with the code under test is a
# gate people learn to rerun until it is green, which is worse than not having one.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nihongo-store-gates.XXXXXX")"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '/build' \
  --exclude '.claude' \
  --exclude '.swiftpm' \
  --exclude '/.venv-jp' \
  --exclude '/.dictation-wav' \
  --exclude '/*.xcodeproj' \
  --exclude '/NihongoRide-*' \
  "$REPO/" "$WORK/"

cd "$WORK"
xcodegen generate >/dev/null

# The scheme reference is written ONLY when `storeKitConfiguration` sits under the scheme's `run:`
# block. Under `test:` or at the scheme's top level xcodegen ignores it silently, with no
# diagnostic at all — so the check is a grep, not somebody's memory.
if ! grep -q "StoreKitConfigurationFileReference" \
     "NihongoRide.xcodeproj/xcshareddata/xcschemes/NihongoRide.xcscheme"; then
  echo "HARNESS ERROR: the generated scheme carries no StoreKitConfigurationFileReference." >&2
  echo "  xcodegen honours storeKitConfiguration only under a scheme's run: block." >&2
  # 4, not 3. This used to exit 3 as well, so "the harness could not even start" and "the gates
  # ran and skipped" printed the same number — two different things to do next, reported
  # identically. (v1.32 §D6.)
  exit 4
fi

echo
echo "  Running the StoreKit purchase gates. If they SKIP, read the skip reason: it means"
echo "  SKTestSession is inert for this app on this machine and the gates prove NOTHING."
echo "  In that state PLAN-STAGE1 §L's manual list is the only coverage there is."
echo

LOG="$WORK/gates.log"
set +e
# `caffeinate -d -i` for the same measured reason as `run_ios_placement_tests.sh`: a sleeping
# display stalls the build→test handoff at 0% CPU indefinitely. These gates are macOS unit tests
# rather than XCUITest so they are less exposed, but the cost of the guard is nothing and the cost
# of rediscovering the stall was most of an afternoon.
caffeinate -d -i xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRide \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:NihongoRideMacTests \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS= 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
tail -3 "$LOG" >/dev/null   # keep the log alive until the trap

# ⚠️ A run where the PURCHASE gates SKIPPED must not exit 0.
#
# 2026-09-06: this target gained `MenuEntranceHitTests`, which does run. So "every test
# skipped" stopped being the condition and "the StoreKit gates skipped" became it. The
# grep below already measured the right thing — it fires on any non-zero skip count — but
# the message said "the gates did not run", which is now false in the literal reading a
# hurried person takes. Naming which suite is dark keeps the warning true.
#
# `xcodebuild` reports skipped tests as success, which is correct for xcodebuild and wrong for
# this script: exit 0 is what every human and every automation reads as "the purchase flow is
# covered". It is not — a fully-skipped run has covered NOTHING, and the whole reason the gates
# skip is that they would otherwise have proved nothing while passing. Reporting that as a pass
# would put the same lie back one layer out.
#
# 3 = the harness could not obtain coverage. Distinct from 65 (a gate genuinely failed) and from
# 0 (gates ran and passed), because those are three different things to do next.

echo
exit "$(classify_store_gates "$STATUS" "$LOG")"
