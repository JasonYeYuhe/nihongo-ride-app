#!/usr/bin/env bash
#
# One entry point for every gate that can run without a device, an account or a signature.
# (v1.32 §D6.)
#
# WHY THIS EXISTS
# ---------------
# Four python self-tests in this directory were run by NOTHING. `check_versions.py` defaulted to a
# release that had already shipped and said FAIL for the right reason by luck. The iOS placement
# tests were written, correct, and never invoked while the defect they describe shipped. A gate
# nobody runs is a comment.
#
# WHY THERE IS NO GIT HOOK, and this is a decision rather than an omission
# -----------------------------------------------------------------------
# `PLAN-V1.32` §D6 dropped it on three arguments, all of them measured here:
#   * a 4–8 minute pre-push hook gets `--no-verify`'d, which is WORSE than no hook because it
#     looks like coverage;
#   * `.git/hooks` is global to a working tree that several agent sessions share;
#   * two concurrent `xcodebuild test` runs fight over one simulator and manufacture failures
#     shaped exactly like real defects — measured, `742c38e`.
#
# WHAT IT DELIBERATELY DOES NOT RUN
# ---------------------------------
# Anything needing a booted simulator, a keychain, an Apple credential or a live container:
#   run_ios_placement_tests.sh   XCUITest, one simulator, ~4 min, and two sessions sharing this
#                                machine will collide. Run it yourself, on a UI or placement change.
#   check_prod_schema.sh         needs a CloudKit management token in the keychain. It is already
#                                hardwired into BOTH upload paths and fails the build, so it is
#                                not on anybody's memory.
#   launch_gate.sh               needs a signed .app and a real iCloud account.
# Naming them here is the point: a runner that silently covered less than a reader assumes is the
# failure this whole file is about.
#
# CONTRACT
#   exit 0   every gate ran and passed (a gate at its documented no-coverage state is NOT a pass —
#            it is reported, and it does not make the run green on its own; see NO-COVERAGE below)
#   exit 1   at least one gate failed, or a gate could not be run at all
#
# THREE TRAPS THIS REPO HAS PAID FOR, and how this file answers each:
#   1. "A pipe replaces the exit code of the command before it." `xcodebuild test … | tail` reported
#      exit 0 for a FAILED suite on the gate that decides whether a release ships (v1.26). So every
#      status here comes from the process that produced it: redirect to a file, read `$?`, never
#      pipe.
#   2. "`&&` swallows the first failure." Gates are run one per line with the status captured
#      immediately, never chained.
#   3. "`swift test` output is not a reliable input to a script." With a failure present the runner
#      can exit on a signal with truncated, interleaved output, so a harness that parses the
#      console can see a suite as "not failing" when it never ran at all. So this asserts the run
#      HAPPENED — the summary line must be present — and treats its absence as a failure rather
#      than as silence.

set -uo pipefail

# --headless        skip every gate that needs xcodebuild, a simulator or a GUI session.
#                   This is what CI runs, and it runs THIS script rather than a second copy of
#                   the gate list — one rule written twice will drift, and this repo has three
#                   recorded instances of exactly that.
# --vocab-base REF  what check_vocab_diff.py compares against. Locally the default (HEAD, i.e.
#                   the working tree) is right. On CI it is WRONG and silently so: a clean
#                   checkout compares HEAD with itself and is green whatever the commit changed.
HEADLESS=""
VOCAB_BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --headless) HEADLESS=1; shift ;;
    --vocab-base) VOCAB_BASE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# `GATE_LOG_DIR` lets a caller (CI) put the logs somewhere it can upload them. A temp dir that
# dies with the job is why the first CI run reported WHICH gate failed and not why.
LOGS="${GATE_LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/nihongo-all-gates.XXXXXX")}"
mkdir -p "$LOGS"
trap 'echo; echo "logs: $LOGS"' EXIT

FAILED=()
PASSED=()
NOCOVERAGE=()
# A gate that RAN and had nothing to inspect. Distinct from a pass, because "0 problems found"
# and "0 things looked at" print the same sentence and are not the same fact.
VACUOUS=()

# Run one gate, capture ITS status, and record the outcome. No pipes, no chaining.
#
# `expect_no_coverage` names the ONE exit code a gate is allowed to return that is neither a pass
# nor a failure, and it must be documented by that gate. It is reported in its own column and
# never absorbed into a green — the summary says how many gates are dark, every time.
run_gate() {
  local name="$1" nocoverage="$2"; shift 2
  local log="$LOGS/${name//\//_}.log" status
  printf '  %-34s ' "$name"
  "$@" > "$log" 2>&1
  status=$?
  if [ "$status" -eq 0 ]; then
    printf 'ok\n'; PASSED+=("$name"); return
  fi
  if [ -n "$nocoverage" ] && [ "$status" -eq "$nocoverage" ]; then
    printf 'NO COVERAGE (exit %s, documented)\n' "$status"
    NOCOVERAGE+=("$name"); return
  fi
  printf 'FAILED (exit %s)\n' "$status"
  # The tail, inline. On CI the log lives in a temp dir that dies with the job, and a runner that
  # reports WHICH gate failed but not WHY sends the reader back to reproduce it by hand. Twelve
  # lines is enough to name the assertion and cheap enough to keep in every local run.
  echo "        ┌─ last 12 lines of $name"
  tail -12 "$log" | sed 's/^/        │ /'
  echo "        └─"
  FAILED+=("$name (exit $status) — $log")
}

# `swift test`, with the "did it actually run" assertion the console cannot be trusted for.
run_swift_test() {
  local log="$LOGS/swift-test.log" status
  printf '  %-34s ' "swift test"
  swift test > "$log" 2>&1
  status=$?
  # The run must have REACHED a summary. A signal death mid-suite can leave status 0-ish output
  # and truncated text; "no summary line" is a failure, not silence.
  if ! grep -qE "Test run with [0-9]+ tests" "$log"; then
    printf 'FAILED (no summary line — the suite did not complete)\n'
    echo "        ┌─ last 20 lines (a signal death leaves truncated output)"
    tail -20 "$log" | sed 's/^/        │ /'
    echo "        └─"
    FAILED+=("swift test (never completed) — $log"); return
  fi
  local summary
  summary=$(grep -oE "Test run with [0-9]+ tests in [0-9]+ suites" "$log" | tail -1)
  if [ "$status" -ne 0 ]; then
    printf 'FAILED (exit %s) — %s\n' "$status" "$summary"
    echo "        ┌─ failing tests"
    grep -E '^✘ Test |error: ' "$log" | head -12 | sed 's/^/        │ /'
    echo "        └─"
    FAILED+=("swift test (exit $status) — $log"); return
  fi
  printf 'ok — %s\n' "$summary"
  PASSED+=("swift test")
}

echo
echo "Gates that need no device, account or signature:"
echo

run_swift_test

# The four python self-tests. Until v1.32 §D6 these were run by nothing at all.
for t in scripts/test_*.py; do
  run_gate "$(basename "$t")" "" python3 "$t"
done
# …and the shell one, which is the newest and guards the classification below.
run_gate "test_run_store_gates.sh" "" bash scripts/test_run_store_gates.sh

run_gate "check_versions.py" "" python3 scripts/check_versions.py

# `check_vocab_diff.py` is a DIFF guard: it compares the working tree against `--base` (default
# HEAD). With a clean tree there is nothing to compare, and it prints "ok  n5.json: 0 problem(s)"
# — the same words it prints after inspecting a real change. A null result from an instrument that
# had nothing to look at is not a pass, and this repo has a trap entry for exactly that.
#
# So the runner asks first whether there was anything to inspect, and says so.
#
# (§D6's own text specifies `check_vocab_diff.py --manifest`. That is not a valid invocation —
#  `--manifest` takes a path to a JSON declaring a reviewed structural change. The runner found
#  it on the first run, by exit 2.)
if [ -n "$VOCAB_BASE" ]; then
  # An explicit base was given, so there IS something to compare. Refuse a base that is not a
  # real commit rather than letting git's error read as "nothing changed".
  if ! git rev-parse --verify --quiet "$VOCAB_BASE^{commit}" > /dev/null; then
    printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (base '$VOCAB_BASE' is not a commit)"
    FAILED+=("check_vocab_diff.py — base '$VOCAB_BASE' does not resolve; a shallow checkout does this")
  else
    run_gate "check_vocab_diff.py --base $VOCAB_BASE" "" \
      python3 scripts/check_vocab_diff.py --base "$VOCAB_BASE"
  fi
elif [ -z "$(git diff --name-only HEAD -- Sources/VocabKit/Resources)" ]; then
  printf '  %-34s %s\n' "check_vocab_diff.py" "vacuous (no corpus change in the working tree)"
  VACUOUS+=("check_vocab_diff.py")
else
  run_gate "check_vocab_diff.py" "" python3 scripts/check_vocab_diff.py
fi

# 3 = "the StoreKit gates ran and SKIPPED" — its documented no-coverage state, and the state this
# repo has been in since 2026-08-30. It is reported, never absorbed. 4 (harness error) and 65 (a
# gate genuinely failed) are failures and are NOT on the tolerated list.
if [ -n "$HEADLESS" ]; then
  printf '  %-34s %s\n' "run_store_gates.sh" "skipped (--headless: needs xcodebuild)"
else
  run_gate "run_store_gates.sh" "3" bash scripts/run_store_gates.sh
fi

echo
echo "──────────────────────────────────────────────────────────────"
printf '  passed:      %d\n' "${#PASSED[@]}"
printf '  no coverage: %d' "${#NOCOVERAGE[@]}"
if [ "${#NOCOVERAGE[@]}" -gt 0 ]; then printf '  → %s' "${NOCOVERAGE[*]}"; fi
printf '\n'
printf '  vacuous:     %d' "${#VACUOUS[@]}"
if [ "${#VACUOUS[@]}" -gt 0 ]; then printf '  → %s' "${VACUOUS[*]}"; fi
printf '\n'
printf '  FAILED:      %d\n' "${#FAILED[@]}"

# A summary that cannot lie: it names how many gates it RAN, and refuses to report a pass if that
# number is implausible. A loop over a glob that matched nothing would otherwise print "0 failed"
# and read exactly like a clean run — this repo's oldest defect, pointed at its own runner.
TOTAL=$(( ${#PASSED[@]} + ${#NOCOVERAGE[@]} + ${#FAILED[@]} + ${#VACUOUS[@]} ))
printf '  gates run:   %d\n' "$TOTAL"
FLOOR=8
if [ -n "$HEADLESS" ]; then FLOOR=7; fi
if [ "$TOTAL" -lt "$FLOOR" ]; then
  echo
  echo "  ❌ only $TOTAL gate(s) ran. This script expects at least $FLOOR; a glob that matched nothing"
  echo "     would otherwise print a clean summary. Fix the runner before believing it."
  exit 1
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo
  echo "  ❌ failures:"
  for f in "${FAILED[@]}"; do echo "     $f"; done
  exit 1
fi

if [ "${#NOCOVERAGE[@]}" -gt 0 ]; then
  echo
  echo "  ⚠️  ${#NOCOVERAGE[@]} gate(s) at a documented NO-COVERAGE state. Nothing failed, and"
  echo "     nothing proved the purchase flow either. See PLAN-STAGE1 §L."
fi
if [ "${#VACUOUS[@]}" -gt 0 ]; then
  echo
  echo "  ℹ️  ${#VACUOUS[@]} gate(s) had nothing to inspect. That is not the same as passing."
fi
echo
echo "  ✅ every gate that ran, passed."
echo "     NOT run here: run_ios_placement_tests.sh (simulator), check_prod_schema.sh (keychain,"
echo "     and already wired into both upload paths), launch_gate.sh (signed .app + iCloud)."
exit 0
