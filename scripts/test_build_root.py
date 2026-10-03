#!/usr/bin/env python3
"""Self-test for scripts/build_root.sh — each branch against its pair, and proof it is actually used.

A helper that picks the right directory and that nothing calls would pass a unit test forever while
every signed build still died under ~/Documents. So besides the three branches (plain directory,
File Provider domain on the root, File Provider domain on an ANCESTOR), a symlinked or differently
spelled path to the same checkout (case, NFD), and the override, this reads the gate runner and fails
unless its `swift test` takes its scratch path from the helper.

The attribute is planted with `xattr -w` on temp directories: the helper only reads it, so a
planted value is indistinguishable from iCloud's for the question being asked.
"""

import hashlib
import os
import subprocess
import sys
import tempfile
import unicodedata
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
        check(rc == 0 and out.startswith(f"{cache}/NihongoRide-build/synced-") and "File Provider domain" in err,
              f"domain on the root: expected {cache}/NihongoRide-build/synced-<tag>, got rc={rc} {out!r} ({err})")
        print(f"  domain on the root         → {out}")

        # The real layout: the attribute sits on ~/Documents, two levels above the repo root.
        ancestor = tmp / "Documents"
        repo = ancestor / "typing_app"
        repo.mkdir(parents=True)
        plant(ancestor)
        rc, out, err = run_helper(repo, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc == 0 and out.startswith(f"{cache}/NihongoRide-build/typing_app-"),
              f"domain on an ancestor: expected {cache}/NihongoRide-build/typing_app-<tag>, got rc={rc} {out!r} ({err})")
        print(f"  domain on an ancestor      → {out}")

        # Two checkouts under the same synced folder (the live tree and an agent worktree) must not
        # share one SwiftPM build directory: they would queue on its lock and evict each other.
        worktree = repo / ".claude" / "worktrees" / "typing_app"
        worktree.mkdir(parents=True)
        rc2, out2, _ = run_helper(worktree, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc2 == 0 and out2.startswith(f"{cache}/NihongoRide-build/typing_app-") and out2 != out,
              f"two checkouts with the same name must get different build roots: {out!r} vs {out2!r}")
        print(f"  second checkout, same name → {out2}")

        # A symlink to a checkout inside the synced folder is still inside it.
        link = tmp / "elsewhere" / "repo-link"
        link.parent.mkdir()
        link.symlink_to(repo)
        rc3, out3, err3 = run_helper(link, {"NIHONGO_BUILD_CACHE": str(cache)})
        check(rc3 == 0 and out3 == out,
              f"symlinked checkout: expected the real checkout's root {out!r}, got {out3!r} ({err3})")
        print(f"  symlink to that checkout   → {out3}")

        # A differently SPELLED path to the same checkout gets the same root. git records the on-disk
        # spelling and the sweep maps that; the gate runner hashes whatever spelling its caller's cwd
        # had. bash's builtin `pwd -P` echoed the caller's case and Unicode form back, so the two
        # hashes differed and the sweep called a live root an orphan (review 2026-10-03). Only
        # testable where the filesystem itself treats the spellings as one directory.
        # The expected root is derived here from the on-disk name, not taken from a helper run.
        def documented_root(on_disk):
            tag = hashlib.sha1(str(on_disk).encode("utf-8")).hexdigest()[:8]
            return f"{cache}/NihongoRide-build/{on_disk.name}-{tag}"

        spelled = ancestor / "CaseRepo"
        spelled.mkdir()
        if os.path.isdir(ancestor / "caserepo"):
            rc4, out4, err4 = run_helper(ancestor / "caserepo", {"NIHONGO_BUILD_CACHE": str(cache)})
            check(rc4 == 0 and out4 == documented_root(spelled),
                  f"case-respelled checkout: expected the on-disk spelling's root {documented_root(spelled)!r}, "
                  f"got {out4!r} ({err4})")
            print(f"  same checkout, other case  → {out4}")
        else:
            print("  (skipped: this temp filesystem is case-sensitive, so a case-respelled path is "
                  "another directory)")
        nfc = unicodedata.normalize("NFC", "café")
        nfd = unicodedata.normalize("NFD", nfc)
        (ancestor / nfc).mkdir()
        if os.path.isdir(ancestor / nfd):
            rc5, out5, err5 = run_helper(ancestor / nfd, {"NIHONGO_BUILD_CACHE": str(cache)})
            check(rc5 == 0 and out5 == documented_root(ancestor / nfc),
                  f"NFD-spelled checkout: expected the NFC directory's root {documented_root(ancestor / nfc)!r}, "
                  f"got {out5!r} ({err5})")
            print(f"  same checkout, NFD spelled → {out5}")
        else:
            print("  (skipped: this temp filesystem keeps NFC and NFD names apart)")

        rc, out, err = run_helper(repo, {"NIHONGO_BUILD_CACHE": str(cache),
                                         "NIHONGO_BUILD_ROOT": str(tmp / "chosen")})
        check(rc == 0 and out == str(tmp / "chosen"),
              f"override: expected {tmp / 'chosen'}, got rc={rc} {out!r}")
        print(f"  NIHONGO_BUILD_ROOT         → {out}")

    # Used, not merely present. Each script that signs bundles must take its build directory from
    # the helper; a hard-coded "$ROOT/build/…" or a bare `swift test` in the runner is the defect.
    # (The App Store build scripts are deliberately NOT listed: they already build from an rsync'd
    # copy under $TMPDIR, where this helper would change nothing — see build_root.sh's header.)
    uses = {
        "run_all_gates.sh": ("build_root.sh", "--scratch-path"),
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
    print("  run_all_gates.sh takes its swift test scratch path from the helper")

    if failures:
        print(f"{len(failures)} FAILURE(S)")
        return 1
    print("every branch holds against its pair, and the gate runner uses it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
