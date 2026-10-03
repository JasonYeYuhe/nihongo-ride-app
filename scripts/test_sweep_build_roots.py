#!/usr/bin/env python3
"""Self-test for scripts/sweep_build_roots.py — it moves the old orphan and nothing else, and each thing
it keeps is shown to be kept by the guard that is supposed to keep it.

"Only the old orphan was selected" is a clean result that a sweep ignoring worktrees, or ignoring time,
could also print on the wrong fixture. So each keep is paired with its mutant: the same fixture with
the mapping cut down to the main checkout selects the live worktree's root; the same fixture with the
age guard at 0 selects the fresh orphan; the same orphan held open, or used as a working directory, or
named in a running process's arguments, is kept, and released it is selected.

Added after the 2026-10-03 review, each with the code mutation that it was seen to fail on (listed in
that commit): the age guard looks at the whole tree, counts minutes, defaults to 60 and obeys
--min-age-minutes; lsof and ps that exit non-zero are refused (or, for lsof with output, read); an
exported NIHONGO_BUILD_ROOT does not collapse the mapping; an unreadable root is skipped; symlinks
inside a root and at its level are not followed; nothing beside NihongoRide-build/, under a protected
name, or outside the scope at move time is moved; a symlinked NihongoRide-build is refused; a process
naming a root through an unresolved cache path keeps it; a separate clone that does not build into
the cache is refused (and --hint is silent there); and a clone that does is kept apart from the main
repository's roots by the .checkout record that run_all_gates.sh writes, run here as written there.
From the second round of that review: the record is checked in a root of its own each time (a write
that was skipped must not compare equal to an earlier one), a dangling .checkout link is not written
through, an empty or stale record is replaced, and a .checkout that is a directory, a FIFO (under a
timeout, through --hint as the runner calls it) or that names a file rather than a directory is no
record at all.

Everything happens in a temporary directory: a git repository with worktrees under a planted File
Provider attribute (so build_root.sh names their roots exactly as it does under ~/Documents), a cache
beside it, and HOME pointed into the temp dir too, so even a sweep that ignored NIHONGO_BUILD_CACHE could
not reach the real cache. The Trash is a stand-in that records what it was handed; the real Trash and
the real cache are never touched.
"""

import contextlib
import hashlib
import importlib.util
import io
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
    """Set every mtime in the tree to `seconds` ago, children first (touching a child moves its parent).
    Symlinks get their OWN mtime set (the sweep reads that one, never the target's)."""
    t = time.time() - seconds
    for dirpath, dirnames, filenames in os.walk(path, topdown=False):
        for name in filenames:
            os.utime(os.path.join(dirpath, name), (t, t), follow_symlinks=False)
        for name in dirnames:                    # a symlink to a directory is listed here, not walked
            if os.path.islink(os.path.join(dirpath, name)):
                os.utime(os.path.join(dirpath, name), (t, t), follow_symlinks=False)
        os.utime(dirpath, (t, t))


PRODUCTS = 3 * 131072      # the object files fill() writes, which swiftpm/debug points at


def fill(root):
    """A root shaped like the real ones: <root>/swiftpm/ with a lock, a build db, some products, and the
    `debug -> out/Products/Debug` symlink every real root has (checked 2026-10-03, read-only)."""
    swiftpm = root / "swiftpm"
    (swiftpm / "out" / "Products" / "Debug").mkdir(parents=True)
    (swiftpm / ".lock").write_text("")
    (swiftpm / "build.db").write_bytes(b"\0" * 65536)
    for i in range(3):
        (swiftpm / "out" / "Products" / "Debug" / f"obj{i}.o").write_bytes(b"\1" * 131072)
    (swiftpm / "debug").symlink_to("out/Products/Debug")


def runner_function(name):
    """The text of a shell function in run_all_gates.sh, from `name() {` to its closing `}`, so a test
    can run the runner's own code rather than a copy of it."""
    lines = RUNNER.read_text(encoding="utf-8").splitlines()
    start = lines.index(f"{name}() {{")
    end = lines.index("}", start)
    return "\n".join(lines[start:end + 1])


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
        # The siblings above are not root-shaped, so they would be "other" however wide the scan was.
        # This one IS root-shaped: only the scope (rule 1) keeps a sweep off it.
        beside = cache / "beside-deadbeef"
        fill(beside)
        age(cache, OLD)
        age(gone_new_root, 0)                    # the fresh orphan: a build may be running in it

        everything = [live_main, live_wt_root, gone_old_root, gone_new_root, legacy, build / "scratch",
                      build / "notes-deadbeef", *siblings, beside]
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

        def sweep(*args, repo_arg=repo, cmd=fake_trash, extra_env=None, timeout=300):
            r = subprocess.run([sys.executable, str(SWEEP), "--repo", str(repo_arg), "--trash-cmd", str(cmd),
                                *args], env={**env, **(extra_env or {})}, capture_output=True, text=True,
                               timeout=timeout)
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
        check(f" {beside.name}/" not in out,
              f"--dry-run: named {beside.name}/, a root-shaped directory BESIDE NihongoRide-build/:\n{out}")
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

        def verdict(root, repo_arg=repo, run_env=env):
            return {e.name: e for e in mod.plan(repo_arg, build_dir, run_env, mod.DEFAULT_MIN_AGE_MINUTES)[1]}[root.name]

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
        # Run FROM that worktree, the sweep is not a foreign checkout: its worktree list is the main
        # checkout's, so the main checkout's root stays live and its own name stays held. (Testing the
        # checkout it runs from, rather than the main checkout, refused here.)
        v_main, v_own = verdict(live_main, repo_arg=outside), verdict(outside_root, repo_arg=outside)
        check(v_main.verdict == "live" and v_own.verdict == "held",
              f"from a linked worktree outside the cache: expected the main root 'live' and its own 'held', "
              f"got {v_main.verdict} / {v_own.verdict}")
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

        def calls_now():
            return log.read_text().splitlines() if log.exists() else []

        # ── 7. the age guard: the whole tree, in minutes, 60 by default, and the flag reaches it ──────
        # held_root is an old orphan here (section 5 showed it). One object file deep inside it is
        # touched now and nothing else: the root's own mtime stays old, as after an incremental build.
        deep = held_root / "swiftpm" / "out" / "Products" / "Debug" / "obj1.o"
        os.utime(deep, None)
        v = verdict(held_root)
        check(v.verdict == "recent", f"one fresh file deep in an old root: expected 'recent', got {v.verdict} ({v.reason})")
        # Either side of the 60-minute default, through the CLI (the default lives in main()).
        age(held_root, 59 * 60)
        rc, out, err = sweep("--dry-run")
        check(line_for(out, held_root).lstrip().startswith("skip"),
              f"59 minutes old, default guard: expected 'skip', got {line_for(out, held_root)!r}")
        age(held_root, 61 * 60)
        rc, out, err = sweep("--dry-run")
        check("would move" in line_for(out, held_root),
              f"61 minutes old, default guard: expected 'would move', got {line_for(out, held_root)!r}")
        age(held_root, 30 * 60)
        rc, out, err = sweep("--dry-run", "--min-age-minutes", "20")
        check("would move" in line_for(out, held_root),
              f"30 minutes old, --min-age-minutes 20: expected 'would move', got {line_for(out, held_root)!r}")
        age(held_root, OLD)
        print("  age guard                  → whole tree, in minutes, 60 by default, the flag obeyed")

        # ── 8. lsof and ps that run but exit non-zero ───────────────────────────────────────────────
        # Under a sandbox both really do this (lsof exit 1, ps exit 71, nothing on stdout; measured in
        # the review). lsof also exits 1 when it could not read SOME processes but listed the rest:
        # that output is read, not thrown away.
        bin_dir = tmp / "bin"
        bin_dir.mkdir()

        def stand_in(name, body):
            path = bin_dir / name
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
            return str(path)

        lock = held_root / "swiftpm" / ".lock"
        for label, attr, bad, expected in (
                ("lsof exits 1, nothing on stdout", "LSOF", stand_in("lsof-denied", "echo 'lsof: denied' >&2; exit 1"), "refused"),
                ("lsof exits 1 after listing files", "LSOF",
                 stand_in("lsof-partial", f"printf 'p4242\\ncpartial\\nn%s\\n' '{lock}'; exit 1"), "in use"),
                ("ps exits 71, nothing on stdout", "PS", stand_in("ps-denied", "echo 'ps: denied' >&2; exit 71"), "refused"),
                ("ps exits 1 after some output", "PS", stand_in("ps-partial", "echo '1 /sbin/launchd'; exit 1"), "refused"),
                ("ps exits 0 with nothing on stdout", "PS", stand_in("ps-empty", "exit 0"), "refused")):
            saved = getattr(mod, attr)
            setattr(mod, attr, bad)
            try:
                got = verdict(held_root).verdict
            except mod.SweepError:
                got = "refused"
            finally:
                setattr(mod, attr, saved)
            check(got == expected, f"{label}: expected {expected!r}, got {got!r}")
        print("  lsof / ps exiting non-zero → refused; lsof's partial listing is still read")

        # ── 9. an exported NIHONGO_BUILD_ROOT ───────────────────────────────────────────────────────
        # build_root.sh answers that override verbatim for EVERY checkout, so the sweep must ask it
        # without it, or every live checkout but one maps to the same root and the rest look orphaned.
        rc, out, err = sweep("--dry-run", extra_env={"NIHONGO_BUILD_ROOT": str(live_main)})
        check(rc == 0 and "live:" in line_for(out, live_wt_root),
              f"NIHONGO_BUILD_ROOT exported: the live worktree's root must still map, got rc={rc} "
              f"{line_for(out, live_wt_root)!r}")
        print("  NIHONGO_BUILD_ROOT set     → the live worktree's root still maps")

        # ── 10. a root that cannot be read is skipped, not moved ─────────────────────────────────────
        sealed = held_root / "swiftpm" / "out"
        sealed.chmod(0)
        try:
            v = verdict(held_root)
            check(v.verdict == "unreadable", f"a subdirectory it cannot read: expected 'unreadable', got {v.verdict} ({v.reason})")
            before = calls_now()
            rc, out, err = sweep()
            check(held_root.exists() and calls_now() == before,
                  f"an unreadable root was handed to the trash: {calls_now()[len(before):]} {line_for(out, held_root)!r}")
        finally:
            for p in (sealed, trash / held_root.name / "swiftpm" / "out"):
                if os.path.lexists(p):
                    p.chmod(0o755)
        age(held_root, OLD)
        print("  unreadable subdirectory    → skipped, not moved")

        # ── 11. symlinks: never followed, inside a root or at its level ──────────────────────────────
        # Every real root has swiftpm/debug -> out/Products/Debug (fill() makes one). Followed, its
        # products would be counted twice.
        v = verdict(held_root)
        check(v.verdict == "orphan" and 65536 + PRODUCTS <= v.size < 65536 + PRODUCTS + PRODUCTS // 2,
              f"an orphan with swiftpm/debug: expected ~{65536 + PRODUCTS} bytes counted once, got {v.verdict} {v.size}")
        # A link out of the root, to fresh data: followed, it would make an old orphan look busy.
        fresh_elsewhere = tmp / "fresh-elsewhere"
        fresh_elsewhere.mkdir()
        (fresh_elsewhere / "big.bin").write_bytes(b"\3" * 1048576)
        (held_root / "swiftpm" / "ext").symlink_to(fresh_elsewhere)
        age(held_root, OLD)
        v = verdict(held_root)
        check(v.verdict == "orphan" and v.size < 1048576,
              f"a link out of an old root to fresh data: expected an orphan not counting it, got {v.verdict} "
              f"{v.size} ({v.reason})")
        # A root-shaped SYMLINK directly in NihongoRide-build/, to an old directory: left alone.
        old_target = tmp / "old-target"
        fill(old_target)
        age(old_target, OLD)
        linked = build / "linked-deadbeef"
        linked.symlink_to(old_target)
        os.utime(linked, (time.time() - OLD,) * 2, follow_symlinks=False)
        rc, out, err = sweep("--dry-run")
        check("not a directory — left alone" in line_for(out, linked),
              f"a root-shaped symlink in the build dir: expected it left alone, got {line_for(out, linked)!r}")
        print("  symlinks                   → debug/ counted once, a link out not followed, a linked root left alone")

        # ── 12. scope: under a protected name, or outside NihongoRide-build/ when it comes to moving ──
        pcache = tmp / "NihongoRide-v1-work" / "cache"
        protected_root = pcache / "NihongoRide-build" / "gone-p-deadbeef"
        fill(protected_root)
        age(pcache.parent, OLD)
        before = calls_now()
        rc, out, err = sweep(extra_env={"NIHONGO_BUILD_CACHE": str(pcache)})
        check(rc == 0 and "protected name" in line_for(out, protected_root) and protected_root.exists()
              and calls_now() == before,
              f"a cache under NihongoRide-v1-work/: expected its old root left alone, got rc={rc} "
              f"{line_for(out, protected_root)!r}")
        # The move loop's own re-check, reached by handing it orphans that classify() would never make.
        real_plan = mod.plan
        for label, cache_dir, path in (("beside NihongoRide-build/", cache, beside),
                                       ("under a protected name", pcache, protected_root)):
            saved_environ = dict(os.environ)
            mod.plan = lambda *a, _p=path, **k: (mod.Live(1, {}, set(), []),
                                                  [mod.Entry(_p.name, _p, "orphan", "planted by the test", 0)])
            os.environ.update({"HOME": str(home), "NIHONGO_BUILD_CACHE": str(cache_dir)})
            buf = io.StringIO()
            try:
                with contextlib.redirect_stdout(buf):
                    rc = mod.main(["--repo", str(repo), "--trash-cmd", str(fake_trash)])
            finally:
                mod.plan = real_plan
                os.environ.clear()
                os.environ.update(saved_environ)
            check(rc == 1 and "outside the sweep's scope" in buf.getvalue() and path.exists(),
                  f"an orphan {label} reaching the move loop must not be moved: rc={rc} {buf.getvalue()!r}")
        print("  scope                      → a protected cache and an out-of-scope path are never moved")

        # ── 13. NihongoRide-build itself a symlink ───────────────────────────────────────────────────
        # Its target is named NihongoRide-build too, so the live checkouts map normally and only the
        # link check stands between the sweep and a dated folder that has a root's shape.
        lcache = tmp / "linked-cache"
        lcache.mkdir()
        target = tmp / "other-disk" / "NihongoRide-build"
        photos = target / "photos-20250101"
        photos.mkdir(parents=True)
        (photos / "IMG_0001.jpg").write_bytes(b"\4" * 4096)
        age(target.parent, OLD)
        (lcache / "NihongoRide-build").symlink_to(target)
        rc, out, err = sweep(extra_env={"NIHONGO_BUILD_CACHE": str(lcache)})
        check(rc == 1 and "REFUSED" in out and photos.exists(),
              f"NihongoRide-build as a symlink: expected a refusal with nothing moved, got rc={rc} {out!r}")
        general = tmp / "general-folder"
        (general / "photos-20250101").mkdir(parents=True)
        lcache2 = tmp / "linked-cache-2"
        lcache2.mkdir()
        (lcache2 / "NihongoRide-build").symlink_to(general)
        rc, out, err = sweep("--hint", extra_env={"NIHONGO_BUILD_CACHE": str(lcache2)})
        check(rc == 0 and len(out.splitlines()) == 1 and out.startswith("build cache: could not check"),
              f"--hint with NihongoRide-build a symlink: expected one 'could not check' line, got rc={rc} {out!r}")
        dangling = tmp / "dangling-cache"
        dangling.mkdir()
        (dangling / "NihongoRide-build").symlink_to(tmp / "nowhere")
        rc, out, err = sweep(extra_env={"NIHONGO_BUILD_CACHE": str(dangling)})
        check(rc == 1 and "REFUSED" in out,
              f"NihongoRide-build a dangling symlink: expected a refusal, got rc={rc} {out!r}")
        print("  NihongoRide-build a symlink → refused; --hint says it could not check")

        # ── 14. a process naming a root through an unresolved cache path ─────────────────────────────
        # build_root.sh prints "$NIHONGO_BUILD_CACHE/NihongoRide-build/…" without resolving it, and that
        # is what `swift test --scratch-path` is handed; lsof could report it either way.
        cache_link = tmp / "cache-link"
        cache_link.symlink_to(cache)
        lenv = {**env, "NIHONGO_BUILD_CACHE": str(cache_link)}
        spelled = cache_link / "NihongoRide-build" / held_root.name / "swiftpm"
        proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", "--scratch-path", str(spelled)])
        try:
            v = verdict(held_root, run_env=lenv)
            check(v.verdict == "in use" and f"pid {proc.pid}" in v.reason,
                  f"named in arguments through a symlinked cache path: expected 'in use' by pid {proc.pid}, "
                  f"got {v.verdict} ({v.reason})")
        finally:
            proc.kill()
            proc.wait()
        saved = mod.LSOF
        mod.LSOF = stand_in("lsof-unresolved", f"printf 'p4343\\ncswift-build\\nn%s\\n' '{spelled}/.lock'")
        try:
            v = verdict(held_root, run_env=lenv)
        finally:
            mod.LSOF = saved
        check(v.verdict == "in use" and "pid 4343" in v.reason,
              f"held open under a symlinked cache path: expected 'in use' by pid 4343, got {v.verdict} ({v.reason})")
        print("  unresolved cache spelling  → a process naming the root through it still keeps it")

        # ── 15. the runner's .checkout record, run as written in run_all_gates.sh ────────────────────
        record_fn = runner_function("record_checkout")

        def record(checkout, root, log_path):
            r = subprocess.run(["bash", "-c", f"set -uo pipefail\n{record_fn}\nrecord_checkout \"$1\" \"$2\" \"$3\"",
                                "_", str(checkout), str(root), str(log_path)],
                               env=env, capture_output=True, text=True, timeout=30)
            return r.returncode, (log_path.read_text() if log_path.exists() else "")

        def recorded_text(root):
            path = root / ".checkout"
            return path.read_text() if path.is_file() else None

        probe = tmp / "record-probe"
        repo_link = tmp / "repo-link"
        repo_link.symlink_to(repo)
        rc, _ = record(repo_link, probe, tmp / "record-1.log")
        check(rc == 0 and recorded_text(probe) == f"{repo}\n",
              f"record through a symlink: expected {repo}, got rc={rc} {recorded_text(probe)!r}")
        respelled = docs.parent / docs.name.lower() / repo.name
        if os.path.isdir(respelled):
            # A root of its own. Written into `probe`, which already holds the right path, a write that
            # was skipped altogether compared equal too (review 2026-10-03, round 2: the shell builtin
            # `pwd -P` together with "do not overwrite a record" passed).
            probe_case = tmp / "record-probe-case"
            rc, _ = record(respelled, probe_case, tmp / "record-2.log")
            check(rc == 0 and recorded_text(probe_case) == f"{repo}\n",
                  f"record from a case-respelled cwd: expected the on-disk {repo}, got {recorded_text(probe_case)!r}")
        else:
            print("  (skipped: case-respelled record — this temp filesystem is case-sensitive)")
        blocker = tmp / "a-file"
        blocker.write_text("")
        rc, logged = record(repo, blocker / "root", tmp / "record-3.log")
        check(rc == 0 and "could not record" in logged,
              f"a record that cannot be written must be logged and not fail: rc={rc} log={logged!r}")
        victim = tmp / "owners-file.txt"
        victim.write_text("the owner's\n")
        probe2 = tmp / "record-probe-2"
        probe2.mkdir()
        (probe2 / ".checkout").symlink_to(victim)
        rc, logged = record(repo, probe2, tmp / "record-4.log")
        check(rc == 0 and victim.read_text() == "the owner's\n" and "could not record" in logged,
              f"a symlinked .checkout must not be written through: rc={rc} victim={victim.read_text()!r} log={logged!r}")
        # The same for a DANGLING link. The link above points at a file that exists, so a test for
        # "exists" in place of "is a link" refused it just the same; this one it would call absent,
        # and the write would create the link's target wherever it points.
        planted = tmp / "planted-target"
        probe3 = tmp / "record-probe-3"
        probe3.mkdir()
        (probe3 / ".checkout").symlink_to(planted)
        rc, logged = record(repo, probe3, tmp / "record-5.log")
        check(rc == 0 and not os.path.lexists(planted) and (probe3 / ".checkout").is_symlink()
              and "could not record" in logged,
              f"a dangling .checkout link must not be written through: rc={rc} target created="
              f"{os.path.lexists(planted)} log={logged!r}")
        # A record already there is replaced, not kept: one left empty by a write that hit a full disk
        # (`>` truncates first), or one naming a checkout that has since moved, is repaired by the next
        # gate run. Kept, the empty one would vouch for nothing until someone removed it by hand.
        for label, old in (("empty", ""), ("stale", f"{docs / 'moved-away'}\n")):
            probe_old = tmp / f"record-probe-{label}"
            probe_old.mkdir()
            (probe_old / ".checkout").write_text(old)
            rc, logged = record(repo, probe_old, tmp / f"record-{label}.log")
            check(rc == 0 and recorded_text(probe_old) == f"{repo}\n" and "could not record" not in logged,
                  f"an existing {label} record must be replaced by {repo}: rc={rc} "
                  f"record={recorded_text(probe_old)!r} log={logged!r}")
        body = [line.strip() for line in runner_function("run_swift_test").splitlines()
                if line.strip() and not line.lstrip().startswith("#")]

        def first(needle):
            return next((i for i, line in enumerate(body) if needle in line), None)

        at_root, at_record, at_build = first("scripts/build_root.sh"), first("record_checkout"), first("swift test --scratch-path")
        check(None not in (at_root, at_record, at_build) and at_root < at_record < at_build
              and body[at_record] == 'record_checkout "$REPO" "$root" "$log"',
              f"run_swift_test must call `record_checkout \"$REPO\" \"$root\" \"$log\"` after naming the root and "
              f"before building into it: {body[at_record] if at_record is not None else 'no call'}")
        print("  record_checkout            → the on-disk path, replacing an old record, never through a link;"
              " a failure is logged, never a failed gate")

        # ── 16. separate clones ──────────────────────────────────────────────────────────────────────
        # Outside the File Provider attribute a clone builds into <clone>/build, so its worktree list
        # names none of this cache's owners: refused, and --hint says nothing.
        clone_out = tmp / "elsewhere" / "clone-out"
        git(env, "clone", "-q", str(repo), str(clone_out))
        before = calls_now()
        rc, out, err = sweep(repo_arg=clone_out)
        check(rc == 1 and "REFUSED" in out and "main checkout or one of its worktrees" in out and calls_now() == before,
              f"a sweep from a clone outside the cache must refuse with nothing moved: rc={rc} {out!r}")
        intact("a sweep from a clone outside the cache", [live_main, live_wt_root, held_root])
        rc, out, err = sweep("--hint", repo_arg=clone_out)
        check(rc == 0 and out == "", f"--hint from a clone outside the cache must print nothing: rc={rc} {out!r}")
        # Inside it, a clone builds into this cache, and each side's roots are unknown to the other's
        # worktree list. The record written by the runner is what keeps them apart.
        clone_in = docs / "clone-in"
        git(env, "clone", "-q", str(repo), str(clone_in))
        clone_in_root = root_for(clone_in)
        for checkout, root in ((repo, live_main), (live_wt, live_wt_root)):
            rc, _ = record(checkout, root, tmp / "record-fixture.log")
            check(rc == 0, f"fixture: record_checkout failed for {checkout}")
            age(root, OLD)
        age(clone_in_root, OLD)
        for root, owner in ((live_main, repo), (live_wt_root, live_wt)):
            v = verdict(root, repo_arg=clone_in)
            check(v.verdict == "recorded" and v.reason == f"live (recorded): {owner}",
                  f"from a clone under the attribute, {root.name} (recorded for {owner}): expected "
                  f"'live (recorded)', got {v.verdict} ({v.reason})")
        # The same from the CLI, in both modes that only look: --dry-run keeps them, and --hint counts only
        # the two roots that nobody claims (the old orphan and the fresh one), not the recorded two.
        rc, out, err = sweep("--dry-run", repo_arg=clone_in)
        check(rc == 0 and all(line_for(out, root).lstrip().startswith("keep") and "live (recorded)" in line_for(out, root)
                              for root in (live_main, live_wt_root)),
              f"--dry-run from the clone: expected both recorded roots kept, got rc={rc}\n{out}")
        rc, out, err = sweep("--hint", repo_arg=clone_in)
        check(rc == 0 and out.startswith("build cache: 2 build roots "),
              f"--hint from the clone: expected 2 unclaimed roots, got rc={rc} {out!r}")
        os.rename(live_wt_root / ".checkout", tmp / "set-aside")
        age(live_wt_root, OLD)
        v = verdict(live_wt_root, repo_arg=clone_in)
        check(v.verdict == "orphan",
              f"the same root without its record, from the clone: expected an orphan (the LIMIT), got {v.verdict}")
        os.rename(tmp / "set-aside", live_wt_root / ".checkout")
        age(live_wt_root, OLD)
        # The other direction, from the main checkout: the clone's root, first without a record.
        v = verdict(clone_in_root)
        check(v.verdict == "orphan", f"from the main checkout, the clone's unrecorded root: expected an orphan, got {v.verdict}")
        rc, _ = record(clone_in, clone_in_root, tmp / "record-fixture.log")
        age(clone_in_root, OLD)
        v = verdict(clone_in_root)
        check(rc == 0 and v.verdict == "recorded" and v.reason == f"live (recorded): {clone_in}",
              f"from the main checkout, the clone's recorded root: expected 'live (recorded)', got {v.verdict} ({v.reason})")
        print("  clones                     → outside: refused, hint silent; inside: kept by their records")

        # ── 17. a record is checked, not trusted ─────────────────────────────────────────────────────
        rec = clone_in_root / ".checkout"
        good = rec.read_text()
        good_elsewhere = tmp / "good-record"
        good_elsewhere.write_text(good)
        sealed_checkout = docs / "sealed-checkout"
        sealed_checkout.mkdir()

        def writes(text):
            return lambda: rec.write_text(text)

        def make_link():
            rec.symlink_to(good_elsewhere)

        def make_unreadable():
            rec.write_text(good)
            rec.chmod(0)

        def seal():
            rec.write_text(f"{sealed_checkout}\n")
            sealed_checkout.chmod(0)

        # Only a regular file is a record, and only a directory is a checkout. Read as a record, a
        # directory named .checkout fails with EISDIR and would keep the root ("could not be read");
        # a record naming a file would send build_root.sh into `cd FILE`, fail, and keep it too.
        not_a_checkout = docs / "a-file.txt"
        not_a_checkout.write_text("a file where a checkout might have been\n")

        for n, (label, make, expected, why) in enumerate((
                ("names a directory that no longer exists", writes(f"{docs / 'removed-checkout'}\n"), "orphan", ""),
                ("names a live checkout whose root is another", writes(f"{live_wt}\n"), "orphan", ""),
                ("is a symlink to a good record", make_link, "orphan", ""),
                ("is over the size cap", writes(good + "\n" * 5000), "orphan", ""),
                ("is a directory", rec.mkdir, "orphan", ""),
                ("names a regular file, not a directory", writes(f"{not_a_checkout}\n"), "orphan", ""),
                ("cannot be read", make_unreadable, "held", "could not be read"),
                ("names a directory build_root.sh cannot enter", seal, "held", "could not be computed"))):
            os.rename(rec, tmp / "set-aside")
            try:
                make()
                age(clone_in_root, OLD)
                v = verdict(clone_in_root)
                check(v.verdict == expected and why in v.reason,
                      f"a record that {label}: expected {expected!r}, got {v.verdict} ({v.reason})")
            finally:
                sealed_checkout.chmod(0o755)
                if os.path.lexists(rec):
                    if not rec.is_symlink():
                        rec.chmod(0o755 if rec.is_dir() else 0o644)
                    os.rename(rec, tmp / f"discarded-record-{n}")
                os.rename(tmp / "set-aside", rec)
                age(clone_in_root, OLD)

        # A FIFO named .checkout. Opened without O_NONBLOCK it blocks until something writes to it, and
        # run_all_gates.sh runs --hint with no timeout, so the whole gate run would hang (review
        # 2026-10-03, round 2). Run as the runner runs it, under a timeout. It is not a record, so the
        # root is counted with the two that nobody claims (the fresh orphan and gone-held's root).
        os.rename(rec, tmp / "set-aside")
        os.mkfifo(rec)
        age(clone_in_root, OLD)
        try:
            try:
                rc, out, err = sweep("--hint", timeout=30)
                said = f"rc={rc} {out!r} {err[-300:]!r}"
            except subprocess.TimeoutExpired:
                rc, out, said = None, "", "HUNG (killed after 30 s)"
            check(rc == 0 and out.startswith("build cache: 3 build roots "),
                  f"--hint with a FIFO as a root's {mod.RECORD}: expected it to finish and count that root "
                  f"among 3, got {said}")
            if rc is not None:                   # hung once, a dry run would hang the same way
                try:
                    rc, out, err = sweep("--dry-run", timeout=120)
                    said = line_for(out, clone_in_root)
                except subprocess.TimeoutExpired:
                    said = "HUNG (killed after 120 s)"
                check("would move" in said,
                      f"--dry-run with a FIFO as a root's {mod.RECORD}: expected 'would move', got {said!r}")
        finally:
            os.rename(rec, tmp / "discarded-fifo")
            os.rename(tmp / "set-aside", rec)
            age(clone_in_root, OLD)
        check(verdict(clone_in_root).verdict == "recorded", "fixture: the clone's good record was not restored")
        print("  records                    → a missing, foreign, linked, oversized, directory, file-naming or"
              " FIFO one ignored; unreadable ones keep")

        # ── 18. the real run over all of it: the old orphan alone goes ───────────────────────────────
        before = calls_now()
        rc, out, err = sweep()
        check(rc == 0 and calls_now()[len(before):] == [f"-s {held_root}"],
              f"the final sweep must move the old orphan alone: rc={rc} calls={calls_now()[len(before):]}\n{out}")
        check(os.path.lexists(linked) and old_target.exists(),
              f"the final sweep moved the root-shaped symlink in the build dir:\n{line_for(out, linked)}")
        intact("the final sweep", [live_main, live_wt_root, clone_in_root, gone_new_root, beside, legacy])
        print("  final sweep                → the old orphan alone; links, records, clones and siblings stay")

        # ── 19. --hint is silent when every root has a live checkout ──────────────────────────────────
        clean = tmp / "clean-cache"
        (clean / "NihongoRide-build").mkdir(parents=True)
        os.rename(live_main, clean / "NihongoRide-build" / live_main.name)
        r = subprocess.run([sys.executable, str(SWEEP), "--hint", "--repo", str(repo)],
                           env={**env, "NIHONGO_BUILD_CACHE": str(clean)}, capture_output=True, text=True)
        check(r.returncode == 0 and r.stdout == "", f"--hint with nothing orphaned should print nothing: {r.stdout!r}")

    # ── 20. the code keeps the promises its header makes ──────────────────────────────────────────────
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
