#!/usr/bin/env python3
"""Nihongo Ride — census downloads from App Store Connect Sales and Trends.

WHY THIS AND NOT THE ANALYTICS API
----------------------------------
The Analytics reports API counts only users who opted into "Share With App
Developers" and applies a privacy noise floor, so it can report ZERO while real
downloads exist. Sales and Trends is the census. For an app at this traffic
level that difference is the whole measurement, so the baseline is taken here
and the Analytics figures are calibrated AGAINST it, never the other way round.

WHY THE PRODUCT TYPE CODES ARE NOT COPIED FROM ANOTHER PROJECT
--------------------------------------------------------------
A sibling repo's version of this script carries the whitelist
{1, 1F, 1T, 1E, 1EP, 1EU} for downloads and {3, 3F, 3T, 7, 7F, 7T} for updates.
Run against Nihongo Ride that whitelist reports 5 downloads where the census
says 12: this app is a UNIVERSAL PURCHASE app and Apple reports it with `F1`
(first download, Desktop), `1F` (first download, iOS) and `F7` (update, on ALL
devices including iPhone and iPad). `F7` is absent from that whitelist entirely.

So the sets below were derived from this app's own data, and `--calibrate`
re-proves them rather than trusting this comment:

  * every code in DOWNLOAD/UPDATE must actually OCCUR in the window, or the run
    fails — a whitelist member that never occurs is an unverified claim about
    the data (the v1.24 `inflectionalTails` lesson);
  * any code NOT in any set is reported per-occurrence, never silently dropped
    — the question is not what the classifier catches but what it cannot see;
  * updates must be release-locked and downloads must not be. That is the
    behavioural proof that `F7` means "update", independent of Apple's code
    table, and it is what distinguishes this instrument from a broken one.

MONETIZATION CODES ARE EXPECTED-ABSENT, ON PURPOSE
--------------------------------------------------
IAP codes cannot occur yet — there is no StoreKit in this app. They are listed
in EXPECTED_ABSENT with that reason, so that when Stage 1 ships, the FIRST run
that sees one flips it out of that set. An IAP unit landing in "unclassified"
would be the exact failure this file exists to prevent.

Exit codes: 0 ran · 2 vendor number not on file · 3 API failure ·
4 calibration failed (the instrument is not trustworthy — do not use the number)
"""

import argparse
import datetime as dt
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path
from zoneinfo import ZoneInfo

KEY_ID = os.environ.get("ASC_KEY_ID", "DMMFP6XTXX")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "c5671c11-49ec-47d9-bd38-5e3c1a249416")
KEY_PATH = Path(os.environ.get(
    "ASC_KEY_PATH", str(Path.home() / ".appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8")))
APP_ID = "6777469778"
APP_SKU = "nihongoride-mac-2026"
LAUNCH_DATE = dt.date(2026, 6, 6)          # 1.0 READY_FOR_SALE, both platforms
BASE = "https://api.appstoreconnect.apple.com"
CACHE_DIR = Path.home() / "Library/Application Support/NihongoRide-Stats/sales"

# Derived from this app's own reports (see module docstring), not from Apple's table.
DOWNLOAD = {"F1": "macOS", "1F": "iOS"}
UPDATE = {"F7"}
REDOWNLOAD = {"3F", "F3"}                  # 4 units across the app's whole life
EXPECTED_ABSENT = {
    "IA1": "IAP — impossible until Stage 1 ships StoreKit",
    "IA9": "IAP — impossible until Stage 1 ships StoreKit",
    "IAY": "IAP subscription — not planned",
    "FI1": "Mac IAP — impossible until Stage 1 ships StoreKit",
}
# Days a version reached users. Used ONLY by --calibrate, as known-positive events.
RELEASE_DAYS = {"2026-08-11", "2026-08-16", "2026-08-18",
                "2026-08-20", "2026-08-22", "2026-08-24"}


def resolve_vendor_number(cli_value):
    if cli_value:
        return cli_value.strip()
    env = os.environ.get("ASC_VENDOR_NUMBER", "").strip()
    if env:
        return env
    credits = Path.home() / "Documents/credits.md"
    if credits.exists():
        for line in credits.read_text(encoding="utf-8", errors="replace").splitlines():
            if "vendor" in line.lower():
                m = re.search(r"\b(\d{8,10})\b", line)
                if m:
                    return m.group(1)
    return None


def make_jwt():
    import jwt  # PyJWT
    now = int(time.time())
    return jwt.encode({"iss": ISSUER_ID, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID})


def fetch_day(token, vendor, day):
    """("data", tsv) | ("nosales", detail) | ("pending", detail); raises on anything else.

    Apple returns 404 both for "no transactions that day" and "report not built
    yet". Those are different facts and collapsing them is how a pipeline that
    is merely LATE reads as a census zero.
    """
    params = (f"filter[frequency]=DAILY&filter[reportDate]={day.isoformat()}"
              f"&filter[reportSubType]=SUMMARY&filter[reportType]=SALES"
              f"&filter[vendorNumber]={vendor}&filter[version]=1_1")
    req = urllib.request.Request(
        f"{BASE}/v1/salesReports?{params}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/a-gzip"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return "data", gzip.decompress(resp.read()).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            detail = " ".join(x.get("detail", "") for x in json.loads(body).get("errors", []))
        except Exception:
            detail = body[:300]
        if e.code == 404:
            low = detail.lower()
            if "no sales" in low or "no data" in low or "were no" in low:
                return "nosales", detail
            return "pending", detail
        if e.code == 401:
            raise RuntimeError(f"auth failed (401): {detail}") from e
        if e.code in (400, 403):
            raise RuntimeError(f"rejected ({e.code}) — wrong vendor number? {detail}") from e
        raise RuntimeError(f"salesReports HTTP {e.code}: {detail}") from e


def our_rows(tsv_text):
    lines = tsv_text.splitlines()
    if not lines:
        return
    hdr = lines[0].split("\t")
    idx = {k: i for i, k in enumerate(hdr)}

    def col(r, k):
        i = idx.get(k)
        return r[i].strip() if i is not None and i < len(r) else ""

    for ln in lines[1:]:
        if not ln.strip():
            continue
        r = ln.split("\t")
        if col(r, "Apple Identifier") != APP_ID and col(r, "Parent Identifier") != APP_SKU:
            continue
        try:
            units = int(float(col(r, "Units") or "0"))
        except ValueError:
            units = 0
        yield {"pti": col(r, "Product Type Identifier"), "units": units,
               "country": col(r, "Country Code"), "device": col(r, "Device"),
               "version": col(r, "Version"), "sku": col(r, "SKU"),
               "platforms": col(r, "Supported Platforms"),
               "proceeds": col(r, "Developer Proceeds")}


def collect(token, vendor, start, end, use_cache=True):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    days = {}
    day = start
    while day <= end:
        key = day.isoformat()
        tsv_c = CACHE_DIR / f"{key}.tsv"
        nos_c = CACHE_DIR / f"{key}.nosales"
        if use_cache and tsv_c.exists():
            state, payload = "data", tsv_c.read_text(encoding="utf-8")
        elif use_cache and nos_c.exists():
            state, payload = "nosales", nos_c.read_text(encoding="utf-8")
        else:
            state, payload = fetch_day(token, vendor, day)
            if state == "data":
                tsv_c.write_text(payload, encoding="utf-8")
            elif state == "nosales":
                nos_c.write_text(payload, encoding="utf-8")
        days[key] = (state, payload)
        day += dt.timedelta(days=1)
    return days


def tally(days):
    per_day = defaultdict(lambda: defaultdict(int))
    seen_codes = defaultdict(int)
    unclassified = []
    terr = defaultdict(int)
    platforms = set()
    for key, (state, payload) in sorted(days.items()):
        if state != "data":
            per_day[key]["_state"] = state
            continue
        per_day[key]["_state"] = "data"
        for row in our_rows(payload):
            pti, u = row["pti"], row["units"]
            seen_codes[pti] += u
            platforms.add(row["platforms"])
            if pti in DOWNLOAD:
                per_day[key]["dl"] += u
                per_day[key]["dl_" + DOWNLOAD[pti]] += u
                terr[row["country"]] += u
            elif pti in UPDATE:
                per_day[key]["upd"] += u
            elif pti in REDOWNLOAD:
                per_day[key]["redl"] += u
            else:
                per_day[key]["unclassified"] += u
                unclassified.append((key, pti, row["device"], row["version"], u))
    return per_day, seen_codes, unclassified, terr, platforms


def calibrate(per_day, seen_codes, unclassified):
    """Prove the instrument responds to known-positive events. Returns list of failures."""
    fails = []
    for code in list(DOWNLOAD) + list(UPDATE):
        if seen_codes.get(code, 0) == 0:
            fails.append(f"whitelisted code {code!r} never occurs in this window — "
                         f"it is an unverified claim, not a measurement")
    for code, reason in EXPECTED_ABSENT.items():
        if seen_codes.get(code, 0):
            fails.append(f"code {code!r} was declared impossible ({reason}) and OCCURRED "
                         f"{seen_codes[code]} times — reclassify it before trusting any total")
    if unclassified:
        fails.append(f"{len(unclassified)} row(s) carry a code this classifier does not know: "
                     + ", ".join(sorted({u[1] for u in unclassified})))

    rel = [d for d in per_day if d in RELEASE_DAYS and per_day[d]["_state"] == "data"]
    oth = [d for d in per_day if d not in RELEASE_DAYS and per_day[d]["_state"] == "data"
           and d >= "2026-08-01"]
    if not rel or not oth:
        fails.append("no release days in window — cannot run the positive control")
        return fails
    ru = sum(per_day[d]["upd"] for d in rel) / len(rel)
    ou = sum(per_day[d]["upd"] for d in oth) / len(oth)
    rd = sum(per_day[d]["dl"] for d in rel) / len(rel)
    od = sum(per_day[d]["dl"] for d in oth) / len(oth)
    print(f"  positive control · updates  release-day {ru:.1f}/d vs other {ou:.1f}/d "
          f"= {ru / max(ou, 0.01):.2f}x")
    print(f"  positive control · downloads release-day {rd:.1f}/d vs other {od:.1f}/d "
          f"= {rd / max(od, 0.01):.2f}x")
    if ru <= ou:
        fails.append("updates are NOT elevated on release days — either the classification of "
                     "F7 is wrong or the report is not tracking reality. The download total "
                     "from this run must not be used.")
    return fails


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vendor")
    ap.add_argument("--since", default=LAUNCH_DATE.isoformat())
    ap.add_argument("--until", default=None)
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--calibrate", action="store_true",
                    help="run the positive control and exit non-zero if it fails")
    ap.add_argument("--json", help="write the tally to this path")
    ap.add_argument("--daily", action="store_true", help="print the per-day series")
    args = ap.parse_args()

    vendor = resolve_vendor_number(args.vendor)
    if not vendor:
        print("VENDOR-NUMBER-MISSING: put it in ~/Documents/credits.md on a line "
              "containing 'vendor' (ASC → Business, under the legal entity name).")
        return 2

    # Daily reports cut on Pacific time and materialise the next morning.
    newest = dt.datetime.now(ZoneInfo("America/Los_Angeles")).date() - dt.timedelta(days=1)
    start = dt.date.fromisoformat(args.since)
    end = min(dt.date.fromisoformat(args.until), newest) if args.until else newest

    try:
        days = collect(make_jwt(), vendor, start, end, use_cache=not args.no_cache)
    except RuntimeError as e:
        print(f"API-FAILURE: {e}")
        return 3

    per_day, seen_codes, unclassified, terr, platforms = tally(days)
    states = defaultdict(int)
    for d in per_day:
        states[per_day[d]["_state"]] += 1

    dl = sum(per_day[d]["dl"] for d in per_day)
    mac = sum(per_day[d]["dl_macOS"] for d in per_day)
    ios = sum(per_day[d]["dl_iOS"] for d in per_day)
    upd = sum(per_day[d]["upd"] for d in per_day)
    redl = sum(per_day[d]["redl"] for d in per_day)

    print(f"window {start} .. {end}  ({(end - start).days + 1} days)")
    print(f"  report states: " + " · ".join(f"{k}={v}" for k, v in sorted(states.items())))
    print(f"  FIRST-TIME DOWNLOADS  {dl}   (macOS {mac} · iOS {ios})")
    print(f"  updates {upd} · redownloads {redl} · unclassified {len(unclassified)} row(s)")
    print(f"  Supported Platforms values seen: {sorted(platforms)}")
    if unclassified:
        for u in unclassified:
            print(f"    UNCLASSIFIED {u}")

    data_days = [d for d in per_day if per_day[d]["_state"] == "data"]
    if data_days:
        print(f"  per-30-days rate over the window: "
              f"{dl / len(data_days) * 30:.1f} downloads")
    top = sorted(terr.items(), key=lambda x: -x[1])[:12]
    print("  territory: " + ", ".join(f"{k}={v}" for k, v in top))

    if args.daily:
        for d in sorted(data_days):
            print(f"    {d}  dl={per_day[d]['dl']:3} (mac {per_day[d]['dl_macOS']:2} "
                  f"ios {per_day[d]['dl_iOS']:2})  upd={per_day[d]['upd']:3}")

    rc = 0
    if args.calibrate:
        print("calibration:")
        fails = calibrate(per_day, seen_codes, unclassified)
        for f in fails:
            print(f"  CALIBRATION-FAIL: {f}")
        if fails:
            rc = 4
        else:
            print("  OK — the instrument responds to known-positive events.")

    if args.json:
        out = {
            "generated": dt.datetime.now(ZoneInfo("America/Los_Angeles")).isoformat(),
            "window": {"start": start.isoformat(), "end": end.isoformat()},
            "report_states": dict(states),
            "first_time_downloads": {"total": dl, "macOS": mac, "iOS": ios},
            "updates": upd, "redownloads": redl,
            "unclassified_rows": unclassified,
            "product_type_units": dict(seen_codes),
            "territory_downloads": dict(sorted(terr.items(), key=lambda x: -x[1])),
            "daily": {d: {"dl": per_day[d]["dl"], "dl_macOS": per_day[d]["dl_macOS"],
                          "dl_iOS": per_day[d]["dl_iOS"], "upd": per_day[d]["upd"]}
                      for d in sorted(data_days)},
            "calibrated": args.calibrate and rc == 0,
        }
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        tmp = Path(args.json).with_suffix(".tmp")
        tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.replace(tmp, args.json)     # never truncate-then-write; see STATE
        print(f"  wrote {args.json}")

    return rc


if __name__ == "__main__":
    sys.exit(main())
