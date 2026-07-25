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

3. **Not every screen is deterministic.** The game/practice/results captures draw words
   from a randomly ordered deck, so they differ run to run with no code change at all.
   Comparing a "before" and "after" set without knowing which screens are stable turns
   noise into a false alarm — and, worse, makes a real regression look like more noise.
   `--control` takes a second render of the CANDIDATE's code and uses it to classify each
   screen as STABLE or NOISY, then holds only the stable ones to a strict standard. (Second
   render of the candidate, not the baseline: the baseline is usually a commit you no longer
   have checked out, and the noise is a property of the capture, not of the change.)

Usage:
    NIHONGO_SHOT=/tmp/a swift run NihongoRideApp     # baseline, before the change
    …make changes…
    NIHONGO_SHOT=/tmp/b swift run NihongoRideApp
    NIHONGO_SHOT=/tmp/b2 swift run NihongoRideApp    # again, unchanged — the control
    scripts/compare_renders.py /tmp/a /tmp/b --control /tmp/b2

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
    ap.add_argument("--control", help="a second render of the CANDIDATE's code; classifies "
                                      "screens as stable vs run-to-run noisy")
    args = ap.parse_args()

    base = names(args.baseline)
    if not base:
        print(f"no PNGs in {args.baseline}", file=sys.stderr)
        return 1

    noisy = set()
    if args.control:
        for n in base:
            other = os.path.join(args.control, n)
            cand = os.path.join(args.candidate, n)
            if not (os.path.exists(other) and os.path.exists(cand)):
                continue
            verdict, _ = compare(cand, other)
            if verdict != "same":
                noisy.add(n)
        print(f"control: {len(noisy)} of {len(base)} screens vary run-to-run "
              f"(random deck order) — they cannot be held to a pixel standard")
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

    print()
    print("stable screens unchanged" if failures == 0
          else f"{failures} stable screen(s) changed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
