#!/usr/bin/env python3
"""Self-test for scripts/build_root.sh — each branch against its pair, and proof it is actually used.

A helper that picks the right directory and that nothing calls would pass a unit test forever while
every signed build still died under ~/Documents. So besides the three branches (plain directory,
File Provider domain on the root, File Provider domain on an ANCESTOR) and the override, this reads
the three scripts that build signed bundles and fails unless each one takes its paths from the
helper.

The attribute is planted with `xattr -w` on temp directories: the helper only reads it, so a
planted value is indistinguishable from iCloud's for the question being asked.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "build_root.sh"
ATTR = "com.apple.file-provider-domain-id"


def run_helper(root, env_extra):
    env = {k: v for k, v in os.environ.items() if k not in ("NIHONGO_BUILD_ROOT", "NIHONGO_BUILD_CACHE")}
    env.update(env_extra)
    r = subprocess.run(["bash", str(HELPER), str(root)], capture_output=True, text=True, env=env, timeout=30)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def plant(path):
    subprocess.run(["xattr", "-w", ATTR, "com.apple.CloudDocs.iCloudDriveFileProvider/TEST", str(path)],
                   check=True, capture_output=True)


def main():
    failures = []

    def check(ok, message):
        if not ok:
            failures.append(message)
            print(f"FAIL  {message}")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(os.path.realpath(tmp))
        cache = tmp / "cache"

        plain = tmp / "plain" / "repo"
        plain.mkdir(parents=True)
        rc, out, err = run_helper(plain, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc == 0 and out == f"{plain}/build",
              f"plain directory: expected {plain}/build, got rc={rc} {out!r} ({err})")
        print(f"  plain directory            → {out}")

        synced = tmp / "synced"
        synced.mkdir()
        plant(synced)
        rc, out, err = run_helper(synced, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc == 0 and out == f"{cache}/NihongoRide-build" and "File Provider domain" in err,
              f"domain on the root: expected {cache}/NihongoRide-build, got rc={rc} {out!r} ({err})")
        print(f"  domain on the root         → {out}")

        # The real layout: the attribute sits on ~/Documents, two levels above the repo root.
        ancestor = tmp / "Documents"
        repo = ancestor / "typing_app"
        repo.mkdir(parents=True)
        plant(ancestor)
        rc, out, err = run_helper(repo, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc == 0 and out == f"{cache}/NihongoRide-build",
              f"domain on an ancestor: expected {cache}/NihongoRide-build, got rc={rc} {out!r} ({err})")
        print(f"  domain on an ancestor      → {out}")

        rc, out, err = run_helper(repo, {"NIHONGO_BUILD_CACHE": str(cache),
                                         "NIHONGO_BUILD_ROOT": str(tmp / "chosen")})
        check(rc == 0 and out == str(tmp / "chosen"),
              f"override: expected {tmp / 'chosen'}, got rc={rc} {out!r}")
        print(f"  NIHONGO_BUILD_ROOT         → {out}")

    # Used, not merely present. Each script that signs bundles must take its build directory from
    # the helper; a hard-coded "$ROOT/build/…" or a bare `swift test` in the runner is the defect.
    uses = {
        "run_all_gates.sh": ("build_root.sh", "--scratch-path"),
        "build-appstore.sh": ("build_root.sh",),
        "build-appstore-ios.sh": ("build_root.sh",),
    }
    for name, needles in uses.items():
        text = (SCRIPTS / name).read_text(encoding="utf-8")
        lines = [line.strip() for line in text.splitlines() if not line.lstrip().startswith("#")]
        code = "\n".join(lines)
        for needle in needles:
            check(needle in code, f"{name} does not use {needle} outside comments")
        check('BUILD_DIR="$ROOT/build' not in code, f"{name} still hard-codes BUILD_DIR under $ROOT/build")
        # The INVOCATION, not any line that merely mentions the flag (an `echo` of the command
        # line satisfied the first version of this check while the real call had no flag).
        invocations = [line for line in lines if line.startswith("swift test")]
        if name == "run_all_gates.sh":
            check(invocations and all("--scratch-path" in line for line in invocations),
                  f"{name}: every `swift test` invocation must pass --scratch-path: {invocations}")
    print("  run_all_gates.sh, build-appstore.sh, build-appstore-ios.sh take their paths from the helper")

    if failures:
        print(f"{len(failures)} FAILURE(S)")
        return 1
    print("every branch holds against its pair, and the three signing scripts use it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
