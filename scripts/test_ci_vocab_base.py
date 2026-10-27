#!/usr/bin/env python3
"""Self-test for scripts/ci_vocab_base.py — CI's corpus-check base, without GitHub.

The defect it exists for: with `cancel-in-progress: true`, push 2 cancels push 1's run, and push 2
compared the corpus against push 1's head, so push 1's corpus change was checked by nothing. The
selection is driven here against a temporary repository (A ← B ← C ← D, plus X on a side branch
that is not an ancestor of D) and canned run lists shaped like the Actions API's (the fields read
are the ones `gh api .../actions/workflows/gates.yml/runs` returned on 2026-10-27):

  1. a cancelled push: A and B succeeded, C's run was cancelled, D is HEAD with before = C → B.
     The fixture the "latest push" selection gets wrong (it answers C).
  2. a cancelled run between two successes: A ok, B cancelled, C ok → C, the closest success,
     even when the API lists a later re-run of A first.
  3. the API failing (raised, refused connection, HTTP 500, malformed body) → before, loudly.
  4. no success ever (cancelled, failed, in progress, other branch, pull_request runs) → before,
     loudly; a first push (before all zeros) → HEAD~1.
  5. a successful head that is not an ancestor (X), or not in the clone, or HEAD itself → passed
     over, with A chosen behind it, or the fallback when nothing else qualifies.
  6. pull_request → the PR's base, and the API is never called.

The CLI is run end to end against a local HTTP server, so the real request is what is checked:
its path and query, the bearer token (which must never be printed), the GITHUB_OUTPUT line and the
`::warning::` annotation. Last, the workflow's wiring is read: the step calls this script with its
own file name, the gates take the step's output, the token gets `actions: read` and `contents:
read` only, the clone stays full-depth, and no third-party action was added.
"""

import http.server
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
import ci_vocab_base as cvb  # noqa: E402

WORKFLOW = REPO / ".github" / "workflows" / "gates.yml"
TOKEN = "fixture-token-must-not-be-printed"


def sh(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True)
    return r.stdout.strip()


def make_repo(root):
    """A ← B ← C ← D on main (HEAD = D), and X branched from A. Returns {name: sha}."""
    sh(root, "init", "-q", "-b", "main")
    sh(root, "config", "user.email", "fixture@example.invalid")
    sh(root, "config", "user.name", "fixture")
    sh(root, "config", "commit.gpgsign", "false")
    shas = {}
    for name in "ABCD":
        (root / "f.txt").write_text(name)
        sh(root, "add", "f.txt")
        sh(root, "commit", "-q", "-m", name)
        shas[name] = sh(root, "rev-parse", "HEAD")
    sh(root, "checkout", "-q", "-b", "side", shas["A"])
    (root / "f.txt").write_text("X")
    sh(root, "commit", "-q", "-am", "X")
    shas["X"] = sh(root, "rev-parse", "HEAD")
    sh(root, "checkout", "-q", "main")
    return shas


def run(sha, conclusion="success", status="completed", event="push", branch="main", run_id=1,
        created="2026-10-26T00:00:00Z"):
    return {"id": run_id, "head_sha": sha, "status": status, "conclusion": conclusion,
            "event": event, "head_branch": branch, "created_at": created,
            "path": ".github/workflows/gates.yml"}


class Server:
    """A one-route HTTP server standing in for GITHUB_API_URL; records every request."""

    def __init__(self, status, body):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                outer.requests.append((self.path, dict(self.headers)))
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *a):
                pass

        self.httpd = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def cli(repo, api_url, *args):
    """Run the script as CI does. Returns (rc, stdout+stderr, the GITHUB_OUTPUT file's text)."""
    with tempfile.NamedTemporaryFile("r", suffix=".out", delete=False) as out:
        path = out.name
    env = {k: v for k, v in os.environ.items() if not k.startswith("GITHUB_")}
    env.update({"GITHUB_API_URL": api_url, "GITHUB_REPOSITORY": "owner/repo",
                "GITHUB_TOKEN": TOKEN, "GITHUB_OUTPUT": path})
    r = subprocess.run([sys.executable, str(SCRIPTS / "ci_vocab_base.py"), "--repo-dir", str(repo),
                        "--branch", "main", "--workflow", "gates.yml", *args],
                       capture_output=True, text=True, env=env, timeout=60)
    text = Path(path).read_text()
    os.unlink(path)
    return r.returncode, r.stdout + r.stderr, text


def closed_port_url():
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()                       # nothing listens there now: connection refused
    return f"http://127.0.0.1:{port}"


def main():
    failures = []

    def check(ok, message):
        if not ok:
            failures.append(message)
            print(f"FAIL  {message}")
        return ok

    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(os.path.realpath(tmp)) / "repo"
        repo.mkdir()
        s = make_repo(repo)
        A, B, C, D, X = (s[k] for k in "ABCDX")

        def pick(runs, before=C, event="push"):
            return cvb.resolve(repo, event, before, "", "main", lambda: runs)

        # 1. The cancelled push. The base a "latest push" rule picks (before = C) is wrong.
        runs = [run(D, status="in_progress", conclusion=None, run_id=4), run(C, "cancelled", run_id=3),
                run(B, run_id=2), run(A, run_id=1)]
        base, warns, log = pick(runs)
        check(base == B, f"1. cancelled push: expected B {B[:9]}, got {str(base)[:9]} "
                         f"({'C — the cancelled push, unchecked' if base == C else 'other'})")
        check(not warns, f"1. a clean selection warned: {warns}")
        check(any("did not succeed" in line for line in log),
              f"1. the log does not say the push's own base was passed over: {log}")
        print(f"  1. cancelled push (before = C)         → {'B' if base == B else base}")

        # 2. A cancelled run between two successes: the closer success wins, whatever the API's
        #    order — a re-run of A, created later, is listed first.
        runs = [run(A, run_id=9, created="2026-10-27T00:00:00Z"), run(C, run_id=3),
                run(B, "cancelled", run_id=2), run(A, run_id=1)]
        base, warns, _ = pick(runs)
        check(base == C and not warns, f"2. between two successes: expected C, got {str(base)[:9]} {warns}")
        # The same with before = D's parent missing from the list entirely.
        base, warns, _ = pick([run(A, run_id=1), run(B, "failure", run_id=2)], before=B)
        check(base == A and not warns, f"2b. a failed run is not a base: expected A, got {str(base)[:9]}")
        print(f"  2. cancelled between two successes     → {'C' if pick(runs)[0] == C else '?'}")

        # 3. The API failing: the previous behaviour, with a warning that says why.
        def boom():
            raise cvb.APIError("HTTPError: HTTP Error 500")
        base, warns, _ = cvb.resolve(repo, "push", C, "", "main", boom)
        check(base == C, f"3. API failure: expected the push's before C, got {str(base)[:9]}")
        check(len(warns) == 1 and "could not be read" in warns[0] and "HTTP Error 500" in warns[0],
              f"3. API failure is not loud, or does not say why: {warns}")
        base, warns, _ = cvb.resolve(repo, "push", C, "", "main", lambda: (_ for _ in ()).throw(ValueError("x")))
        check(base == C and warns, "3b. a loader raising something other than APIError is not a fallback")

        # 4. No success ever, in every way a run can fail to count.
        never = [run(D, status="in_progress", conclusion=None), run(C, "cancelled"), run(B, "failure"),
                 run(B, "success", event="pull_request"), run(A, "success", branch="feature"),
                 run(A, "skipped"), run(A, "success", status="queued")]
        base, warns, _ = pick(never)
        check(base == C and len(warns) == 1 and "no successful gates run" in warns[0],
              f"4. no success ever: expected before C with one warning, got {str(base)[:9]} {warns}")
        base, warns, _ = pick([], before=cvb.ZERO_SHA)
        check(base == C and warns, f"4b. first push, no runs: expected HEAD~1 (C), got {str(base)[:9]}")
        base, warns, _ = pick([], before="")
        check(base == C and warns, f"4c. empty before, no runs: expected HEAD~1 (C), got {str(base)[:9]}")

        # 5. Successful heads that cannot be a base.
        base, warns, log = pick([run(X, run_id=5), run(A, run_id=1)])
        check(base == A and not warns, f"5. a non-ancestor success: expected A behind it, got {str(base)[:9]}")
        check(any("not an ancestor" in line for line in log), f"5. X was not reported as passed over: {log}")
        base, warns, _ = pick([run(X)])
        check(base == C and warns, f"5b. only a non-ancestor success: expected the loud fallback, got {str(base)[:9]}")
        base, warns, log = pick([run("f" * 40), run(D, run_id=7), run(B, run_id=2)])
        check(base == B and any("not a commit" in line for line in log) and any("HEAD itself" in line for line in log),
              f"5c. a missing sha and HEAD itself: expected B, got {str(base)[:9]} {log}")

        # 6. A pull request is compared against its base and never asks the API.
        called = []
        base, warns, _ = cvb.resolve(repo, "pull_request", "", A, "main", lambda: called.append(1) or [])
        check(base == A and not warns and not called, f"6. pull_request: expected A and no API call, got {base} {called}")

        # workflow_dispatch chains too (its before is empty).
        base, warns, _ = pick([run(B, event="workflow_dispatch")], before="", event="workflow_dispatch")
        check(base == B and not warns, f"6b. workflow_dispatch: expected B, got {str(base)[:9]}")

        # 7. End to end, against a local server: the request, the token, the output, the warning.
        srv = Server(200, {"total_count": 3, "workflow_runs": [run(C, "cancelled"), run(B), run(A)]})
        try:
            rc, out, gho = cli(repo, srv.url, "--event", "push", "--before", C)
            check(rc == 0 and gho == f"base={B}\n", f"7. CLI: expected base={B[:9]} in GITHUB_OUTPUT, rc={rc} {gho!r}\n{out}")
            check(TOKEN not in out, "7. the token was printed")
            check(len(srv.requests) == 1, f"7. expected one API request, got {len(srv.requests)}")
            if srv.requests:
                path, headers = srv.requests[0]
                check(path.startswith("/repos/owner/repo/actions/workflows/gates.yml/runs?")
                      and "branch=main" in path and "status=success" in path,
                      f"7. the request was {path}")
                check(headers.get("Authorization") == f"Bearer {TOKEN}", "7. the token was not sent as a bearer token")
            check("::warning" not in out, f"7. a clean selection printed a warning:\n{out}")
        finally:
            srv.close()
        print(f"  7. CLI, local API                      → {gho.strip()[:17]}…")

        for label, url in (("HTTP 500", None), ("malformed body", None), ("connection refused", closed_port_url())):
            srv = None
            if url is None:
                srv = Server(500, {"message": "boom"}) if label == "HTTP 500" else Server(200, b"[1, 2]")
                url = srv.url
            try:
                rc, out, gho = cli(repo, url, "--event", "push", "--before", C)
                check(rc == 0 and gho == f"base={C}\n", f"8. {label}: expected the fallback base={C[:9]}, rc={rc} {gho!r}\n{out}")
                check("::warning title=vocabulary base fallback::" in out and "FALLBACK:" in out,
                      f"8. {label}: the fallback is not loud:\n{out}")
                check(TOKEN not in out, f"8. {label}: the token was printed")
            finally:
                if srv:
                    srv.close()
            print(f"  8. CLI, {label:<18}            → fallback, warned")

        srv = Server(200, {"workflow_runs": []})
        try:
            rc, out, gho = cli(repo, srv.url, "--event", "push", "--before", "e" * 40)
            check(rc == 1 and gho == "" and "::error::" in out,
                  f"9. a base that is not a commit must fail the step: rc={rc} {gho!r}\n{out}")
        finally:
            srv.close()

    # 10. The workflow's wiring.
    wf = WORKFLOW.read_text()
    step = re.search(r"- name: Resolve the vocabulary comparison base\n(.*?)(?=\n      - name: |\Z)", wf, re.S)
    if check(step is not None, "10. gates.yml has no 'Resolve the vocabulary comparison base' step"):
        body = step.group(1)
        check("id: base" in body, "10. the step lost id: base")
        check("python3 scripts/ci_vocab_base.py" in body, "10. the step does not call scripts/ci_vocab_base.py")
        check(f"--workflow {WORKFLOW.name}" in body, f"10. the step does not pass its own file name ({WORKFLOW.name})")
        check("GITHUB_TOKEN: ${{ github.token }}" in body, "10. the step does not hand the script the job's token")
        for flag, expr in (("--event", "github.event_name"), ("--before", "github.event.before"),
                           ("--pr-base", "github.event.pull_request.base.sha"), ("--branch", "github.ref_name")):
            var = re.search(rf"(\w+): \$\{{\{{ {re.escape(expr)} \}}\}}", body)
            check(var is not None and f'{flag} "${var.group(1)}"' in body,
                  f"10. {flag} is not passed from {expr} through the environment")
        check("run:" in body and "${{" not in body.split("run:", 1)[1],
              "10. the run script interpolates ${{ }} directly (pass it through env)")
    check('--vocab-base "${{ steps.base.outputs.base }}"' in wf, "10. the gates do not take the step's base")
    check(re.search(r"^permissions:\n  contents: read\n  actions: read\n(?!  )", wf, re.M) is not None,
          "10. the workflow's token is not exactly contents: read + actions: read")
    check(wf.count("permissions:") == 1, "10. a job widens the token's permissions")
    check("fetch-depth: 0" in wf, "10. the clone is no longer full-depth; a base may not be fetched")
    uses = sorted(set(re.findall(r"uses: (\S+)", wf)))
    check(uses == ["actions/checkout@v4", "actions/upload-artifact@v4"], f"10. the actions used changed: {uses}")
    check("cancel-in-progress: true" in wf,
          "10. cancel-in-progress is gone; re-read whether this script is still the fix it claims to be")

    print()
    if failures:
        print(f"FAILED: {len(failures)} check(s)")
        return 1
    print("ok — the base is the newest successful run's head; every fallback is loud")
    return 0


if __name__ == "__main__":
    sys.exit(main())
