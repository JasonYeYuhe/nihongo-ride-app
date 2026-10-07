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

# Set to this release's corpus-change manifest, or None when the release changes no corpus.
CORPUS_MANIFEST = "docs/measurements/v136-reading-manifest.json"   # v1.36: n5-kazoku 四人 よにん (PLAN-V1.36 §C item 3)
# Was "docs/measurements/v135-residue-manifest.json" for v1.35 (7 residue + 13 何 + 2 round-3 corrections).
# Was None from v1.27 through v1.34 ("v1.30 ships the paid route and touches no vocabulary file").


# Advanced with every release. v1.27 moved it from 60c9ed9 (the v1.25 baseline) to the v1.26
# release commit, so "this release" means since 1.26 and not since 1.25. Leaving it behind is how
# a delta silently becomes a two-release total — the stale-number failure this module exists for.
BASELINE_REF = "fdb2b5f"      # release(v1.35): the tree 1.35 (macOS 60 / iOS 61) was built from
# Also the window run_all_gates.sh's LOCAL vocabulary gate inspects (v1.35 round 3): it used
# HEAD~1, which a release's closing version-bump commit empties. One ref, read by both.
# Moved 2026-10-07 in the same commit as v1.36's first corpus change and CORPUS_MANIFEST's move to
# v1.36 (PLAN-V1.36 §C items 3 and 5), so the two name one window from the start. 1.35 is on sale.
# Was 281fc45 (release(v1.34): the tree 1.34, macOS 59 / iOS 60, was built from) through v1.35.
# Moved 2026-09-29 (v1.35 round 2), and late: it still named v1.32 while CORPUS_MANIFEST named
# v1.35, so every "this release" delta spanned v1.33 + v1.34 + v1.35. The printed figures did not
# move when it was corrected (793 excluded / 5,931 pool at both refs) only because v1.33 and v1.34
# withheld or released no sentence: right by luck, which is not the same as right. "This release"
# means against what is on sale, and 1.34 is what is on sale.
# Was 0d98a20 (v1.32) through v1.34 — "advanced with v1.33" said the comment, and it was not.
# Was f258801 (v1.31) through v1.32.
# Was eb28e02 (v1.30) until v1.32 — two releases behind, so every "this release" delta computed
# from it silently included v1.31. n2.json changed inside that window, which is exactly the
# stale-number failure the paragraph above names. Advance it WITH the release, not after it.


def previous(ref=BASELINE_REF):
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

    # The corpus manifest for the CURRENT release, or none when a release changes no corpus.
    # v1.27 changes none, so `correctedThisRelease` must be 0 rather than v1.26's 5 — a number
    # that describes the previous release while the copy calls it "this release" is the exact
    # defect this module was written to end.
    manifest = ({"entries": []} if CORPUS_MANIFEST is None
                else json.loads((REPO / CORPUS_MANIFEST)
                                .read_text(encoding="utf-8")))
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

    # The shape of the two roads, read from the shipped route rather than typed beside it.
    #
    # v1.30's copy names how many stretches the paid road has and where it starts and ends, and
    # the review notes name the free road's length in kilometres. Those are claims about a
    # constant, and a claim about a constant belongs next to the constant — the same reason the
    # run caps above are read out of AppModel. A route edit that left the copy behind is
    # `passages` all over again: 183 in two live listings for months after the corpus said 233.
    route_src = (REPO / "Sources/SceneryKit/RideRoute.swift").read_text(encoding="utf-8")
    stages = re.findall(
        r'RideStage\(id: (\d+), road: \.(\w+), name: "([^"]+)", romaji: "([^"]+)",'
        r'\s*startMetres: ([\d_]+)', route_src)
    roads = {}
    for sid, road, name, romaji, metres in stages:
        roads.setdefault(road, []).append((int(sid), name, romaji, int(metres.replace("_", ""))))
    # A regex that silently matches nothing produces a plausible zero, and this project has
    # shipped that shape more than once. Assert the population before reading anything off it:
    # both roads present, both non-empty, and the ids contiguous from 0 — so a renamed field or
    # a reformatted declaration fails loudly here instead of quietly halving a number in copy.
    for road in ("tokaido", "west"):
        if not roads.get(road):
            raise SystemExit(f"release_numbers: parsed no {road} stretches out of RideRoute.swift "
                             "— the declaration shape changed and the copy would quote a zero")
    ids = sorted(sid for group in roads.values() for sid, *_ in group)
    if ids != list(range(len(ids))):
        raise SystemExit(f"release_numbers: stage ids are not contiguous from 0: {ids}")
    tokaido = sorted(roads["tokaido"])
    west = sorted(roads["west"])

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
        # Quoted in the App Store description in every locale. Both live listings said 183 for
        # months after the corpus reached 233 -- the same defect as v1.25's "fifty more
        # sentences" against a measured 42, moved from What's New to the description, where
        # nobody was re-reading it. Computed here so the copy cannot be typed.
        "passages": len(json.loads((RESOURCES / "passages.json").read_text(encoding="utf-8"))),
        "weakWordsRunSize": caps["weakWordsRunSize"],
        "conjugationRunSize": caps["conjugationRunSize"],
        "dictationPoolBefore": before.get("dictationPool"),
        # Signed: positive means sentences LEFT the dictation pool this release, negative
        # means they returned to it. v1.28 released 11, so this reads -11 — a figure that
        # says the opposite of its own name if quoted without its sign. `releasedThisRelease`
        # exists so release copy can never quote the wrong direction.
        "withheldThisRelease": withheld,
        "releasedThisRelease": (-withheld if withheld is not None and withheld < 0 else 0),
        # Sentences withheld from Dictation that are PROVEN to be spoken differently from their
        # own answer key, as opposed to merely undecided. The review notes quote it, so it is
        # computed: a figure typed into copy sent to App Review is the same defect as one typed
        # into What's New, only with a smaller audience and a worse consequence.
        "dictationProvenMisread": sum(
            1 for r in json.loads((REPO / "docs/measurements/dictation-reading-mismatches.json")
                                  .read_text(encoding="utf-8"))["excluded"]
            if str(r.get("evidence", "")).startswith("proven")),
        # The free road, and the paid one appended to it. `freeRouteEndKm` is where the Tōkaidō
        # ends and therefore where the offer becomes any use — the one number App Review and a
        # buyer both need, and the one this plan's own Part I got wrong twice by estimating it.
        "freeRouteStretches": len(tokaido),
        "freeRouteEndKm": int(tokaido[-1][3] / 1000),
        "paidRouteStretches": len(west),
        "paidRouteFirst": west[0][2],
        "paidRouteLast": west[-1][2],
        "paidRouteStops": ", ".join(romaji for _, _, romaji, _ in west),
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
