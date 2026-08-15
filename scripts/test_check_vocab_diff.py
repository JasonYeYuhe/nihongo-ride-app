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
"""
import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GUARD = REPO / "scripts/check_vocab_diff.py"
SOURCE = REPO / "Sources/VocabKit/Resources/n5.json"


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
    print(f"\nall {len(probes)} probes behaved: the guard rejects what it must and allows what it must.")
    return 0


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
