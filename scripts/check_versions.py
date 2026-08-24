#!/usr/bin/env python3
"""Cross-check every version and build number a release depends on.

WHY THIS IS A SCRIPT. The check that caught v1.25's crossed build numbers was run by hand and
never committed, so it protected exactly one release. The defect it caught: bumping with a
chained string replace — "46"->"47" then "47"->"48" — made the first replace turn macOS into
something the second replace then treated as iOS, and BOTH platforms came out 48. Version
numbers are per-platform and getting them crossed is a rejection.

WHAT IS ACTUALLY REQUIRED, and each rule has a failure behind it:

  * A host app and its widget extension must carry the SAME build. A mismatch is a rejection.
  * macOS and iOS builds are INDEPENDENT and here deliberately differ, so "they are equal" is
    the symptom the chained replace produces.
  * The submit script's numbers must equal the project's, or the release attaches a build that
    is not the one that was archived.
  * Every marketing version must be the same string.

Usage:
    python3 scripts/check_versions.py                 # verify, exit non-zero on any problem
    python3 scripts/check_versions.py --bump 1.26     # bump, located BY TARGET, then verify
"""
import argparse
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "project.yml"

# target -> platform. A target absent here is an error, not something to skip: a new versioned
# target must be classified deliberately rather than fall through a filter unnoticed.
PLATFORM = {
    "NihongoRide": "macOS",
    "NihongoRideWidget": "macOS",
    "NihongoRideiOS": "iOS",
    "NihongoRideWidgetiOS": "iOS",
}


def read_project():
    """{target: {"marketing": str, "build": str, "lines": {field: line_number}}}"""
    out, target = {}, None
    for number, line in enumerate(PROJECT.read_text(encoding="utf-8").split("\n"), 1):
        header = re.match(r"^  (\w[\w.-]*):\s*$", line)
        if header:
            target = header.group(1)
        for field, key in (("MARKETING_VERSION", "marketing"), ("CURRENT_PROJECT_VERSION", "build")):
            m = re.match(rf'^\s*{field}:\s*"([^"]+)"\s*$', line)
            if m and target:
                out.setdefault(target, {"lines": {}})[key] = m.group(1)
                out[target]["lines"][key] = number
    return out


def read_submit(path):
    text = path.read_text(encoding="utf-8")
    version = re.search(r'^VERSION\s*=\s*"([^"]+)"', text, re.M)
    builds = dict(re.findall(r'"name":\s*"(\w+)".*?"build_num":\s*"(\d+)"', text))
    return (version.group(1) if version else None), builds


def bump(to_version):
    """Rewrite project.yml, locating every field BY ENCLOSING TARGET.

    Never by value: two targets hold the same number, so a value-keyed replace cannot tell them
    apart and that is exactly how v1.25 crossed its platforms.
    """
    project = read_project()
    plan = {}
    for target, data in project.items():
        platform = PLATFORM.get(target)
        if platform is None:
            sys.exit(f"unclassified versioned target {target!r} — add it to PLATFORM")
        plan[data["lines"]["marketing"]] = ("MARKETING_VERSION", to_version)
        plan[data["lines"]["build"]] = ("CURRENT_PROJECT_VERSION", str(int(data["build"]) + 1))

    lines = PROJECT.read_text(encoding="utf-8").split("\n")
    for number, (field, value) in plan.items():
        old = lines[number - 1]
        new = re.sub(rf'({field}:\s*)"[^"]+"', rf'\g<1>"{value}"', old)
        assert new != old or f'"{value}"' in old, f"line {number} did not change: {old}"
        lines[number - 1] = new
        print(f"  line {number}: {old.strip()}  ->  {new.strip()}")
    # Temp file + os.replace: open(path, "w") truncates BEFORE it writes, and a script that
    # raises between the two leaves an empty file. A stray None emptied project.yml in v1.25.
    tmp = PROJECT.with_suffix(".yml.tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(tmp, PROJECT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bump", metavar="VERSION", help="increment every build by one and set this marketing version")
    ap.add_argument("--submit-script", default="scripts/submit_1_26.py")
    args = ap.parse_args()

    if args.bump:
        print(f"bumping to {args.bump}:")
        bump(args.bump)
        print()

    project = read_project()
    problems = []
    print(f"{'target':24s} {'platform':8s} {'marketing':10s} build")
    for target, data in sorted(project.items()):
        platform = PLATFORM.get(target, "???")
        if platform == "???":
            problems.append(f"unclassified versioned target {target!r}")
        print(f"{target:24s} {platform:8s} {data['marketing']:10s} {data['build']}")

    missing = set(PLATFORM) - set(project)
    if missing:
        problems.append(f"targets declared but carrying no version: {sorted(missing)}")

    # One marketing version everywhere.
    marketing = {d["marketing"] for d in project.values()}
    if len(marketing) != 1:
        problems.append(f"marketing versions disagree: {sorted(marketing)}")

    # Host and widget must MATCH within a platform.
    by_platform = {}
    for target, data in project.items():
        by_platform.setdefault(PLATFORM.get(target), {})[target] = data["build"]
    for platform, targets in by_platform.items():
        if len(set(targets.values())) != 1:
            problems.append(f"{platform} host/widget build mismatch (a rejection): {targets}")

    # …and the two platforms must DIFFER here, because equality is the chained-replace symptom.
    builds = {p: sorted(set(t.values()))[0] for p, t in by_platform.items() if t}
    if len(builds) == 2 and len(set(builds.values())) == 1:
        problems.append(
            f"macOS and iOS are both build {list(builds.values())[0]} — this is what a chained "
            "string replace produces, and it is what v1.25 shipped by accident")

    # The submit script must agree with the project.
    submit = REPO / args.submit_script
    if not submit.exists():
        problems.append(f"submit script not found: {args.submit_script}")
    else:
        version, submit_builds = read_submit(submit)
        print(f"\n{args.submit_script}: version {version}, builds {submit_builds}")
        if version not in marketing:
            problems.append(f"submit script version {version!r} != project {sorted(marketing)}")
        for platform, build in builds.items():
            got = submit_builds.get(platform)
            if got != build:
                problems.append(f"submit script says {platform} build {got!r}, project says {build!r}")

    print()
    if problems:
        for p in problems:
            print(f"FAIL  {p}")
        return 1
    print(f"ok — marketing {sorted(marketing)[0]}, "
          + ", ".join(f"{p} build {b}" for p, b in sorted(builds.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
