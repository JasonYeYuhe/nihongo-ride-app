#!/usr/bin/env python3
"""Pick the commit CI's corpus check compares against: the newest commit on this branch whose
gates run SUCCEEDED, not the push's own "before".

WHY (v1.36 §H, recorded for v1.37)
----------------------------------
`.github/workflows/gates.yml` runs with `concurrency: cancel-in-progress: true`. When push 1 (with a
corpus change) is cancelled by push 2, push 2's run used to compare against `github.event.before`,
which is push 1's head: push 1's corpus change was never checked by anything. It happened for real
on 2026-10-26: the runs for f5165ed and 24684c2 were cancelled, and 06e941c's run compared against
24684c2. That window held no corpus change, so nothing slipped through; the next one might.

A successful run certifies its own window, base..head. Chained through this script, every
successful run's base is the previous success, so the windows join and no commit falls between two
of them. (Runs from before this script certify only `before..head`; the chain starts with the
first run that uses it.)

RULE
----
* pull_request: the PR's base sha, unchanged. The PR is compared whole, so a cancelled push to it
  is covered by the next one, and no API call is made.
* push / workflow_dispatch: ask the Actions API for this workflow's successful runs on this branch
  and take, among their head commits, the one closest to HEAD (fewest commits between) that is a
  STRICT ancestor of HEAD and exists in the clone. Closest in history, not newest by creation
  time: a re-run of an old commit is created later but certifies less. HEAD itself is skipped (an
  earlier success at the same commit would make the base HEAD, a comparison with itself).
* Otherwise — the API failed, no run ever succeeded, or no successful head is an ancestor (a force
  push) — the previous behaviour: the push's "before", or HEAD~1 when "before" is empty or all
  zeros. LOUDLY: a `::warning::` annotation that names why, never a quiet substitution.

The final base must resolve to a commit in this clone or the step fails; `actions/checkout` runs
with `fetch-depth: 0`, so every ancestor of HEAD is here.

The token is the job's GITHUB_TOKEN, read from the environment, sent only to GITHUB_API_URL and
never printed; the workflow grants it `actions: read` and `contents: read` and nothing else.

    python3 scripts/ci_vocab_base.py --event push --before <sha> --branch main --workflow gates.yml

scripts/test_ci_vocab_base.py drives every branch of this against a temporary repository and a
local HTTP server, and pins the workflow's wiring.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ZERO_SHA = "0" * 40
# Events whose runs chain through this script. A pull_request run certifies the PR against ITS
# base, which says nothing about the branch's own history.
CHAINED_EVENTS = ("push", "workflow_dispatch")


class APIError(Exception):
    pass


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)


def commit_of(repo, ref):
    """The full sha `ref` names in `repo`, or None when it is not a commit there."""
    if not ref:
        return None
    r = git(repo, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def is_ancestor(repo, sha, head):
    return git(repo, "merge-base", "--is-ancestor", sha, head).returncode == 0


def distance(repo, sha, head):
    """Commits reachable from `head` and not from `sha`: how far `sha` is behind."""
    return int(git(repo, "rev-list", "--count", f"{sha}..{head}").stdout.strip())


def fetch_runs(api_url, repository, workflow, branch, token, timeout=20):
    """This workflow's successful runs on `branch`, newest first, as the API returns them.

    `status=success` filters on the server; `newest_success` checks `conclusion` again itself, so
    a filter the API stopped honouring cannot turn a cancelled run into a base.
    """
    if not (api_url and repository and workflow and branch):
        raise APIError("missing GITHUB_API_URL, GITHUB_REPOSITORY, --workflow or --branch")
    query = urllib.parse.urlencode({"branch": branch, "status": "success", "per_page": 100})
    url = (f"{api_url.rstrip('/')}/repos/{repository}/actions/workflows/"
           f"{urllib.parse.quote(workflow, safe='')}/runs?{query}")
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=timeout) as r:
            body = json.load(r)
    except Exception as e:  # HTTP errors, refused connections, timeouts, bad JSON: all one outcome
        raise APIError(f"{type(e).__name__}: {e}") from None
    runs = body.get("workflow_runs") if isinstance(body, dict) else None
    if not isinstance(runs, list):
        raise APIError("the response has no workflow_runs list")
    return runs


def newest_success(runs, repo, head, branch):
    """(sha, run, notes): the successful run's head closest to HEAD that is a strict ancestor of it.

    sha is None when no run qualifies. `notes` says why each successful run was passed over.
    """
    best, notes = None, []
    for run in runs:
        if not isinstance(run, dict):
            continue
        if run.get("status") != "completed" or run.get("conclusion") != "success":
            continue
        if run.get("event") not in CHAINED_EVENTS or run.get("head_branch") != branch:
            continue
        raw = run.get("head_sha") or ""
        sha = commit_of(repo, raw)
        if sha is None:
            notes.append(f"{raw[:12] or '(no sha)'}: not a commit in this clone (force-pushed away?)")
            continue
        if sha == head:
            notes.append(f"{sha[:12]}: is HEAD itself — a comparison with itself is not one")
            continue
        if not is_ancestor(repo, sha, head):
            notes.append(f"{sha[:12]}: not an ancestor of HEAD (history was rewritten)")
            continue
        d = distance(repo, sha, head)
        if best is None or d < best[0]:
            best = (d, sha, run)
    return (best[1], best[2], notes) if best else (None, None, notes)


def previous_behaviour(repo, event, before, pr_base):
    """The base this workflow computed before this script: the PR's base, or the push's before,
    or HEAD~1 when before is empty or all zeros (a first push to a branch)."""
    if event == "pull_request":
        return pr_base
    if before and before != ZERO_SHA:
        return before
    return commit_of(repo, "HEAD~1")


def resolve(repo, event, before, pr_base, branch, load_runs):
    """(base, warnings, log): the base, the `::warning::` lines owed, and what to print.

    `load_runs` is called only for chained events and may raise anything; that is the API failing.
    """
    log, warnings = [], []
    if event == "pull_request":
        log.append(f"pull request: comparing against the PR's base {pr_base}")
        return pr_base, warnings, log
    head = commit_of(repo, "HEAD")
    fallback = previous_behaviour(repo, event, before, pr_base)
    try:
        runs = load_runs()
    except Exception as e:
        warnings.append(f"the Actions API could not be read ({e}); falling back to the push's own "
                        f"base {fallback}, so a cancelled earlier push's corpus change may go unchecked")
        return fallback, warnings, log
    sha, run, notes = newest_success(runs, repo, head, branch)
    for n in notes:
        log.append(f"passed over a successful run at {n}")
    if sha is None:
        warnings.append(f"no successful gates run on {branch} is an ancestor of HEAD "
                        f"({len(runs)} run(s) listed); falling back to the push's own base {fallback}, "
                        "so a cancelled earlier push's corpus change may go unchecked")
        return fallback, warnings, log
    log.append(f"newest successful gates run on {branch}: run {run.get('id')} at {sha} "
               f"({run.get('created_at', '?')}), {distance(repo, sha, head)} commit(s) behind HEAD")
    if fallback and commit_of(repo, fallback) != sha:
        log.append(f"the push's own base was {fallback}; its run did not succeed (cancelled or "
                   "failed), so the commits after the last success are checked here")
    return sha, warnings, log


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--event", required=True, help="github.event_name")
    ap.add_argument("--before", default="", help="github.event.before (push)")
    ap.add_argument("--pr-base", default="", help="github.event.pull_request.base.sha")
    ap.add_argument("--branch", default="", help="github.ref_name")
    ap.add_argument("--workflow", default="", help="the workflow's file name, e.g. gates.yml")
    ap.add_argument("--repo-dir", default=str(REPO))
    args = ap.parse_args(argv)

    def load():
        return fetch_runs(os.environ.get("GITHUB_API_URL", ""), os.environ.get("GITHUB_REPOSITORY", ""),
                          args.workflow, args.branch, os.environ.get("GITHUB_TOKEN", ""))

    base, warnings, log = resolve(args.repo_dir, args.event, args.before, args.pr_base, args.branch, load)
    for line in log:
        print(line)
    for w in warnings:
        # An annotation on the run's summary page AND a plain line in the log.
        print(f"::warning title=vocabulary base fallback::{w}")
        print(f"FALLBACK: {w}")
    resolved = commit_of(args.repo_dir, base)
    if resolved is None:
        print(f"::error::the vocabulary comparison base {base!r} is not a commit in this clone")
        return 1
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"base={resolved}\n")
    print(f"comparing the corpus against {resolved}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
