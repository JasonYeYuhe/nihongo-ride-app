#!/usr/bin/env python3
"""`acquisition_funnel.py` must count each date once, and must not print zeros for a window it never read.

WHAT IS UNDER TEST. Two defects found on 2026-10-27 (docs/measurements/v137-funnel-post-day0.md §1):
* On the ONGOING request each DAILY instance carries the last 2-3 dates, and the script summed every
  instance, so 94 first-time downloads printed as 184. Each date must now come from one instance.
* `--until` defaulted to 2026-08-24, so any later `--since` printed a clean table of zeros and exit 0.

No network, no `jwt`: `get` is replaced by a fake App Store Connect that serves synthetic reports in
Apple's TSV shape, so the real `report_rows` → `latest_per_date` → `main` path runs. Every expected
number below is counted by hand from the fixture, not computed by the script.

    python3 scripts/test_acquisition_funnel.py
"""
import contextlib
import io
import json
import random
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import acquisition_funnel as af                                # noqa: E402

ENG = "App Store Discovery and Engagement Standard"
DL = "App Downloads Standard"
ENG_COLS = ["Date", "Event", "Territory", "Page Type", "Source Type", "Counts"]
DL_COLS = ["Date", "Download Type", "Territory", "Page Type", "Source Type", "Counts"]


def tsv(cols, rows):
    return ("\t".join(cols) + "\n" + "".join("\t".join(r) + "\n" for r in rows)).encode()


def first(date, terr, n, page="No page", src="App Store search"):
    return [date, "First-time download", terr, page, src, str(n)]


def event(date, ev, terr, n):
    return [date, ev, terr, "Product page", "App Store search", str(n)]


# Three download instances, each carrying the last two dates (the ONGOING shape). Summing them all
# counts 09-21 and 09-22 twice. Correct first-time downloads: 09-20 → 2, 09-21 → 3, 09-22 → 1 = 6.
# The 09-22 instance restates 09-21 as 3 (the 09-21 instance said 3 too: Apple's restatements were
# identical on 2026-10-27). An Auto-update row on 09-21 must not count.
DL_INSTANCES = [
    ("i-dl-0921", "2026-09-21", [first("2026-09-20", "JP", 2), first("2026-09-21", "JP", 3),
                                 ["2026-09-21", "Auto-update", "JP", "", "", "7"]]),
    ("i-dl-0922", "2026-09-22", [first("2026-09-21", "JP", 3), first("2026-09-22", "CN", 1),
                                 ["2026-09-21", "Auto-update", "JP", "", "", "7"]]),
    ("i-dl-0923", "2026-09-23", [first("2026-09-22", "CN", 1)]),
]
# Engagement: three dates per instance. Correct impressions: 09-20 → 10, 09-21 → 20, 09-22 → 40 = 70.
ENG_INSTANCES = [
    ("i-en-0922", "2026-09-22", [event("2026-09-20", "Impression", "JP", 10),
                                 event("2026-09-21", "Impression", "JP", 20),
                                 event("2026-09-22", "Impression", "CN", 40)]),
    ("i-en-0923", "2026-09-23", [event("2026-09-21", "Impression", "JP", 20),
                                 event("2026-09-22", "Impression", "CN", 40),
                                 event("2026-09-22", "Page view", "CN", 5)]),
]


class FakeASC:
    """Serves the four GETs report_rows makes, in the order and shapes the real API uses."""

    def __init__(self, dl=DL_INSTANCES, eng=ENG_INSTANCES):
        self.by_report = {"rep-dl": (DL, DL_COLS, dl), "rep-en": (ENG, ENG_COLS, eng)}

    def __call__(self, url, tok, auth=True):
        if "/reports?" in url:
            return json.dumps({"data": [{"id": rid, "attributes": {"name": name}}
                                        for rid, (name, _, _) in self.by_report.items()]}).encode()
        if url.startswith("/v1/analyticsReports/"):
            rid = url.split("/")[3]
            insts = self.by_report[rid][2]
            return json.dumps({"data": [{"id": iid, "attributes": {"granularity": "DAILY",
                                                                     "processingDate": pd}}
                                        for iid, pd, _ in insts]}).encode()
        if url.startswith("/v1/analyticsReportInstances/"):
            iid = url.split("/")[3]
            return json.dumps({"data": [{"attributes": {"url": f"https://s3.invalid/{iid}"}}]}).encode()
        if url.startswith("https://s3.invalid/"):
            assert not auth, "segment URLs are pre-signed; sending Authorization returns HTTP 400"
            iid = url.rsplit("/", 1)[1]
            for _, cols, insts in self.by_report.values():
                for i, _, rows in insts:
                    if i == iid:
                        return tsv(cols, rows)
        raise AssertionError(f"unexpected GET {url}")


def run_main(argv, fake=None):
    af.get = fake or FakeASC()
    af.token = lambda: "tok"
    out = io.StringIO()
    sys.argv = ["acquisition_funnel.py"] + argv
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        try:
            code = af.main()
        except SystemExit as e:
            code = e.code
    return code, out.getvalue()


FAILS = []


def check(name, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  — {detail}"))
    if not cond:
        FAILS.append(name)


def first_dl(rows):
    return sum(int(r["Counts"]) for r in rows if r.get("Download Type") == "First-time download")


# 1. The pure rule: each date from one instance, the latest processed.
inst = [(pd, iid, [dict(zip(DL_COLS, r)) for r in rows]) for iid, pd, rows in DL_INSTANCES]
merged = af.latest_per_date(inst)
check("each date counted once (6 first-time downloads, not 9)", first_dl(merged) == 6, first_dl(merged))
check("a doubled date comes from the later instance",
      {r["Date"]: r for r in merged if r["Download Type"] == "First-time download"}["2026-09-22"]
      is next(r for r in inst[2][2] if r["Date"] == "2026-09-22"))
random.seed(7)
orders = set()
for _ in range(20):
    shuffled = inst[:]
    random.shuffle(shuffled)
    orders.add(tuple(sorted((r["Date"], r["Counts"], r["Download Type"]) for r in af.latest_per_date(shuffled))))
check("the result does not depend on the order Apple lists instances in", len(orders) == 1, len(orders))
tie = [("2026-09-22", "b", [{"Date": "2026-09-21", "Counts": "3"}]),
       ("2026-09-22", "a", [{"Date": "2026-09-21", "Counts": "4"}])]
picked = {tuple(r["Counts"] for r in af.latest_per_date(t)) for t in (tie, tie[::-1])}
check("a processingDate tie keeps one instance, the same one in either order", picked == {("3",)}, picked)

# 2. End to end through report_rows and main.
code, out = run_main(["--since", "2026-09-20", "--until", "2026-09-22"])
check("main exits 0 on a covered window", code == 0, code)
check("main prints 6 first-time downloads and 70 impressions",
      "impressions 70 · page views 5 · taps 0 · first-time downloads 6" in out, out.splitlines()[:3])

code, out = run_main(["--since", "2026-09-21"])
check("no --until reads through the last covered date",
      code == 0 and "window 2026-09-21 .. 2026-09-22" in out and "first-time downloads 4" in out, out[:200])

code, out = run_main(["--since", "2026-10-01"])
check("a window after every file is EMPTY WINDOW, exit 4, not zeros",
      code == 4 and "EMPTY WINDOW" in out and "impressions" not in out, (code, out[:200]))
code, out = run_main(["--since", "2026-06-06", "--until", "2026-08-24"])
check("a window before every file is EMPTY WINDOW, exit 4", code == 4 and "EMPTY WINDOW" in out, (code, out[:200]))

code, out = run_main(["--since", "2026-09-22", "--until", "2026-09-20"])
check("--since after --until is refused", code == 2, code)

# 3. The two reports' files need not start together. Downloads here begin 09-21, engagement 09-20.
late_dl = FakeASC(dl=[("d", "2026-09-23", [first("2026-09-21", "JP", 1), first("2026-09-22", "JP", 1)])],
                  eng=[("e", "2026-09-23", [event("2026-09-20", "Impression", "JP", 4),
                                            event("2026-09-21", "Impression", "JP", 4),
                                            event("2026-09-22", "Impression", "JP", 4)])])
code, out = run_main(["--since", "2026-09-20", "--until", "2026-09-22"], late_dl)
check("a window that starts before the download files says PARTIAL",
      code == 0 and "PARTIAL: only 2026-09-21 .. 2026-09-22" in out, out[:300])
code, out = run_main(["--since", "2026-09-21", "--until", "2026-09-22"], late_dl)
check("a window both reports cover is not PARTIAL", code == 0 and "PARTIAL" not in out, out[:300])
code, out = run_main(["--since", "2026-09-20", "--until", "2026-09-20"], late_dl)
check("a date only one report covers is EMPTY WINDOW, exit 4", code == 4 and "EMPTY WINDOW" in out, (code, out[:300]))

# 4. A quiet date inside the files' coverage is a real zero, and still prints (the guard at the pct lambda).
quiet = FakeASC(dl=[("q", "2026-09-23", [first("2026-09-20", "JP", 1), first("2026-09-22", "JP", 1)])],
                eng=[("qe", "2026-09-23", [event("2026-09-20", "Impression", "JP", 4),
                                           event("2026-09-22", "Impression", "JP", 4)])])
code, out = run_main(["--since", "2026-09-21", "--until", "2026-09-21"], quiet)
check("a quiet date inside coverage prints zeros, exit 0",
      code == 0 and "first-time downloads 0" in out, (code, out[:200]))

print()
print(f"{len(FAILS)} failed" if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
