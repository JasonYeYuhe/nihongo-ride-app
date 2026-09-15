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

MONETIZATION CODES — FLIPPED OUT OF EXPECTED-ABSENT FOR STAGE 1
---------------------------------------------------------------
This block used to say IAP codes "cannot occur yet — there is no StoreKit in
this app", and put them in EXPECTED_ABSENT so that the first run seeing one
would fail loudly. That tripwire did its job: it is the reason this file was
opened before the SKU went on sale rather than on the morning of the first sale,
which is the worst possible day to be editing the instrument.

They are now a tallied class (PURCHASE), and three things had to move with them,
because a code that is merely *recognised* is still not *counted*:

  * TERRITORY was incremented only inside the DOWNLOAD branch, so a purchase
    would have had no country at all. Purchases get their own tally rather than
    joining `terr` — silently widening an existing number's meaning is how a
    figure quoted in one release comes to mean something else in the next.
  * DEVELOPER PROCEEDS was parsed and then never used anywhere in the file.
  * REFUNDS arrive as NEGATIVE Units, up to ~90 days after the sale, and no code
    path in this repo had ever seen a negative. Gross units and refunded units
    are tallied separately and never netted silently: "6 sold" and "8 sold, 2
    refunded" are different facts about the same net 6.

The replacement tripwire matters more than the one removed. `--calibrate` now
drives a SYNTHETIC purchase row through the real `tally()` on every run and
fails if it does not land in units, territory, proceeds and refunds. So the
purchase path is proven to fire before a real sale exists, rather than being
trusted until a sale silently fails to appear — a classifier that has never
recognised anything reports "0 sales" exactly like a working one.

Unknown codes still fail calibration, so a product-type identifier nobody
anticipated cannot be quietly absorbed by the new class.

ONE CLASSIFICATION RULE
-----------------------
`classify_row` is the only place a product type code becomes a kind. `tally`
(the totals above) and `cell_tally` (units per day · kind · platform · country,
which is what the registry below subtracts from) both call it, and
`scripts/test_sales_report.py` fails if the two ever disagree. Two classifiers
that are each right on their own day are how a subtraction ends up taking a
unit away from a number that never contained it.

THE KNOWN-POSITIVE REGISTRY
---------------------------
`docs/measurements/stage1-known-positives.json` records what the owner's own
walk put into the report: §K's day-0 purchase, its refund, and any first-time
downloads or redownloads the walk caused. The owner maintains it; NO tool ever
writes it, this one included. It is validated strictly on every read (unknown
kind / platform / status, a 3-letter or lowercase country code, non-positive
units, a report day that is not a date, a local timestamp without an explicit
UTC offset, duplicate ids, unknown or non-boolean decisions), and an invalid
registry stops both modes below with every problem listed.

What is subtracted is fixed here so it cannot be decided per reading:
  * kind=purchase and kind=refund entries are ALWAYS subtracted from the
    purchase numerator (gross, refunded, net, purchase territory). §K says
    "exclude it from the cohort", and excluding a purchase while keeping its
    refund would print net −1. It is the only exclusion §K itself licenses.
  * kind=first_download entries are subtracted from N only when
    decisions.exclude_walk_first_downloads_from_N is true; false → counted;
    null while such entries sit in the window → N is printed unadjusted with
    the undecided count, and the bound is withheld.
  * decisions.exclude_owner_refund_from_refund_ceiling is echoed, never applied:
    nothing here evaluates the day-180 refund ceiling.
  * kind=redownload entries are listed and never subtracted; they feed no §K
    number, and they are recorded so nobody later moves them into N.
Report rows are totals, not transactions, so an entry subtracts units from a
cell, and a cell gives up at most the units it holds. An entry claiming more
(the wrong Pacific day, the wrong country, or an awaiting-report row Apple has
not published) is a disagreement between the registry and the report: the
excess is never subtracted, the bound is withheld, and no figure it touches is
printed as a count: the ADJUSTED PURCHASES line reads NOT PRINTED, and an N that
should have lost walk units the report does not hold where the registry says
(decision true) reads NOT SETTLED.

--checkpoint
------------
Collects the full default window (so calibration runs exactly as `--calibrate`
runs it), then prints the cohort since §K's day 0 (2026-09-09) raw and with the
registry applied, the 2026-09-08 first-time download count (§K's day 0 is
"09-08 or 09-09", and N is the same under both only while that count is
zero), and §K's pre-registered
checkpoint list with which rows have been reached. It prints the rule-of-three
bound — 3/N and 3/(N+114) on the adjusted N — only when calibration passed, a
kind=purchase status=matched entry lies in the cohort window, no decision the
bound depends on is null while entries it governs are in the window, the
registry agrees with the report, every cohort report day is built, N > 0, and
adjusted net purchases are exactly zero. Net above zero → the zero-purchase
bound does not apply, and the tool says so and decides nothing.

WHY THE BOUND IS WITHHELD RATHER THAN FOOTNOTED
-----------------------------------------------
A bound printed with a caveat under it is quoted without the caveat — that is
what a number is for. "Zero purchases in N installs rules out conversion
≥ 3/N" is only true of an instrument that has been seen to record a purchase,
and until §K's day-0 row has been matched in a real report this one has only
recorded synthetic ones. So the number is not printed at all until every
condition holds, and the reasons it is not are printed in its place, every one
of them, so that "withheld" can never be mistaken for "zero".

--confirm-known-positive
------------------------
`--kind purchase|refund --at <ISO-8601 with offset> --platform macOS|iOS
--country XX`. Converts --at to the Pacific report day D (daily reports cut on
America/Los_Angeles; a purchase before 16:00 JST in summer, 17:00 in winter,
lands on the PREVIOUS Pacific day). If D is not published yet → PENDING. Otherwise it refetches D-1..D+1 with
no cache, lists every purchase-class row and every UNCLASSIFIED row on those
days (an unexpected product type code on the owner's purchase is the likeliest
real-world finding), matches kind/platform/country on D, warns when the matched
cell holds more units than the owner's one, and runs the full default-window
calibration. On a match with calibration OK it PRINTS a draft registry entry
and a draft §K sentence, each labelled "DRAFT — not recorded; the owner
confirms". It writes nothing but the sales cache that fetching already writes.

The platform is the code map's (PURCHASE), and nobody has seen which code Apple
gives a Mac purchase of this in-app item — that is part of what the owner's
known-positive tests. So: with no match, the same day · kind · country under
the OTHER platform's code is listed with its codes and Device values and called
what it is (NOT a match; the question is PURCHASE's map; flipping --platform is
the wrong response); with a match, a Device value that contradicts --platform
puts a WARNING on the draft. The draft §K sentence counts the days from day 0
and says §K's "before the SKU goes on sale" was not met when it was not, and it
says "to be registered", because nothing is registered until the owner does it.

Exit codes: 0 ran (--checkpoint: bound printed, or the zero-purchase bound does
not apply · --confirm-known-positive: matched and calibrated) · 2 vendor number
not on file, or a usage error · 3 API failure ·
4 calibration failed, or the known-positive registry is invalid (the instrument
is not trustworthy — do not use the number) · 5 --checkpoint: bound withheld ·
6 --confirm-known-positive: report day not published yet (PENDING) ·
7 --confirm-known-positive: the built report has no matching row (including when
the only candidate is under the other platform's code — that is not a match)
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
# Stage 1's non-consumable. Universal Purchase means one SKU serves both platforms, so all
# three shapes Apple uses for a paid in-app item are accepted rather than guessed between —
# and anything NOT listed still lands in `unclassified` and fails calibration, so a code
# nobody anticipated cannot hide inside this class.
PURCHASE = {"IA1": "iOS", "IA9": "iOS", "FI1": "macOS"}
# The report's Device column, as spelled in this vendor's cached reports (2026-09-16: Desktop, iPhone,
# iPad, Apple Watch). NOT a classifier — platform comes from the code map above, and this app's own F7
# lands on every device. It is read in ONE place: --confirm-known-positive warns when a matched row's
# device contradicts the platform the code map gave it, because nobody has yet seen which code Apple
# uses for a Mac purchase of this in-app item, and the owner's known-positive is what will show it.
DEVICE_PLATFORM = {"Desktop": "macOS", "iPhone": "iOS", "iPad": "iOS"}
EXPECTED_ABSENT = {
    "IAY": "IAP subscription — Stage 1 sells one non-consumable; a subscription code "
           "appearing means either a misconfigured product or the wrong app's rows",
}
# Days a version reached users. Used ONLY by --calibrate, as known-positive events.
RELEASE_DAYS = {"2026-08-11", "2026-08-16", "2026-08-18",
                "2026-08-20", "2026-08-22", "2026-08-24"}

PACIFIC = ZoneInfo("America/Los_Angeles")
# §K: "DAY 0 = 2026-09-09". A constant here, not a registry field anybody can edit — the registry
# repeats it only so a registry written against a different day 0 is rejected rather than applied.
DAY0 = dt.date(2026, 9, 9)
LEGACY_BASE = 114                          # §K: "the ceiling denominator (+114 legacy base)"
REGISTRY_PATH = Path(__file__).resolve().parent.parent / "docs/measurements/stage1-known-positives.json"
# §K's pre-registered checkpoints, quoted. The tool says which have been reached and nothing more.
CHECKPOINT_N = ((35, "record, falsifies nothing"),
                (100, "first checkpoint that can falsify §D's 8.2%"))
INTERIM_DATE = dt.date(2026, 12, 8)
DECISION_N = 200
BACKSTOP_DATE = dt.date(2027, 3, 8)

REGISTRY_KINDS = ("purchase", "refund", "first_download", "redownload")
REGISTRY_PLATFORMS = ("macOS", "iOS")
REGISTRY_STATUSES = ("awaiting-report", "matched")
REGISTRY_DECISIONS = ("exclude_walk_first_downloads_from_N",
                      "exclude_owner_refund_from_refund_ceiling")
REGISTRY_ENTRY_KEYS = ("id", "kind", "report_day_pt", "platform", "country_code", "units",
                       "status", "matched_product_type", "local_timestamp", "walk_step",
                       "evidence", "notes")
# Explicit offset required: "10:00" on the owner's Mac and "10:00" in a report are nine hours apart,
# and a naive stamp silently picks one. `Z` is accepted because it IS an explicit offset.
_ISO_WITH_OFFSET = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$")


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
               "proceeds": col(r, "Developer Proceeds"),
               "proceeds_currency": col(r, "Currency of Proceeds"),
               "price": col(r, "Customer Price"), "price_currency": col(r, "Customer Currency")}


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


def classify_row(pti, units):
    """(kind, platform) for one report row — THE classification rule, and the only one.

    kind is first_download · update · redownload · purchase · refund · unclassified. platform comes
    from the code map (never the Device column) and is None where the map carries none. A refund
    is the SAME purchase code with negative Units, arriving up to ~90 days after the sale, so the
    sign is part of the rule rather than something each caller re-derives.
    """
    if pti in DOWNLOAD:
        return "first_download", DOWNLOAD[pti]
    if pti in UPDATE:
        return "update", None
    if pti in REDOWNLOAD:
        return "redownload", None
    if pti in PURCHASE:
        return ("purchase" if units >= 0 else "refund"), PURCHASE[pti]
    return "unclassified", None


def tally(days):
    per_day = defaultdict(lambda: defaultdict(int))
    seen_codes = defaultdict(int)
    unclassified = []
    terr = defaultdict(int)
    buy_terr = defaultdict(int)
    proceeds = 0.0
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
            kind, platform = classify_row(pti, u)
            if kind == "first_download":
                per_day[key]["dl"] += u
                per_day[key]["dl_" + platform] += u
                terr[row["country"]] += u
            elif kind == "update":
                per_day[key]["upd"] += u
            elif kind == "redownload":
                per_day[key]["redl"] += u
            elif kind in ("purchase", "refund"):
                # Gross and refunded are kept apart on purpose: netting them would make "nobody
                # bought it" and "somebody bought it and asked for their money back" print the
                # same number, and those are opposite findings about the offer.
                if kind == "purchase":
                    per_day[key]["buy"] += u
                    per_day[key]["buy_" + platform] += u
                else:
                    per_day[key]["refund"] += -u
                buy_terr[row["country"]] += u
                try:
                    per_unit = float(row["proceeds"] or 0)
                except ValueError:
                    # Never silently zero: an unparseable proceeds figure on a real sale is a
                    # broken instrument, and calibration below turns this into a failure.
                    per_day[key]["proceeds_unparsed"] += 1
                else:
                    # ⚠️ ASSUMPTION, ASSERTED RATHER THAN TRUSTED. "Developer Proceeds" is
                    # read as a PER-UNIT figure that is always positive, with the sign of the
                    # transaction carried by Units — so a refund subtracts through its negative
                    # Units. Nobody here has seen a real refund row, because the app has never
                    # sold anything. If Apple ALSO negates the proceeds cell, this
                    # multiplication would silently ADD money on a refund, and a total that is
                    # too high by twice the refund looks exactly like a total that is right.
                    # So the unexpected sign is counted and calibration fails on it.
                    if per_unit < 0:
                        per_day[key]["proceeds_sign_conflict"] += 1
                    proceeds += per_unit * u
            else:
                per_day[key]["unclassified"] += u
                unclassified.append((key, pti, row["device"], row["version"], u))
    return per_day, seen_codes, unclassified, terr, platforms, buy_terr, proceeds


def cell_tally(days):
    """Units per (day, kind, platform, country) cell, and the codes seen in each cell.

    Report rows are totals, not transactions (`F1 units=3 JP` is three people), so excluding the
    owner means subtracting units from a cell — there is no row of theirs to delete. Classified by
    `classify_row`, the same call `tally` makes; refund cells hold refunded units as a positive
    count, exactly as `tally`'s "refund" does.
    """
    cells = defaultdict(int)
    codes = defaultdict(set)
    for key, (state, payload) in sorted(days.items()):
        if state != "data":
            continue
        for row in our_rows(payload):
            kind, platform = classify_row(row["pti"], row["units"])
            cell = (key, kind, platform, row["country"])
            cells[cell] += -row["units"] if kind == "refund" else row["units"]
            codes[cell].add(row["pti"])
    return cells, codes


# A fabricated day of purchase rows, in Apple's own TSV shape, used ONLY as the known-positive
# for the purchase path. It is driven through the real `our_rows` + `tally` — not through a
# reimplementation — so it proves the shipping classifier fires, which is the only thing a
# positive control is worth. Header names must match `fetch_day`'s real report; a rename in
# Apple's format therefore fails calibration instead of silently zeroing sales.
_CONTROL_HEADER = ("Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\t"
                   "Product Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\t"
                   "Customer Currency\tCountry Code\tCurrency of Proceeds\tApple Identifier\t"
                   "Customer Price\tPromo Code\tParent Identifier\tSubscription\tPeriod\t"
                   "Category\tCDR\tPromotion Name\tClient\tDevice\tSupported Platforms\t"
                   "Proceeds Reason\tPreserved Pricing\tClient\tOrder Type")


def _control_row(pti, units, proceeds, country):
    cells = [""] * 30
    cells[5] = "1.30"
    cells[6] = pti
    cells[7] = str(units)
    cells[8] = proceeds
    cells[12] = country
    cells[14] = "0"                 # not APP_ID — admitted via Parent Identifier, like real IAP rows
    cells[17] = APP_SKU             # Parent Identifier: what actually routes an IAP row to this app
    cells[24] = "Desktop"
    cells[25] = "iOS and macOS"
    return "\t".join(cells)


def purchase_path_control():
    """Drive synthetic purchase rows through the real tally. Returns a list of failures.

    This exists because of the rule this project pays for most often: a classifier that has
    never recognised a purchase reports "0 sales" in exactly the same words as one that works.
    Before Stage 1 there will be no real sale to prove the path on for weeks or months, so the
    proof has to be manufactured — and it has to run on EVERY calibration, not once.
    """
    fails = []
    payload = "\n".join([
        _CONTROL_HEADER,
        _control_row("IA1", 2, "8.42", "CHN"),     # two sales, iOS
        _control_row("FI1", 1, "8.42", "JPN"),     # one sale, macOS
        _control_row("IA1", -1, "8.42", "CHN"),    # one refund: negative Units, per-unit
                                                   # proceeds still positive — the assumption
                                                   # `tally` asserts rather than trusts
    ])
    days = {"2026-01-01": ("data", payload)}
    per_day, seen, unclassified, terr, _plat, buy_terr, proceeds = tally(days)
    d = per_day["2026-01-01"]
    if d["buy"] != 3:
        fails.append(f"purchase control: expected 3 gross units, tallied {d['buy']}")
    if d["buy_iOS"] != 2 or d["buy_macOS"] != 1:
        fails.append(f"purchase control: platform split wrong "
                     f"(iOS {d['buy_iOS']}, macOS {d['buy_macOS']})")
    if d["refund"] != 1:
        fails.append(f"purchase control: expected 1 refunded unit, tallied {d['refund']}")
    if dict(buy_terr) != {"CHN": 1, "JPN": 1}:
        fails.append(f"purchase control: territory tally wrong — {dict(buy_terr)} "
                     f"(CHN nets to 1 after the refund)")
    if abs(proceeds - 8.42 * 2) > 0.005:
        fails.append(f"purchase control: proceeds {proceeds:.2f}, expected {8.42 * 2:.2f} "
                     f"(3 sold − 1 refunded = 2 net units at 8.42)")
    if d["proceeds_sign_conflict"]:
        fails.append("purchase control: the control's own rows tripped the proceeds sign "
                     "guard — the guard is inverted")
    if terr:
        fails.append(f"purchase control: purchases leaked into the DOWNLOAD territory tally — "
                     f"{dict(terr)}")
    if unclassified:
        fails.append(f"purchase control: purchase codes were not recognised — {unclassified}")
    return fails


def pacific_report_day(stamp):
    """The America/Los_Angeles calendar date of an ISO-8601 timestamp that carries its own offset.

    Apple cuts daily reports on Pacific time, so a purchase at 10:00 in Tokyo lands in the
    PREVIOUS day's report. A naive timestamp is rejected rather than read as local time: the
    machine running this and the device that bought need not share a timezone, and a guess here
    moves the purchase to a report day that does not contain it.
    """
    return _parse_stamp(stamp).astimezone(PACIFIC).date()


def _parse_stamp(stamp):
    if not isinstance(stamp, str) or not _ISO_WITH_OFFSET.match(stamp):
        raise ValueError(f"{stamp!r} is not an ISO-8601 timestamp with an explicit UTC offset "
                         f"(e.g. 2026-09-17T10:00:00+09:00)")
    return dt.datetime.fromisoformat(stamp[:-1] + "+00:00" if stamp.endswith("Z") else stamp)


def days_after_day0(stamp):
    """Calendar days from §K's day 0 to the date `stamp` names in its OWN offset — the date on the
    buyer's clock, which is the date §K's "Day 0" sentence is about (not the Pacific report day)."""
    return (_parse_stamp(stamp).date() - DAY0).days


def lateness(stamp):
    """How a timestamp stands against §K's "Day 0, before the SKU goes on sale", in words a record can
    carry. After day 0 the condition was not met — the SKU was on sale by day 0 (§K: "the true day 0
    is 09-08 or 09-09, never later"). On or before day 0 a sales report cannot show whether it was
    before the SKU went on sale, so the words say that instead of guessing either way."""
    n = days_after_day0(stamp)
    if n >= 1:
        return (f"{n} {_plural(n, 'day', 'days')} after day 0 ({DAY0}); the SKU was on sale by day 0, "
                f"so §K's \"before the SKU goes on sale\" was not met")
    where = "on day 0" if n == 0 else f"{-n} {_plural(-n, 'day', 'days')} before day 0"
    return (f"{where} ({DAY0}); whether that was before the SKU went on sale is not something a sales "
            f"report can show — the owner states it")


def pacific_today():
    return dt.datetime.now(PACIFIC).date()


def _reject_duplicate_keys(pairs):
    # json.loads keeps the LAST of two equal keys without a word, so a hand-edited registry could
    # carry a decision that is not the one a reader sees first.
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key {key!r}")
        out[key] = value
    return out


def load_registry(path):
    """(registry, problems). Any problem means the registry must not be used at all."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        return None, [f"cannot read {path}: {e}"]
    try:
        obj = json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except ValueError as e:
        return None, [f"not valid JSON: {e}"]
    return obj, validate_registry(obj)


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def _is_iso_day(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return False
    try:
        dt.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def _is_one_of(value, allowed):
    # `1 in (True, False)` is True in Python; the registry's enumerations are compared by type too.
    return any(type(value) is type(a) and value == a for a in allowed)


def validate_registry(obj):
    """Every problem with a registry, not the first. An empty list is the only valid result."""
    if not isinstance(obj, dict):
        return [f"the registry must be a JSON object, got {type(obj).__name__}"]
    problems = []
    top = ("schema", "day0", "decisions", "entries")
    problems += [f"unknown top-level key {k!r}" for k in sorted(set(obj) - set(top))]
    problems += [f"missing top-level key {k!r}" for k in top if k not in obj]
    if "schema" in obj and not (_is_int(obj["schema"]) and obj["schema"] == 1):
        problems.append(f"schema must be 1, got {obj['schema']!r}")
    if "day0" in obj and obj["day0"] != DAY0.isoformat():
        problems.append(f"day0 must be {DAY0} (§K), got {obj['day0']!r} — day 0 is fixed by §K, "
                        f"not by this file")
    if "decisions" in obj:
        decisions = obj["decisions"]
        if not isinstance(decisions, dict):
            problems.append("decisions must be an object")
        else:
            problems += [f"unknown decision key {k!r}"
                         for k in sorted(set(decisions) - set(REGISTRY_DECISIONS))]
            for k in REGISTRY_DECISIONS:
                if k not in decisions:
                    problems.append(f"missing decision {k!r}")
                elif not _is_one_of(decisions[k], (True, False, None)):
                    problems.append(f"decision {k!r} must be true, false or null, "
                                    f"got {decisions[k]!r}")
    if "entries" in obj and not isinstance(obj["entries"], list):
        problems.append("entries must be a list")
    seen_ids = set()
    for i, e in enumerate(obj.get("entries") if isinstance(obj.get("entries"), list) else []):
        if not isinstance(e, dict):
            problems.append(f"entries[{i}] must be an object")
            continue
        where = f"entries[{i}]" + (f" ({e['id']})" if isinstance(e.get("id"), str) else "")
        problems += [f"{where}: unknown key {k!r}" for k in sorted(set(e) - set(REGISTRY_ENTRY_KEYS))]
        problems += [f"{where}: missing key {k!r}" for k in REGISTRY_ENTRY_KEYS if k not in e]
        if "id" in e:
            if not isinstance(e["id"], str) or not e["id"].strip():
                problems.append(f"{where}: id must be a non-empty string")
            elif e["id"] in seen_ids:
                problems.append(f"{where}: duplicate id {e['id']!r}")
            else:
                seen_ids.add(e["id"])
        if "kind" in e and not _is_one_of(e["kind"], REGISTRY_KINDS):
            problems.append(f"{where}: kind must be one of {', '.join(REGISTRY_KINDS)}, "
                            f"got {e['kind']!r}")
        if "report_day_pt" in e and not _is_iso_day(e["report_day_pt"]):
            problems.append(f"{where}: report_day_pt must be a YYYY-MM-DD date, "
                            f"got {e['report_day_pt']!r}")
        if "platform" in e and not _is_one_of(e["platform"], REGISTRY_PLATFORMS):
            problems.append(f"{where}: platform must be macOS or iOS, got {e['platform']!r}")
        if "country_code" in e and not (isinstance(e["country_code"], str)
                                        and re.fullmatch(r"[A-Z]{2}", e["country_code"])):
            problems.append(f"{where}: country_code must be the report's 2-letter uppercase code "
                            f"(JP, CN, US), got {e['country_code']!r} — a 3-letter code never "
                            f"matches a real row")
        if "units" in e and not (_is_int(e["units"]) and e["units"] > 0):
            problems.append(f"{where}: units must be a positive integer, got {e['units']!r}")
        if "status" in e and not _is_one_of(e["status"], REGISTRY_STATUSES):
            problems.append(f"{where}: status must be awaiting-report or matched, "
                            f"got {e['status']!r}")
        if "matched_product_type" in e:
            code, status = e["matched_product_type"], e.get("status")
            if code is not None and not isinstance(code, str):
                problems.append(f"{where}: matched_product_type must be null or a string")
            elif status == "awaiting-report" and code is not None:
                problems.append(f"{where}: an awaiting-report entry cannot carry a "
                                f"matched_product_type ({code!r})")
            elif status == "matched":
                kind, platform = e.get("kind"), e.get("platform")
                code_map = {"purchase": PURCHASE, "refund": PURCHASE,
                            "first_download": DOWNLOAD}.get(kind)
                if code is None:
                    problems.append(f"{where}: a matched entry needs its matched_product_type")
                elif kind == "redownload":
                    if code not in REDOWNLOAD:
                        problems.append(f"{where}: {code!r} is not a redownload code "
                                        f"({', '.join(sorted(REDOWNLOAD))})")
                elif code_map is not None and code_map.get(code) != platform:
                    problems.append(f"{where}: {code!r} is not a {kind} code for {platform!r} "
                                    f"under this classifier")
        if "local_timestamp" in e:
            try:
                pacific_report_day(e["local_timestamp"])
            except ValueError as err:
                problems.append(f"{where}: local_timestamp: {err}")
        for k in ("walk_step", "notes"):
            if k in e and not isinstance(e[k], str):
                problems.append(f"{where}: {k} must be a string")
        if "evidence" in e:
            if not isinstance(e["evidence"], list):
                problems.append(f"{where}: evidence must be a list")
            else:
                for j, ev in enumerate(e["evidence"]):
                    if (not isinstance(ev, dict) or set(ev) != {"file", "sha256"}
                            or not isinstance(ev["file"], str) or not ev["file"]
                            or not isinstance(ev["sha256"], str)
                            or not re.fullmatch(r"[0-9a-f]{64}", ev["sha256"])):
                        problems.append(f"{where}: evidence[{j}] must be exactly "
                                        f"{{\"file\": <name>, \"sha256\": <64 lowercase hex>}}")
    return problems


def apply_registry(cells, registry, start, end):
    """Cohort numbers for report days start..end, raw and with a VALID registry applied. Pure.

    The subtraction semantics are the module docstring's; they are fixed there, once, so the
    readout's words and this arithmetic cannot drift apart.
    """
    s, e = start.isoformat(), end.isoformat()

    def units(kind, platform=None):
        return sum(u for (day, k, p, _c), u in cells.items()
                   if s <= day <= e and k == kind and (platform is None or p == platform))

    raw = {"dl": units("first_download"), "dl_macOS": units("first_download", "macOS"),
           "dl_iOS": units("first_download", "iOS"), "buy": units("purchase"),
           "buy_macOS": units("purchase", "macOS"), "buy_iOS": units("purchase", "iOS"),
           "refund": units("refund")}
    raw["net"] = raw["buy"] - raw["refund"]
    raw_terr = defaultdict(int)
    for (day, k, _p, country), u in cells.items():
        if s <= day <= e and k in ("purchase", "refund"):
            raw_terr[country] += u if k == "purchase" else -u

    decision = registry["decisions"]["exclude_walk_first_downloads_from_N"]
    in_window = [x for x in registry["entries"] if s <= x["report_day_pt"] <= e]
    walk_installs = [x for x in in_window if x["kind"] == "first_download"]

    # An entry subtracts from its CELL, and a cell can give up only the units it holds. An entry that
    # claims more is the wrong day (the Pacific cut), the wrong country, a row Apple has not published
    # yet (an awaiting-report entry), or a unit that was never a first download. Subtracting the
    # excess anyway would take it out of a number that never contained it — a stranger's purchase in
    # the same column, or nothing at all, printed as "refunded -1". So each cell gives up
    # min(claimed, held), and the excess is a disagreement that withholds the bound, never a subtraction.
    claimed = defaultdict(int)
    for x in in_window:
        claimed[_entry_cell(x)] += x["units"]
    adjusted = dict(raw)
    adj_terr = defaultdict(int, raw_terr)
    problems, notes, short_cells = [], [], set()
    unheld_walk_units = 0
    for cell in sorted(claimed, key=str):
        day, kind, platform, country = cell
        held = cells.get(cell, 0)
        taken = min(claimed[cell], max(held, 0))
        if kind == "purchase":
            adjusted["buy"] -= taken
            adjusted["buy_" + platform] -= taken
            adj_terr[country] -= taken
        elif kind == "refund":
            adjusted["refund"] -= taken
            adj_terr[country] += taken
        elif kind == "first_download" and decision is True:
            adjusted["dl"] -= taken
            adjusted["dl_" + platform] -= taken
        if held < claimed[cell]:
            msg = (f"{day} {kind} {platform or '(any platform)'} {country}: the registry claims "
                   f"{claimed[cell]} unit(s), the report holds {held}")
            if kind == "redownload":
                notes.append(msg)
            else:
                problems.append(msg)
                short_cells.add(cell)
                if kind == "first_download":
                    unheld_walk_units += claimed[cell] - max(held, 0)
    adjusted["net"] = adjusted["buy"] - adjusted["refund"]
    return {"raw": raw, "adjusted": adjusted,
            "raw_territory": {c: u for c, u in raw_terr.items() if u},
            "adjusted_territory": {c: u for c, u in adj_terr.items() if u},
            "decision": decision, "in_window": in_window, "walk_installs": walk_installs,
            "walk_install_units": sum(x["units"] for x in walk_installs),
            "walk_install_units_unheld": unheld_walk_units,
            "problems": problems, "short_cells": short_cells,
            "problem_kinds": {cell[1] for cell in short_cells}, "notes": notes}


def _entry_cell(x):
    """The (day, kind, platform, country) cell a registry entry subtracts from."""
    platform = None if x["kind"] == "redownload" else x["platform"]   # redownload codes carry none
    return (x["report_day_pt"], x["kind"], platform, x["country_code"])


def exclusion_control(apply=None):
    """Drive a synthetic owner purchase, refund and walk install through the real `cell_tally` and
    `apply_registry`. Returns a list of failures.

    The registry is a subtraction, and a subtraction that silently does nothing prints exactly what
    a working one prints on every day nobody is registered — which, until the owner's walk, is
    every day. So it is proven paired, on every calibration: matched entries move the adjusted
    figures by EXACTLY their units; the same report with no entries leaves adjusted equal to raw;
    an entry whose row is not in the report, or that claims more units than its cell holds, is
    reported AND subtracts no more than the cell holds — both halves checked, because either one
    alone reads as working.
    """
    apply = apply or apply_registry
    fails = []
    day1 = "\n".join([
        _CONTROL_HEADER,
        _control_row("FI1", 2, "8.42", "JP"),      # the owner's sale and a customer's, ONE cell
        _control_row("IA1", 1, "8.42", "CN"),      # a customer, iOS
        _control_row("F1", 3, "0", "JP"),          # the owner's walk install among two strangers'
        _control_row("1F", 1, "0", "CN"),
    ])
    day2 = "\n".join([_CONTROL_HEADER, _control_row("FI1", -1, "8.42", "JP")])   # the owner's refund
    cells, _codes = cell_tally({"2026-01-02": ("data", day1), "2026-01-03": ("data", day2)})
    start, end = dt.date(2026, 1, 1), dt.date(2026, 1, 31)

    def registry(decision, entries):
        return {"schema": 1, "day0": DAY0.isoformat(),
                "decisions": {"exclude_walk_first_downloads_from_N": decision,
                              "exclude_owner_refund_from_refund_ceiling": None},
                "entries": entries}

    def entry(eid, kind, day, country, code, units=1):
        return {"id": eid, "kind": kind, "report_day_pt": day, "platform": "macOS",
                "country_code": country, "units": units, "status": "matched",
                "matched_product_type": code, "local_timestamp": f"{day}T12:00:00-08:00",
                "walk_step": "exclusion control", "evidence": [], "notes": ""}

    owner = [entry("c-buy", "purchase", "2026-01-02", "JP", "FI1"),
             entry("c-refund", "refund", "2026-01-03", "JP", "FI1"),
             entry("c-install", "first_download", "2026-01-02", "JP", "F1")]
    expected_raw = {"dl": 4, "dl_macOS": 3, "dl_iOS": 1, "buy": 3, "buy_macOS": 2, "buy_iOS": 1,
                    "refund": 1, "net": 2}
    exact = {"dl": 1, "dl_macOS": 1, "dl_iOS": 0, "buy": 1, "buy_macOS": 1, "buy_iOS": 0,
             "refund": 1, "net": 0}

    bare = apply(cells, registry(None, []), start, end)
    if bare["raw"] != expected_raw:
        fails.append(f"exclusion control: raw cohort {bare['raw']}, expected {expected_raw}")
    if bare["adjusted"] != bare["raw"] or bare["problems"]:
        fails.append(f"exclusion control: with NO entries adjusted {bare['adjusted']} differs from "
                     f"raw {bare['raw']} (problems {bare['problems']})")
    for decision, dl_moved in ((True, 1), (False, 0), (None, 0)):
        r = apply(cells, registry(decision, owner), start, end)
        moved = {k: r["raw"].get(k, 0) - r["adjusted"].get(k, 0) for k in expected_raw}
        want = dict(exact, dl=dl_moved, dl_macOS=dl_moved)
        if r["raw"] != expected_raw or moved != want or r["problems"]:
            fails.append(f"exclusion control: decision {decision!r} moved the figures by {moved}, "
                         f"expected exactly {want} (problems {r['problems']})")
    alone = apply(cells, registry(True, owner[:1]), start, end)
    if alone["adjusted_territory"] != {"CN": 1} or alone["adjusted"]["net"] != 1:
        fails.append(f"exclusion control: the owner's purchase alone should leave territory "
                     f"{{'CN': 1}} and net 1, got {alone['adjusted_territory']} and net "
                     f"{alone['adjusted']['net']}")
    # (entry, the adjusted figures it must leave): an orphan US purchase takes nothing; a claim of 3
    # on the JP cell that holds 2 takes the 2 and not the CN customer's unit; a refund entry on a day
    # with no refund row takes nothing from the real refund on the next day.
    for orphan, want in ((entry("c-orphan", "purchase", "2026-01-02", "US", "FI1"),
                          {"buy": 3, "buy_macOS": 2, "refund": 1}),
                         (entry("c-overclaim", "purchase", "2026-01-02", "JP", "FI1", units=3),
                          {"buy": 1, "buy_macOS": 0, "refund": 1}),
                         (entry("c-refund-orphan", "refund", "2026-01-02", "JP", "FI1"),
                          {"buy": 3, "buy_macOS": 2, "refund": 1})):
        r = apply(cells, registry(True, [orphan]), start, end)
        if not r["problems"]:
            fails.append(f"exclusion control: entry {orphan['id']} claims units its cell does not "
                         f"hold and nothing was reported — it would be subtracted from a number "
                         f"that never contained it")
        got = {k: r["adjusted"].get(k) for k in want}
        if got != want:
            fails.append(f"exclusion control: entry {orphan['id']} left adjusted {got}, expected "
                         f"{want} — it subtracted units its cell does not hold")
    return fails


def calibrate(per_day, seen_codes, unclassified):
    """Prove the instrument responds to known-positive events. Returns list of failures."""
    fails = purchase_path_control()
    fails += exclusion_control()
    for key in per_day:
        if per_day[key].get("proceeds_sign_conflict"):
            fails.append(
                f"{key}: a purchase row carries NEGATIVE Developer Proceeds, which this "
                f"classifier assumed impossible. Every proceeds figure from this run is "
                f"suspect — read the raw TSV before quoting money.")
        if per_day[key].get("proceeds_unparsed"):
            fails.append(f"{key}: a purchase row's Developer Proceeds could not be parsed")
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


def report_calibration(per_day, seen_codes, unclassified, heading="calibration:"):
    """`calibrate`, printed the way `--calibrate` prints it. Returns the failures."""
    print(heading)
    fails = calibrate(per_day, seen_codes, unclassified)
    for f in fails:
        print(f"  CALIBRATION-FAIL: {f}")
    if not fails:
        print("  OK — the instrument responds to known-positive events.")
    return fails


FULL_WINDOW_CALIBRATION = "calibration (the full default window — every check --calibrate runs):"


def _day_keys(start, end):
    day = start
    while day <= end:
        yield day.isoformat()
        day += dt.timedelta(days=1)


def _states_line(per_day, keys):
    states = defaultdict(int)
    for key in keys:
        states[per_day[key]["_state"] if key in per_day else "missing"] += 1
    return " · ".join(f"{k}={v}" for k, v in sorted(states.items()))


def _registry_label():
    path = Path(REGISTRY_PATH)
    try:
        return str(path.resolve().relative_to(Path(__file__).resolve().parent.parent))
    except ValueError:
        return str(path)


def _refuse_registry(mode, problems):
    print(f"{mode}: REGISTRY-INVALID — {_registry_label()} has {len(problems)} problem(s), "
          f"so nothing is subtracted, matched or bounded:")
    for p in problems:
        print(f"  - {p}")
    return 4


def _plural(n, one, many):
    return one if n == 1 else many


def _json_word(value):
    return json.dumps(value)


def run_checkpoint(registry, fetch, newest, until=None, daily=False):
    """§K's cohort readout. `fetch(start, end, use_cache) -> days` is injected. Returns the exit code."""
    problems = validate_registry(registry)
    if problems:
        return _refuse_registry("--checkpoint", problems)
    decisions = registry["decisions"]
    print(f"checkpoint — PLAN-STAGE1 §K, day 0 = {DAY0}")
    print(f"  registry {_registry_label()} · schema {registry['schema']} · "
          f"{len(registry['entries'])} {_plural(len(registry['entries']), 'entry', 'entries')}")
    print("  decisions: " + " · ".join(f"{k}={_json_word(decisions[k])}" for k in REGISTRY_DECISIONS))
    print("    (exclude_owner_refund_from_refund_ceiling is echoed, never applied: nothing here "
          "evaluates the day-180 refund ceiling)")

    end = min(until, newest) if until else newest
    days = fetch(LAUNCH_DATE, end, True)
    per_day, seen_codes, unclassified, *_rest = tally(days)
    print(f"window {LAUNCH_DATE} .. {end}  ({(end - LAUNCH_DATE).days + 1} days)")
    print(f"  report states: {_states_line(per_day, _day_keys(LAUNCH_DATE, end))}")
    fails = report_calibration(per_day, seen_codes, unclassified, FULL_WINDOW_CALIBRATION)

    cells, _codes = cell_tally(days)
    c = apply_registry(cells, registry, DAY0, end)
    raw, adj = c["raw"], c["adjusted"]
    cohort_keys = list(_day_keys(DAY0, end))
    print(f"cohort since day 0: {DAY0} .. {end}  ({len(cohort_keys)} days · report states: "
          f"{_states_line(per_day, cohort_keys) or 'none'})")

    # §K: "the true day 0 is 09-08 or 09-09, never later". N is independent of that ambiguity only
    # while the eve has no first-time downloads — true in the cache today, printed so it is SEEN if
    # a refetch ever changes it, rather than assumed forever.
    eve = (DAY0 - dt.timedelta(days=1)).isoformat()
    eve_state = per_day[eve]["_state"] if eve in per_day else "not fetched"
    eve_dl = sum(u for (d, k, _p, _c), u in cells.items() if d == eve and k == "first_download")
    if eve_state not in ("data", "nosales"):
        print(f"  ⚠️  {eve} report {eve_state}: whether N depends on §K's 09-08/09-09 day 0 is "
              f"unknown until it is read")
    elif eve_dl == 0:
        print(f"  {eve} first-time downloads (F1/1F): 0 — N is the same whether day 0 is 09-08 "
              f"or 09-09")
    else:
        print(f"  ⚠️  {eve} first-time downloads (F1/1F): {eve_dl} — N counts from {DAY0}; had "
              f"day 0 been {eve}, N would be {adj['dl'] + eve_dl}")

    print(f"  FIRST-TIME DOWNLOADS  raw {raw['dl']} (macOS {raw['dl_macOS']} · iOS {raw['dl_iOS']})")
    walk, walk_units, decision = c["walk_installs"], c["walk_install_units"], c["decision"]
    if walk:
        how = {True: "SUBTRACTED (decision true)", False: "not subtracted (decision false)",
               None: "NOT subtracted — decision null, the owner has not decided"}[decision]
        print(f"    registered walk first_download: {len(walk)} "
              f"{_plural(len(walk), 'entry', 'entries')} · {walk_units} unit(s) · {how}")
    else:
        print("    registered walk first_download: none in the cohort window")
    undecided = walk_units if (walk and decision is None) else 0
    # Decision true, but some registered walk units are not in the cell the registry names: they were
    # not subtracted (a cell gives up only what it holds), yet the owner's install is still somewhere
    # in N. So N is a ceiling, not a count, until the registry and the report agree.
    unlocated = c["walk_install_units_unheld"] if decision is True else 0
    print(f"  N = {adj['dl']} (macOS {adj['dl_macOS']} · iOS {adj['dl_iOS']})  first-time downloads "
          f"F1+1F since {DAY0}"
          + (f", UNADJUSTED — {undecided} undecided walk unit(s) inside it" if undecided else "")
          + (f", NOT SETTLED — {unlocated} registered walk unit(s) are not in the cell the registry "
             f"names, so they were not subtracted (see BOUND WITHHELD)" if unlocated else ""))

    # A purchase or refund entry the report does not hold makes every adjusted purchase figure a
    # number about the registry rather than the report, so none is printed — a figure with a caveat
    # is quoted without it.
    purchases_disagree = bool(c["problem_kinds"] & {"purchase", "refund"})
    reg_buy = sum(x["units"] for x in c["in_window"] if x["kind"] == "purchase")
    reg_refund = sum(x["units"] for x in c["in_window"] if x["kind"] == "refund")
    print(f"  PURCHASES  raw gross {raw['buy']} (macOS {raw['buy_macOS']} · iOS {raw['buy_iOS']}) "
          f"· refunded {raw['refund']} · net {raw['net']}")
    print(f"    registered, always subtracted (§K: \"exclude it from the cohort\"): purchase "
          f"{reg_buy} · refund {reg_refund}"
          + (" — each only up to the units its cell holds" if purchases_disagree else ""))
    if purchases_disagree:
        print("  ADJUSTED PURCHASES  NOT PRINTED — the registry claims purchase or refund units the "
              "report does not hold (listed under BOUND WITHHELD); a figure adjusted by entries the "
              "report contradicts is not a count")
    else:
        print(f"  ADJUSTED PURCHASES  gross {adj['buy']} (macOS {adj['buy_macOS']} · iOS "
              f"{adj['buy_iOS']}) · refunded {adj['refund']} · net {adj['net']}")
        if c["adjusted_territory"]:
            print("    adjusted purchase territory: " + ", ".join(
                f"{k}={v}" for k, v in sorted(c["adjusted_territory"].items(), key=lambda x: -x[1])))

    in_window_ids = {x["id"] for x in c["in_window"]}
    if registry["entries"]:
        print("  registry entries:")
        for x in registry["entries"]:
            if x["id"] not in in_window_ids:
                effect = f"outside the cohort window {DAY0} .. {end}, not subtracted"
            elif _entry_cell(x) in c["short_cells"]:
                # What is subtracted still depends on the kind and, for a walk install, on the
                # owner's decision: a short cell withholds the bound, it does not start a subtraction
                # the decision never allowed (review 2026-09-16).
                if x["kind"] == "first_download" and decision is not True:
                    subtracted = ("nothing is subtracted from N (decision false)" if decision is False
                                  else "nothing is subtracted from N (decision pending)")
                else:
                    subtracted = "only what the cell holds is subtracted"
                effect = (f"its cell holds fewer units than the registry claims there — {subtracted}, "
                          f"and the bound is withheld")
            elif x["kind"] in ("purchase", "refund"):
                effect = "subtracted from the purchase numerator"
            elif x["kind"] == "redownload":
                effect = "listed, never subtracted (feeds no §K number)"
            else:
                effect = {True: "subtracted from N", False: "counted in N (decision false)",
                          None: "counted in N, decision pending"}[decision]
            print(f"    {x['id']}  {x['kind']} {x['platform']} {x['country_code']} units={x['units']} "
                  f"report day {x['report_day_pt']} status={x['status']} — {effect}")
    else:
        print("  registry entries: none")
    for note in c["notes"]:
        print(f"  note: {note}")

    if daily:
        for d in cohort_keys:
            if d in per_day and per_day[d]["_state"] == "data":
                p = per_day[d]
                print(f"    {d}  dl={p['dl']:3} (mac {p['dl_macOS']:2} ios {p['dl_iOS']:2})  "
                      f"buy={p['buy']} refund={p['refund']}  (raw)")
            else:
                print(f"    {d}  {per_day[d]['_state'] if d in per_day else 'missing'}")

    # Which pre-registered rows are reached. With an undecided walk install the answer can depend on
    # the decision; that is printed as UNDECIDED rather than resolved in either direction.
    n_high, n_low = adj["dl"], adj["dl"] - undecided - unlocated

    def by_n(threshold):
        if n_low >= threshold:
            return "REACHED"
        return "UNDECIDED" if n_high >= threshold else "not reached"

    print("pre-registered checkpoints (§K, quoted):")
    for threshold, text in CHECKPOINT_N:
        print(f"  {by_n(threshold):11}  N = {threshold:<4} {text}")
    print(f"  {'REACHED' if end >= INTERIM_DATE else 'not reached':11}  {INTERIM_DATE} (day 90)  "
          f"interim record, no decision attached — a dated waypoint regardless of N")
    print(f"  {'REACHED' if end >= BACKSTOP_DATE else by_n(DECISION_N):11}  N = {DECISION_N}, or "
          f"{BACKSTOP_DATE} (day 180), whichever comes first  the go / iterate / stop decision")
    print(f"  {'REACHED' if end >= BACKSTOP_DATE else 'not reached':11}  {BACKSTOP_DATE} (day 180)  "
          f"refunds")
    print(f"  (read at N = {n_high}" + (f", or {n_low} if the undecided walk units are subtracted"
                                        if undecided else
                                        f", or {n_low} if the registered walk units the report does "
                                        f"not hold where the registry says are in N elsewhere"
                                        if unlocated else "")
          + f", with {end} the newest report day read)")

    reasons = []
    if fails:
        reasons.append("calibration failed — see CALIBRATION-FAIL above; no number from this run "
                       "can be trusted")
    if not any(x["kind"] == "purchase" and x["status"] == "matched" for x in c["in_window"]):
        elsewhere = [x["id"] for x in registry["entries"] if x["id"] not in in_window_ids
                     and x["kind"] == "purchase" and x["status"] == "matched"]
        reasons.append("no matched day-0 known-positive purchase: the registry holds no "
                       "kind=purchase entry with status=matched in the cohort window"
                       + (f" ({', '.join(elsewhere)} reports outside {DAY0} .. {end})"
                          if elsewhere else "")
                       + " — §K: \"this project does not trust an instrument that has not fired\"")
    if undecided:
        reasons.append(f"owner decision pending: decisions.exclude_walk_first_downloads_from_N is "
                       f"null while the cohort window holds {len(walk)} first_download "
                       f"{_plural(len(walk), 'entry', 'entries')} ({walk_units} unit(s)), so N is "
                       f"not settled")
    for p in c["problems"]:
        reasons.append(f"the registry and the report disagree — {p}")
    unbuilt = [d for d in cohort_keys
               if d not in per_day or per_day[d]["_state"] not in ("data", "nosales")]
    if unbuilt:
        reasons.append(f"{len(unbuilt)} cohort report day(s) not built: {', '.join(unbuilt)} — a "
                       f"purchase on a day not yet read is indistinguishable from none")
    if adj["net"] < 0 and not purchases_disagree:
        reasons.append(f"adjusted net purchases is {adj['net']}: more refunds than purchases in the "
                       f"window, so the numerator is not a count")
    if adj["dl"] <= 0:
        reasons.append(f"N = {adj['dl']}: 3/N is undefined")

    if reasons:
        print("BOUND WITHHELD:")
        for r in reasons:
            print(f"  - {r}")
        if adj["net"] > 0 and not purchases_disagree:
            print(f"  (and the zero-purchase bound would not apply anyway: adjusted net purchases "
                  f"= {adj['net']})")
        return 4 if fails else 5
    if adj["net"] != 0:
        print(f"ZERO-PURCHASE BOUND DOES NOT APPLY: adjusted net purchases = {adj['net']} since {DAY0}")
        return 0
    n = adj["dl"]
    which = ("walk installs subtracted, decision true" if walk and decision is True
             else "walk installs counted, decision false" if walk
             else "no walk installs registered in the window")
    print(f"BOUND (rule of three, 95%) — zero adjusted net purchases in N = {n} first-time downloads "
          f"(F1+1F) since {DAY0}, {which}:")
    print(f"  per-install conversion ≥ 3/{n} = {300 / n:.2f}% is ruled out")
    print(f"  against the ceiling denominator N + {LEGACY_BASE} = {n + LEGACY_BASE}: "
          f"≥ 3/{n + LEGACY_BASE} = {300 / (n + LEGACY_BASE):.2f}%")
    return 0


DRAFT_LABEL = "DRAFT — not recorded; the owner confirms"


def _describe_row(day, kind, platform, row):
    return (f"{day}  {row['pti']} → {kind}{'/' + platform if platform else ''}  units={row['units']}  "
            f"country={row['country']}  device={row['device']}  version={row['version']}  "
            f"price={row['price']} {row['price_currency']}  "
            f"proceeds={row['proceeds']} {row['proceeds_currency']}").rstrip()


def run_confirm(registry, fetch, newest, kind, at, platform, country, today=None):
    """Find the owner's purchase or refund in its Pacific report day. Never writes the registry.

    `fetch(start, end, use_cache) -> days` is injected so the whole mode runs without a network.
    Returns the exit code.
    """
    problems = validate_registry(registry)
    if problems:
        return _refuse_registry("--confirm-known-positive", problems)
    today = today or pacific_today()
    day = pacific_report_day(at)
    D = day.isoformat()
    print(f"confirm-known-positive — kind={kind} · at={at} · platform={platform} · country={country}")
    print(f"  Pacific report day D = {D}  (the America/Los_Angeles date of {at})")
    if day > newest:
        print(f"PENDING: the {D} report cannot exist yet — the newest report day now is {newest}. "
              f"Re-run once it is published.")
        return 6

    lo, hi = day - dt.timedelta(days=1), min(day + dt.timedelta(days=1), newest)
    near = fetch(lo, hi, False)                 # D-1..D+1, never from the cache
    print("  refetched with no cache:")
    for key in _day_keys(lo, day + dt.timedelta(days=1)):
        state = (near[key][0] if key in near else "missing") if key <= hi.isoformat() \
            else "not published yet — not fetched"
        print(f"    {key}  {state}")
    if (near[D][0] if D in near else "missing") not in ("data", "nosales"):
        print(f"PENDING: Apple has not built the {D} report yet. Re-run later.")
        return 6

    buys, odd = [], []
    rows_by_cell = defaultdict(list)
    for key in sorted(near):
        state, payload = near[key]
        if state != "data":
            continue
        for row in our_rows(payload):
            k, p = classify_row(row["pti"], row["units"])
            rows_by_cell[(key, k, p, row["country"])].append(row)
            if k in ("purchase", "refund"):
                buys.append(_describe_row(key, k, p, row))
            elif k == "unclassified":
                odd.append(_describe_row(key, k, p, row))
    print(f"  purchase-class rows on {lo} .. {hi}: {len(buys) or 'none'}")
    for line in buys:
        print(f"    {line}")
    print(f"  UNCLASSIFIED rows on {lo} .. {hi}: {len(odd) or 'none'}")
    for line in odd:
        print(f"    UNCLASSIFIED {line}")
    if odd:
        print("    (a product type code this classifier does not know. If one of these is the "
              "owner's purchase, its code is not in PURCHASE — calibration below fails on it)")

    cells, codes = cell_tally(near)
    cell = (D, kind, platform, country)
    held = cells.get(cell, 0)
    cell_codes = sorted(codes.get(cell, ()))
    if held > 0:
        print(f"  MATCH on {D}: {kind} · {platform} · {country} holds {held} unit(s), "
              f"code {' + '.join(cell_codes)}")
        if held > 1:
            print(f"  WARNING: the matched cell holds {held} units and the owner's {kind} is 1 — a "
                  f"customer's {kind} in the same day · platform · country cell is "
                  f"indistinguishable from the owner's in this report")
        already = sum(x["units"] for x in registry["entries"]
                      if (x["report_day_pt"], x["kind"], x["platform"], x["country_code"]) == cell)
        if already:
            print(f"  note: the registry already holds {already} unit(s) for this cell")
    else:
        print(f"  no {kind} units for {platform} · {country} on {D}")
        for other in (lo.isoformat(), (day + dt.timedelta(days=1)).isoformat()):
            n = cells.get((other, kind, platform, country), 0)
            if n > 0:
                print(f"  note: {other} (not D) holds {n} {kind} unit(s) for {platform} · {country} — "
                      f"check --at and its offset; this is NOT a match")
    # The same day, kind and country under the OTHER platform's code. This is where a Mac purchase
    # lands if Apple reports it under a code PURCHASE maps to iOS — the very mapping the owner's
    # known-positive exists to test — and there "no matching row" alone reads as "nothing was
    # bought", with flipping --platform the obvious-looking fix that records the wrong platform.
    other_platform = next(p for p in REGISTRY_PLATFORMS if p != platform)
    other_cell = (D, kind, other_platform, country)
    other_held = cells.get(other_cell, 0) if held <= 0 else 0
    if other_held > 0:
        print(f"  NOT A MATCH: the {D} report holds {other_held} {kind} unit(s) for {other_platform} · "
              f"{country} — rows whose code PURCHASE maps to {other_platform}:")
        for row in rows_by_cell[other_cell]:
            read_as = DEVICE_PLATFORM.get(row["device"], "no platform this tool reads")
            print(f"    {_describe_row(D, kind, other_platform, row)}  (Device {row['device']!r} → {read_as})")
        print(f"    --platform says where the owner bought, which the owner knows first-hand. If it is "
              f"right and one of these rows is that {kind}, what is in question is PURCHASE's "
              f"platform map, not --platform. Re-running with --platform {other_platform} to get a "
              f"match is the wrong response: it would draft a record saying a {platform} {kind} "
              f"happened on {other_platform}. A customer's {other_platform} {kind} in the same cell "
              f"looks exactly like this; the Device column is the only hint.")

    full = dict(fetch(LAUNCH_DATE, newest, True))
    full.update(near)                           # calibrate on exactly the report just refetched
    per_day, seen_codes, unclassified, *_rest = tally(full)
    print(f"window {LAUNCH_DATE} .. {newest}  ({(newest - LAUNCH_DATE).days + 1} days)")
    print(f"  report states: {_states_line(per_day, _day_keys(LAUNCH_DATE, newest))}")
    fails = report_calibration(per_day, seen_codes, unclassified, FULL_WINDOW_CALIBRATION)
    if fails:
        print("NOT CONFIRMED: calibration failed, and a match — or its absence — read by an instrument "
              "that fails calibration is not evidence.")
        return 4
    if held <= 0:
        if other_held > 0:
            print(f"NO MATCHING ROW for {platform} · {country}: the {D} report holds no {kind} units under "
                  f"a code PURCHASE maps to {platform}, and {other_held} under a code it maps to "
                  f"{other_platform} (listed above). That is NOT a match, and not a typo to fix by "
                  f"re-running with --platform {other_platform}: the question is PURCHASE's platform map.")
        else:
            print(f"NO MATCHING ROW: the {D} report holds no {kind} units for {platform} · {country}.")
        return 7

    code = cell_codes[0] if len(cell_codes) == 1 else None
    if code is None:
        print(f"  WARNING: the cell carries {len(cell_codes)} product type codes; the draft leaves "
              f"matched_product_type null and it will not validate until the owner picks one")
    # The draft's platform is PURCHASE's reading of the code. Where the Device column says otherwise,
    # the draft would record the map's answer as if it were the device's, so it says so on its face.
    devices = sorted({row["device"] for row in rows_by_cell[cell]})
    device_word = ", ".join(d or "(empty)" for d in devices)
    device_warnings = []
    for device in devices:
        read_as = DEVICE_PLATFORM.get(device)
        if read_as is None:
            device_warnings.append(
                f"a matched row's Device is {device!r}, which this tool does not read as a platform "
                f"({', '.join(f'{d} → {p}' for d, p in DEVICE_PLATFORM.items())}), so the draft's "
                f"platform {platform} — PURCHASE's reading of {' + '.join(cell_codes)} — is not "
                f"cross-checked against the device")
        elif read_as != platform:
            device_warnings.append(
                f"a matched row's Device is {device!r} ({read_as}), which contradicts --platform "
                f"{platform}: the draft's platform is PURCHASE's reading of {' + '.join(cell_codes)}, "
                f"not the device's, and this report cannot say which one is the platform of the "
                f"{kind} — the owner knows where they bought; do not record it until that is resolved")
    ids = {x["id"] for x in registry["entries"]}
    eid, suffix = f"{kind}-{D}-{platform}-{country}", 1
    while eid in ids:
        suffix += 1
        eid = f"{kind}-{D}-{platform}-{country}-{suffix}"
    entry = {"id": eid, "kind": kind, "report_day_pt": D, "platform": platform,
             "country_code": country, "units": 1, "status": "matched",
             "matched_product_type": code, "local_timestamp": at,
             "walk_step": "OWNER FILLS IN: the walk step this served",
             "evidence": [],
             "notes": f"drafted by sales_report.py --confirm-known-positive on {today} (Pacific); "
                      f"the matched cell held {held} unit(s); Device column: {device_word}"
                      + "".join(f"; WARNING: {w}" for w in device_warnings)}
    shown = f"{code or '?'} units={'-' if kind == 'refund' else ''}{held}"
    # "reported for", never "made on": the platform in this sentence is the code map's reading.
    reported = (f"It appears in the {D} (Pacific) daily sales report as {shown}, storefront {country} — "
                f"reported for {platform}, the platform PURCHASE maps that code to; Device column: "
                f"{device_word}. The full-window calibration ({LAUNCH_DATE} .. {newest}) passed on "
                f"{today} (Pacific).")
    to_register = f"To be registered as `{eid}` in docs/measurements/stage1-known-positives.json"
    if kind == "purchase":
        sentence = (f"Known-positive purchase for §K's day-0 step: made {at}, {lateness(at)}. "
                    f"{reported} {to_register}; once registered it is excluded from the cohort.")
    else:
        bought = [x for x in registry["entries"] if x["kind"] == "purchase" and x["status"] == "matched"
                  and x["platform"] == platform and x["country_code"] == country]
        if len(bought) == 1:
            of = (f"the purchase registered as `{bought[0]['id']}`, made {bought[0]['local_timestamp']}, "
                  f"{lateness(bought[0]['local_timestamp'])}")
        elif bought:
            of = (f"one of the {len(bought)} matched purchases registered for {platform} · {country} "
                  f"({', '.join(x['id'] for x in bought)}) — the owner says which")
        else:
            of = (f"which purchase is not recorded yet: the registry holds no matched purchase entry "
                  f"for {platform} · {country}")
        sentence = (f"Refund of the known-positive purchase for §K's day-0 step ({of}); refund time "
                    f"given as {at}. {reported} {to_register}; once registered it is excluded from the "
                    f"purchase numerator together with its purchase.")
    for w in device_warnings:
        print(f"WARNING: {w}")
    print(f"{DRAFT_LABEL}. Registry entry:")
    print(json.dumps(entry, indent=2, ensure_ascii=False))
    print(f"{DRAFT_LABEL}. §K sentence:")
    print(f"  {sentence}")
    return 0


def _fetcher(vendor):
    """A `fetch` over the real API that mints its token on first use, not at construction."""
    token = []

    def fetch(start, end, use_cache):
        if not token:
            token.append(make_jwt())
        return collect(token[0], vendor, start, end, use_cache=use_cache)
    return fetch


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vendor")
    ap.add_argument("--since", default=None, help=f"default {LAUNCH_DATE}")
    ap.add_argument("--until", default=None)
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--calibrate", action="store_true",
                    help="run the positive control and exit non-zero if it fails")
    ap.add_argument("--json", help="write the tally to this path")
    ap.add_argument("--daily", action="store_true", help="print the per-day series")
    ap.add_argument("--checkpoint", action="store_true",
                    help="§K's cohort since day 0 with the known-positive registry applied; prints "
                         "the rule-of-three bound only when every condition holds")
    ap.add_argument("--confirm-known-positive", action="store_true",
                    help="find the owner's purchase/refund in its Pacific report day and print a "
                         "DRAFT registry entry (never written)")
    ap.add_argument("--kind", choices=("purchase", "refund"))
    ap.add_argument("--at", help="ISO-8601 with an explicit offset, e.g. 2026-09-17T10:00:00+09:00")
    ap.add_argument("--platform", choices=REGISTRY_PLATFORMS)
    ap.add_argument("--country", help="the report's 2-letter uppercase country code (JP, CN, US)")
    args = ap.parse_args(argv)

    confirm_flags = (("--kind", args.kind), ("--at", args.at), ("--platform", args.platform),
                     ("--country", args.country))
    mode = ("--checkpoint" if args.checkpoint
            else "--confirm-known-positive" if args.confirm_known_positive else None)
    if args.checkpoint and args.confirm_known_positive:
        ap.error("--checkpoint and --confirm-known-positive are separate modes")
    stray = [flag for flag, value in confirm_flags if value is not None]
    if stray and not args.confirm_known_positive:
        ap.error(f"{', '.join(stray)} only apply to --confirm-known-positive")
    registry = None
    if mode:
        clash = [flag for flag, on in (("--calibrate", args.calibrate), ("--json", args.json),
                                       ("--no-cache", args.no_cache), ("--since", args.since))
                 if on]
        if args.confirm_known_positive:
            clash += [flag for flag, on in (("--until", args.until), ("--daily", args.daily)) if on]
        if clash:
            ap.error(f"{mode} does not take {', '.join(clash)} — it reads the full default window "
                     f"and runs the calibration itself")
        if args.confirm_known_positive:
            missing = [flag for flag, value in confirm_flags if value is None]
            if missing:
                ap.error(f"--confirm-known-positive needs {', '.join(missing)}")
            if not re.fullmatch(r"[A-Z]{2}", args.country):
                ap.error(f"--country must be the report's 2-letter uppercase code (JP, CN, US), "
                         f"got {args.country!r}")
            try:
                pacific_report_day(args.at)
            except ValueError as e:
                ap.error(f"--at: {e}")
        registry, problems = load_registry(REGISTRY_PATH)
        if problems:
            return _refuse_registry(mode, problems)

    vendor = resolve_vendor_number(args.vendor)
    if not vendor:
        print("VENDOR-NUMBER-MISSING: put it in ~/Documents/credits.md on a line "
              "containing 'vendor' (ASC → Business, under the legal entity name).")
        return 2

    # Daily reports cut on Pacific time and materialise the next morning.
    newest = pacific_today() - dt.timedelta(days=1)
    if mode:
        fetch = _fetcher(vendor)
        try:
            if args.checkpoint:
                until = dt.date.fromisoformat(args.until) if args.until else None
                return run_checkpoint(registry, fetch, newest, until=until, daily=args.daily)
            return run_confirm(registry, fetch, newest, args.kind, args.at, args.platform,
                               args.country)
        except RuntimeError as e:
            print(f"API-FAILURE: {e}")
            return 3
    start = dt.date.fromisoformat(args.since or LAUNCH_DATE.isoformat())
    end = min(dt.date.fromisoformat(args.until), newest) if args.until else newest

    try:
        days = collect(make_jwt(), vendor, start, end, use_cache=not args.no_cache)
    except RuntimeError as e:
        print(f"API-FAILURE: {e}")
        return 3

    per_day, seen_codes, unclassified, terr, platforms, buy_terr, proceeds = tally(days)
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

    # Stage 1's numerator. Printed unconditionally, including the zero: "no purchase rows yet"
    # and "the classifier no longer recognises purchase rows" must not look the same, and the
    # only thing separating them is that `--calibrate` drives a synthetic sale through the
    # same code every run.
    buy = sum(per_day[d]["buy"] for d in per_day)
    buy_mac = sum(per_day[d]["buy_macOS"] for d in per_day)
    buy_ios = sum(per_day[d]["buy_iOS"] for d in per_day)
    refunds = sum(per_day[d]["refund"] for d in per_day)
    print(f"  PURCHASES  gross {buy} (macOS {buy_mac} · iOS {buy_ios}) · refunded {refunds} "
          f"· net {buy - refunds} · proceeds {proceeds:.2f}")
    if buy_terr:
        print("  purchase territory: "
              + ", ".join(f"{k}={v}" for k, v in sorted(buy_terr.items(), key=lambda x: -x[1])))
    if buy == 0:
        print("    (zero is a RESULT only if calibration passed — see --calibrate)")
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
        if report_calibration(per_day, seen_codes, unclassified):
            rc = 4

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
            "purchases": {"gross": buy, "macOS": buy_mac, "iOS": buy_ios,
                          "refunded": refunds, "net": buy - refunds,
                          "developer_proceeds": round(proceeds, 2)},
            "territory_purchases": dict(sorted(buy_terr.items(), key=lambda x: -x[1])),
            "daily": {d: {"dl": per_day[d]["dl"], "dl_macOS": per_day[d]["dl_macOS"],
                          "dl_iOS": per_day[d]["dl_iOS"], "upd": per_day[d]["upd"],
                          "buy": per_day[d]["buy"], "refund": per_day[d]["refund"]}
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
