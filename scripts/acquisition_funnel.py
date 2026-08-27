#!/usr/bin/env python3
"""Nihongo Ride — the App Store acquisition funnel, from ASC Analytics reports.

WHAT THIS IS FOR
----------------
`sales_report.py` answers "how many installs". This answers "out of how many
people who saw it", which is the question that separates *nobody sees this app*
from *people see it and do not install it*. Those have opposite fixes, and
PLAN-V2-PRODUCT §G is built on being able to tell them apart.

THE CALIBRATION, WHICH CAME OUT THE OPPOSITE WAY FROM THE WARNING
-----------------------------------------------------------------
`~/Documents/credits.md` records that the Analytics API "only counts users who
opted into sharing with developers and can show 0 when the real number is not 0".
For the **download** report in the modern `analyticsReportRequests` API that is
measured FALSE: over 2026-06-06..08-24 it reports 109 first-time downloads
against the Sales and Trends census's 109, agreeing exactly on both platforms
(macOS 60 / iOS 49) and on **all 20 territories**. The only discrepancy in the
raw totals (111 vs 109) was one extra day of coverage.

So the download report is census-grade and needs no scaling. **The impression and
page-view numbers have no second instrument and are NOT calibrated** — treat them
as Apple's own count, not as verified truth.

WHAT DID NOT ARRIVE, WHICH IS ALSO A MEASUREMENT
-------------------------------------------------
Of 156 reports, 8 materialised ~28 hours after the request, and they are all
acquisition-side. Sessions, retention, installation-and-deletion, crashes and
App Opt In did not. If it were latency they would have arrived together; the
split falls exactly along "needs an opted-in user sample". Plan for §G's
engagement guardrails being permanently unavailable at this traffic level.

PAGE VIEWS ARE NOT A FUNNEL STAGE
----------------------------------
41% of first-time downloads carry Page Type "No page" — installed straight from
search results, never opening the product page. So page-view-to-download can and
does exceed 100% (Australia: 4 downloads, 3 page views) and must never be quoted
as a conversion rate. The honest denominator is impressions.

Usage:  python3 scripts/acquisition_funnel.py [--json PATH] [--since D] [--until D]
"""
import argparse, csv, gzip, io, json, os, sys, time, urllib.request
from collections import defaultdict
from pathlib import Path

KEY_ID = os.environ.get("ASC_KEY_ID", "DMMFP6XTXX")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "c5671c11-49ec-47d9-bd38-5e3c1a249416")
KEY_PATH = Path(os.environ.get(
    "ASC_KEY_PATH", str(Path.home() / ".appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8")))
BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6777469778"
# The ONE_TIME_SNAPSHOT request created 2026-08-26. A new one can be POSTed to
# /v1/analyticsReportRequests if this is ever revoked; ONGOING is c57c770b-….
REPORT_REQUEST = os.environ.get("ASC_ANALYTICS_REQUEST", "4c53fdae-17db-4666-a557-cceeb6795e85")


def token():
    import jwt
    return jwt.encode({"iss": ISSUER_ID, "exp": int(time.time()) + 1100,
                       "aud": "appstoreconnect-v1"},
                      KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID})


def get(url, tok, auth=True):
    # Segment URLs are pre-signed S3 links. Sending Authorization to them returns
    # HTTP 400 — which looks exactly like a malformed request, and is not one.
    req = urllib.request.Request(url if url.startswith("http") else BASE + url,
                                 headers={"Authorization": f"Bearer {tok}"} if auth else {})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def report_rows(tok, name, granularity="DAILY"):
    """Every row of one named report at one granularity, as dicts."""
    reports = json.loads(get(
        f"/v1/analyticsReportRequests/{REPORT_REQUEST}/reports"
        f"?limit=200&fields[analyticsReports]=name", tok))["data"]
    match = [r for r in reports if r["attributes"]["name"] == name]
    if not match:
        raise SystemExit(f"acquisition_funnel: no report named {name!r}")
    # NOTE: passing fields[analyticsReportInstances] to this endpoint returns HTTP 400.
    instances = json.loads(get(f"/v1/analyticsReports/{match[0]['id']}/instances?limit=200", tok))["data"]
    chosen = [i for i in instances if i["attributes"]["granularity"] == granularity]
    if not chosen:
        return None      # "no instance" is a different fact from "no rows"
    rows = []
    for inst in chosen:
        segs = json.loads(get(f"/v1/analyticsReportInstances/{inst['id']}/segments?limit=50", tok))["data"]
        for seg in segs:
            blob = get(seg["attributes"]["url"], tok, auth=False)
            try:
                text = gzip.decompress(blob).decode("utf-8", errors="replace")
            except Exception:
                text = blob.decode("utf-8", errors="replace")
            rows += list(csv.DictReader(io.StringIO(text), delimiter="\t"))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--since", default="2026-06-06")
    ap.add_argument("--until", default="2026-08-24")
    ap.add_argument("--json")
    args = ap.parse_args()
    tok = token()

    eng = report_rows(tok, "App Store Discovery and Engagement Standard")
    dl = report_rows(tok, "App Downloads Standard")
    if eng is None or dl is None:
        print("NO-INSTANCE: Apple has generated no file for one of the reports. That is NOT "
              "the same as a report of zero — do not read it as zero traffic.")
        return 3

    def inwin(rows):
        return [r for r in rows if args.since <= r["Date"] <= args.until]

    eng, dl = inwin(eng), inwin(dl)
    first = [r for r in dl if r["Download Type"] == "First-time download"]

    terr = defaultdict(lambda: defaultdict(int))
    for r in eng:
        terr[r["Territory"]][r["Event"]] += int(r["Counts"])
    for r in first:
        terr[r["Territory"]]["Download"] += int(r["Counts"])
        terr[r["Territory"]]["page:" + (r["Page Type"] or "blank")] += int(r["Counts"])
    src = defaultdict(int)
    for r in first:
        src[r["Source Type"]] += int(r["Counts"])

    tot = defaultdict(int)
    for t in terr:
        for k, v in terr[t].items():
            tot[k] += v
    impressions, pageviews, downloads = tot["Impression"], tot["Page view"], tot["Download"]
    nopage = tot["page:No page"]

    print(f"window {args.since} .. {args.until}")
    print(f"  impressions {impressions} · page views {pageviews} · taps {tot['Tap']} · "
          f"first-time downloads {downloads}")
    # Guarded: a window with no impressions or no downloads is a legitimate query (a new app,
    # a quiet week) and must print zeros, not raise. Line 153 already guarded; these did not.
    pct = lambda a, b: (a / b) if b else 0.0
    print(f"  impression -> download  {pct(downloads, impressions):.2%}   <- the honest rate")
    print(f"  {nopage} of {downloads} downloads ({pct(nopage, downloads):.0%}) never opened the "
          f"product page, so page-view-to-download is not a conversion rate")
    print("  source: " + " · ".join(f"{k}={v} ({pct(v, downloads):.0%})"
                                    for k, v in sorted(src.items(), key=lambda x: -x[1])))
    print()
    print(f"  {'terr':5}{'impr':>8}{'pv':>7}{'dl':>5}{'impr->dl':>10}")
    ranked = sorted(terr.items(), key=lambda x: -x[1]["Impression"])[:12]
    for t, d in ranked:
        i, p, dd = d["Impression"], d["Page view"], d["Download"]
        print(f"  {t:5}{i:8}{p:7}{dd:5}{(dd / i if i else 0):10.2%}")

    if args.json:
        out = {"window": {"start": args.since, "end": args.until},
               "totals": {"impressions": impressions, "pageViews": pageviews,
                          "taps": tot["Tap"], "firstTimeDownloads": downloads,
                          "downloadsWithNoPageView": nopage},
               "sourceType": dict(src),
               "byTerritory": {t: {"impressions": d["Impression"], "pageViews": d["Page view"],
                                   "taps": d["Tap"], "downloads": d["Download"]}
                               for t, d in sorted(terr.items(), key=lambda x: -x[1]["Impression"])}}
        tmp = Path(args.json).with_suffix(".tmp")
        tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.replace(tmp, args.json)     # never truncate-then-write
        print(f"  wrote {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
