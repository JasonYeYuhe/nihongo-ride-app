#!/usr/bin/env python3
"""Nihongo Ride — the reader for the one Stage 1 guardrail that has anything behind it.

WHY THIS EXISTS (PLAN-STAGE1 §K, PLAN-V1.34 §C2)
-------------------------------------------------
§K: "Any new store review mentioning the purchase negatively is a stop-and-fix, regardless of
units. At one lifetime review, n=1 is a real signal here and it costs nothing to watch." Until
2026-09-25 nothing in `scripts/` read reviews, so the guardrail was watched by nobody. This tool
is that watch: a read-only App Store Connect GET of the app's customer reviews, printed in full.

WHAT IT PRINTS, AND WHY THERE IS NO HIGH-WATER MARK
---------------------------------------------------
Every run prints EVERY review whose Pacific day is on or after §K's day 0 (2026-09-09): rating,
territory, date, title and body verbatim. There is no "new since last time" and no cache file,
because a high-water mark is a place a review can hide — a run that crashed after advancing it
would never show that review again. The cost is re-reading a handful of lines each run; the
guardrail's subject is a review count in single digits.

It also prints the count of reviews BEFORE day 0 and the lifetime total, so a reader can tell
"none since day 0" from "none at all" — the app has one lifetime review (2026-07-10, CHN), and a
run that printed only "0 since day 0" would look identical for an app the API had never heard of.

"Since day 0" compares the review's `createdDate` converted to its America/Los_Angeles calendar
day — the Pacific report day `sales_report.py` uses for the sales cohort — against 2026-09-09.
So a review and a purchase on the same clock land on the same side of day 0. The API returns
`createdDate` with an explicit offset (measured 2026-09-25: `-07:00`), so no guess is involved.

THE FLAG
--------
A review whose title or body contains purchase vocabulary is printed LOUDLY, in en, zh and ja:
Latin terms (purchase, purchased, paid, pay, refund, in-app) match case-insensitively at a word
start — "Refunded" and "PAID" match, "display" does not (it contains "pay" but not at a word
start); CJK terms (购买, 付费, 退款, 内购, 購入, 課金, 返金) match as substrings. The flag is a
prompt for a PERSON to read the review against §K's sentence — "negatively" is a human reading;
this tool decides nothing. The lifetime review's body contains 付费 and is a real-data control
for the flagger (`scripts/test_review_watch.py`).

EXIT CODES
----------
    0  the read succeeded. Flags are printed, not encoded: a flagged review exits 0, and the exit
       code is about whether the reviews could be READ, not about what they said.
    2  HARNESS ERROR: the key could not be loaded (asc_api.sh exit 2), asc_api.sh failed, the
       body was empty, non-JSON or carried `errors`, a paging link pointed off the API, or a
       review lacked a field this tool prints. NEVER 0 for reviews it could not read: a run that
       cannot read prints no "since day 0" count at all, so "0 since day 0" is only ever printed
       by a run that read the endpoint.

WHAT IT NEVER DOES (and `scripts/test_review_watch.py` scans this file to keep it that way)
-------------------------------------------------------------------------------------------
It sends nothing but GET to App Store Connect, through `scripts/asc_api.sh GET` and through one
guarded runner (`_run_get`) that refuses any other argv. It writes no cache and no file, with one
opt-in exception: `--json PATH` dumps the raw pages and the parsed reviews to the path the caller
names, in `_dump_json`, the only writer in the file. It never purchases, never signs anything in
or out, never runs the app.

NOT A GATE
----------
`run_all_gates.sh` runs "everything that runs without a device, an account or a signature", and
CI has no ASC key, so the LIVE read is not in it — its fixture self-test is. The live read is a
command run on every release day and every checkpoint day, and its output is pasted verbatim into
the checkpoint entry (`docs/measurements/stage1-checkpoints.md`).

CAVEAT THE OUTPUT REPEATS
-------------------------
The endpoint shows the reviews visible to the App Store Connect API. It may lag the storefronts,
and a review a storefront shows may not be here yet; the reverse — a review here that no
storefront shows — has not been observed but is not excluded by anything Apple documents.

    python3 scripts/review_watch.py            # print-only, exit 0 or 2
    python3 scripts/review_watch.py --json P   # …and dump the pages + parsed reviews to P
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional
from zoneinfo import ZoneInfo

REPO = Path(__file__).resolve().parent.parent
ASC_API = REPO / "scripts" / "asc_api.sh"
ASC_BASE = "https://api.appstoreconnect.apple.com"
BASH = "/bin/bash"

APP_ID = "6777469778"
# `sort=createdDate` is one of the four sort keys the endpoint documents (createdDate, -createdDate,
# rating, -rating); the listing is re-sorted locally anyway, so the parameter only makes paging
# deterministic across a run.
ENDPOINT = f"/v1/apps/{APP_ID}/customerReviews?limit=200&sort=createdDate"
# §K's day 0 — the same constant sales_report.py carries as DAY0.
DAY0 = dt.date(2026, 9, 9)
PACIFIC = ZoneInfo("America/Los_Angeles")

LATIN_TERMS = ("purchase", "purchased", "paid", "pay", "refund", "in-app")
CJK_TERMS = ("购买", "付费", "退款", "内购", "購入", "課金", "返金")
_LATIN_RE = re.compile(r"(?<![A-Za-z])(" + "|".join(re.escape(t) for t in LATIN_TERMS) + r")",
                       re.IGNORECASE)

EXIT_OK = 0
EXIT_HARNESS = 2


class HarnessError(Exception):
    """The reviews could not be read. Exit 2, never a count."""


# =============================================================================================
# The one runner, and the GET helpers (the shape of stage1_walk.py's, kept local so this file
# is scanned on its own)
# =============================================================================================

@dataclass
class Completed:
    argv: List[str]
    returncode: Optional[int]
    stdout: str
    stderr: str
    error: str = ""


def _assert_get_argv(argv: List[str]) -> None:
    """Refuse anything that is not `bash scripts/asc_api.sh GET /v…`."""
    ok = (len(argv) == 4 and argv[0] == BASH and argv[1] == str(ASC_API) and argv[2] == "GET"
          and argv[3].startswith("/v"))
    if not ok:
        raise HarnessError(f"refusing to run a command that is not a GET through asc_api.sh: "
                           f"{argv!r}")


def _run_get(argv: List[str], timeout: float) -> Completed:
    argv = [str(a) for a in argv]
    _assert_get_argv(argv)
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=timeout, cwd=str(REPO),
                              stdin=subprocess.DEVNULL)
    except FileNotFoundError as exc:
        return Completed(argv, None, "", "", f"not found: {exc}")
    except subprocess.TimeoutExpired:
        return Completed(argv, None, "", "", f"timed out after {timeout:.0f}s")
    return Completed(argv, proc.returncode, proc.stdout or "", proc.stderr or "")


def asc_get(endpoint: str, run: Callable[..., Completed]) -> dict:
    """One GET. A non-zero exit, an empty body, non-JSON or an `errors` payload is a failure."""
    r = run([BASH, str(ASC_API), "GET", endpoint], timeout=120)
    if r.returncode != 0:
        raise HarnessError(f"GET {endpoint}: asc_api.sh exit {r.returncode} {r.error} "
                           f"{r.stderr.strip()[:300]}".strip())
    if not r.stdout.strip():
        raise HarnessError(f"GET {endpoint}: empty body")
    try:
        payload = json.loads(r.stdout)
    except ValueError:
        raise HarnessError(f"GET {endpoint}: non-JSON body {r.stdout[:200]!r}")
    if not isinstance(payload, dict):
        raise HarnessError(f"GET {endpoint}: body is not a JSON object")
    if payload.get("errors"):
        first = payload["errors"][0] if isinstance(payload["errors"], list) else payload["errors"]
        raise HarnessError(f"GET {endpoint}: {json.dumps(first)[:300]}")
    return payload


def asc_get_all(endpoint: str, get: Callable[[str], dict]) -> List[dict]:
    """Every page's `data`, following `links.next` while it stays on the API's own host."""
    pages: List[dict] = []
    current: Optional[str] = endpoint
    while current:
        payload = get(current)
        if not isinstance(payload.get("data"), list):
            raise HarnessError(f"GET {current}: `data` is not a list")
        pages.append(payload)
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        if not str(nxt).startswith(ASC_BASE) or len(pages) >= 20:
            raise HarnessError(f"GET {current}: unexpected paging link {nxt!r} after "
                               f"{len(pages)} pages")
        current = str(nxt)[len(ASC_BASE):]
    return pages


# =============================================================================================
# Parsing and classification
# =============================================================================================

def parse_iso(text: str) -> dt.datetime:
    """ISO-8601 with an explicit offset or Z. A naive stamp is refused: without an offset the
    Pacific day is a guess, and a guess can move a review across day 0."""
    s = str(text).strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?([+-]\d\d:\d\d)$", s)
    if not m:
        raise ValueError(f"not an ISO-8601 timestamp with an offset: {text!r}")
    base, frac, offset = m.groups()
    digits = ((frac or ".")[1:] + "000000")[:6]
    return dt.datetime.fromisoformat(f"{base}.{digits}{offset}")


def pacific_day(stamp: dt.datetime) -> dt.date:
    """The America/Los_Angeles calendar day — the day sales_report.py files a purchase under."""
    return stamp.astimezone(PACIFIC).date()


def purchase_terms(text: str) -> List[str]:
    """The purchase vocabulary found in `text`, in a stable order, each term once."""
    found: List[str] = []
    for m in _LATIN_RE.finditer(text or ""):
        term = m.group(1).lower()
        if term not in found:
            found.append(term)
    for term in CJK_TERMS:
        if term in (text or "") and term not in found:
            found.append(term)
    return found


@dataclass
class Review:
    id: str
    rating: int
    title: str
    body: str
    nickname: str
    created: dt.datetime
    created_text: str
    territory: str
    flags: List[str] = field(default_factory=list)

    @property
    def day_pt(self) -> dt.date:
        return pacific_day(self.created)

    @property
    def since_day0(self) -> bool:
        return self.day_pt >= DAY0


def parse_reviews(pages: List[dict]) -> List[Review]:
    """Every `data` item of every page as a Review. A review missing a field this tool prints
    is a harness error, never a silently shorter list."""
    reviews: List[Review] = []
    for page in pages:
        for item in page["data"]:
            if not isinstance(item, dict) or item.get("type") != "customerReviews":
                raise HarnessError(f"unexpected item in `data`: {json.dumps(item)[:200]}")
            attrs = item.get("attributes")
            if not isinstance(attrs, dict):
                raise HarnessError(f"review {item.get('id')!r} has no attributes")
            rid = item.get("id")
            if not isinstance(rid, str) or not rid:
                raise HarnessError("a review has no id")
            created_text = attrs.get("createdDate")
            try:
                created = parse_iso(created_text)
            except (TypeError, ValueError) as exc:
                raise HarnessError(f"review {rid}: createdDate unreadable: {exc}")
            rating = attrs.get("rating")
            if not isinstance(rating, int) or isinstance(rating, bool) or not 1 <= rating <= 5:
                raise HarnessError(f"review {rid}: rating is {rating!r}, not 1–5")
            territory = attrs.get("territory")
            if not isinstance(territory, str) or not territory:
                raise HarnessError(f"review {rid}: territory is {territory!r}")
            title = attrs.get("title", "")
            body = attrs.get("body", "")
            nickname = attrs.get("reviewerNickname", "")
            for name, value in (("title", title), ("body", body), ("reviewerNickname", nickname)):
                if value is not None and not isinstance(value, str):
                    raise HarnessError(f"review {rid}: {name} is not text: {value!r}")
            review = Review(rid, rating, title or "", body or "", nickname or "", created,
                            str(created_text), territory)
            review.flags = purchase_terms(review.title + "\n" + review.body)
            reviews.append(review)
    reviews.sort(key=lambda r: (r.created, r.id))
    return reviews


# =============================================================================================
# Output
# =============================================================================================

CAVEAT = ("NOTE: this endpoint shows the reviews visible to the App Store Connect API. It may lag "
          "the storefronts; a review a storefront shows may not be here yet.")


def _indent(text: str, prefix: str) -> str:
    lines = (text or "").splitlines() or [""]
    return "\n".join(prefix + line for line in lines)


def render(reviews: List[Review], pages: int, now: dt.datetime, out) -> None:
    since = [r for r in reviews if r.since_day0]
    before = [r for r in reviews if not r.since_day0]
    flagged = [r for r in since if r.flags]
    w = out.write
    w(f"review_watch — App Store customer reviews for app {APP_ID} "
      f"(read-only GET via scripts/asc_api.sh)\n")
    w(f"read at {now.astimezone(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} · "
      f"{ENDPOINT} · {pages} page(s)\n")
    w(CAVEAT + "\n")
    w(f"\"since day 0\" = the review's createdDate converted to its America/Los_Angeles calendar "
      f"day (the Pacific report day sales_report.py uses) is on or after {DAY0}.\n")
    w("\n")
    w(f"total reviews (lifetime, as the API shows them): {len(reviews)}\n")
    w(f"before day 0 ({DAY0}): {len(before)}   (counted; not the guardrail's subject)\n")
    w(f"since day 0 ({DAY0}):  {len(since)}   ({len(flagged)} with purchase vocabulary)\n")
    w("\n")
    w(f"REVIEWS SINCE DAY 0 ({DAY0}) — every one, on every run; no high-water mark\n")
    if not since:
        w("  (none visible to the API)\n")
    for i, r in enumerate(since, 1):
        w(f"\n[{i}] {r.day_pt} PT (createdDate {r.created_text}) · rating {r.rating}/5 · "
          f"territory {r.territory} · id {r.id}\n")
        w(f"  nickname: {r.nickname}\n")
        w(f"  title: {r.title}\n")
        w("  body:\n" + _indent(r.body, "    | ") + "\n")
        if r.flags:
            w(f"  ⚠️  PURCHASE VOCABULARY: {', '.join(r.flags)} — §K: \"any new store review "
              f"mentioning the purchase negatively is a stop-and-fix, regardless of units\". "
              f"Whether it is negative is a person's reading; read it now.\n")
    w("\n")
    w(f"BEFORE DAY 0 — counted above, not listed as since day 0; one line each\n")
    if not before:
        w("  (none)\n")
    for r in before:
        vocab = f" · purchase vocabulary: {', '.join(r.flags)}" if r.flags else ""
        w(f"  {r.day_pt} PT · rating {r.rating}/5 · {r.territory} · id {r.id}{vocab}\n")
    w("\n")
    w(f"SUMMARY: since day 0: {len(since)} review(s), {len(flagged)} flagged · "
      f"before day 0: {len(before)} · total {len(reviews)}\n")
    if flagged:
        w(f"⚠️  {len(flagged)} review(s) since day 0 carry purchase vocabulary — printed above, "
          f"exit code unchanged (it reports the READ).\n")


def _dump_json(path: Path, pages: List[dict], reviews: List[Review]) -> None:
    """The only writer: an opt-in dump to the path the caller named."""
    payload = {
        "app_id": APP_ID, "endpoint": ENDPOINT, "day0": DAY0.isoformat(),
        "pages": pages,
        "reviews": [{"id": r.id, "rating": r.rating, "title": r.title, "body": r.body,
                     "nickname": r.nickname, "createdDate": r.created_text,
                     "day_pt": r.day_pt.isoformat(), "territory": r.territory,
                     "since_day0": r.since_day0, "flags": r.flags} for r in reviews],
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=1)
        handle.write("\n")


# =============================================================================================
# Entry point
# =============================================================================================

def main(argv: Optional[List[str]] = None, get: Optional[Callable[[str], dict]] = None,
         out=None, now: Optional[Callable[[], dt.datetime]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", metavar="PATH", default=None,
                        help="also dump the raw pages and parsed reviews to PATH (opt-in; the "
                             "default run writes nothing)")
    args = parser.parse_args(argv)
    out = out if out is not None else sys.stdout
    now = now or (lambda: dt.datetime.now(dt.timezone.utc))
    if get is None:
        def get(endpoint: str) -> dict:
            return asc_get(endpoint, _run_get)
    try:
        pages = asc_get_all(ENDPOINT, get)
        reviews = parse_reviews(pages)
    except HarnessError as exc:
        out.write(f"HARNESS ERROR: {exc}\n")
        out.write("The reviews were NOT read. This is not \"no reviews\" — nothing below this "
                  "line was observed, and exit 2 says so.\n")
        return EXIT_HARNESS
    render(reviews, len(pages), now(), out)
    if args.json:
        _dump_json(Path(args.json), pages, reviews)
        out.write(f"dumped pages and parsed reviews to {args.json}\n")
    out.write(f"exit {EXIT_OK} (the read succeeded)\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
