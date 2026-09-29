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
# --vocab-base REF  what check_vocab_diff.py compares against. CI passes the push's "before" or
#                   the PR's base. Without it the runner compares against the last shipped
#                   release, release_numbers.BASELINE_REF — this release's whole corpus change
#                   plus the working tree — never against HEAD alone, which on a clean tree is a
#                   comparison with itself (see the vocabulary gate below).
# --vocab-only      run ONLY the vocabulary gate and exit with its verdict: 0 pass, 1 fail,
#                   3 vacuous. Not a release check — the floor below does not apply to it. It
#                   exists so scripts/test_check_vocab_diff.py can drive THIS file's gate end to
#                   end on a fixture, and prove the manifest actually reaches the guard.
HEADLESS=""
VOCAB_BASE=""
VOCAB_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --headless) HEADLESS=1; shift ;;
    --vocab-base) VOCAB_BASE="$2"; shift 2 ;;
    --vocab-only) VOCAB_ONLY=1; shift ;;
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
  # Built outside any iCloud-synced folder: since macOS 27, codesign refuses every test bundle
  # created under ~/Documents (see scripts/build_root.sh). Same tests, different build directory.
  local root scratch
  : > "$log"
  if ! root="$(bash "$REPO/scripts/build_root.sh" "$REPO" 2>>"$log")" || [ -z "$root" ]; then
    printf 'FAILED (scripts/build_root.sh could not name a build root — see %s)\n' "$log"
    FAILED+=("swift test (build_root.sh failed) — $log"); return
  fi
  scratch="$root/swiftpm"
  echo "swift test --scratch-path $scratch" >> "$log"
  swift test --scratch-path "$scratch" >> "$log" 2>&1
  status=$?
  # The run must have REACHED a summary. A signal death mid-suite can leave status 0-ish output
  # and truncated text; "no summary line" is a failure, not silence.
  if ! grep -qE "Test run with [0-9]+ tests?" "$log"; then
    printf 'FAILED (no summary line — the suite did not complete)\n'
    echo "        ┌─ last 20 lines (a signal death leaves truncated output)"
    tail -20 "$log" | sed 's/^/        │ /'
    echo "        └─"
    FAILED+=("swift test (never completed) — $log"); return
  fi
  local summary
  # Swift 6.3 prints ONE "Test run with N tests in M suites" line; Swift 6.4 prints one PER TEST
  # TARGET. Taking the last line reported "42 tests in 3 suites" for a run of 796 (measured
  # 2026-09-17) — the number shown and the run produced, computed two different ways. Sum them.
  summary=$(grep -oE "Test run with [0-9]+ tests? in [0-9]+ suites?" "$log" \
    | awk '{t += $4; s += $7; n++} END {printf "Test run with %d tests in %d suites (%d summary line%s)", t, s, n, (n == 1 ? "" : "s")}')
  # Per-target summaries (Swift 6.4) must be COMPLETE: one line per test target. A run cut short
  # after some targets would otherwise print "ok" with a partial total. A single aggregate line
  # (Swift 6.3, CI) is complete by construction. (Review 2026-09-17.)
  local lines targets
  lines=$(grep -cE "Test run with [0-9]+ tests? in [0-9]+ suites?" "$log")
  targets=$(grep -c '\.testTarget(' "$REPO/Package.swift")
  if [ "$lines" -gt 1 ] && [ "$lines" -lt "$targets" ]; then
    printf 'FAILED (%s of %s test targets reported a summary — the run is incomplete)\n' "$lines" "$targets"
    FAILED+=("swift test (incomplete: $lines/$targets targets) — $log"); return
  fi
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

# The vocabulary gate. A function so `--vocab-only` can run exactly this code and nothing else.
#
# `check_vocab_diff.py` is a DIFF guard: it compares the working tree against `--base`. Two ways
# for it to say "ok" while inspecting nothing, both of which this runner used to have:
#
#   1. A base equal to the tree. Its own default is HEAD, so a clean tree compared with HEAD
#      prints "ok  n5.json: 0 problem(s)" — the same words it prints after inspecting a real
#      change. The runner's LOCAL mode asked whether HEAD~1 had a corpus change, found one, and
#      then ran the guard with no --base at all: it tested the last commit's change for being
#      empty and then compared the tree with HEAD. v1.35 round 2 made it pass --base HEAD~1, so
#      the window tested for emptiness and the window inspected were one window — but HEAD~1 is
#      still the wrong window. A release ends with a version-bump commit that touches no corpus
#      file, and from then on HEAD~1..tree is empty: the gate reported VACUOUS for a release
#      carrying 20+ reviewed corpus corrections, exactly when the release is checked last.
#      (`git diff HEAD` goes empty the moment a corpus change is committed for the same reason.)
#      So local mode compares against release_numbers.BASELINE_REF, the last shipped release —
#      the window CORPUS_MANIFEST declares — read from release_numbers.py, never typed here. It
#      is VACUOUS only when no Sources/VocabKit/Resources/n*.json differs from that release; a
#      BASELINE_REF that cannot be read or does not resolve is a FAILURE, not a fallback.
#      (v1.32 pre-submission review; v1.35 rounds 2 and 3.)
#   2. No manifest. A release that DECLARES reviewed rewrites (release_numbers.CORPUS_MANIFEST)
#      fails the guard without the declaration. CI does pass a real base, so it failed v1.35's
#      seven declared corrections for exactly that reason (reproduced 2026-09-29 with
#      `--headless --vocab-base 060ced9` on the v1.35 branch). The manifest path is read from
#      release_numbers.py, the one place a release names it, never typed here: two copies of one
#      fact drift, and this repo has three recorded instances. A set path that does not exist, or
#      a release_numbers.py that cannot be read, is a FAILURE rather than a run without it —
#      a guard quietly run without its manifest fails for the wrong reason or, worse, a later
#      edit "fixes" that by dropping the base.
#
# (§D6's own text specifies `check_vocab_diff.py --manifest` with no path. That is not a valid
#  invocation — `--manifest` takes a JSON declaring a reviewed structural change. The runner
#  found it on the first run, by exit 2.)
#
# scripts/test_check_vocab_diff.py drives this function end to end (`--vocab-only`) on a fixture
# worktree, in both modes, and pins that every guard call below carries the manifest arguments.
# Its CI probes commit the change and pass the commit BEFORE it as the base, so the tree equals
# HEAD: a runner that dropped `--base` would compare HEAD with itself and pass, and they fail.
# Its local probes commit a change and then a corpus-free "version bump" on top, the case HEAD~1
# could not see.
#
# With no corpus change in the window the gate is reported VACUOUS — a null result from an
# instrument that had nothing to look at is not a pass, and this repo has a trap entry for that.
run_vocab_gate() {
  local manifest base
  if ! manifest="$(cd "$REPO" && python3 -c 'import sys; sys.path.insert(0, "scripts"); import release_numbers as r; print(r.CORPUS_MANIFEST or "")')"; then
    printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (cannot read CORPUS_MANIFEST from scripts/release_numbers.py)"
    FAILED+=("check_vocab_diff.py — scripts/release_numbers.py did not import; the manifest is unknown"); return
  fi
  VOCAB_MANIFEST_ARGS=()
  if [ -n "$manifest" ]; then
    if [ ! -f "$REPO/$manifest" ]; then
      printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (CORPUS_MANIFEST names $manifest, which does not exist)"
      FAILED+=("check_vocab_diff.py — manifest $manifest is missing"); return
    fi
    VOCAB_MANIFEST_ARGS=(--manifest "$manifest")
  fi

  if [ -n "$VOCAB_BASE" ]; then
    # An explicit base was given, so there IS something to compare. Refuse a base that is not a
    # real commit rather than letting git's error read as "nothing changed".
    if ! git rev-parse --verify --quiet "$VOCAB_BASE^{commit}" > /dev/null; then
      printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (base '$VOCAB_BASE' is not a commit)"
      FAILED+=("check_vocab_diff.py — base '$VOCAB_BASE' does not resolve; a shallow checkout does this")
      return
    fi
    base="$VOCAB_BASE"
  else
    if ! base="$(cd "$REPO" && python3 -c 'import sys; sys.path.insert(0, "scripts"); import release_numbers as r; print(r.BASELINE_REF or "")')" \
        || [ -z "$base" ]; then
      printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (cannot read BASELINE_REF from scripts/release_numbers.py)"
      FAILED+=("check_vocab_diff.py — local mode compares against release_numbers.BASELINE_REF, which did not read"); return
    fi
    if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
      printf '  %-34s %s\n' "check_vocab_diff.py" "FAILED (BASELINE_REF '$base' is not a commit)"
      FAILED+=("check_vocab_diff.py — BASELINE_REF '$base' does not resolve; a shallow checkout does this")
      return
    fi
    if [ -z "$(git diff --name-only "$base" -- 'Sources/VocabKit/Resources/n*.json')" ]; then
      printf '  %-34s %s\n' "check_vocab_diff.py" "vacuous (no corpus change since BASELINE_REF $base)"
      VACUOUS+=("check_vocab_diff.py"); return
    fi
  fi
  # ONE array is the command. The .cmd file, the row label and the "(manifest: …)" line are all
  # derived from it, and it is what runs. They used to be three separate strings beside the real
  # argv, so a flag dropped from the call still showed in the log and in the row, and a probe
  # that looked for "--base X" in the output was satisfied by the label (v1.35 round 4). The
  # guard also prints what it RECEIVED on its own first line; the probes read that line.
  # Bash 3.2 (macOS's /bin/bash) treats "${a[@]}" of an EMPTY array as unbound under `set -u`;
  # the `+` form expands to nothing instead.
  local -a cmd
  cmd=(python3 scripts/check_vocab_diff.py --base "$base" ${VOCAB_MANIFEST_ARGS[@]+"${VOCAB_MANIFEST_ARGS[@]}"})
  printf '%q ' "${cmd[@]}" > "$LOGS/check_vocab_diff.cmd"
  echo >> "$LOGS/check_vocab_diff.cmd"
  local i label cmd_base="" cmd_manifest=""
  for ((i = 2; i < ${#cmd[@]}; i++)); do
    case "${cmd[$i]}" in
      --base) cmd_base="${cmd[$((i + 1))]:-}" ;;
      --manifest) cmd_manifest="${cmd[$((i + 1))]:-}" ;;
    esac
  done
  label="${cmd[1]##*/}"
  if [ -n "$cmd_base" ]; then label="$label --base $cmd_base"; else label="$label (no --base)"; fi
  run_gate "$label" "" "${cmd[@]}"
  if [ -n "$cmd_manifest" ]; then
    printf '  %-34s %s\n' "" "(manifest: $cmd_manifest — scripts/release_numbers.py CORPUS_MANIFEST)"
  elif [ -n "$manifest" ]; then
    printf '  %-34s %s\n' "" "(NO --manifest passed, although CORPUS_MANIFEST names $manifest)"
  fi
}

if [ -n "$VOCAB_ONLY" ]; then
  run_vocab_gate
  if [ "${#FAILED[@]}" -gt 0 ]; then exit 1; fi
  if [ "${#VACUOUS[@]}" -gt 0 ]; then exit 3; fi
  exit 0
fi

echo
echo "Gates that need no device, account or signature:"
echo

run_swift_test

# The python self-tests — nine since 2026-09-29: the sales instrument (test_sales_report.py) and
# the Stage 1 walk tool (test_stage1_walk.py) got theirs on 2026-09-16, the build-root helper
# (test_build_root.py) on 2026-09-17, the review watch (test_review_watch.py, the §K guardrail
# reader's fixture test — its LIVE read needs the ASC key and is not a gate) on 2026-09-25
# (v1.34 §C2), and the corpus writers' quoting-residue refusal (test_escape_residue.py — 3e9407a's
# `I'''m`) on 2026-09-29, when its merge reached main. Until v1.32 §D6 these were run by nothing
# at all.
for t in scripts/test_*.py; do
  run_gate "$(basename "$t")" "" python3 "$t"
done
# …and the shell ones. Both guard a script that can REFUSE A RELEASE, which is exactly the
# authority a gate should not have before somebody has watched it fail.
run_gate "test_run_store_gates.sh" "" bash scripts/test_run_store_gates.sh
# exit 3 = the one POSITIVE case could not be built on this machine (no ad-hoc entitlements).
# Every other case expects a non-zero exit, so a run without it has proved only that the gate can
# say no — that is NO COVERAGE, not a pass, and it used to print `ok`.
run_gate "test_launch_gate.sh" "3" bash scripts/test_launch_gate.sh

run_gate "check_versions.py" "" python3 scripts/check_versions.py

run_vocab_gate

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
# The floor is the EXACT number of gates this script runs, not one below it. It used to be one
# below, which meant the single failure it exists to catch — a gate quietly disappearing, from a
# glob that stopped matching or a file that got renamed — left the total at exactly the floor and
# printed a clean summary. A threshold that the failure mode cannot cross is not a threshold.
# Adding a gate raises the total and still passes; REMOVING one has to be done in a diff that also
# moves this number, which is the whole point. (v1.32 pre-submission review.)
FLOOR=15
if [ -n "$HEADLESS" ]; then FLOOR=14; fi
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
