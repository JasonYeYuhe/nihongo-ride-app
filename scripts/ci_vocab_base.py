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
successful run's base is the previous success or release_numbers.BASELINE_REF, which is older, so
from BASELINE_REF onward the windows join and no commit falls between two of them. (Runs from
before this script certify only `before..head`; the chain starts with the first run that uses it.)
The one exception is the last resort below: a run that had to take it certifies less than it
should, and it says so on its summary page.

RULE
----
* pull_request: the PR's base sha, unchanged. The PR is compared whole, so a cancelled push to it
  is covered by the next one, and no API call is made.
* push / workflow_dispatch: ask the Actions API for this workflow's successful runs on this branch
  and take, among their head commits, the one closest to HEAD (fewest commits between) that is a
  STRICT ancestor of HEAD and exists in the clone. Closest in history, not newest by creation
  time: a re-run of an old commit is created later but certifies less. HEAD itself is skipped (an
  earlier success at the same commit would make the base HEAD, a comparison with itself).
* CLAMP (v1.37 round 1, ci-2): if that success does not contain BASELINE_REF (it is older than
  the release boundary, or on a line that never merged it), the base is BASELINE_REF instead.
  Everything before BASELINE_REF is the previous release's, gated locally against ITS manifest;
  a window reaching back past it would show that release's corrections as undeclared to this
  release's manifest, and a main that stayed red across a release could never go green again.
* FALLBACK (ci-1, ci-5) — the API failed, no run ever succeeded, no successful head is an ancestor,
  or a workflow_dispatch on a branch with no successes of its own (a release branch): BASELINE_REF,
  the window the local runner and CORPUS_MANIFEST already agree on. It is wider than needed, never
  narrower, so a run that takes it skips nothing and is a sound base for the next one.
* LAST RESORT — only when BASELINE_REF itself is unusable (empty, not in the clone, not a strict
  ancestor of HEAD): the previous behaviour, the push's "before", or HEAD~1 when "before" is empty
  or all zeros. This one CAN skip a cancelled push's change, and its warning says that.
Every clamp, fallback and last resort is LOUD: a `::warning::` annotation that names why, never a
quiet substitution.

The final base must resolve to a commit in this clone or the step fails; `actions/checkout` runs
with `fetch-depth: 0`, so every ancestor of HEAD is here. A FORCE PUSH is the case this is for:
its "before" is the overwritten tip, which checkout (fetching refs only) does not have. When the
rewrite left BASELINE_REF in place, the fallback above compares the whole release window. When it
rewrote BASELINE_REF too (a history purge), the last resort is that unfetched "before", and the
force push's own run goes RED by design — fail closed, test_ci_vocab_base.py fixture 9. The next
push's "before" is the new tip and resolves; BASELINE_REF is moved to its rewritten sha in the
purge itself, or every release_numbers delta breaks with it.

ONE PAGE (ci-4). The API is read once, newest first, PER_PAGE runs; older successes are never
looked at, and the log says how many were listed of how many exist. With linear history the
closest ancestor is always on that page. It can fall off it only after PER_PAGE or more successes
on heads that are not ancestors of HEAD — a rewrite — and then the result is the BASELINE_REF
fallback: wider, never narrower. Paging would add API calls and code for no case that changes
what is checked.

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

import release_numbers  # scripts/ is sys.path[0] when this runs as a script

REPO = Path(__file__).resolve().parent.parent
ZERO_SHA = "0" * 40
PER_PAGE = 100
# The release boundary: the tree the version on sale was built from. Read, never copied, so the CI
# window moves in the same commit as CORPUS_MANIFEST and the local runner's window.
BASELINE_REF = release_numbers.BASELINE_REF
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
    """(runs, total_count): this workflow's successful runs on `branch`, newest first, as the API
    returns them — ONE page of PER_PAGE (see ONE PAGE above) — and how many the API says exist
    (None when it does not say).

    `status=success` filters on the server; `newest_success` checks `conclusion` again itself, so
    a filter the API stopped honouring cannot turn a cancelled run into a base.
    """
    if not (api_url and repository and workflow and branch):
        raise APIError("missing GITHUB_API_URL, GITHUB_REPOSITORY, --workflow or --branch")
    query = urllib.parse.urlencode({"branch": branch, "status": "success", "per_page": PER_PAGE})
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
    total = body.get("total_count")
    return runs, (total if isinstance(total, int) else None)


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
    or HEAD~1 when before is empty or all zeros (a first push to a branch). Now the LAST RESORT."""
    if event == "pull_request":
        return pr_base
    if before and before != ZERO_SHA:
        return before
    return commit_of(repo, "HEAD~1")


def usable_baseline(repo, ref, head):
    """(sha, None) when `ref` is a strict ancestor of HEAD in this clone, else (None, why not)."""
    if not ref:
        return None, "release_numbers.BASELINE_REF is empty"
    sha = commit_of(repo, ref)
    if sha is None:
        return None, f"BASELINE_REF {ref} is not a commit in this clone (history rewritten?)"
    if sha == head:
        return None, f"BASELINE_REF {ref} is HEAD itself"
    if not is_ancestor(repo, sha, head):
        return None, f"BASELINE_REF {ref} is not an ancestor of HEAD"
    return sha, None


def resolve(repo, event, before, pr_base, branch, load_runs, baseline_ref=BASELINE_REF):
    """(base, warnings, log): the base, the `::warning::` lines owed, and what to print.

    `load_runs` is called only for chained events and may raise anything; that is the API failing.
    It returns the run list, or (run list, total_count) as fetch_runs does.
    """
    log, warnings = [], []
    if event == "pull_request":
        log.append(f"pull request: comparing against the PR's base {pr_base}")
        return pr_base, warnings, log
    head = commit_of(repo, "HEAD")
    baseline, why_not = usable_baseline(repo, baseline_ref, head)
    previous = previous_behaviour(repo, event, before, pr_base)

    def fallback(reason):
        if baseline:
            warnings.append(f"{reason}; falling back to release_numbers.BASELINE_REF {baseline_ref} "
                            f"({baseline[:12]}), this release's whole window: wider than needed, "
                            "never narrower")
            return baseline
        warnings.append(f"{reason}, and {why_not}; LAST RESORT: the push's own base {previous}, so a "
                        "cancelled earlier push's corpus change may go unchecked")
        return previous

    try:
        loaded = load_runs()
    except Exception as e:
        return fallback(f"the Actions API could not be read ({e})"), warnings, log
    runs, total = loaded if isinstance(loaded, tuple) else (loaded, None)
    listed = f"{len(runs)} of {total if total is not None else '?'}"
    log.append(f"listed {listed} successful run(s) on {branch} (one page of {PER_PAGE}; "
               "older runs are not read)")
    sha, run, notes = newest_success(runs, repo, head, branch)
    for n in notes:
        log.append(f"passed over a successful run at {n}")
    if sha is None:
        return fallback(f"no successful gates run on {branch} is an ancestor of HEAD "
                        f"({listed} listed)"), warnings, log
    log.append(f"newest successful gates run on {branch}: run {run.get('id')} at {sha} "
               f"({run.get('created_at', '?')}), {distance(repo, sha, head)} commit(s) behind HEAD")
    if baseline is None:
        warnings.append(f"{why_not}, so the window cannot be clamped to the release boundary; "
                        f"comparing against the newest success {sha[:12]} as found")
    elif not is_ancestor(repo, baseline, sha):
        warnings.append(f"the newest successful run's head {sha[:12]} does not contain "
                        f"release_numbers.BASELINE_REF {baseline_ref} ({baseline[:12]}): no run has "
                        "succeeded since the release boundary. Comparing against BASELINE_REF instead; "
                        "what precedes it is the previous release's, gated against its own manifest")
        return baseline, warnings, log
    if previous and commit_of(repo, previous) != sha:
        log.append(f"the push's own base was {previous}; its run did not succeed (cancelled or "
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
    ap.add_argument("--baseline-ref", default=BASELINE_REF,
                    help="the release boundary (default: release_numbers.BASELINE_REF; gates.yml "
                         "passes nothing, the fixtures pass their own)")
    args = ap.parse_args(argv)

    def load():
        return fetch_runs(os.environ.get("GITHUB_API_URL", ""), os.environ.get("GITHUB_REPOSITORY", ""),
                          args.workflow, args.branch, os.environ.get("GITHUB_TOKEN", ""))

    base, warnings, log = resolve(args.repo_dir, args.event, args.before, args.pr_base, args.branch, load,
                                  args.baseline_ref)
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
