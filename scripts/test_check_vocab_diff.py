#!/usr/bin/env python3
"""Self-check for check_vocab_diff.py — does the guard actually fire?

This project's most expensive lesson is that a checker reporting "no problems" is
indistinguishable from a broken checker until it has been shown to catch a known
defect. `check_vocab_diff.py` prints "clean" on every commit, which is exactly the
shape of output that hides a rule that stopped working — and two of its rules were
measured to be doing nothing at all before v1.21: `exKana` could be rewritten
silently, and naming an entry in a manifest switched off the append-only rule for
that entry's other languages.

So each rule gets a POSITIVE probe (a mutation it must reject) and, where the rule
has a permitted counterpart, a NEGATIVE probe (a change it must still allow). A rule
that passes only its positive probe is a rule that rejects everything.

    python3 scripts/test_check_vocab_diff.py

Mutations are applied to a scratch copy of a real data file and reverted; the working
tree is never modified. Exit 0 when every probe behaves.

Since v1.35 round 2 it also tests the guard AS THE GATE RUNNER CALLS IT. The guard was
right and the runner was not: `run_all_gates.sh` invoked it without `--manifest`, so CI
(which passes a real base) failed on v1.35's declared corrections, and local mode compared
a clean tree with HEAD and printed a vacuous "ok". So three more groups of probes:

  * the release's OWN manifest (release_numbers.CORPUS_MANIFEST) against the release
    baseline (release_numbers.BASELINE_REF) must pass, and dropping any single declaration
    from it must fail — a declaration the diff does not need is a manifest out of step;
  * the runner, driven end to end (`--vocab-only`) on a fixture worktree whose
    release_numbers names a fixture manifest: a declared rewrite passes, the same rewrite
    with its declaration dropped fails, with no manifest it fails, and a manifest path that
    does not exist fails — in CI mode and in local mode;
  * a pin that every guard invocation in the runner carries the manifest arguments and that
    the path is read from release_numbers.py rather than typed.
"""
import ast
import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GUARD = REPO / "scripts/check_vocab_diff.py"
RUNNER = REPO / "scripts/run_all_gates.sh"
SOURCE = REPO / "Sources/VocabKit/Resources/n5.json"

sys.path.insert(0, str(REPO / "scripts"))
import release_numbers  # noqa: E402  — the ONE place a release names its manifest and baseline


def run_guard(entries, manifest=None, extra=()):
    """Runs the guard over `entries` written into a throwaway checkout of the repo.

    The guard diffs the working tree against a git ref, so the probe needs a place
    where the working tree can differ from HEAD without touching the real one: a
    linked worktree at HEAD gives exactly that, and is discarded afterwards.
    """
    with tempfile.TemporaryDirectory() as tmp:
        wt = Path(tmp) / "wt"
        subprocess.run(["git", "-C", str(REPO), "worktree", "add", "--detach", str(wt), "HEAD"],
                       capture_output=True, text=True, check=True)
        try:
            target = wt / "Sources/VocabKit/Resources/n5.json"
            target.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
            # Run the guard as it stands NOW, not as it stands at HEAD. Without this the
            # probes silently test the last committed version of the rules — which is how
            # the first run of this file reported all four new rules dead when they were
            # working, and would just as happily have reported a deleted rule alive.
            (wt / "scripts/check_vocab_diff.py").write_text(
                GUARD.read_text(encoding="utf-8"), encoding="utf-8")
            cmd = [sys.executable, str(wt / "scripts/check_vocab_diff.py"), *extra]
            if manifest is not None:
                mpath = Path(tmp) / "manifest.json"
                mpath.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
                cmd += ["--manifest", str(mpath)]
            out = subprocess.run(cmd, capture_output=True, text=True, cwd=str(wt))
            return out.returncode, out.stdout
        finally:
            subprocess.run(["git", "-C", str(REPO), "worktree", "remove", "--force", str(wt)],
                           capture_output=True, text=True)


# Every structural vocabulary change this project has actually shipped, with the commit
# that made it. Each must still pass the guard as it stands today.
HISTORICAL = [
    ("f0762d43b374bd52ff6a33bb7e1950856ee13696", "n3-conflated-gloss-manifest"),
    ("8823a3abd5582f5706014c4487c8ef1d31b3ad27", "n1-gloss-fix-manifest"),
    ("fea5435dd01bc9554a008c3d423509b22eb05ec2", "n3-chinese-fix-manifest"),
    ("78eeadbe6a71d9811738c1634a9c0fe0ca3ddbd5", "n3-retirement-manifest"),
]


def replay(commit, manifest_name):
    """Re-runs a shipped structural change through the CURRENT guard."""
    with tempfile.TemporaryDirectory() as tmp:
        wt = Path(tmp) / "wt"
        add = subprocess.run(["git", "-C", str(REPO), "worktree", "add", "--detach",
                              str(wt), commit], capture_output=True, text=True)
        if add.returncode != 0:
            return False, f"could not check out {commit}: {add.stderr}"
        try:
            (wt / "scripts/check_vocab_diff.py").write_text(
                GUARD.read_text(encoding="utf-8"), encoding="utf-8")
            out = subprocess.run(
                [sys.executable, str(wt / "scripts/check_vocab_diff.py"),
                 "--base", f"{commit}^",
                 "--manifest", str(wt / f"docs/measurements/{manifest_name}.json")],
                capture_output=True, text=True, cwd=str(wt))
            return out.returncode == 0, out.stdout + out.stderr
        finally:
            subprocess.run(["git", "-C", str(REPO), "worktree", "remove", "--force", str(wt)],
                           capture_output=True, text=True)


def main():
    base = json.loads(SOURCE.read_text(encoding="utf-8"))
    by_id = {e["id"]: e for e in base}

    # Pick real entries with the shapes the probes need, so a probe never depends on a
    # fabricated record the guard might treat differently.
    with_kana = next(e for e in base if e.get("exKana") and e.get("exTokens"))
    with_two_en = next(e for e in base if len(e.get("meanings", {}).get("en", [])) >= 2)
    without_example = next((e for e in base if not e.get("exJP")), None)

    def mutate(eid, change):
        entries = copy.deepcopy(base)
        for e in entries:
            if e["id"] == eid:
                change(e)
        return entries

    probes = []

    def probe(name, entries, must_fail, manifest=None, extra=(), expect_text=None):
        probes.append((name, entries, must_fail, manifest, extra, expect_text))

    # --- the two rules that were measured to be doing nothing before v1.21 -------------
    probe("exKana rewritten (the string a learner is graded against)",
          mutate(with_kana["id"], lambda e: e.__setitem__("exKana", e["exKana"] + "ん")),
          must_fail=True, expect_text="exKana OVERWRITTEN")
    probe("exTokens rewritten (furigana drifting off its kanji)",
          mutate(with_kana["id"], lambda e: e.__setitem__("exTokens", [["x", "x"]])),
          must_fail=True, expect_text="exTokens OVERWRITTEN")
    probe("manifest for ZH must not unguard EN — a reorder on a declared entry",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", list(reversed(e["meanings"]["en"])))),
          must_fail=True, manifest={"reason": "probe", "entries": [{"id": with_two_en["id"],
                                                                   "removeZH": []}]},
          expect_text="not append-only")
    probe("manifest for ZH must not unguard EN — a duplicated gloss on a declared entry",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", e["meanings"]["en"]
                                                     + [e["meanings"]["en"][0]])),
          must_fail=True, manifest={"reason": "probe", "entries": [{"id": with_two_en["id"],
                                                                   "removeZH": []}]},
          expect_text="duplicate gloss")

    # --- v1.21 §C: the one frozen field a manifest may move, and its four fences --------
    surf = with_kana
    probe("surface rewritten with NO manifest",
          mutate(surf["id"], lambda e: e.__setitem__("surface", e["surface"] + "々")),
          must_fail=True, expect_text="surface changed")
    probe("surface rewritten to a value the manifest did NOT name",
          mutate(surf["id"], lambda e: e.__setitem__("surface", e["surface"] + "々")),
          must_fail=True,
          manifest={"reason": "probe", "entries": [{"id": surf["id"],
                                                    "rewriteSurface": "something-else"}]},
          expect_text="manifest declared")
    probe("surface and kana moved TOGETHER under a manifest (the refused kana edit in a hat)",
          mutate(surf["id"], lambda e: (e.__setitem__("surface", e["surface"] + "々"),
                                        e.__setitem__("kana", e["kana"] + "ん"))),
          must_fail=True,
          manifest={"reason": "probe", "entries": [{"id": surf["id"],
                                                    "rewriteSurface": surf["surface"] + "々"}]},
          expect_text="TOGETHER")
    probe("manifest promises a surface rewrite that did not happen",
          copy.deepcopy(base), must_fail=True,
          manifest={"reason": "probe", "entries": [{"id": surf["id"],
                                                    "rewriteSurface": "never-applied"}]},
          expect_text="manifest promised surface")
    probe("a DECLARED surface rewrite, kana untouched, is allowed",
          mutate(surf["id"], lambda e: e.__setitem__("surface", e["surface"] + "々")),
          must_fail=False,
          manifest={"reason": "probe", "entries": [{"id": surf["id"],
                                                    "rewriteSurface": surf["surface"] + "々"}]})

    # --- v1.22: a retirement has to say where its learners actually go -----------------
    retiree = base[0]
    probe("a retirement whose replacedBy names nothing in the corpus",
          [e for e in copy.deepcopy(base) if e["id"] != retiree["id"]],
          must_fail=True,
          manifest={"reason": "probe", "entries": [{"id": retiree["id"], "retire": True,
                                                    "replacedBy": "n9-does-not-exist"}]},
          expect_text="not an entry anywhere in the corpus")
    probe("a retirement whose replacedBy names an entry in ANOTHER level file is allowed",
          [e for e in copy.deepcopy(base) if e["id"] != retiree["id"]],
          must_fail=False,
          manifest={"reason": "probe", "entries": [{"id": retiree["id"], "retire": True,
                                                    "replacedBy": _any_id_in("n1")}]})

    # --- the permitted counterparts: a guard that rejects everything is not a guard ----
    probe("filling an ABSENT exKana is still allowed (write-once, not frozen)",
          mutate(with_kana["id"], lambda e: e.pop("exKana", None)) and None or
          _fill_from(base, with_kana["id"]),
          must_fail=False)
    probe("appending a gloss is still allowed",
          mutate(with_two_en["id"], lambda e: e["meanings"]["en"].append("probe-gloss")),
          must_fail=False)
    probe("a declared gloss removal is still allowed",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", e["meanings"]["en"][:-1])),
          must_fail=False,
          manifest={"reason": "probe", "entries": [
              {"id": with_two_en["id"], "removeEN": [with_two_en["meanings"]["en"][-1]]}]})
    probe("an unchanged tree is clean", copy.deepcopy(base), must_fail=False)

    # --- v1.35 round 2: finalEN / finalZH were written into every gloss manifest and read by
    # nothing. A manifest promising one list while the data ships another must now fail. ---
    probe("a declared removal whose finalEN does not match the shipped list",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", e["meanings"]["en"][:-1])),
          must_fail=True,
          manifest={"reason": "probe", "entries": [
              {"id": with_two_en["id"], "removeEN": [with_two_en["meanings"]["en"][-1]],
               "finalEN": with_two_en["meanings"]["en"]}]},
          expect_text="manifest declared final meanings.en")
    probe("a declared removal whose finalEN matches the shipped list is allowed",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", e["meanings"]["en"][:-1])),
          must_fail=False,
          manifest={"reason": "probe", "entries": [
              {"id": with_two_en["id"], "removeEN": [with_two_en["meanings"]["en"][-1]],
               "finalEN": with_two_en["meanings"]["en"][:-1]}]})

    # --- the rules that were already working, so a refactor cannot quietly drop them ---
    probe("kana rewritten (identity is frozen)",
          mutate(with_kana["id"], lambda e: e.__setitem__("kana", e["kana"] + "ん")),
          must_fail=True, expect_text="kana changed")
    probe("a gloss removed with no manifest",
          mutate(with_two_en["id"],
                 lambda e: e["meanings"].__setitem__("en", e["meanings"]["en"][:-1])),
          must_fail=True, expect_text="not append-only")
    probe("exEN rewritten with no manifest",
          mutate(next(e["id"] for e in base if e.get("exEN")),
                 lambda e: e.__setitem__("exEN", "probe rewrite")),
          must_fail=True, expect_text="exEN OVERWRITTEN")

    # --- and the changes this project HAS made must all still pass ---------------------
    # A guard is only as good as the legitimate work it lets through. Tightening the
    # manifest rules in v1.21 rejected n3-conflated-gloss-manifest — a reviewed correction
    # that shipped in v1.18 — because correcting a wrong gloss list is exactly the case
    # where the surviving glosses get reordered around the removal. Nothing would have said
    # so; every synthetic probe passed. So the real history is a probe now.
    replay_failures = []
    for commit, manifest_name in HISTORICAL:
        ok, out = replay(commit, manifest_name)
        print(f"{'ok  ' if ok else 'FAIL'}  must allow   shipped manifest {manifest_name} "
              f"({commit[:8]})")
        if not ok:
            replay_failures.append((manifest_name, out))

    failures = list(replay_failures)
    failures += release_manifest_probes()
    failures += runner_probes(with_kana)
    failures += runner_pins()
    for name, entries, must_fail, manifest, extra, expect_text in probes:
        code, out = run_guard(entries, manifest, extra)
        fired = code != 0
        ok = fired == must_fail
        if ok and expect_text and expect_text not in out:
            ok = False
            out += f"\n(fired, but not for the expected reason {expect_text!r})"
        print(f"{'ok  ' if ok else 'FAIL'}  {'must reject' if must_fail else 'must allow '}  {name}")
        if not ok:
            failures.append((name, out))

    if failures:
        print(f"\n{len(failures)} probe(s) behaved wrongly — the guard is not doing what it says.")
        for name, out in failures:
            print(f"\n--- {name} ---\n{out.strip()}")
        return 1
    print(f"\nall {len(probes)} guard probes, {len(HISTORICAL)} replays, the release-manifest probes, "
          f"the runner probes and the pin behaved: the guard rejects what it must and allows what it "
          f"must, and run_all_gates.sh hands it this release's manifest.")
    return 0


def _report(ok, must_fail, name, out, failures):
    print(f"{'ok  ' if ok else 'FAIL'}  {'must reject' if must_fail else 'must allow '}  {name}")
    if not ok:
        failures.append((name, out))


def release_manifest_probes():
    """The release's own manifest against the release baseline, and every declaration in it
    shown to be NEEDED.

    "With the manifest it passes" alone is satisfied by a manifest that declares everything
    and by a guard that ignores manifests. So each permission the manifest grants is removed
    in turn, and the guard must then refuse: that proves the pass came from the declaration,
    and that the manifest declares nothing the release does not contain. A declaration that
    turns out unnecessary means CORPUS_MANIFEST and BASELINE_REF are out of step (one was
    advanced for a release and the other was not), which is a finding, not noise.
    """
    failures = []
    path, base = release_numbers.CORPUS_MANIFEST, release_numbers.BASELINE_REF
    if path is None:
        print("n/a   release manifest probes: CORPUS_MANIFEST is None — this release declares "
              "no corpus change, so there is nothing of its own to replay")
        return failures
    real = json.loads((REPO / path).read_text(encoding="utf-8"))

    def guard(manifest):
        with tempfile.TemporaryDirectory() as tmp:
            mpath = Path(tmp) / "manifest.json"
            mpath.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
            out = subprocess.run([sys.executable, str(GUARD), "--base", base,
                                  "--manifest", str(mpath)],
                                 capture_output=True, text=True, cwd=str(REPO))
            return out.returncode, out.stdout + out.stderr

    code, out = guard(real)
    _report(code == 0, False, f"this release's manifest ({Path(path).name}) against the "
            f"release baseline {base}", out, failures)

    # Every permission, one at a time: a whole entry, and each field inside it that grants one.
    variants = []
    for k, entry in enumerate(real["entries"]):
        variants.append((f"{entry['id']} (whole declaration)", k, None))
        for field in entry.get("rewrite") or []:
            variants.append((f"{entry['id']} rewrite {field}", k, ("rewrite", field)))
        for key in ("removeEN", "removeZH"):
            if entry.get(key):
                variants.append((f"{entry['id']} {key}", k, (key, None)))
    for label, k, what in variants:
        m = copy.deepcopy(real)
        if what is None:
            del m["entries"][k]
        elif what[0] == "rewrite":
            m["entries"][k]["rewrite"] = [f for f in m["entries"][k]["rewrite"] if f != what[1]]
        else:
            del m["entries"][k][what[0]]
        code, out = guard(m)
        eid = real["entries"][k]["id"]
        ok = code != 0 and eid in out
        if not ok:
            out += (f"\n(dropping {label} did not make the guard refuse {eid} against {base}: "
                    "either the manifest declares a change the corpus does not contain, or "
                    "CORPUS_MANIFEST and BASELINE_REF in release_numbers.py are out of step)")
        _report(ok, True, f"release manifest minus {label}", out, failures)
    return failures


@contextmanager
def _fixture_worktree():
    """A throwaway checkout at HEAD carrying the CURRENT runner and guard."""
    with tempfile.TemporaryDirectory() as tmp:
        wt = Path(tmp) / "wt"
        subprocess.run(["git", "-C", str(REPO), "worktree", "add", "--detach", str(wt), "HEAD"],
                       capture_output=True, text=True, check=True)
        try:
            for rel in ("scripts/check_vocab_diff.py", "scripts/run_all_gates.sh"):
                (wt / rel).write_text((REPO / rel).read_text(encoding="utf-8"), encoding="utf-8")
            yield wt, Path(tmp)
        finally:
            subprocess.run(["git", "-C", str(REPO), "worktree", "remove", "--force", str(wt)],
                           capture_output=True, text=True)


def _point_release_numbers_at(wt, value):
    """Make the fixture's release_numbers.py name `value` (a repo-relative path, or None)."""
    rn = wt / "scripts/release_numbers.py"
    text = rn.read_text(encoding="utf-8")
    new, n = re.subn(r"^CORPUS_MANIFEST = .*$", f"CORPUS_MANIFEST = {value!r}", text,
                     count=1, flags=re.M)
    if n != 1:
        raise SystemExit("probe setup failed: release_numbers.py has no `CORPUS_MANIFEST = …` "
                         "line to point at a fixture — the runner probes would test nothing")
    rn.write_text(new, encoding="utf-8")


def _run_runner(wt, tmp, extra):
    logs = tmp / f"logs-{len(list(tmp.glob('logs-*')))}"
    env = dict(os.environ, GATE_LOG_DIR=str(logs))
    out = subprocess.run(["bash", str(wt / "scripts/run_all_gates.sh"), "--vocab-only", *extra],
                         capture_output=True, text=True, cwd=str(wt), env=env)
    text = out.stdout + out.stderr
    for log in sorted(logs.glob("*")) if logs.exists() else []:
        text += f"\n--- {log.name}\n" + log.read_text(encoding="utf-8", errors="replace")
    return out.returncode, text


def runner_probes(with_kana):
    """run_all_gates.sh's vocabulary gate, end to end, on a fixture.

    The fixture rewrites one reviewed exKana — the change a release declares — and names a
    fixture manifest through the worktree's own release_numbers.py, the way a release does.
    """
    failures = []
    fixture_rel = "fixture-corpus-manifest.json"
    declared = {"id": with_kana["id"], "rewrite": ["exKana"]}
    with _fixture_worktree() as (wt, tmp):
        # The fixture is HEAD, so the "real" manifest is HEAD's — read from the fixture's own
        # release_numbers.py before it is re-pointed, not from the working tree's.
        m = re.search(r"^CORPUS_MANIFEST = (.*?)(\s+#.*)?$",
                      (wt / "scripts/release_numbers.py").read_text(encoding="utf-8"), re.M)
        real_path = ast.literal_eval(m.group(1)) if m else None
        real_entries = (json.loads((wt / real_path).read_text(encoding="utf-8"))["entries"]
                        if real_path else [])
        target = wt / "Sources/VocabKit/Resources/n5.json"
        entries = json.loads(target.read_text(encoding="utf-8"))
        for e in entries:
            if e["id"] == with_kana["id"]:
                e["exKana"] = e["exKana"] + "ん"
        target.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")

        def case(name, must_fail, manifest_entries, point_at, extra, expect=()):
            if manifest_entries is not None:
                (wt / fixture_rel).write_text(json.dumps(
                    {"reason": "runner probe", "entries": manifest_entries},
                    ensure_ascii=False), encoding="utf-8")
            _point_release_numbers_at(wt, point_at)
            code, out = _run_runner(wt, tmp, extra)
            ok = (code == 1) if must_fail else (code == 0)
            missing = [t for t in expect if t not in out]
            if ok and missing:
                ok = False
                out += f"\n(right exit code, but the output lacks {missing!r})"
            _report(ok, must_fail, f"runner: {name}", out, failures)

        # CI mode: an explicit base, exactly as .github/workflows/gates.yml calls it. HEAD here
        # is the fixture's HEAD, so the one difference is the fixture rewrite.
        ci = ["--vocab-base", "HEAD"]
        case("CI mode, the rewrite declared in CORPUS_MANIFEST", False, [declared],
             fixture_rel, ci,
             expect=("structural change declared", f"--manifest {fixture_rel}"))
        case("CI mode, the same rewrite with its declaration dropped", True, [],
             fixture_rel, ci, expect=("exKana OVERWRITTEN",))
        case("CI mode, CORPUS_MANIFEST = None", True, None, None, ci,
             expect=("exKana OVERWRITTEN",))
        case("CI mode, CORPUS_MANIFEST names a file that does not exist", True, None,
             "docs/measurements/no-such-manifest.json", ci, expect=("does not exist",))
        # Local mode: no base, so the runner compares against HEAD~1 — the last commit's
        # corpus change as well as the working tree. That window holds whatever the real
        # release manifest declares, so the fixture manifest is the real one plus the fixture.
        case("local mode, the rewrite declared (compared against HEAD~1)", False,
             real_entries + [declared], fixture_rel, [],
             expect=("--base HEAD~1", "structural change declared"))
        case("local mode, the same rewrite with its declaration dropped", True,
             real_entries, fixture_rel, [], expect=("exKana OVERWRITTEN",))
    return failures


def runner_pins():
    """The runner reads the manifest from release_numbers and passes it on EVERY invocation."""
    failures = []
    text = RUNNER.read_text(encoding="utf-8")
    calls = [ln for ln in text.splitlines()
             if re.search(r"python3 scripts/check_vocab_diff\.py", ln)
             and not ln.lstrip().startswith("#")]
    problems = []
    if not calls:
        problems.append("no invocation of check_vocab_diff.py found — the pin would pass vacuously")
    problems += [f"invocation without the manifest arguments: {ln.strip()}"
                 for ln in calls if "VOCAB_MANIFEST_ARGS" not in ln]
    if "import release_numbers" not in text or "CORPUS_MANIFEST" not in text:
        problems.append("the runner does not read CORPUS_MANIFEST from release_numbers.py")
    typed = re.findall(r"docs/measurements/[\w.-]*manifest[\w.-]*\.json", text)
    if typed:
        problems.append(f"the runner types a manifest path instead of reading it: {typed}")
    _report(not problems, True, "pin: every guard call in run_all_gates.sh carries "
            "release_numbers.CORPUS_MANIFEST", "\n".join(problems), failures)
    return failures


def _any_id_in(level):
    """An id from a DIFFERENT level file — the cross-file case a per-file check would have
    rejected, and which is exactly what ぺん -> ペン did."""
    path = REPO / f"Sources/VocabKit/Resources/{level}.json"
    return json.loads(path.read_text(encoding="utf-8"))[0]["id"]


def _fill_from(base, eid):
    """An entry whose exKana was never there, so the probe fills rather than overwrites.

    Removing the field from the WORKING TREE copy is a deletion, not a fill. To test the
    fill the old side must be the empty one — which needs a field the shipped data does
    not carry. `exKana` is absent on exactly 14 entries; use one of those and give it a
    value, which is precisely the write-once-allowed case.
    """
    entries = copy.deepcopy(base)
    for e in entries:
        if e.get("exJP") and not e.get("exKana"):
            e["exKana"] = "ぷろーぶ"
            return entries
    # No such entry in this file. A no-op tree would PASS the must-allow probe while
    # testing nothing, which is the exact failure this whole file exists to prevent — so
    # say so instead.
    raise SystemExit("probe setup failed: n5.json has no entry with exJP and no exKana, "
                     "so the fill-an-empty-field case cannot be exercised. Point _fill_from "
                     "at a file that does, or drop the probe deliberately.")


if __name__ == "__main__":
    sys.exit(main())
