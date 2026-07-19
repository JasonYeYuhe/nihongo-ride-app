#!/usr/bin/env python3
"""Measure the contrast white text actually gets against the ride scene.

Why this exists, when SceneryKitTests already asserts 7:1 for every stage:

The Swift test computes contrast from the PALETTE — land, road, and their far variants.
That model is blind to the brightest things in the scene, because none of them are ground
colours: the sun disc (luminance ~0.75-0.9), its radial glow, the clouds, the horizon haze,
and the white road-edge strokes. All of those are drawn in the region the word card sits on.

So the model said every stage passed 7:1 while the RENDERED PIXELS were 3.0-4.9:1 — and the
shipped v1.11 scene, whose palette is stage 0, measured 3.7:1. The model was not wrong about
what it modelled; it was wrong about what mattered. This script measures the thing itself.

It reads the text-free `bare-*.png` renders (scene + scrim, no HUD, no words — measuring the
composed screen just finds the white text and reports 1:1), composites the word card's own
backing, and reports the worst case in the card's region.

Usage:
    NIHONGO_SHOT=/tmp/shot NIHONGO_SHOT_STAGES=1 swift run NihongoRideApp
    scripts/check_scene_contrast.py /tmp/shot

Exit 0 if every stage clears the floor, 1 otherwise.
"""
import glob
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs pillow:  pip3 install pillow")

# Must match SceneryKit.RidePalette.
CARD_ALPHA = 0.85
FLOOR = 7.0

# The word card's rectangle as a fraction of the frame, from GameView's layout.
CARD_BOX = (0.20, 0.24, 0.80, 0.78)
# Sample the top 0.5% of luminance: a small bright feature (the sun) that lands under a
# glyph ruins that glyph, so the worst case is what matters, not the average.
PERCENTILE = 0.995


def luminance(px):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(px[0]) + 0.7152 * lin(px[1]) + 0.0722 * lin(px[2])


def main(directory, results_mode=False):
    if results_mode:
        # Results screens: the panel carries the cards (CARD_ALPHA), but the big title
        # ("到站!") and the action buttons sit naked on the scene. The title is 30-36pt
        # heavy — WCAG large-text — so its floor is 4.5:1, not 7:1.
        # Everything textual on results now sits INSIDE the arrival panel (the naked
        # title measured 2-5:1 against the clouds, exactly as the Codex review predicted,
        # and dimming the whole sky to fix a title would defeat the feature). The panel
        # rect below extends over the title area; outside it only self-backed buttons
        # remain, whose label contrast is against their own fills, not the scene.
        pattern, checks = "bare-results-*.png", [
            ("panel", (0.20, 0.10, 0.80, 0.80), CARD_ALPHA, FLOOR),
        ]
    else:
        pattern, checks = "bare-[0-9]*.png", [("card", CARD_BOX, CARD_ALPHA, FLOOR)]
    files = sorted(glob.glob(os.path.join(directory, pattern)),
                   key=lambda f: int([p for p in os.path.basename(f).split("-") if p.isdigit()][0]))
    if not files:
        sys.exit(f"no {pattern} in {directory} — run with NIHONGO_SHOT_STAGES=1 first")

    worst, worst_name, failed = 99.0, None, []
    for path in files:
        image = Image.open(path).convert("RGB")
        w, h = image.size
        name = os.path.basename(path).replace(".png", "").split("-")[-1]
        for label, box_frac, alpha, floor in checks:
            box = image.crop((int(w * box_frac[0]), int(h * box_frac[1]),
                              int(w * box_frac[2]), int(h * box_frac[3])))
            levels = sorted(luminance(p) for p in box.getdata())
            brightest = levels[int(len(levels) * PERCENTILE)]
            contrast = 1.05 / (brightest * (1 - alpha) + 0.05)
            ok = contrast >= floor
            print(f"  {'✅' if ok else '❌'} {name:<12} {label:<6} {contrast:5.1f}:1 (floor {floor}:1)")
            if not ok:
                failed.append(f"{name}/{label}")
            if contrast - floor < worst:
                worst, worst_name = contrast - floor, f"{name}/{label}"

    print(f"\nsmallest margin above floor: {worst:+.1f} ({worst_name})")
    if failed:
        print(f"❌ below the floor: {', '.join(failed)}")
        print("   Dim that stage's sun / sunGlow / cloudAlpha — those are what sit under the card.")
        return 1
    print("✅ every stretch of road keeps white text above the floor.")
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sys.exit(main(args[0] if args else "/tmp/shot", results_mode="--results" in sys.argv))
