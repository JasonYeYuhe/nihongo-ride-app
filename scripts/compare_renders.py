#!/usr/bin/env python3
"""Compare two directories of headless renders, pixel by pixel.

Why this is a script and not three lines of Pillow inline:

1. **`getbbox()` on an RGBA image looks at the ALPHA channel only** (Pillow 10's
   `alpha_only=True` default). Differencing two RGBA renders and asking for a bbox
   therefore reports "identical" for *any* colour change, because the alpha delta is
   zero everywhere. That check silently passed 21/21 screens for me while the menu
   footer had visibly changed its wording. Everything here converts to RGB first.

2. **PNG bytes are not stable** for these renders, so `cmp`/md5 report differences on
   screens the change cannot reach. Compare decoded pixels, never files.

3. **Capture is seeded since v1.34 §C3, so every screen is deterministic WITHIN ONE CALENDAR
   DAY.** Before that the game/practice/results captures drew words from a randomly ordered
   deck and differed run to run with no code change at all — and so did road.png, whose
   odometer text depended on how far the random decks had ridden. `Screenshotter` now
   reseeds `DeckRandomness` per screen and clears the capture's stores before each one.
   What was measured (v1.34 round 2 and 2026-09-27; the 2026-09-27 addendum to PLAN-V1.34
   §C3): two renders of the same binary on the same day, each made SEQUENTIALLY, were
   pixel-identical every time. Renders made CONCURRENTLY were usually pixel-identical too, but
   not always: once, a zh render (the day's first run, made beside an en render) differed
   from a later sequential zh render on game-mid, results and results-sentence at luminance
   Δ ≤ 2; and with four captures at once, one render per language in one round differed the
   same way on game-mid and results. Those differences are classified SUBPIXEL below, so a
   plain `compare_renders.py A B` still exits 0 on them. The one thing the seed
   does not fix is the clock: journal.png and stats.png draw the wall-clock date (the demo
   fortnight is placed relative to today — "Today", "Yesterday", "9/23"; the words-per-day
   axis is labelled with day numbers; today's stud is ringed), so they, and any screen that
   shows a relative date, change across local midnight. A baseline and a candidate must
   therefore be rendered on the same local day, or compared with `--control`, which remains
   for every comparison where determinism does NOT hold: a pair straddling midnight, renders
   made by a tool older than §C3, or any capture that bypasses the seam. It takes a second
   render of the CANDIDATE's code and uses it to classify each screen as STABLE or NOISY,
   then holds only the stable ones to a strict standard. (Second render of the candidate,
   not the baseline: the baseline is usually a commit you no longer have checked out, and
   the noise is a property of the capture, not of the change.) Make every --control render
   SEQUENTIALLY: sequential renders have always matched pixel for pixel, while a control
   rendered concurrently can mark screens noisy on SUBPIXEL differences alone (the
   observation above). A noisy screen whose control difference is
   CHANGED-level (above Δ32) means the tool has stopped being deterministic, which is itself
   a finding.

Usage:
    NIHONGO_SHOT=/tmp/a swift run NihongoRideApp     # baseline, before the change
    …make changes…
    NIHONGO_SHOT=/tmp/b swift run NihongoRideApp
    NIHONGO_SHOT=/tmp/b2 swift run NihongoRideApp    # again, unchanged — a control
    NIHONGO_SHOT=/tmp/b3 swift run NihongoRideApp    # and again; one control undersamples
    scripts/compare_renders.py /tmp/a /tmp/b --control /tmp/b2 --control /tmp/b3

Exit 0 if every STABLE screen is unchanged, 1 otherwise. Without --control every screen
is treated as stable, which is the right default for widget/panel-only comparisons.
"""
import argparse, glob, os, sys

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("needs Pillow: pip install Pillow")

# A layout change of half a pixel shifts antialiasing without moving anything a person
# would see. Report those separately rather than calling them "identical" — the honest
# summary is "geometry unchanged, subpixel differences", not "byte for byte the same".
SUBPIXEL_MAX_DELTA = 32


def compare(path_a: str, path_b: str):
    """→ (verdict, detail). verdict in {"same", "subpixel", "changed", "size"}."""
    a = Image.open(path_a).convert("RGB")
    b = Image.open(path_b).convert("RGB")
    if a.size != b.size:
        return "size", f"{a.size} → {b.size}"
    diff = ImageChops.difference(a, b)
    nonzero = [p for p in diff.getdata() if p != (0, 0, 0)]
    if not nonzero:
        return "same", ""
    peak = max(max(p) for p in nonzero)
    loud = sum(1 for p in nonzero if max(p) > SUBPIXEL_MAX_DELTA)
    detail = f"{len(nonzero)}px differ, peak Δ{peak}, {loud}px above Δ{SUBPIXEL_MAX_DELTA}"
    return ("subpixel" if loud == 0 else "changed"), detail


def names(directory: str):
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(directory, "*.png")))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline")
    ap.add_argument("candidate")
    ap.add_argument("--control", action="append", default=[],
                    help="a second render of the CANDIDATE's code; classifies screens as "
                         "stable vs run-to-run noisy. Repeatable — ONE control run "
                         "undersamples, because two runs can draw the same deck by luck and "
                         "a genuinely noisy screen then gets held to a pixel standard. Pass "
                         "two or three.")
    args = ap.parse_args()

    base = names(args.baseline)
    if not base:
        print(f"no PNGs in {args.baseline}", file=sys.stderr)
        return 1

    noisy = set()
    if args.control:
        # A screen is noisy if ANY control pair differs — one matching pair proves nothing.
        for control in args.control:
            for n in base:
                other = os.path.join(control, n)
                cand = os.path.join(args.candidate, n)
                if not (os.path.exists(other) and os.path.exists(cand)):
                    continue
                verdict, _ = compare(cand, other)
                if verdict != "same":
                    noisy.add(n)
        print(f"control: {len(noisy)} of {len(base)} screens vary run-to-run "
              f"(a date-bearing screen, or a capture that bypassed the seed) — they cannot be "
              f"held to a pixel standard")
        if noisy:
            print("  noisy: " + ", ".join(sorted(noisy)))
        print()

    failures = 0
    for n in base:
        cand = os.path.join(args.candidate, n)
        if not os.path.exists(cand):
            print(f"  MISSING  {n}")
            failures += 1
            continue
        verdict, detail = compare(os.path.join(args.baseline, n), cand)
        if n in noisy:
            print(f"  (noisy)  {n}: {detail or 'same'}")
            continue
        if verdict == "same":
            continue
        marker = "SUBPIXEL" if verdict == "subpixel" else "CHANGED "
        print(f"  {marker} {n}: {detail}")
        if verdict != "subpixel":
            failures += 1

    # Screens the comparison COULD NOT SEE.
    #
    # The loop above walks the baseline's filenames, so a render that exists only in the
    # candidate is never opened — and the summary line then says "stable screens unchanged"
    # having never looked at it. That is this project's oldest rule in a new costume: a checker
    # that reports "no problems" is indistinguishable from a broken one, and the fix is not to
    # widen the check but to make it state the population it skipped.
    #
    # These are NOT failures. A change that adds screens is the normal reason for them, and the
    # operator is the one who knows whether the new files were expected. Silence is the bug.
    added = sorted(set(names(args.candidate)) - set(base))
    if added:
        print(f"  NEW      {len(added)} screen(s) exist only in the candidate and were NOT compared:")
        for n in added:
            print(f"           {n}")
        print()

    print()
    summary = ("stable screens unchanged" if failures == 0
               else f"{failures} stable screen(s) changed")
    if added:
        summary += f" — over {len(base)} baseline screen(s); {len(added)} new screen(s) uninspected"
    print(summary)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
