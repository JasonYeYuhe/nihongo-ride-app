#!/usr/bin/env bash
#
# What `run_store_gates.sh` reports, for each combination of (xcodebuild status, skip banner).
#
# WHY THIS EXISTS
# ---------------
# The skip check used to run FIRST and unconditionally, so a run where the StoreKit gates skipped
# — which is EVERY run today — and another test in the same target genuinely FAILED exited 3,
# "no coverage". Every document in this repo tells the reader to run that script and expect 3, so
# a real failure would have printed a number everyone has been taught to walk past.
#
# WHY IT SOURCES THE REAL FUNCTION
# --------------------------------
# A copy of the classification rules written out here would be `EntitlementSeamTests`' defect
# (v1.32 §D4): a control that certifies a parser which is not the one doing the work. So this
# sources `run_store_gates.sh` with `RUN_STORE_GATES_SOURCE_ONLY` set, which returns before the
# rsync/xcodegen/xcodebuild, and calls `classify_store_gates` directly.
#
# Exit 0 = every case classified correctly.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_STORE_GATES_SOURCE_ONLY=1
# shellcheck source=/dev/null
. "$HERE/run_store_gates.sh"

if ! declare -f classify_store_gates >/dev/null; then
  echo "FAIL: sourcing run_store_gates.sh did not define classify_store_gates — the guard moved" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/store-gate-classify.XXXXXX")"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

# xcodebuild summary lines in XCTest's REAL format. The first version of this block claimed they
# were "copied from a run"; they were not, and both were strings XCTest cannot emit — which made
# the `clean` case exercise a branch that never occurs and never exercise the branch that does.
#
# The format is XCTestCore's own, extracted from the binary on this machine (2026-09-10,
# /Applications/Xcode.app/Contents/SharedFrameworks/XCTestCore.framework/Versions/A/XCTestCore):
#
#   Executed %lu test%s, with%@ %lu failure%s (%lu unexpected) in %.3f (%.3f) seconds
#
# where the %@ is either empty or " %lu test%s skipped and". So a run WITH skips reads
# "...with 9 tests skipped and 0 failures...", and a run WITHOUT skips has no "skipped" clause at
# all — it does not say "0 tests skipped". A synthetic log the script's greps happen not to match
# would make every case below pass for the wrong reason, which is what was happening.
write_log() {
  printf '%s\n' "$2" > "$WORK/$1.log"
}
write_log skipped   "Executed 9 tests, with 9 tests skipped and 0 failures (0 unexpected) in 0.412 (0.418) seconds"
write_log clean     "Executed 9 tests, with 0 failures (0 unexpected) in 3.104 (3.120) seconds"
write_log noskipline "Test Suite 'NihongoRideMacTests.xctest' passed at 2026-09-10 12:00:00.000"

FAILURES=0
check() {
  local name="$1" status="$2" log="$3" want="$4" got
  got="$(classify_store_gates "$status" "$WORK/$log.log" 2>/dev/null)"
  if [ "$got" = "$want" ]; then
    printf '  ok    %-52s -> %s\n' "$name" "$got"
  else
    printf '  FAIL  %-52s -> %s (want %s)\n' "$name" "$got" "$want"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "classify_store_gates:"
# The state the repo is actually in today.
check "gates skipped, nothing else failed"        0  skipped     3
# THE DEFECT. Before v1.32 §D6 this returned 3 and the failure was invisible.
check "gates skipped AND a test failed"           65 skipped     65
check "gates skipped AND a signal death"          134 skipped    134
# Coverage obtained.
check "gates ran and passed"                      0  clean       0
check "gates ran and one failed"                  65 clean       65
# A log with no skip line at all must fall through to the status untouched.
check "no skip banner, passed"                    0  noskipline  0
check "no skip banner, failed"                    65 noskipline  65

# The negative control for the harness itself: if `classify_store_gates` were a constant, every
# line above could still pass. These two demand that it DISCRIMINATES on both inputs.
echo "instrument:"
if [ "$(classify_store_gates 0 "$WORK/skipped.log" 2>/dev/null)" = "$(classify_store_gates 0 "$WORK/clean.log" 2>/dev/null)" ]; then
  echo "  FAIL  the classifier ignores the LOG — skipped and clean give the same answer"
  FAILURES=$((FAILURES + 1))
else
  echo "  ok    the classifier reads the log"
fi
if [ "$(classify_store_gates 0 "$WORK/skipped.log" 2>/dev/null)" = "$(classify_store_gates 65 "$WORK/skipped.log" 2>/dev/null)" ]; then
  echo "  FAIL  the classifier ignores the STATUS — that is the defect this file exists for"
  FAILURES=$((FAILURES + 1))
else
  echo "  ok    the classifier reads the status"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "run_store_gates classification: all cases correct"
  exit 0
fi
echo "run_store_gates classification: $FAILURES case(s) wrong"
exit 1
