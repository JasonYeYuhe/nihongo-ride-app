#!/usr/bin/env python3
"""Every number that may appear in release copy, measured from the shipped corpus.

WHY. v1.25's What's New told users "Fifty more sentences are available in Dictation". The
measured figure is 42: the pool went 5,720 -> 5,762, and eight sentences were put back into
exclusion by the final review pass AFTER the copy was written. The repo then disagreed with
itself in three places about the pool size. This is the count-vs-run defect wearing marketing
copy, and the fix is that a number in release copy is derived here rather than typed.

Import it (`from release_numbers import numbers`) or run it to print the table.
"""
import json
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"


def previous(ref="60c9ed9"):
    """The same figures at the release baseline, so a delta is measured rather than remembered."""
    out = {}
    try:
        for level in ("n1", "n2", "n3", "n4", "n5"):
            raw = subprocess.run(["git", "show", f"{ref}:Sources/VocabKit/Resources/{level}.json"],
                                 cwd=REPO, capture_output=True, text=True, check=True).stdout
            out.setdefault("entries", []).extend(json.loads(raw))
        raw = subprocess.run(["git", "show", f"{ref}:Sources/VocabKit/Resources/dictation-exclusions.json"],
                             cwd=REPO, capture_output=True, text=True, check=True).stdout
        excluded = {r["id"] for r in json.loads(raw)["excluded"]}
    except subprocess.CalledProcessError as exc:
        return {"error": str(exc)}
    typeable = [e for e in out["entries"] if e.get("exJP") and e.get("exKana")]
    return {"dictationExcluded": len(excluded),
            "dictationPool": len([e for e in typeable if e["id"] not in excluded])}


def numbers():
    entries = []
    for level in ("n1", "n2", "n3", "n4", "n5"):
        entries += json.loads((RESOURCES / f"{level}.json").read_text(encoding="utf-8"))
    excluded = {r["id"] for r in json.loads(
        (RESOURCES / "dictation-exclusions.json").read_text(encoding="utf-8"))["excluded"]}
    typeable = [e for e in entries if e.get("exJP") and e.get("exKana")]
    with_example = [e for e in entries if e.get("exJP")]

    manifest = json.loads((REPO / "docs/measurements/v126-stem-reading-manifest.json")
                          .read_text(encoding="utf-8"))
    residue = json.loads((REPO / "docs/measurements/v126-uninspected-residue.json")
                         .read_text(encoding="utf-8"))
    notes = json.loads((RESOURCES / "reading-notes.json").read_text(encoding="utf-8"))["notes"]

    # The run caps the release copy quotes. Read from the source of truth rather than typed
    # beside it: "the menu announces fifteen and rides fifteen" is a claim about a constant,
    # and a claim about a constant belongs next to the constant.
    app = (REPO / "Sources/NihongoRideApp/AppModel.swift").read_text(encoding="utf-8")
    caps = {}
    for name in ("weakWordsRunSize", "conjugationRunSize"):
        m = re.search(rf"static let {name}\s*=\s*(\d+)", app)
        if not m:
            raise SystemExit(f"release_numbers: cannot find {name} in AppModel.swift — "
                             "the copy quotes it, so a rename must not silently keep the old figure")
        caps[name] = int(m.group(1))

    before = previous()
    withheld = (len(excluded) - before["dictationExcluded"]) if "error" not in before else None

    return {
        "entries": len(entries),
        "withExample": len(with_example),
        "typeable": len(typeable),
        "dictationExcluded": len(excluded),
        "dictationPool": len([e for e in typeable if e["id"] not in excluded]),
        "correctedThisRelease": len(manifest["entries"]),
        "uninspectedResidue": residue["total"],
        "readingNotes": len(notes),
        "weakWordsRunSize": caps["weakWordsRunSize"],
        "conjugationRunSize": caps["conjugationRunSize"],
        "dictationPoolBefore": before.get("dictationPool"),
        "withheldThisRelease": withheld,
    }


if __name__ == "__main__":
    now, before = numbers(), previous()
    for key, value in now.items():
        print(f"  {key:24s} {value}")
    print("\n  --- against the release baseline ---")
    for key, value in before.items():
        if key in now:
            print(f"  {key:24s} {value} -> {now[key]}  ({now[key] - value:+d})")
        else:
            print(f"  {key:24s} {value}")
