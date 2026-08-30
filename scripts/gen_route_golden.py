#!/usr/bin/env python3
"""Regenerate the frozen-road golden by compiling a PAST commit's RideRoute, never the working tree.

WHY THIS FILE EXISTS, AND WHY IT REFUSES THINGS
------------------------------------------------
`Tests/SceneryKitTests/Fixtures/tokaido-v1.29-sweep.json` is what proves an unentitled rider's
road is unchanged. It is 147 KB of machine-generated JSON, which means it is unreviewable by eye —
so if anyone ever regenerates it from the working tree, the test silently becomes one that grades
the code under test against itself, NOTHING goes red, and the review that should catch it is
reading a diff no human can check.

That is this project's `feedback-a-test-that-grades-itself` memory, and it would be pre-installed
into the one test carrying HARD CONSTRAINT 1. So the generator makes it impossible by construction:

  * it reads `Sources/SceneryKit/*.swift` out of `git show <ref>:...` and NEVER off disk;
  * it refuses any ref whose RideRoute already knows about the paid road (`westStages`), because
    such a ref cannot be a baseline for "the road before the paid road existed";
  * it refuses a ref whose road does not have exactly eight stretches;
  * it stamps the ref and its resolved sha INTO the fixture, and the Swift test asserts that sha
    equals the one baked into the test — so a hand-edited or re-pointed fixture fails.

The one thing it cannot prevent is somebody deleting this file and writing their own. Nothing can.
What it can do is make the wrong thing harder than the right thing and say why.

Usage:
    scripts/gen_route_golden.py                 # verify the committed fixture still reproduces
    scripts/gen_route_golden.py --write         # regenerate it (same ref)
    scripts/gen_route_golden.py --ref <sha>     # only with a very good reason; update the Swift
                                                # test's expected sha in the same commit

Exit codes: 0 ok · 1 mismatch · 2 refused (bad ref) · 3 toolchain failure
"""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = REPO / "Tests/SceneryKitTests/Fixtures/tokaido-v1.29-sweep.json"

# The last commit before the paid road existed. v1.29 shipped from here.
BASELINE_REF = "48de373"

SWEEP = r"""
import Foundation
var rows: [[String: String]] = []
var points: [Double] = []
for m in stride(from: -2_000.0, through: 40_000.0, by: 37.0) { points.append(m) }
for s in RideRoute.stages {
    points.append(contentsOf: [s.startMetres - 1, s.startMetres, s.startMetres + 1])
}
points.append(contentsOf: [-.infinity, .infinity, .nan, 0, 1_000_000, 138_000, 25_000])
for m in points.sorted(by: { ($0.isNaN ? .infinity : $0) < ($1.isNaN ? .infinity : $1) }) {
    let st = RideRoute.stage(forLifetimeMetres: m)
    let p = RideRoute.progressWithinStage(forLifetimeMetres: m)
    let n = RideRoute.metresToNextStage(forLifetimeMetres: m)
    rows.append([
        "m": m.isNaN ? "nan" : String(m),
        "stage": st.name,
        "id": String(st.id),
        "progress": String(format: "%.9f", p),
        "next": n.map { $0.isNaN ? "nan" : String(format: "%.6f", $0) } ?? "nil",
    ])
}
let data = try! JSONSerialization.data(withJSONObject: rows,
                                       options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
"""


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args],
                          capture_output=True, text=True, check=True).stdout


def source_at(ref, path):
    try:
        return git("show", f"{ref}:{path}")
    except subprocess.CalledProcessError:
        sys.exit(f"REFUSED: {path} does not exist at {ref}")


def build_sweep(ref):
    route = source_at(ref, "Sources/SceneryKit/RideRoute.swift")
    palette = source_at(ref, "Sources/SceneryKit/RidePalette.swift")

    # The refusals. A baseline that already knows about the paid road is not a baseline.
    if "westStages" in route or "RideRoad" in route:
        sys.exit(f"REFUSED: {ref} already contains the paid road; it cannot be the baseline "
                 f"for 'the road before the paid road existed'")
    stages = route.count("RideStage(id:")
    if stages != 8:
        sys.exit(f"REFUSED: {ref} defines {stages} stretches, not 8 — that is not the v1.29 road")

    with tempfile.TemporaryDirectory() as tmp:
        d = pathlib.Path(tmp)
        (d / "RideRoute.swift").write_text(route)
        (d / "RidePalette.swift").write_text(palette)
        (d / "main.swift").write_text(SWEEP)
        r = subprocess.run(["swiftc", "-O", "-o", str(d / "sweep"),
                            str(d / "RideRoute.swift"), str(d / "RidePalette.swift"),
                            str(d / "main.swift")],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr, file=sys.stderr)
            sys.exit(3)
        out = subprocess.run([str(d / "sweep")], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", default=BASELINE_REF)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    sha = git("rev-parse", args.ref).strip()
    rows = build_sweep(args.ref)
    print(f"swept {len(rows)} points from {args.ref} ({sha[:12]})")

    payload = {"generatedFromRef": args.ref, "generatedFromSHA": sha, "rows": rows}

    if args.write:
        # Temp file then replace: `open(path, "w")` truncates before it writes, and a script that
        # raises between the two leaves an empty fixture. STATE records that one costing v1.25 a
        # `project.yml`.
        tmp = FIXTURE.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, indent=1, ensure_ascii=False) + "\n")
        tmp.replace(FIXTURE)
        canon = "\n".join("|".join(f"{k}={r[k]}" for k in sorted(r)) for r in rows)
        import hashlib
        digest = hashlib.sha256(canon.encode()).hexdigest()
        print(f"wrote {FIXTURE.relative_to(REPO)}")
        print(f"goldenRowsSHA256 = \"{digest}\"   <- paste into RideRouteFreezeTests.swift")
        print(f"⚠️  If --ref was not {BASELINE_REF}, update the expected SHA in "
              f"Tests/SceneryKitTests/RideRouteFreezeTests.swift in the SAME commit.")
        return 0

    if not FIXTURE.exists():
        sys.exit(f"{FIXTURE} is missing; run with --write")
    on_disk = json.loads(FIXTURE.read_text())
    if on_disk.get("generatedFromSHA") != sha:
        print(f"MISMATCH: fixture says {on_disk.get('generatedFromSHA')}, {args.ref} is {sha}")
        return 1
    if on_disk.get("rows") != rows:
        print("MISMATCH: the committed fixture does not reproduce from that ref")
        return 1
    print("OK — the committed fixture reproduces byte-for-byte from the baseline commit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
