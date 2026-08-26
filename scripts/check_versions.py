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
import subprocess
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


DT_PLATFORM = {"macosx": "macOS", "iphoneos": "iOS"}


def plist_value(path, key):
    proc = subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", str(path)],
                          capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else None


def check_archive(archive, marketing, builds):
    """Verify what was actually BUILT against what project.yml declares.

    project.yml is the INPUT; an archive is the artifact Apple receives, and they can disagree —
    a stale generated .xcodeproj, a cached build, an export that picked up the wrong config.

    **The first version of this function did not do that.** It compared the archived bundles
    against EACH OTHER and nothing else, so a stale archive carrying the previous release's
    version and build — the exact artifact this exists to catch — printed `ok` and exited 0.
    It was caught by the pre-submission review, which built a synthetic 1.25/47 archive and
    watched it pass. A checker that reports "fine" without comparing anything is this repo's
    oldest defect, committed inside the release whose subject is that defect.

    The archive's platform comes from `DTPlatformName` (macosx / iphoneos), not from which
    build number it happens to carry — deriving the expectation from the thing being checked
    would make the check unfalsifiable.
    """
    root = Path(archive)
    app = plist_value(root / "Info.plist", "ApplicationProperties:ApplicationPath")
    if not app:
        return [f"{archive}: no ApplicationProperties:ApplicationPath — not an .xcarchive?"]

    problems, seen = [], {}
    platform = None
    for plist in sorted(root.glob("Products/**/Info.plist")):
        if ".bundle/" in str(plist):
            continue                                  # resource bundles carry no app version
        version = plist_value(plist, "CFBundleShortVersionString")
        if version is None:
            continue
        build = plist_value(plist, "CFBundleVersion")
        bundle = plist_value(plist, "CFBundleIdentifier")
        platform = platform or DT_PLATFORM.get(plist_value(plist, "DTPlatformName") or "")
        print(f"  {bundle or plist.name:44s} {version:8s} build {build}")
        seen[bundle or str(plist)] = (version, build)

    if not seen:
        return [f"{archive}: contains no versioned bundle — wrong path?"]
    if platform is None:
        problems.append(f"{archive}: no DTPlatformName — cannot tell which platform this is")
    if len(set(seen.values())) > 1:
        problems.append(f"archived bundles disagree with each other (a rejection): {seen}")

    # …and against the project, which is the half the first version was missing.
    if platform:
        expected = (marketing, builds.get(platform))
        print(f"  expected for {platform}: {expected[0]} build {expected[1]}")
        for bundle, got in sorted(seen.items()):
            if got != expected:
                problems.append(
                    f"{bundle} in the archive is {got[0]} build {got[1]}, but project.yml "
                    f"declares {expected[0]} build {expected[1]} for {platform}")
    return problems


def newest_submit_script():
    """The highest-versioned scripts/submit_<major>_<minor>.py on disk."""
    best, best_key = None, ()
    for path in Path(__file__).resolve().parent.glob("submit_*.py"):
        m = re.fullmatch(r"submit_(\d+)_(\d+)(?:_(\d+))?", path.stem)
        if not m:
            continue
        key = tuple(int(g) for g in m.groups() if g is not None)
        if key > best_key:
            best, best_key = path, key
    if best is None:
        raise SystemExit("check_versions: no scripts/submit_<version>.py found")
    return str(best.relative_to(Path(__file__).resolve().parent.parent))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bump", metavar="VERSION", help="increment every build by one and set this marketing version")
    # Resolved, not hardcoded. This defaulted to submit_1_26.py while the project was on
    # 1.27, so a bare run compared the build numbers against a release that had already
    # shipped — a checker reading the wrong file reports "clean" exactly like a working one.
    ap.add_argument("--submit-script", default=newest_submit_script())
    ap.add_argument("--archive", help="also verify the Info.plists inside a built .xcarchive")
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

    if args.archive:
        print(f"\narchive {args.archive}:")
        problems += check_archive(args.archive, sorted(marketing)[0], builds)

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
