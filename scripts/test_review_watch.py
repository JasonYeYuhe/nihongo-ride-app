#!/usr/bin/env python3
"""`review_watch.py` must print every review since day 0 that it read, must flag purchase
vocabulary, and must be unable to say "none" about reviews it could not read.

WHY THIS FILE EXISTS. The tool watches PLAN-STAGE1 §K's one guardrail with anything behind it,
and its wrong answers look exactly like right ones: "0 since day 0" from a read that failed, a
review that fell before day 0 because its offset was ignored, a 返金 that no term matched, a
review silently dropped because one field was missing. So every verdict below is tested as a
PAIR — the planted state that must pass and the one-variable change that must not — and the
"none" answer is tested against a broken instrument that must NOT produce it.

WHAT IS PLANTED, AND WHERE IT CAME FROM. Nothing here touches the network, App Store Connect,
the key, or any cache (the tool has none). Pages are dicts shaped like the API's response, and
the positive control for parsing is the app's one lifetime review EXACTLY as
`scripts/asc_api.sh GET /v1/apps/6777469778/customerReviews` returned it on 2026-09-25 — every
attribute, the relationship and the links block included, so the parser is graded against the
real shape, not against a shape this file imagined. That review's title contains 收费 and its
body contains 收费 and 付费, which makes it a real-data control for the flagger as well. The
tool's GET layer is exercised through an injected getter or an injected runner that returns
canned `Completed` results; the two OS-level failures (the runner's subprocess call raising
PermissionError, and an exception the tool never anticipated) are exercised by monkeypatching
the tool's `subprocess.run` and by a getter that raises, and both must end as exit 2 with the
HARNESS ERROR line — the tool has exactly two exit codes, and a source pin checks that `main`
keeps the last-resort handler that makes that true.

THE PRINT-ONLY RUN. "Writes nothing" is tested where a stray write would land: the process is
moved into a fresh temporary cwd with HOME (and `Path.home()`) pointed at a second fresh
temporary directory for the duration of one print-only run, and both must still be empty after
it. A scratch mutation that wrote a cache file into cwd made this line red (recorded in the
commit that added it), so it is a check that can fail, not a certification.

THE NO-SIDE-EFFECTS SCAN. The tool's source is parsed and must contain no network import, no
subprocess use outside its single guarded runner, no file write outside the opt-in `--json`
writer, and no string naming a write verb (`POST`, `PATCH`, `PUT`, `DELETE`) or a store action.
Docstrings are exempt so the tool can say what it never does. The scan is itself controlled:
each rule has a planted violation appended to the real source that must be reported, and a
docstring-only mention that must not.

    python3 scripts/test_review_watch.py
"""
import ast
import copy
import datetime as dt
import importlib.util
import io
import json
import os
import sys
import tempfile
import traceback
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SCRIPT = SCRIPTS / "review_watch.py"


def load():
    spec = importlib.util.spec_from_file_location("review_watch_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


W = load()


class Problems(list):
    def check(self, condition, message):
        if not condition:
            self.append(message)
        return condition


# --- The positive control: the lifetime review as the API returned it on 2026-09-25 --------------
LIVE_REVIEW = {
    "type": "customerReviews",
    "id": "00000193-f7fb-5203-538a-6cdb00000000",
    "attributes": {
        "rating": 5,
        "title": "非常完美怎么收费的找不到路口",
        "body": "怎么收费找不到付费路口希望有一次性",
        "reviewerNickname": "不说你急吗",
        "createdDate": "2026-07-10T08:10:55-07:00",
        "territory": "CHN",
    },
    "relationships": {"response": {"links": {
        "self": "https://api.appstoreconnect.apple.com/v1/customerReviews/"
                "00000193-f7fb-5203-538a-6cdb00000000/relationships/response",
        "related": "https://api.appstoreconnect.apple.com/v1/customerReviews/"
                   "00000193-f7fb-5203-538a-6cdb00000000/response"}}},
    "links": {"self": "https://api.appstoreconnect.apple.com/v1/customerReviews/"
                      "00000193-f7fb-5203-538a-6cdb00000000"},
}
LIVE_SELF = ("https://api.appstoreconnect.apple.com/v1/apps/6777469778/customerReviews"
             "?sort=createdDate&limit=200")
FIXED_NOW = dt.datetime(2026, 9, 25, 12, 0, tzinfo=dt.timezone.utc)


def review(rid, created, title="Good app", body="Fun way to practise", rating=5, territory="JPN",
           nickname="rider"):
    """A review in the live shape, differing from LIVE_REVIEW only where the caller says."""
    item = copy.deepcopy(LIVE_REVIEW)
    item["id"] = rid
    item["attributes"] = {"rating": rating, "title": title, "body": body,
                          "reviewerNickname": nickname, "createdDate": created,
                          "territory": territory}
    return item


def page(items, self_link=LIVE_SELF, nxt=None, total=None):
    links = {"self": self_link}
    if nxt:
        links["next"] = nxt
    return {"data": items, "links": links,
            "meta": {"paging": {"total": len(items) if total is None else total, "limit": 200}}}


def getter(*pages_by_endpoint, first=None):
    """An injected `get`: the tool's own first endpoint returns `first`; later calls are looked
    up by the endpoint the tool derived from `links.next`. Keyed on the endpoint, not the call
    count, so one getter serves several runs (the no-high-water-mark pair runs twice)."""
    table = dict(pages_by_endpoint)
    calls = []

    def get(endpoint):
        calls.append(endpoint)
        if endpoint == W.ENDPOINT and first is not None:
            return first
        if endpoint not in table:
            raise W.HarnessError(f"test getter has no page for {endpoint!r}")
        return table[endpoint]
    get.calls = calls
    return get


def run_main(get, argv=()):
    out = io.StringIO()
    code = W.main(list(argv), get=get, out=out, now=lambda: FIXED_NOW)
    return code, out.getvalue()


def since_section(text):
    """The lines between the SINCE DAY 0 heading and the BEFORE DAY 0 heading."""
    start = text.index("REVIEWS SINCE DAY 0")
    end = text.index("BEFORE DAY 0")
    return text[start:end]


# =================================================================================================
# 1. Parsing the real shape, and the one-field changes that must be harness errors
# =================================================================================================

def test_parse_live_shape(problems):
    print("PARSE — the lifetime review as the API returned it, then one field broken at a time")
    reviews = W.parse_reviews([page([LIVE_REVIEW])])
    problems.check(len(reviews) == 1, f"live review: parsed {len(reviews)} reviews, expected 1")
    r = reviews[0]
    checks = [
        ("id", r.id, "00000193-f7fb-5203-538a-6cdb00000000"),
        ("rating", r.rating, 5),
        ("title", r.title, "非常完美怎么收费的找不到路口"),
        ("body", r.body, "怎么收费找不到付费路口希望有一次性"),
        ("nickname", r.nickname, "不说你急吗"),
        ("territory", r.territory, "CHN"),
        ("createdDate text", r.created_text, "2026-07-10T08:10:55-07:00"),
        ("created", r.created, dt.datetime(2026, 7, 10, 8, 10, 55,
                                           tzinfo=dt.timezone(dt.timedelta(hours=-7)))),
        ("day_pt", r.day_pt, dt.date(2026, 7, 10)),
        ("since_day0", r.since_day0, False),
        ("flags", r.flags, ["付费", "收费"]),
    ]
    for label, got, want in checks:
        problems.check(got == want, f"live review: {label} = {got!r}, expected {want!r}")
        print(f"  {label:<16} {got!r}")

    # Each broken field is a harness error, never a shorter list.
    def broken(mutate):
        item = copy.deepcopy(LIVE_REVIEW)
        mutate(item)
        return item
    breaks = [
        ("no attributes", lambda i: i.pop("attributes")),
        ("no createdDate", lambda i: i["attributes"].pop("createdDate")),
        ("naive createdDate", lambda i: i["attributes"].__setitem__(
            "createdDate", "2026-07-10T08:10:55")),
        ("createdDate not a date", lambda i: i["attributes"].__setitem__("createdDate", "soon")),
        ("rating 0", lambda i: i["attributes"].__setitem__("rating", 0)),
        ("rating '5'", lambda i: i["attributes"].__setitem__("rating", "5")),
        ("rating true", lambda i: i["attributes"].__setitem__("rating", True)),
        ("no territory", lambda i: i["attributes"].pop("territory")),
        ("body not text", lambda i: i["attributes"].__setitem__("body", ["x"])),
        ("no id", lambda i: i.pop("id")),
        ("wrong type", lambda i: i.__setitem__("type", "apps")),
    ]
    for label, mutate in breaks:
        try:
            W.parse_reviews([page([broken(mutate)])])
            raised = False
        except W.HarnessError:
            raised = True
        problems.check(raised, f"parse [{label}]: did not raise HarnessError")
        print(f"  {label:<24} → {'HarnessError' if raised else 'PARSED (must not)'}")
    # …and `data` that is not a list is a harness error at the paging layer.
    try:
        W.asc_get_all("/v1/x", lambda e: {"data": {"id": "x"}})
        raised = False
    except W.HarnessError:
        raised = True
    problems.check(raised, "asc_get_all: `data` as an object was accepted")
    print(f"  {'data not a list':<24} → {'HarnessError' if raised else 'ACCEPTED (must not)'}")
    # A missing title or body is tolerated as empty text (Apple requires both, but a partial
    # record must not stop the read of the others); it must still parse, not vanish.
    partial = broken(lambda i: (i["attributes"].pop("title"), i["attributes"].pop("body")))
    got = W.parse_reviews([page([partial])])
    problems.check(len(got) == 1 and got[0].title == "" and got[0].body == "",
                   f"parse [no title/body]: expected one review with empty text, got {got}")
    print(f"  {'no title/body':<24} → parsed with empty text")


# =================================================================================================
# 2. The flag, en / zh / ja, each against its clean twin
# =================================================================================================

def test_flags(problems):
    print("FLAG — each purchase term is found; each clean twin is not; the word-start rule")
    pairs = [
        # (text, expected terms)
        ("我已经购买了", ["购买", "买"]),      # 买 sits inside 购买: substrings are substrings
        ("返金してほしい", ["返金"]),
        ("I want a refund", ["refund"]),
        ("REFUNDED without asking", ["refund"]),
        ("Purchased the scenery, worth it", ["purchased"]),
        ("purchases are confusing", ["purchase"]),
        ("I paid and nothing happened", ["paid"]),
        ("Why should I pay for this", ["pay"]),
        ("the in-app offer is confusing", ["in-app"]),
        ("the in‐app offer", ["in‐app"]),          # U+2010 HYPHEN
        ("the in‑app offer", ["in‑app"]),          # U+2011 NON-BREAKING HYPHEN
        ("bought it, nothing unlocked", ["bought"]),
        ("do not buy", ["buy"]),
        ("charged twice", ["charged"]),
        ("a charge I did not expect", ["charge"]),
        ("price too high", ["price"]),
        ("the cost is absurd", ["cost"]),
        ("the IAP failed", ["iap"]),
        ("付费入口在哪里", ["付费"]),
        ("退款", ["退款"]),
        ("内购太贵", ["内购"]),
        ("購入しました", ["購入"]),
        ("課金要素あり", ["課金"]),
        ("收费太贵", ["收费"]),
        ("买了没解锁", ["买", "解锁"]),
        ("有料版を買った", ["買", "有料"]),
        ("支払いました", ["支払"]),
        ("料金が高い", ["料金"]),
        (LIVE_REVIEW["attributes"]["title"], ["收费"]),                 # real data: the title
        (LIVE_REVIEW["attributes"]["body"], ["付费", "收费"]),           # real data: the body
        ("Refund and 退款 both", ["refund", "退款"]),
        # clean twins
        ("Great app, love the road", []),
        ("很好用,每天都在骑", []),
        ("楽しいです", []),
        ("repayment plan", []),                # "pay" inside a word, not at a word start: clean
        ("unpaid version", []),                # "paid" inside "unpaid": clean by decision (header)
        ("prepaid card", []),                  # "paid" inside "prepaid": clean by decision (header)
        ("the display is crisp", []),          # plain clean text ("display" holds no term at all)
        ("discharge the battery", []),         # "charge" inside a word: clean
        ("", []),
    ]
    for text, expected in pairs:
        got = W.purchase_terms(text)
        problems.check(got == expected, f"purchase_terms({text!r}) = {got}, expected {expected}")
        print(f"  {text[:34]!r:<38} → {got if got else 'clean'}")
    # No Latin term is dead in the alternation: each one, placed in a sentence, is the term the
    # tool reports. (With "purchase" listed before "purchased", the latter could never be reported.)
    for term in W.LATIN_TERMS:
        got = W.purchase_terms(f"well, {term} then")
        problems.check(got == [term], f"LATIN term {term!r} is dead: purchase_terms reported {got}")
    problems.check(len(set(W.LATIN_TERMS)) == len(W.LATIN_TERMS), "LATIN_TERMS lists a term twice")
    problems.check(len(set(W.CJK_TERMS)) == len(W.CJK_TERMS), "CJK_TERMS lists a term twice")
    for term in W.CJK_TERMS:
        got = W.purchase_terms(f"很好{term}了")
        problems.check(term in got, f"CJK term {term!r} not reported for text containing it: {got}")
    print(f"  every one of {len(W.LATIN_TERMS)} Latin terms is reportable (none dead) · "
          f"every one of {len(W.CJK_TERMS)} CJK terms found")
    for must in ("收费", "买", "買", "有料", "料金", "支払", "解锁",
                 "购买", "付费", "退款", "内购", "購入", "課金", "返金"):
        problems.check(must in W.CJK_TERMS, f"CJK_TERMS lost {must!r}")
    for must in ("purchase", "purchased", "paid", "pay", "refund", "in-app", "buy", "bought",
                 "charge", "charged", "price", "cost", "iap", "in‐app", "in‑app"):
        problems.check(must in W.LATIN_TERMS, f"LATIN_TERMS lost {must!r}")
    # Title alone must flag: the vocabulary may be in either field.
    only_title = W.parse_reviews([page([review("t", "2026-09-10T08:00:00-07:00",
                                                title="退款", body="ok")])])[0]
    only_body = W.parse_reviews([page([review("b", "2026-09-10T08:00:00-07:00",
                                               title="ok", body="退款")])])[0]
    neither = W.parse_reviews([page([review("n", "2026-09-10T08:00:00-07:00",
                                             title="ok", body="ok")])])[0]
    problems.check(only_title.flags == ["退款"], f"title-only vocabulary not flagged: {only_title}")
    problems.check(only_body.flags == ["退款"], f"body-only vocabulary not flagged: {only_body}")
    problems.check(neither.flags == [], f"clean review flagged: {neither}")
    print(f"  title-only → {only_title.flags} · body-only → {only_body.flags} · "
          f"neither → {neither.flags or 'clean'}")


# =================================================================================================
# 3. The printed report: since / before day 0, verbatim text, the loud flag, no high-water mark
# =================================================================================================

def test_report(problems):
    print("REPORT — since day 0 listed verbatim, before day 0 counted, the flag printed loudly")
    since_clean = review("s1", "2026-09-12T10:00:00-07:00", title="Nice road",
                         body="Line one\nLine two — verbatim")
    since_flag = review("s2", "2026-09-20T23:30:00+09:00", title="退款", body="I want a refund",
                        rating=1, territory="JPN")
    code, text = run_main(getter(first=page([LIVE_REVIEW, since_clean, since_flag])))
    problems.check(code == 0, f"report: exit {code}, expected 0")
    expect = [
        "total reviews (lifetime, as the API shows them): 3",
        "before day 0 (2026-09-09): 1",
        "since day 0 (2026-09-09):  2   (1 with purchase vocabulary)",
        "[1] 2026-09-12 PT (createdDate 2026-09-12T10:00:00-07:00) · rating 5/5 · territory JPN · id s1",
        "  title: Nice road",
        "    | Line one\n    | Line two — verbatim",
        "[2] 2026-09-20 PT (createdDate 2026-09-20T23:30:00+09:00) · rating 1/5 · territory JPN · id s2",
        "PURCHASE VOCABULARY: refund, 退款",
        "SUMMARY: since day 0: 2 review(s), 1 flagged · before day 0: 1 · total 3",
        "2026-07-10 PT · rating 5/5 · CHN · id 00000193-f7fb-5203-538a-6cdb00000000 · "
        "purchase vocabulary: 付费, 收费",
        "API meta.paging.total: 3   (equals the 3 collected; a mismatch is exit 2)",
        "may lag the storefronts",
        "America/Los_Angeles",
        "exit 0 (the read succeeded)",
    ]
    for line in expect:
        problems.check(line in text, f"report is missing:\n    {line!r}\n--- got ---\n{text}")
    print(f"  {len(expect)} expected lines present · exit {code}")
    # The lifetime review is before day 0: its body must not appear in the since-day-0 section.
    problems.check(LIVE_REVIEW["attributes"]["body"] not in since_section(text),
                   "a review before day 0 was listed under SINCE DAY 0")
    problems.check("00000193-f7fb-5203-538a-6cdb00000000" not in since_section(text),
                   "a review before day 0 was listed under SINCE DAY 0 (by id)")
    print("  lifetime review (2026-07-10): counted, not listed as since day 0")
    # PAIR: the same review moved past day 0 IS listed, body verbatim.
    moved = copy.deepcopy(LIVE_REVIEW)
    moved["attributes"]["createdDate"] = "2026-09-10T08:10:55-07:00"
    code, text2 = run_main(getter(first=page([moved])))
    problems.check("since day 0 (2026-09-09):  1   (1 with purchase vocabulary)" in text2
                   and "before day 0 (2026-09-09): 0" in text2,
                   f"moved review: counts wrong:\n{text2}")
    problems.check(LIVE_REVIEW["attributes"]["body"] in since_section(text2),
                   "moved review: body not listed verbatim under SINCE DAY 0")
    problems.check("PURCHASE VOCABULARY: 付费, 收费" in since_section(text2),
                   "moved review: 付费 and 收费 not flagged loudly")
    print("  same review moved to 2026-09-10: listed, body verbatim, flagged 付费, 收费")
    # PAIR on the Pacific boundary: 2026-09-09T06:59:59Z is still 2026-09-08 in Los Angeles
    # (PDT, UTC−7); one second later it is day 0. A UTC comparison would put both on day 0.
    edge_before = review("e0", "2026-09-09T06:59:59Z")
    edge_on = review("e1", "2026-09-09T07:00:00Z")
    _, t3 = run_main(getter(first=page([edge_before, edge_on])))
    problems.check("before day 0 (2026-09-09): 1" in t3 and "since day 0 (2026-09-09):  1" in t3,
                   f"Pacific boundary: counts wrong (a UTC comparison would say 0 / 2):\n{t3}")
    problems.check("id e1" in since_section(t3) and "id e0" not in since_section(t3),
                   "Pacific boundary: the wrong review is under SINCE DAY 0")
    print("  06:59:59Z → before day 0 · 07:00:00Z → day 0 (Pacific, not UTC)")
    # "None" is distinguishable from "none at all", and both read as exit 0.
    _, t4 = run_main(getter(first=page([LIVE_REVIEW])))
    _, t5 = run_main(getter(first=page([])))
    problems.check("(none visible to the API)" in t4 and "before day 0 (2026-09-09): 1" in t4
                   and "total reviews (lifetime, as the API shows them): 1" in t4,
                   f"one lifetime review: 'none since day 0' must still show the count:\n{t4}")
    problems.check("(none visible to the API)" in t5 and "before day 0 (2026-09-09): 0" in t5
                   and "total reviews (lifetime, as the API shows them): 0" in t5,
                   f"no reviews at all: totals must read 0:\n{t5}")
    problems.check(t4 != t5, "'none since day 0' and 'none at all' printed the same report")
    print("  'none since day 0' (total 1) ≠ 'none at all' (total 0)")
    # PAIR on the API's own count: equal → exit 0 with the cross-check line; fewer collected than
    # meta.paging.total → exit 2 and no count printed (the API said reviews exist and none were
    # read); the field absent → allowed, and the header says the cross-check did not happen.
    code, t6 = run_main(getter(first=page([LIVE_REVIEW], total=1)))
    problems.check(code == 0 and "API meta.paging.total: 1   (equals the 1 collected" in t6,
                   f"total equal: exit {code}:\n{t6}")
    code, t7 = run_main(getter(first=page([], total=5)))
    problems.check(code == 2 and "HARNESS ERROR" in t7 and "meta.paging.total = 5" in t7,
                   f"total 5, collected 0: exit {code}, expected 2:\n{t7}")
    for forbidden in ("since day 0 (2026-09-09):", "SUMMARY:", "(none visible", "total reviews",
                      "exit 0"):
        problems.check(forbidden not in t7, f"total mismatch printed {forbidden!r}:\n{t7}")
    code, t7b = run_main(getter(first=page([LIVE_REVIEW], total=5)))
    problems.check(code == 2 and "HARNESS ERROR" in t7b and "total reviews" not in t7b,
                   f"total 5, collected 1: exit {code}, expected 2:\n{t7b}")
    code, t7c = run_main(getter(first=page([LIVE_REVIEW], total=0)))
    problems.check(code == 2 and "HARNESS ERROR" in t7c and "total reviews" not in t7c,
                   f"total 0, collected 1: exit {code}, expected 2:\n{t7c}")
    code, t7d = run_main(getter(first=page([LIVE_REVIEW], total="1")))
    problems.check(code == 2 and "HARNESS ERROR" in t7d and "not a whole number" in t7d,
                   f"total '1' (text): exit {code}, expected 2:\n{t7d}")
    no_meta = page([LIVE_REVIEW])
    del no_meta["meta"]
    code, t8 = run_main(getter(first=no_meta))
    problems.check(code == 0 and "API meta.paging.total: not supplied" in t8
                   and "total reviews (lifetime, as the API shows them): 1" in t8,
                   f"total absent: exit {code}, expected 0 with the 'not supplied' line:\n{t8}")
    print("  meta.paging.total: equal → exit 0 · 5 vs 0 collected → exit 2, no count · "
          "5 vs 1 / 0 vs 1 / '1' → exit 2 · absent → exit 0, 'not supplied'")
    # No high-water mark: two runs over the same pages print the same report.
    g = getter(first=page([LIVE_REVIEW, since_clean, since_flag]))
    _, a = run_main(g)
    _, b = run_main(g)
    problems.check(a == b, "two runs over the same pages printed different reports (a high-water "
                           "mark, or non-determinism)")
    print("  two runs, same pages → identical output (no high-water mark)")


# =================================================================================================
# 4. A read that failed exits 2 and prints no count
# =================================================================================================

def test_harness_error(problems):
    print("HARNESS ERROR — a failing read exits 2 and never prints a 'since day 0' count")
    failures = [
        ("key not found (asc_api.sh exit 2)",
         W.Completed([], 2, "", "error: key not found at /nowhere/AuthKey.p8")),
        ("asc_api.sh not found", W.Completed([], None, "", "", "not found: bash")),
        ("timed out", W.Completed([], None, "", "", "timed out after 120s")),
        ("empty body", W.Completed([], 0, "  \n", "")),
        ("non-JSON body", W.Completed([], 0, "<html>502</html>", "")),
        ("errors payload", W.Completed([], 0, '{"errors":[{"status":"401","code":"NOT_AUTHORIZED"}]}', "")),
        ("JSON array body", W.Completed([], 0, "[]", "")),
    ]
    for label, completed in failures:
        seen = []

        def run(argv, timeout, c=completed):
            seen.append(list(argv))
            return c

        def get(endpoint):
            return W.asc_get(endpoint, run)
        code, text = run_main(get)
        problems.check(code == 2, f"[{label}]: exit {code}, expected 2")
        problems.check("HARNESS ERROR" in text, f"[{label}]: no HARNESS ERROR line:\n{text}")
        for forbidden in ("since day 0 (2026-09-09):", "SUMMARY:", "(none visible", "total reviews",
                          "exit 0"):
            problems.check(forbidden not in text,
                           f"[{label}]: a failed read printed {forbidden!r}:\n{text}")
        problems.check(seen == [[W.BASH, str(W.ASC_API), "GET", W.ENDPOINT]],
                       f"[{label}]: the argv the tool built was {seen}")
        print(f"  {label:<36} → exit {code}, no count printed")
    # PAIR: the same path with a good body exits 0 and prints the count.
    good = W.Completed([], 0, json.dumps(page([LIVE_REVIEW]), ensure_ascii=False), "")

    def get_good(endpoint):
        return W.asc_get(endpoint, lambda argv, timeout: good)
    code, text = run_main(get_good)
    problems.check(code == 0 and "since day 0 (2026-09-09):  0" in text
                   and "total reviews (lifetime, as the API shows them): 1" in text,
                   f"good read: exit {code}:\n{text}")
    print(f"  {'good body':<36} → exit {code}, counts printed")
    # A page mid-way that fails must also be exit 2 — not the first page's reviews as a total.
    first = page([LIVE_REVIEW], nxt=W.ASC_BASE + "/v1/apps/6777469778/customerReviews?cursor=B")

    def get_second_fails(endpoint):
        if "cursor=B" in endpoint:
            raise W.HarnessError("GET page 2: asc_api.sh exit 22")
        return first
    code, text = run_main(get_second_fails)
    problems.check(code == 2 and "total reviews" not in text,
                   f"second page failed: exit {code}, must be 2 with no total:\n{text}")
    print(f"  {'second page fails':<36} → exit {code}, no partial total")
    # The two shapes that used to escape as a traceback with exit 1 (review finding, 2026-09-25):
    # `links` that is not an object, and the runner's subprocess call raising an OSError other
    # than FileNotFoundError. Both must be exit 2 with the HARNESS ERROR line and no count.
    forbidden_lines = ("since day 0 (2026-09-09):", "SUMMARY:", "(none visible", "total reviews",
                       "exit 0")
    code, text = run_main(lambda endpoint: {"data": [], "links": ["x"]})
    problems.check(code == 2 and "HARNESS ERROR" in text and "`links` is not an object" in text,
                   f"links as a list: exit {code}, expected 2 with HARNESS ERROR:\n{text}")
    for forbidden in forbidden_lines:
        problems.check(forbidden not in text, f"links as a list printed {forbidden!r}:\n{text}")
    print(f"  {'links is a list':<36} → exit {code}, HARNESS ERROR, no count")

    def raise_permission(*args, **kwargs):
        raise PermissionError(13, "Permission denied", "/bin/bash")
    original_run = W.subprocess.run
    W.subprocess.run = raise_permission
    try:
        code, text = run_main(None)  # get=None → the tool's own asc_get(_run_get) path
    finally:
        W.subprocess.run = original_run
    problems.check(code == 2 and "HARNESS ERROR" in text and "PermissionError" in text,
                   f"runner PermissionError: exit {code}, expected 2 with HARNESS ERROR:\n{text}")
    for forbidden in forbidden_lines:
        problems.check(forbidden not in text, f"runner PermissionError printed {forbidden!r}:\n{text}")
    print(f"  {'subprocess.run → PermissionError':<36} → exit {code}, HARNESS ERROR, no count")
    # The last resort: a failure this tool never anticipated is still exit 2 with the line, and
    # the source pin below keeps main's `except Exception` handler in place.

    def get_explodes(endpoint):
        raise RuntimeError("something nobody planned for")
    code, text = run_main(get_explodes)
    problems.check(code == 2 and "HARNESS ERROR: unexpected RuntimeError" in text
                   and "something nobody planned for" in text,
                   f"unanticipated exception: exit {code}, expected 2 with HARNESS ERROR:\n{text}")
    for forbidden in forbidden_lines:
        problems.check(forbidden not in text, f"unanticipated exception printed {forbidden!r}:\n{text}")
    print(f"  {'getter raises RuntimeError':<36} → exit {code}, HARNESS ERROR, no count")
    tree = ast.parse(SCRIPT.read_text(encoding="utf-8"))
    mains = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "main"]
    last_resort = [
        h for m in mains for n in ast.walk(m) if isinstance(n, ast.Try) for h in n.handlers
        if isinstance(h.type, ast.Name) and h.type.id == "Exception"
        and any(isinstance(r, ast.Return) and isinstance(r.value, ast.Name)
                and r.value.id == "EXIT_HARNESS" for r in ast.walk(h))
    ]
    problems.check(len(mains) == 1 and len(last_resort) == 1,
                   "source pin: main must have exactly one `except Exception` handler that "
                   f"returns EXIT_HARNESS (found {len(last_resort)} in {len(mains)} main(s))")
    print("  source pin: main keeps its last-resort `except Exception` → EXIT_HARNESS")
    # The runner guard: anything but a GET through asc_api.sh is refused before it runs.
    for argv in ([W.BASH, str(W.ASC_API), "POST", "/v1/x"],
                 [W.BASH, str(W.ASC_API), "GET", "https://elsewhere/v1/x"],
                 [W.BASH, str(W.ASC_API), "GET", "/v1/x", "extra"],
                 ["/usr/bin/curl", "https://api.appstoreconnect.apple.com/v1/x"],
                 [W.BASH, "/tmp/other.sh", "GET", "/v1/x"]):
        try:
            W._assert_get_argv([str(a) for a in argv])
            refused = False
        except W.HarnessError:
            refused = True
        problems.check(refused, f"runner guard accepted {argv}")
    try:
        W._assert_get_argv([W.BASH, str(W.ASC_API), "GET", "/v1/apps/x"])
        accepted = True
    except W.HarnessError:
        accepted = False
    problems.check(accepted, "runner guard refused a plain GET")
    print("  runner guard: 5 non-GET argvs refused · the GET accepted")


# =================================================================================================
# 5. Paging, and the opt-in --json dump as the only write
# =================================================================================================

def test_paging_and_json(problems):
    print("PAGING — links.next is followed on the API host only; --json writes one file, opt-in")
    second_url = W.ASC_BASE + "/v1/apps/6777469778/customerReviews?cursor=AQ&limit=200"
    p1 = page([LIVE_REVIEW], nxt=second_url, total=2)
    p2 = page([review("p2", "2026-09-15T09:00:00-07:00")], total=2)
    g = getter(("/v1/apps/6777469778/customerReviews?cursor=AQ&limit=200", p2), first=p1)
    code, text = run_main(g)
    problems.check(code == 0 and "total reviews (lifetime, as the API shows them): 2" in text
                   and "· 2 page(s)" in text and "id p2" in since_section(text),
                   f"two pages: exit {code}:\n{text}")
    problems.check(g.calls == [W.ENDPOINT, "/v1/apps/6777469778/customerReviews?cursor=AQ&limit=200"],
                   f"two pages: endpoints requested were {g.calls}")
    print(f"  two pages → 2 reviews, endpoints {g.calls}")
    # PAIR: a next link off the API host is a harness error, not a request.
    off = page([LIVE_REVIEW], nxt="https://example.com/v1/apps/6777469778/customerReviews?cursor=X")
    code, text = run_main(getter(first=off))
    problems.check(code == 2 and "unexpected paging link" in text,
                   f"off-host next link: exit {code}:\n{text}")
    print(f"  off-host next link → exit {code}")
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / "reviews.json"
        code, text = run_main(getter(first=page([LIVE_REVIEW])), argv=["--json", str(target)])
        problems.check(code == 0 and target.exists(), f"--json: exit {code}, exists {target.exists()}")
        dumped = json.loads(target.read_text(encoding="utf-8"))
        problems.check(dumped.get("pages") == [page([LIVE_REVIEW])]
                       and dumped["reviews"][0]["flags"] == ["付费", "收费"]
                       and dumped["reviews"][0]["since_day0"] is False
                       and dumped["reviews"][0]["day_pt"] == "2026-07-10",
                       f"--json: content wrong: {json.dumps(dumped, ensure_ascii=False)[:400]}")
        problems.check(sorted(p.name for p in Path(tmp).iterdir()) == ["reviews.json"],
                       f"--json wrote more than the named file: {list(Path(tmp).iterdir())}")
        print(f"  --json → {target.name} holds the raw page and the parsed review")
        # PAIR: without --json the same run writes nothing — checked where a stray write would
        # land. The process moves into a fresh cwd and HOME (and Path.home()) points at a second
        # fresh directory for the run; both must still be empty afterwards. (The earlier form of
        # this check watched a directory the tool was never pointed at, so it could not fail; a
        # scratch mutation writing a cache file into cwd turns this one red.)
        cwd_dir = Path(tmp) / "cwd"
        home_dir = Path(tmp) / "home"
        cwd_dir.mkdir()
        home_dir.mkdir()
        saved_cwd = os.getcwd()
        saved_home = os.environ.get("HOME")
        saved_path_home = Path.__dict__["home"]  # the classmethod object itself, not a bound copy
        os.chdir(cwd_dir)
        os.environ["HOME"] = str(home_dir)
        Path.home = classmethod(lambda cls: cls(str(home_dir)))
        try:
            problems.check(Path.cwd() == cwd_dir.resolve() and Path.home() == home_dir,
                           f"print-only setup: cwd {Path.cwd()} home {Path.home()}")
            code, _ = run_main(getter(first=page([LIVE_REVIEW])))
        finally:
            Path.home = saved_path_home
            if saved_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = saved_home
            os.chdir(saved_cwd)
        stray_cwd = sorted(p.name for p in cwd_dir.iterdir())
        stray_home = sorted(p.name for p in home_dir.iterdir())
        problems.check(code == 0, f"print-only run: exit {code}")
        ok_cwd = problems.check(stray_cwd == [], f"a print-only run wrote into cwd: {stray_cwd}")
        ok_home = problems.check(stray_home == [], f"a print-only run wrote into HOME: {stray_home}")
        print(f"  print-only run in a fresh cwd with a fresh HOME → "
              f"{'both still empty' if ok_cwd and ok_home else 'WROTE A FILE (must not)'}")


# =================================================================================================
# 6. The no-side-effects source scan, and the planted violations that prove it fires
# =================================================================================================

FORBIDDEN_IMPORTS = {"urllib", "http", "socket", "ssl", "webbrowser", "requests", "ftplib",
                     "smtplib", "telnetlib", "pty", "ctypes", "objc", "AppKit", "Foundation",
                     "StoreKit", "shutil", "asyncio", "multiprocessing", "os", "tempfile",
                     "plistlib"}
FORBIDDEN_EXACT = {"write", "delete", "import", "rename", "remove", "POST", "PATCH", "PUT",
                   "DELETE", "install", "uninstall", "launch", "open", "/usr/bin/open", "mas",
                   "restore", "signin", "signout", "kill", "killall", "curl", "/usr/bin/curl"}
# ("purchase" is deliberately NOT an exact forbidden string: the tool's vocabulary tuple must
#  hold it. The store actions stay forbidden as substrings below: product.purchase, mas purchase.)
FORBIDDEN_SUBSTRINGS = ("defaults write", "defaults delete", "macappstore:", "itms-apps:",
                        "itms:", "apps.apple.com", "product.purchase", "buyproduct",
                        "sktestsession", "/customerreviewresponses", "reviewsubmissions",
                        "mas purchase", "mas signin")
WRITE_FUNCS = {"_dump_json"}
WRITE_METHODS = {"write_text", "write_bytes", "mkdir", "touch", "unlink", "rmdir", "rename",
                 "symlink_to", "hardlink_to", "chmod", "truncate", "makedirs", "replace"}
DYNAMIC = {"eval", "exec", "compile", "__import__", "getattr", "setattr"}
RUNNER = "_run_get"
GUARD = "_assert_get_argv"


def scan_source(source):
    """Problems in the tool's source, as `rule: detail` strings."""
    tree = ast.parse(source)
    problems = []
    docstrings = set()
    enclosing = {}

    def visit(node, fn):
        body = getattr(node, "body", None)
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) \
                and body and isinstance(body[0], ast.Expr) \
                and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
            docstrings.add(id(body[0].value))
        for child in ast.iter_child_nodes(node):
            inner = child.name if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else fn
            enclosing[id(child)] = inner
            visit(child, inner)
    visit(tree, None)

    def where(node):
        return f"line {getattr(node, 'lineno', '?')} in {enclosing.get(id(node)) or 'module'}"

    for node in ast.walk(tree):
        fn = enclosing.get(id(node))
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name.split(".")[0] in FORBIDDEN_IMPORTS:
                    problems.append(f"import: {alias.name} ({where(node)})")
                if alias.name.split(".")[0] == "subprocess" and alias.asname:
                    problems.append(f"import: {alias.name} as {alias.asname} ({where(node)})")
        elif isinstance(node, ast.ImportFrom):
            root = (node.module or "").split(".")[0]
            if root in FORBIDDEN_IMPORTS or root == "subprocess":
                problems.append(f"import: from {node.module} import … ({where(node)})")
        elif isinstance(node, ast.Name) and node.id == "subprocess" and fn != RUNNER:
            problems.append(f"subprocess-outside-runner: ({where(node)})")
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in DYNAMIC:
                problems.append(f"dynamic: {func.id}() ({where(node)})")
            if isinstance(func, ast.Attribute) and func.attr in WRITE_METHODS \
                    and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-dump: .{func.attr}() ({where(node)})")
            if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name) \
                    and func.value.id == "json" and func.attr == "dump" and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-dump: json.dump ({where(node)})")
            is_open = (isinstance(func, ast.Name) and func.id == "open") or \
                (isinstance(func, ast.Attribute) and func.attr == "open")
            if is_open:
                index = 1 if isinstance(func, ast.Name) else 0
                mode = node.args[index] if len(node.args) > index else next(
                    (k.value for k in node.keywords if k.arg == "mode"), None)
                if mode is None:
                    if fn not in WRITE_FUNCS:
                        pass  # a bare open() reads; the tool reads no file, but it is not a write
                elif not (isinstance(mode, ast.Constant) and isinstance(mode.value, str)):
                    problems.append(f"open-mode-unknown: ({where(node)})")
                elif any(c in mode.value for c in "wax+") and fn not in WRITE_FUNCS:
                    problems.append(f"write-outside-dump: open(mode={mode.value!r}) "
                                    f"({where(node)})")
        if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in docstrings:
            if node.value in FORBIDDEN_EXACT:
                problems.append(f"forbidden-string: {node.value!r} ({where(node)})")
            low = node.value.lower()
            for sub in FORBIDDEN_SUBSTRINGS:
                if sub in low:
                    problems.append(f"forbidden-substring: {sub!r} ({where(node)})")

    runners = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == RUNNER]
    if len(runners) != 1:
        problems.append(f"runner-unguarded: expected exactly one {RUNNER}")
    else:
        guard_lines = [n.lineno for n in ast.walk(runners[0]) if isinstance(n, ast.Call)
                       and isinstance(n.func, ast.Name) and n.func.id == GUARD]
        spawn_lines = [n.lineno for n in ast.walk(runners[0])
                       if isinstance(n, ast.Name) and n.id == "subprocess"]
        if not guard_lines or (spawn_lines and min(guard_lines) > min(spawn_lines)):
            problems.append(f"runner-unguarded: {RUNNER} does not call {GUARD} before subprocess")
    writers = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name in WRITE_FUNCS]
    if len(writers) != len(WRITE_FUNCS):
        problems.append(f"writer-missing: expected exactly {sorted(WRITE_FUNCS)}")
    # The writer may only be reached from main under the --json flag: exactly one call site.
    callers = [enclosing.get(id(n)) for n in ast.walk(tree) if isinstance(n, ast.Call)
               and isinstance(n.func, ast.Name) and n.func.id in WRITE_FUNCS]
    if callers != ["main"]:
        problems.append(f"writer-callers: _dump_json is called from {callers}, expected ['main']")
    return problems


RUNNER_GUARD = "    _assert_get_argv(argv)\n"
PLANTED = [
    ("forbidden-string", 'def _p1():\n    return [BASH, str(ASC_API), "POST", "/v1/x"]\n'),
    ("forbidden-string", 'def _p2():\n    return [BASH, str(ASC_API), "PATCH", "/v1/x"]\n'),
    ("forbidden-string", 'def _p3():\n    return [BASH, str(ASC_API), "DELETE", "/v1/x"]\n'),
    ("forbidden-string", 'def _p4():\n    return ["/usr/bin/curl", "https://x"]\n'),
    ("forbidden-substring", 'def _p5():\n    return "/v1/customerReviewResponses"\n'),
    ("forbidden-substring", 'def _p6():\n    return "macappstore://apps.apple.com/app/id1"\n'),
    ("forbidden-substring", 'def _p7():\n    return "Product.purchase()"\n'),
    ("subprocess-outside-runner", 'def _p8():\n    subprocess.run(["true"])\n'),
    ("import", "import urllib.request\n"),
    ("import", "import os\n"),
    ("import", "import shutil\n"),
    ("import", "def _p9(argv):\n    from subprocess import run\n    return run(argv)\n"),
    ("import", "def _p10(argv):\n    import subprocess as sp\n    return sp.run(argv)\n"),
    ("write-outside-dump", 'def _p11(p):\n    with open(p, "w") as handle:\n'
                           '        handle.write("x")\n'),
    ("write-outside-dump", 'def _p12(p):\n    Path(p).write_text("x")\n'),
    ("write-outside-dump", 'def _p13(p):\n    Path(p).mkdir()\n'),
    ("write-outside-dump", 'def _p14(p, q):\n    Path(p).replace(q)\n'),
    ("write-outside-dump", 'def _p15(p, h):\n    json.dump({}, h)\n'),
    ("dynamic", 'def _p16():\n    return eval("1")\n'),
    ("writer-callers", 'def _p17(p):\n    _dump_json(Path(p), [], [])\n'),
]


def test_source_scan(problems):
    print("SOURCE SCAN — the real tool is clean; every planted violation is reported")
    source = SCRIPT.read_text(encoding="utf-8")
    clean = scan_source(source)
    problems.check(clean == [], "review_watch.py violates the no-side-effects scan:\n  " +
                   "\n  ".join(clean))
    print(f"  review_watch.py: {len(clean)} problem(s)")
    for rule, snippet in PLANTED:
        found = scan_source(source + "\n\n" + snippet)
        fired = [p for p in found if p.startswith(rule + ":")]
        problems.check(fired, f"source scan did NOT fire on a planted {rule} violation:\n{snippet}")
        print(f"  planted {rule:<28} → {'fired' if fired else 'SILENT'}")
    problems.check(source.count(RUNNER_GUARD) == 1,
                   "the runner-guard control is vacuous: the guard line was not found verbatim")
    fired = [p for p in scan_source(source.replace(RUNNER_GUARD, "")) if p.startswith("runner-")]
    problems.check(fired, "source scan did NOT notice _run_get losing its argv check")
    print(f"  removed runner guard{'':<14} → {'fired' if fired else 'SILENT'}")
    prose = ('def _prose():\n    """Never POSTs, never PATCHes, never opens macappstore: links, '
             'never writes a cache."""\n    return None\n')
    quiet = scan_source(source + "\n\n" + prose)
    problems.check(quiet == [], f"source scan fired on a docstring (it would get weakened): {quiet}")
    print(f"  docstring-only mention{'':<12} → {'quiet' if not quiet else 'FIRED'}")


def main():
    problems = Problems()
    for test in (test_parse_live_shape, test_flags, test_report, test_harness_error,
                 test_paging_and_json, test_source_scan):
        try:
            test(problems)
        except Exception as exc:  # a crash is a failure with a name, not the end of the run
            problems.append(f"{test.__name__} CRASHED: {exc!r}\n{traceback.format_exc()}")
        print()
    if problems:
        print(f"FAILED — {len(problems)} problem(s):")
        for p in problems:
            print(f"  ✘ {p}")
        return 1
    print("test_review_watch.py: every pair held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
