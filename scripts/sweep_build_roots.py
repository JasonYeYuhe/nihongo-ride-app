#!/usr/bin/env python3
"""Move the build roots of removed checkouts to the Trash — opt-in, and only what provably belongs to nobody.

WHY THIS EXISTS
---------------
scripts/build_root.sh gives every checkout under ~/Documents its own SwiftPM build root,
<cache>/NihongoRide-build/<checkout name>-<8 hex of its resolved path>, and nothing removes one when its
checkout goes. Agent worktrees come and go by the dozen, so the roots pile up: on 2026-09-27, 94 orphaned
roots (~70 GB) filled the disk and two gates failed with "No space left on device"
(docs/STATE-2026-09-27.md). ~/.claude/CLAUDE.md's wrap-up rule covers a session that removes its OWN
worktree; this covers the rest.

WHAT IT MOVES — a directory has to be all of these, or it stays
--------------------------------------------------------------
  1. Directly under <cache>/NihongoRide-build/, where <cache> is ${NIHONGO_BUILD_CACHE:-~/Library/Caches}
     exactly as build_root.sh reads it, and named <name>-<8 hex>, the shape build_root.sh makes. Anything
     else is left alone: swiftpm/ (the shared root from before roots were per-checkout), files, other
     names, symlinks, and every sibling of NihongoRide-build/. Symlinks inside a root are not followed
     either (every real root has swiftpm/debug -> out/Products/Debug). If NihongoRide-build ITSELF is a
     symlink the sweep refuses: its scope would become whatever folder the link points at, where a
     dated "photos-20250101" has exactly the shape of a root. To move the cache, set
     NIHONGO_BUILD_CACHE instead.
  2. Mapped to by NO live checkout. The live set is `git worktree list --porcelain` of this repository
     (the main checkout is its first entry) plus the checkout named by --repo, and each one's root is
     found by RUNNING build_root.sh on it, not by re-deriving its name-and-hash rule here: one rule
     written twice drifts, and this repo has recorded three instances of exactly that. A root is also
     live when its ".checkout" record (run_all_gates.sh writes one on every gate run) is a small
     regular file naming a directory that exists and that build_root.sh maps to this same root; that
     is how a separate clone's roots are seen (LIMIT below).
  3. Nothing under it modified in the last --min-age-minutes (default 60): a build may be running.
  4. No process has a file open under it, has its working directory there, or names it in its
     arguments (one `lsof` and one `ps` for the whole sweep), whether by the resolved path or by the
     unresolved <cache>/NihongoRide-build spelling that build_root.sh hands a build.

It REFUSES — exit 1, nothing moved — when git cannot list the worktrees, when build_root.sh fails for a
checkout that exists, when lsof or ps cannot be read, when NihongoRide-build is a symlink, or when the
main checkout of the --repo repository (the first `git worktree list` entry) does not build into this
cache. The first three would leave the live set or the in-use set incomplete, and an incomplete live
set calls a live root an orphan. The last is the same failure from the other side: a clone whose
checkout does not build into the cache (one under ~/Library/Caches, CI) has a worktree list that
names none of the cache's owners, so every root there would look orphaned. Run the sweep from the
main checkout or one of its worktrees (a linked worktree outside ~/Documents is fine: its list is the
main checkout's); from such a clone --hint prints nothing at all, because its gates do not use the
cache.

A listed worktree whose directory is gone is not live (it is what `git worktree prune` would remove)
unless git has it locked; a locked one keeps every root with its name, since its path cannot be
resolved to compute the exact one. So does ANOTHER listed checkout that build_root.sh places outside
the cache (a worktree added outside ~/Documents, or one whose File Provider attribute the helper
misread): its roots, if any, cannot be told apart by hash. A .checkout record that cannot be read, or
whose directory exists but whose root build_root.sh cannot compute, keeps its root too, rather than
stopping the whole sweep.

LIMIT: `git worktree list` knows the checkouts of THIS repository, not a separate clone of it. A clone
under ~/Documents builds into this cache as well, so each side's roots are unknown to a sweep run from
the other. The .checkout record closes that for every root a gate run has built into since the record
was added (2026-10-03). A root with no record (built before then, or only by a bare
`swift test --scratch-path`) is still called an orphan from the other clone once guards 3 and 4 let
it go; it is moved to the Trash, never deleted, and the next build recreates it.

MOVES, NEVER DELETES: `/usr/bin/trash -s`, one root at a time, and the root must be gone afterwards —
the exit status alone is not taken as proof. The Trash is on the same volume, so the disk gets the space
back only when the Trash is emptied, which only the owner does; the summary says that rather than
calling the space reclaimed.

USAGE
  python3 scripts/sweep_build_roots.py --dry-run   # what it would move, and why everything else stays
  python3 scripts/sweep_build_roots.py             # move the orphans to the Trash
  python3 scripts/sweep_build_roots.py --hint      # at most one line: how many roots map to no live
                                                   # checkout. Mapping only, never moves, always exit 0.
                                                   # run_all_gates.sh prints it; it is not a gate.

Self-test: scripts/test_sweep_build_roots.py (a temporary repository, worktrees and cache; never the
real ones).
"""

import argparse
import errno
import os
import re
import stat
import subprocess
import sys
import time
from collections import namedtuple
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent
HELPER = SCRIPTS / "build_root.sh"
TRASH = "/usr/bin/trash"
LSOF = "lsof"
PS = "ps"
DEFAULT_MIN_AGE_MINUTES = 60
# run_all_gates.sh writes "<root>/.checkout": the checkout's path and a newline. Anything bigger than
# this is not what it wrote.
RECORD = ".checkout"
RECORD_MAX_BYTES = 4096

# build_root.sh names a root "<checkout basename>-<first 8 hex of `shasum` of its resolved path>".
# This shape is repeated here on purpose (it decides what counts as a root at all); the MAPPING of a
# checkout to its root is never re-derived — root_of() runs build_root.sh.
ROOT_NAME = re.compile(r"^(?P<checkout>.+)-[0-9a-f]{8}$")
# Rule 1 already keeps the sweep inside NihongoRide-build/, and the move loop re-checks every path's
# parent before it moves anything. This names, in code, the directories beside it that hold things no
# build can recreate. It is matched against the WHOLE path, so a cache placed under one of them (a
# NIHONGO_BUILD_CACHE inside NihongoRide-v135-work/, say) has nothing moved at all.
PROTECTED = re.compile(r"(^|/)(NihongoRide-v\d+-work|\.venv-jp|NihongoRide-Stats|NihongoRide-Archives)(/|$)")

Live = namedtuple("Live", "checkouts roots held notes")   # roots: {root name: checkout}; held: {basename}
Entry = namedtuple("Entry", "name path verdict reason size")


class SweepError(Exception):
    """Something the live set or the in-use set depends on could not be read. Nothing is moved."""


class ForeignCheckout(SweepError):
    """The main checkout of the --repo repository does not build into this cache, so its worktree list
    cannot say who owns the roots there. The sweep refuses; --hint says nothing (that clone's gates do
    not use the cache)."""


def cache_for(env):
    """<cache> exactly as build_root.sh spells it: ${NIHONGO_BUILD_CACHE:-$HOME/Library/Caches}."""
    return env.get("NIHONGO_BUILD_CACHE") or os.path.join(env.get("HOME") or os.path.expanduser("~"),
                                                          "Library", "Caches")


def build_dir_for(env):
    # Resolved, because lsof reports resolved paths and build_root.sh is handed this same string.
    return Path(os.path.realpath(os.path.join(cache_for(env), "NihongoRide-build")))


def unresolved_spellings(env):
    """The ways a build can name the build dir without resolving it: build_root.sh prints
    "$NIHONGO_BUILD_CACHE/NihongoRide-build/…" verbatim, and run_all_gates.sh hands that to
    `swift test --scratch-path`, so a cache under a symlink (/tmp, $TMPDIR, a linked volume) shows up
    in a process's arguments under a prefix the resolved path does not match."""
    cache = cache_for(env)
    return {f"{cache}/NihongoRide-build", os.path.normpath(os.path.join(cache, "NihongoRide-build"))}


def refuse_linked_build_dir(env):
    link = os.path.join(cache_for(env), "NihongoRide-build")
    if os.path.islink(link):
        raise SweepError(f"{link} is a symlink (to {os.readlink(link)}): the sweep would act on whatever "
                         f"folder it points at, where any '<name>-<8 hex>' folder looks like a root — "
                         f"set NIHONGO_BUILD_CACHE to the real parent directory instead")


def list_worktrees(repo, env):
    """[(path, locked, prunable)] from `git worktree list --porcelain`. Raises rather than returning less."""
    r = subprocess.run(["git", "-C", str(repo), "worktree", "list", "--porcelain"],
                       capture_output=True, text=True, env=env, timeout=60)
    if r.returncode != 0:
        raise SweepError(f"`git -C {repo} worktree list --porcelain` failed (exit {r.returncode}): "
                         f"{r.stderr.strip()}")
    trees, current = [], None
    for line in r.stdout.splitlines():
        if line.startswith("worktree "):
            current = {"path": line[len("worktree "):], "locked": False, "prunable": False, "bare": False}
            trees.append(current)
        elif current is not None and (line == "locked" or line.startswith("locked ")):
            current["locked"] = True
        elif current is not None and (line == "prunable" or line.startswith("prunable ")):
            current["prunable"] = True
        elif current is not None and line == "bare":
            current["bare"] = True
    trees = [(t["path"], t["locked"], t["prunable"]) for t in trees if not t["bare"]]
    if not trees:
        raise SweepError(f"`git -C {repo} worktree list --porcelain` listed no checkout at all")
    return trees


def root_of(checkout, build_dir, env):
    """The root build_root.sh gives this checkout, or None if it builds outside the cache."""
    helper_env = {k: v for k, v in env.items() if k != "NIHONGO_BUILD_ROOT"}
    helper_env["NIHONGO_BUILD_CACHE"] = str(build_dir.parent)
    r = subprocess.run(["bash", str(HELPER), str(checkout)], capture_output=True, text=True,
                       env=helper_env, timeout=60)
    out = r.stdout.strip().splitlines()
    if r.returncode != 0 or not out:
        raise SweepError(f"{HELPER.name} could not name the build root of {checkout} "
                         f"(exit {r.returncode}): {r.stderr.strip()}")
    root = Path(os.path.normpath(out[-1]))
    return root if root.parent == build_dir else None


def live_checkouts(repo, build_dir, env):
    roots, held, notes, count = {}, set(), [], 0
    trees = list_worktrees(repo, env)
    paths = [p for p, _, _ in trees]
    r = subprocess.run(["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True, env=env, timeout=60)
    top = r.stdout.strip()
    if r.returncode != 0 or not top:
        raise SweepError(f"`git -C {repo} rev-parse --show-toplevel` failed (exit {r.returncode}): "
                         f"{r.stderr.strip()}")
    # The repository whose worktree list this reads must be the one whose checkouts build into this
    # cache, and its main checkout (the list's first entry) is the test. From a clone under
    # ~/Library/Caches, or CI, that is the clone itself, which builds elsewhere: its list names none
    # of the checkouts whose roots are here, and every one of them would look orphaned (review
    # 2026-10-03: from a review clone, the main checkout's root and every idle worktree's were "would
    # move"). A linked worktree of the main checkout passes even when it sits outside ~/Documents: its
    # list IS the main checkout's, and its own root-outside-the-cache is held by name below.
    anchor = paths[0] if os.path.isdir(paths[0]) else top
    anchor_root = root_of(anchor, build_dir, env)
    if anchor_root is None:
        raise ForeignCheckout(f"{anchor} does not build into {build_dir}, and the worktree list of a "
                              f"repository whose main checkout does not build into the cache cannot say "
                              f"who owns the roots there — run it from the main checkout or one of its "
                              f"worktrees")
    if top not in paths:
        trees.append((top, False, False))
    for path, locked, prunable in trees:
        count += os.path.isdir(path) or locked
        if os.path.isdir(path):
            root = anchor_root if path == anchor else root_of(path, build_dir, env)
            if root is None:
                # ANOTHER checkout of this repository that builds outside the cache: a worktree added
                # outside ~/Documents, or one whose File Provider attribute the helper could not see.
                # Keep this name's roots rather than let a misread make a live root look orphaned.
                held.add(os.path.basename(path))
                notes.append(f"{path} builds outside the cache — every root named "
                             f"{os.path.basename(path)}-<hex> is kept")
            else:
                roots[root.name] = path
        elif locked:
            held.add(os.path.basename(path))
            notes.append(f"{path} is missing on disk but locked in git — every root named "
                         f"{os.path.basename(path)}-<hex> is kept")
        else:
            notes.append(f"{path} is missing on disk ({'prunable' if prunable else 'not a directory'}) "
                         f"— not live; `git worktree prune` would remove it")
    return Live(count, roots, held, notes)


def read_record(root):
    """The checkout path in <root>/.checkout, or None when there is no usable record: absent, a symlink,
    not a regular file, bigger than RECORD_MAX_BYTES, or not one absolute UTF-8 path. Raises OSError
    when a regular record is there but cannot be read."""
    try:
        # O_NOFOLLOW: a symlinked record is not one a gate run wrote, and following it would let any
        # file on the disk vouch for a root. O_NONBLOCK: a FIFO planted there must not hang the sweep.
        fd = os.open(root / RECORD, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as err:
        if err.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            return None
        raise
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > RECORD_MAX_BYTES:
            return None
        data = os.read(fd, RECORD_MAX_BYTES + 1)
    finally:
        os.close(fd)
    try:
        path = data.decode("utf-8").rstrip("\n")
    except UnicodeDecodeError:
        return None
    if not path or "\n" in path or "\0" in path or not os.path.isabs(path):
        return None
    return path


def recorded_owner(child, build_dir, env):
    """The verdict a root's .checkout record earns it, or None to classify it as if it had none.

    The record is a claim, so it is checked rather than trusted: the directory it names must exist and
    build_root.sh must map it to THIS root. A record naming a removed checkout, or a checkout that now
    builds elsewhere, is ignored. One that cannot be checked (unreadable, or the helper fails on that
    directory) keeps the root without stopping the sweep: it says nothing about the other roots."""
    try:
        owner = read_record(child)
    except OSError as err:
        return Entry(child.name, child, "held", f"its {RECORD} record could not be read ({err}) — kept", None)
    if owner is None or not os.path.isdir(owner):
        return None
    try:
        root = root_of(owner, build_dir, env)
    except (SweepError, OSError, subprocess.SubprocessError) as err:
        return Entry(child.name, child, "held", f"its {RECORD} names {owner}, whose root could not be "
                     f"computed — kept ({err})", None)
    if root != child:
        return None
    return Entry(child.name, child, "recorded", f"live (recorded): {owner}", None)


def classify(build_dir, live, env):
    """Every entry of the build dir, as other / live / recorded / held / candidate. No filesystem walk:
    the most it reads inside a root is the root's .checkout record."""
    entries = []
    for child in sorted(build_dir.iterdir(), key=lambda p: p.name):
        m = ROOT_NAME.match(child.name)
        if child.is_symlink() or not child.is_dir():
            entries.append(Entry(child.name, child, "other", "not a directory — left alone", None))
        elif not m:
            entries.append(Entry(child.name, child, "other", "not a per-checkout root — left alone", None))
        elif child.name in live.roots:
            entries.append(Entry(child.name, child, "live", f"live: {live.roots[child.name]}", None))
        elif m.group("checkout") in live.held:
            entries.append(Entry(child.name, child, "held", "a checkout of this name is live but its root "
                                 "could not be computed — kept", None))
        elif PROTECTED.search(str(child)):
            entries.append(Entry(child.name, child, "other", "protected name — left alone", None))
        else:
            entries.append(recorded_owner(child, build_dir, env)
                           or Entry(child.name, child, "candidate", "no live checkout maps to it", None))
    return entries


def walk(root):
    """(allocated bytes, newest mtime) of root and everything under it; symlinks are not followed."""
    size, newest, seen = 0, os.lstat(root).st_mtime, set()
    stack = [str(root)]
    while stack:
        with os.scandir(stack.pop()) as it:
            for e in it:
                st = e.stat(follow_symlinks=False)
                newest = max(newest, st.st_mtime)
                if st.st_nlink > 1 and not e.is_dir(follow_symlinks=False):
                    if (st.st_dev, st.st_ino) in seen:
                        continue
                    seen.add((st.st_dev, st.st_ino))
                size += st.st_blocks * 512
                if e.is_dir(follow_symlinks=False):
                    stack.append(e.path)
    return size, newest


def processes_using(build_dir, spellings=()):
    """[(pid, command, path)] for every open file or working directory under build_dir, then every
    process whose arguments name a path under it, by its resolved path or by any of `spellings`
    (unresolved ways of writing the same directory). Paths come back in the resolved spelling, so
    they compare with the roots classify() lists. Raises if either cannot be read."""
    resolved = str(build_dir) + os.sep
    prefixes = sorted({resolved, *(str(s).rstrip(os.sep) + os.sep for s in spellings)},
                      key=len, reverse=True)

    def as_resolved(path):
        for p in prefixes:
            if path.startswith(p):
                return resolved + path[len(p):]
        return None

    found = []
    try:
        r = subprocess.run([LSOF, "-n", "-P", "-w", "-F", "pcn"], capture_output=True, text=True,
                           errors="replace", timeout=120)
    except (OSError, subprocess.SubprocessError) as err:
        raise SweepError(f"lsof could not run ({err}) — cannot tell which roots are open")
    if r.returncode != 0 and not r.stdout:
        raise SweepError(f"lsof failed (exit {r.returncode}): {r.stderr.strip()} — cannot tell which "
                         f"roots are open")
    pid, cmd = None, ""
    for line in r.stdout.splitlines():
        if line.startswith("p"):
            pid, cmd = line[1:], ""
        elif line.startswith("c"):
            cmd = line[1:]
        elif line.startswith("n") and as_resolved(line[1:]):
            found.append((pid, cmd, as_resolved(line[1:])))
    try:
        r = subprocess.run([PS, "-axww", "-o", "pid=", "-o", "command="], capture_output=True, text=True,
                           errors="replace", timeout=60)
    except (OSError, subprocess.SubprocessError) as err:
        raise SweepError(f"ps could not run ({err}) — cannot tell which roots a process names")
    if r.returncode != 0 or not r.stdout.strip():
        raise SweepError(f"ps failed (exit {r.returncode}): {r.stderr.strip()} — cannot tell which roots "
                         f"a process names")
    me = str(os.getpid())
    for line in r.stdout.splitlines():
        pid_s, _, command = line.strip().partition(" ")
        if pid_s == me or not any(p in command for p in prefixes):
            continue
        for p in prefixes:
            for m in re.finditer(re.escape(p) + r"[^\s]*", command):
                found.append((pid_s, command.split()[0].rsplit("/", 1)[-1], resolved + m.group(0)[len(p):]))
    return found


def plan(repo, build_dir, env, min_age_minutes, now=None):
    """Every entry of the build dir with its final verdict:
    other / live / recorded / held / recent / in use / unreadable / orphan. Only "orphan" is ever moved."""
    now = time.time() if now is None else now
    refuse_linked_build_dir(env)
    live = live_checkouts(repo, build_dir, env)
    entries = classify(build_dir, live, env)
    candidates = [e for e in entries if e.verdict == "candidate"]
    users = processes_using(build_dir, unresolved_spellings(env)) if candidates else []
    out = []
    for e in entries:
        if e.verdict != "candidate":
            out.append(e)
            continue
        try:
            size, newest = walk(e.path)
        except OSError as err:
            out.append(e._replace(verdict="unreadable", reason=f"no live checkout, but could not be read: {err}"))
            continue
        mine = [(pid, cmd) for pid, cmd, path in users
                if path == str(e.path) or path.startswith(str(e.path) + os.sep)]
        age = (now - newest) / 60
        if age < min_age_minutes:
            out.append(e._replace(verdict="recent", size=size,
                                  reason=f"no live checkout, but modified {age:.0f} min ago "
                                         f"(< {min_age_minutes}) — a build may be running"))
        elif mine:
            who = ", ".join(sorted({f"{cmd or '?'} (pid {pid})" for pid, cmd in mine}))
            out.append(e._replace(verdict="in use", size=size,
                                  reason=f"no live checkout, but in use by {who}"))
        else:
            out.append(e._replace(verdict="orphan", size=size,
                                  reason=f"no live checkout; last modified {age / 60:.1f} h ago"))
    return live, out


def human(n):
    if n >= 1e9:
        return f"{n / 1e9:.1f} GB"
    return f"{n / 1e6:.0f} MB" if n >= 1e6 else f"{n / 1e3:.0f} KB"


def hint(repo, env):
    """At most one line. Mapping only: no walk, no lsof, no move. Nothing at all from a clone whose main
    checkout does not build into the cache: its gates do not use it, and it must not invite a sweep
    from there."""
    build_dir = build_dir_for(env)
    try:
        refuse_linked_build_dir(env)
    except SweepError as err:
        return f"build cache: could not check {os.path.join(cache_for(env), 'NihongoRide-build')} " \
               f"for orphaned build roots ({err})"
    if not build_dir.is_dir():
        return ""
    try:
        live = live_checkouts(repo, build_dir, env)
        n = sum(1 for e in classify(build_dir, live, env) if e.verdict == "candidate")
    except ForeignCheckout:
        return ""
    except (SweepError, OSError, subprocess.SubprocessError) as err:
        return f"build cache: could not check {build_dir} for orphaned build roots ({err})"
    if not n:
        return ""
    return (f"build cache: {n} build root{'s' if n != 1 else ''} in {build_dir} "
            f"map{'' if n != 1 else 's'} to no live checkout "
            f"— review with `python3 scripts/sweep_build_roots.py --dry-run`")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--dry-run", action="store_true", help="print what would be moved; move nothing")
    ap.add_argument("--hint", action="store_true",
                    help="print at most one line if some root maps to no live checkout; never moves")
    ap.add_argument("--min-age-minutes", type=int, default=DEFAULT_MIN_AGE_MINUTES,
                    help=f"keep a root modified more recently than this (default {DEFAULT_MIN_AGE_MINUTES})")
    ap.add_argument("--repo", default=str(REPO),
                    help="a checkout of the repository whose worktrees are live (default: this one)")
    ap.add_argument("--trash-cmd", default=TRASH,
                    help=f"what moves a root, called as `CMD -s ROOT` (default {TRASH}; the self-test "
                         f"passes a stand-in so it never touches the real Trash)")
    args = ap.parse_args(argv)
    env = dict(os.environ)

    if args.hint:
        line = hint(args.repo, env)
        if line:
            print(line)
        return 0

    build_dir = build_dir_for(env)
    print(f"build cache: {build_dir}")
    try:
        refuse_linked_build_dir(env)          # before the existence check: a dangling link refuses too
    except SweepError as err:
        print(f"  REFUSED, nothing moved: {err}")
        return 1
    if not build_dir.is_dir():
        print("  (does not exist — nothing to sweep)")
        return 0
    try:
        live, entries = plan(args.repo, build_dir, env, args.min_age_minutes)
    except SweepError as err:
        print(f"  REFUSED, nothing moved: {err}")
        return 1

    present = sum(1 for e in entries if e.verdict == "live")
    recorded = sum(1 for e in entries if e.verdict == "recorded")
    print(f"live checkouts (`git worktree list` of {args.repo}): {live.checkouts}, "
          f"{present} with a root here" + (f"; {recorded} more root{'s' if recorded != 1 else ''} kept by "
                                           f"{RECORD} records" if recorded else ""))
    for note in live.notes:
        print(f"  note: {note}")
    width = max(len(e.name) for e in entries) + 1 if entries else 0
    action = {"other": "keep", "live": "keep", "recorded": "keep", "held": "keep", "recent": "skip",
              "in use": "skip", "unreadable": "skip", "orphan": "would move" if args.dry_run else "move"}
    for e in entries:
        size = human(e.size) if e.size is not None else ""
        print(f"  {action[e.verdict]:<10} {e.name + '/':<{width}} {size:>8}  {e.reason}")

    orphans = [e for e in entries if e.verdict == "orphan"]
    if args.dry_run:
        print(f"dry run: would move {len(orphans)} orphaned root{'s' if len(orphans) != 1 else ''} "
              f"({human(sum(e.size for e in orphans))}) to the Trash; nothing was moved")
        return 0

    moved, failed = [], []
    for e in orphans:
        if PROTECTED.search(str(e.path)) or e.path.parent != build_dir:
            failed.append(f"{e.path}: outside the sweep's scope — not moved")
            continue
        if not os.path.lexists(e.path):
            print(f"  {e.name}/ vanished before it could be moved (another sweep?) — skipped")
            continue
        try:
            r = subprocess.run([args.trash_cmd, "-s", str(e.path)], capture_output=True, text=True,
                               timeout=600)
            said = f"exit {r.returncode} {r.stderr.strip()}".strip()
        except (OSError, subprocess.SubprocessError) as err:
            said = str(err)
        # The root being gone is the proof, not the exit status: without -s, trash exits 0 on a
        # failed move.
        if os.path.lexists(e.path):
            failed.append(f"{e.path}: still there after `{args.trash_cmd} -s` ({said})")
        else:
            moved.append(e)
    total = sum(e.size for e in moved)
    print(f"moved {len(moved)} orphaned root{'s' if len(moved) != 1 else ''} ({human(total)}) to the Trash. "
          f"The Trash is on the same disk: the space comes back when the Trash is emptied.")
    for f in failed:
        print(f"  FAILED {f}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
