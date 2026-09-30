#!/usr/bin/env python3
"""Self-test for scripts/sweep_build_roots.py — it moves the old orphan and nothing else, and each thing
it keeps is shown to be kept by the guard that is supposed to keep it.

"Only the old orphan was selected" is a clean result that a sweep ignoring worktrees, or ignoring time,
could also print on the wrong fixture. So each keep is paired with its mutant: the same fixture with
the mapping cut down to the main checkout selects the live worktree's root; the same fixture with the
age guard at 0 selects the fresh orphan; the same orphan held open, or used as a working directory, or
named in a running process's arguments, is kept, and released it is selected.

Everything happens in a temporary directory: a git repository with worktrees under a planted File
Provider attribute (so build_root.sh names their roots exactly as it does under ~/Documents), a cache
beside it, and HOME pointed into the temp dir too, so even a sweep that ignored NIHONGO_BUILD_CACHE could
not reach the real cache. The Trash is a stand-in that records what it was handed; the real Trash and
the real cache are never touched.
"""

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SWEEP = SCRIPTS / "sweep_build_roots.py"
HELPER = SCRIPTS / "build_root.sh"
RUNNER = SCRIPTS / "run_all_gates.sh"
ATTR = "com.apple.file-provider-domain-id"
OLD = 3 * 3600          # three hours: well past the default 60-minute guard


def load_module():
    spec = importlib.util.spec_from_file_location("sweep_build_roots", SWEEP)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(env, *args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, env=env, check=True, capture_output=True, text=True)


def age(path, seconds):
    """Set every mtime in the tree to `seconds` ago, children first (touching a child moves its parent)."""
    t = time.time() - seconds
    for dirpath, dirnames, filenames in os.walk(path, topdown=False):
        for name in filenames:
            os.utime(os.path.join(dirpath, name), (t, t), follow_symlinks=False)
        os.utime(dirpath, (t, t))


def fill(root):
    """A root shaped like the real ones: <root>/swiftpm/ with a lock, a build db and some products."""
    swiftpm = root / "swiftpm"
    (swiftpm / "arm64-apple-macosx" / "debug").mkdir(parents=True)
    (swiftpm / ".lock").write_text("")
    (swiftpm / "build.db").write_bytes(b"\0" * 65536)
    for i in range(3):
        (swiftpm / "arm64-apple-macosx" / "debug" / f"obj{i}.o").write_bytes(b"\1" * 131072)


def main():
    failures = []

    def check(ok, message):
        if not ok:
            failures.append(message)
            print(f"FAIL  {message}")
        return ok

    mod = load_module()

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(os.path.realpath(tmp))
        home = tmp / "home"
        home.mkdir()
        cache = tmp / "cache"
        env = {k: v for k, v in os.environ.items() if k not in ("NIHONGO_BUILD_ROOT", "NIHONGO_BUILD_CACHE")}
        env.update({"HOME": str(home), "NIHONGO_BUILD_CACHE": str(cache),
                    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"})

        # The real layout: the attribute on "Documents", the repo two levels below, agent worktrees
        # under .claude/worktrees/.
        docs = tmp / "Documents"
        repo = docs / "typing_app"
        repo.mkdir(parents=True)
        subprocess.run(["xattr", "-w", ATTR, "com.apple.CloudDocs.iCloudDriveFileProvider/TEST", str(docs)],
                       check=True, capture_output=True)
        git(env, "init", "-q", "-b", "main", cwd=repo)
        git(env, "-c", "user.name=sweep-probe", "-c", "user.email=sweep-probe@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "init", cwd=repo)

        def worktree(name):
            path = repo / ".claude" / "worktrees" / name
            git(env, "worktree", "add", "-q", "--detach", str(path), "HEAD", cwd=repo)
            return path

        def root_for(checkout):
            """The root build_root.sh names — and, independently, the name its header documents."""
            r = subprocess.run(["bash", str(HELPER), str(checkout)], env=env, capture_output=True, text=True)
            root = Path(r.stdout.strip())
            real = os.path.realpath(checkout)
            expected = cache / "NihongoRide-build" / f"{os.path.basename(real)}-{hashlib.sha1(real.encode()).hexdigest()[:8]}"
            # Without this the fixture could be vacuous: a helper answering "<checkout>/build" would
            # leave no roots in the cache, and "nothing but the orphan was selected" would still hold.
            check(r.returncode == 0 and root == expected,
                  f"fixture: build_root.sh gave {checkout} the root {root}, expected {expected} ({r.stderr.strip()})")
            fill(root)
            return root

        live_main = root_for(repo)
        live_wt = worktree("live-wt")
        live_wt_root = root_for(live_wt)
        gone_old = worktree("gone-old")
        gone_old_root = root_for(gone_old)
        gone_new = worktree("gone-new")
        gone_new_root = root_for(gone_new)
        for wt in (gone_old, gone_new):
            git(env, "worktree", "remove", str(wt), cwd=repo)

        build = cache / "NihongoRide-build"
        legacy = build / "swiftpm"               # the shared root from before roots were per-checkout
        (legacy / "debug").mkdir(parents=True)
        (legacy / "debug" / "x.o").write_bytes(b"\2" * 4096)
        (build / "scratch").mkdir()              # not root-shaped
        (build / "notes-deadbeef").write_text("a FILE with a root-shaped name")
        siblings = [cache / "NihongoRide-v135-work" / "renders", cache / "NihongoRide-Stats" / "sales",
                    cache / "NihongoRide-Archives" / "old", cache / ".venv-jp" / "bin"]
        for s in siblings:
            s.mkdir(parents=True)
            (s / "keep.txt").write_text("not a build product")
        age(cache, OLD)
        age(gone_new_root, 0)                    # the fresh orphan: a build may be running in it

        everything = [live_main, live_wt_root, gone_old_root, gone_new_root, legacy, build / "scratch",
                      build / "notes-deadbeef", *siblings]
        # Hardlinks hide from `du` and from any size sum: at least prove the fixture sizes are real.
        check(sum(f.stat().st_size for f in gone_old_root.rglob("*") if f.is_file()) >= 3 * 131072,
              "fixture: the old orphan holds less data than was written into it")

        trash = tmp / "Trash"
        trash.mkdir()
        fake_trash = tmp / "fake_trash.py"
        fake_trash.write_text(
            f"#!{sys.executable}\n"
            "import os, sys\n"
            f"TRASH = {str(trash)!r}\n"
            "paths = [a for a in sys.argv[1:] if not a.startswith('-')]\n"
            "with open(os.path.join(TRASH, 'log'), 'a') as f:\n"
            "    f.write(' '.join(sys.argv[1:]) + '\\n')\n"
            "for p in paths:\n"
            "    os.rename(p, os.path.join(TRASH, os.path.basename(p)))\n")
        fake_trash.chmod(0o755)
        log = trash / "log"

        def sweep(*args, repo_arg=repo, cmd=fake_trash):
            r = subprocess.run([sys.executable, str(SWEEP), "--repo", str(repo_arg), "--trash-cmd", str(cmd),
                                *args], env=env, capture_output=True, text=True, timeout=300)
            return r.returncode, r.stdout, r.stderr

        def line_for(out, root):
            hits = [line for line in out.splitlines() if f" {root.name}/ " in line]
            return hits[0] if len(hits) == 1 else f"<{len(hits)} lines name {root.name}>"

        def intact(label, roots):
            gone = [str(p) for p in roots if not p.exists()]
            check(not gone, f"{label}: moved or lost {gone}")

        # ── 1. --hint: one line, counting the roots no live checkout maps to; moves nothing ──────────
        rc, out, err = sweep("--hint")
        lines = out.splitlines()
        check(rc == 0 and len(lines) == 1 and lines[0].startswith("build cache: 2 build roots"),
              f"--hint: expected one line naming 2 unmapped roots, got rc={rc} {out!r} {err!r}")
        intact("--hint", everything)
        check(not log.exists(), "--hint called the trash command")
        print(f"  --hint                     → {lines[0] if lines else '(nothing)'}")

        # ── 2. --dry-run: names the old orphan, moves nothing ─────────────────────────────────────────
        rc, out, err = sweep("--dry-run")
        check(rc == 0, f"--dry-run exit {rc}: {out} {err}")
        check("would move" in line_for(out, gone_old_root), f"--dry-run: old orphan not selected: {line_for(out, gone_old_root)!r}")
        check(line_for(out, gone_new_root).lstrip().startswith("skip"),
              f"--dry-run: fresh orphan not skipped: {line_for(out, gone_new_root)!r}")
        for root in (live_main, live_wt_root):
            check("live:" in line_for(out, root), f"--dry-run: live root {root.name} not kept as live: {line_for(out, root)!r}")
        check("left alone" in line_for(out, legacy), f"--dry-run: swiftpm/ not left alone: {line_for(out, legacy)!r}")
        check("would move 1 orphaned root " in out, f"--dry-run: expected exactly one root to be selected:\n{out}")
        intact("--dry-run", everything)
        check(not log.exists(), "--dry-run called the trash command")
        print("  --dry-run                  → selects the old orphan only, moves nothing")

        # ── 3. the selection, and the mutants that prove each keep is earned ──────────────────────────
        build_dir = mod.build_dir_for(env)
        check(build_dir == build, f"NIHONGO_BUILD_CACHE not honoured: build dir {build_dir}, expected {build}")

        def orphans(min_age=mod.DEFAULT_MIN_AGE_MINUTES):
            return {e.name for e in mod.plan(repo, build_dir, env, min_age)[1] if e.verdict == "orphan"}

        def only_the_old_orphan(selected):
            return selected == {gone_old_root.name}

        selected = orphans()
        check(only_the_old_orphan(selected), f"selection: expected only {gone_old_root.name}, got {sorted(selected)}")

        real_list = mod.list_worktrees
        mod.list_worktrees = lambda r, e: real_list(r, e)[:1]          # the mapping ignores worktrees
        try:
            mutant = orphans()
        finally:
            mod.list_worktrees = real_list
        check(live_wt_root.name in mutant and not only_the_old_orphan(mutant),
              f"mutant (worktrees ignored) should select the live worktree's root and fail the check; got {sorted(mutant)}")
        print(f"  mapping without worktrees  → selects {sorted(mutant)}: the check fails, as it must")

        mutant = orphans(min_age=0)
        check(gone_new_root.name in mutant and not only_the_old_orphan(mutant),
              f"mutant (no age guard) should select the fresh orphan and fail the check; got {sorted(mutant)}")
        print(f"  age guard at 0             → selects {sorted(mutant)}: the fresh orphan is kept only by time")

        # ── 4. the real run: exactly one call to the trash, with exactly the old orphan ───────────────
        rc, out, err = sweep()
        calls = log.read_text().splitlines() if log.exists() else []
        check(rc == 0, f"sweep exit {rc}: {out} {err}")
        check(calls == [f"-s {gone_old_root}"], f"trash was called with {calls}, expected only the old orphan")
        check(not gone_old_root.exists() and (trash / gone_old_root.name).is_dir(),
              "the old orphan is not in the stand-in Trash")
        intact("sweep", [p for p in everything if p != gone_old_root])
        check("moved 1 orphaned root (" in out and "emptied" in out,
              f"sweep: summary does not report the move and the Trash caveat:\n{out}")
        check(all(c.split(" ", 1)[1].startswith(str(build) + "/") for c in calls),
              f"trash was handed a path outside the temporary cache: {calls}")
        print("  sweep                      → moved the old orphan only; everything else is where it was")

        # ── 5. in use: open file, working directory, named in arguments ───────────────────────────────
        gone_held = worktree("gone-held")
        held_root = root_for(gone_held)
        git(env, "worktree", "remove", str(gone_held), cwd=repo)
        age(held_root, OLD)

        def verdict(root):
            return {e.name: e for e in mod.plan(repo, build_dir, env, mod.DEFAULT_MIN_AGE_MINUTES)[1]}[root.name]

        check(verdict(held_root).verdict == "orphan", f"baseline: the released root should be an orphan: {verdict(held_root)}")
        with open(held_root / "swiftpm" / "build.db", "rb"):
            v = verdict(held_root)
            check(v.verdict == "in use", f"open file: expected 'in use', got {v.verdict} ({v.reason})")
        # One holder at a time, each released before the next starts, so each verdict has one cause.
        holders = (
            ("working directory", lambda: subprocess.Popen(["sleep", "60"], cwd=held_root / "swiftpm")),
            ("named in arguments", lambda: subprocess.Popen(
                [sys.executable, "-c", "import time; time.sleep(60)", "--scratch-path", str(held_root / "swiftpm")])),
        )
        for label, start in holders:
            proc = start()
            try:
                v = verdict(held_root)
                check(v.verdict == "in use", f"{label}: expected 'in use', got {v.verdict} ({v.reason})")
            finally:
                proc.kill()
                proc.wait()
            v = verdict(held_root)
            check(v.verdict == "orphan", f"{label} released: the root should be an orphan again, got {v.verdict}")
        print("  open file / cwd / argv     → each keeps the root; released, it is an orphan")

        # ── 5b. the two cases where the exact root cannot be computed keep every root of that name ────
        # A locked worktree whose directory is gone (git says: do not prune) …
        locked = worktree("gone-locked")
        locked_root = root_for(locked)
        age(locked_root, OLD)
        git(env, "worktree", "lock", str(locked), cwd=repo)
        shutil.rmtree(locked)                     # the checkout's directory, in the temp dir
        v = verdict(locked_root)
        check(v.verdict == "held", f"locked worktree missing on disk: expected 'held', got {v.verdict} ({v.reason})")
        git(env, "worktree", "unlock", str(locked), cwd=repo)
        v = verdict(locked_root)
        check(v.verdict == "orphan", f"unlocked, the same missing worktree's root should be an orphan: {v.verdict}")
        git(env, "worktree", "prune", cwd=repo)
        # … and a live checkout that build_root.sh places outside the cache (no File Provider
        # attribute above it — under ~/Documents that means the attribute was misread).
        outside = tmp / "elsewhere" / "outside-wt"
        git(env, "worktree", "add", "-q", "--detach", str(outside), "HEAD", cwd=repo)
        outside_root = build / "outside-wt-0badc0de"
        fill(outside_root)
        age(outside_root, OLD)
        v = verdict(outside_root)
        check(v.verdict == "held", f"live checkout outside the cache: expected its name's roots 'held', got {v.verdict}")
        git(env, "worktree", "remove", str(outside), cwd=repo)
        v = verdict(outside_root)
        check(v.verdict == "orphan", f"that checkout removed, its root should be an orphan: {v.verdict}")
        os.rename(locked_root, tmp / locked_root.name)
        os.rename(outside_root, tmp / outside_root.name)
        print("  locked+missing / outside   → kept by name while the checkout is live; orphans once it is not")

        # ── 6. refusals: nothing moves when the live set or the in-use set cannot be read ─────────────
        not_git = tmp / "not-a-repo"
        not_git.mkdir()
        rc, out, err = sweep(repo_arg=not_git)
        check(rc == 1 and "REFUSED" in out and held_root.exists(),
              f"a directory that is not a repository must be refused with nothing moved: rc={rc} {out!r}")
        for label, attr, bad in (("build_root.sh fails", "HELPER", Path("/usr/bin/false")),
                                 ("lsof missing", "LSOF", "/nonexistent/lsof"),
                                 ("ps missing", "PS", "/nonexistent/ps")):
            saved = getattr(mod, attr)
            setattr(mod, attr, bad)
            try:
                mod.plan(repo, build_dir, env, mod.DEFAULT_MIN_AGE_MINUTES)
                check(False, f"{label}: plan() went ahead instead of refusing")
            except mod.SweepError:
                pass
            finally:
                setattr(mod, attr, saved)
        # A trash command that says yes and moves nothing (the real one does exactly that without -s).
        rc, out, err = sweep(cmd="/usr/bin/true")
        check(rc == 1 and "still there" in out and held_root.exists(),
              f"a trash that exits 0 without moving must be reported as a failure: rc={rc} {out!r}")
        print("  not a repo / helper / lsof / ps / a trash that lies → refused, nothing moved")

        # ── 7. --hint is silent when every root has a live checkout ──────────────────────────────────
        clean = tmp / "clean-cache"
        (clean / "NihongoRide-build").mkdir(parents=True)
        os.rename(live_main, clean / "NihongoRide-build" / live_main.name)
        r = subprocess.run([sys.executable, str(SWEEP), "--hint", "--repo", str(repo)],
                           env={**env, "NIHONGO_BUILD_CACHE": str(clean)}, capture_output=True, text=True)
        check(r.returncode == 0 and r.stdout == "", f"--hint with nothing orphaned should print nothing: {r.stdout!r}")

    # ── 8. the code keeps the promises its header makes ──────────────────────────────────────────────
    code = "\n".join(line for line in SWEEP.read_text(encoding="utf-8").splitlines()
                     if not line.lstrip().startswith("#"))
    for banned in ("rmtree", "os.remove", "os.unlink", "os.rmdir", ".unlink(", ".rmdir(", "import shutil",
                   '"rm"', "'rm'"):
        check(banned not in code, f"sweep_build_roots.py contains {banned!r}: it must move to the Trash, never delete")
    check(mod.TRASH == "/usr/bin/trash", f"the default trash command is {mod.TRASH!r}, not /usr/bin/trash")
    # The gate runner may print the hint; it must never sweep. Every call there carries --hint, and
    # its status cannot reach the verdict.
    runner = [line.strip() for line in RUNNER.read_text(encoding="utf-8").splitlines()
              if "sweep_build_roots.py" in line and not line.lstrip().startswith("#")]
    check(runner, "run_all_gates.sh does not call sweep_build_roots.py --hint")
    for line in runner:
        check("--hint" in line and "run_gate" not in line and "FAILED" not in line,
              f"run_all_gates.sh calls the sweep as something other than a hint: {line}")
    print("  no delete call in the sweep; run_all_gates.sh only ever asks it for --hint")

    if failures:
        print(f"{len(failures)} FAILURE(S)")
        return 1
    print("only the old orphan moves, and every keep is shown to be kept by its own guard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
