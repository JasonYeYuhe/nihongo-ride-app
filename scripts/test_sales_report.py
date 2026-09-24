#!/usr/bin/env python3
"""`sales_report.py`'s Stage 1 additions must do what the contract says, and every guard must fire.

WHAT IS UNDER TEST. The money instrument grew four things at once — a known-positive registry, a
`--checkpoint` readout that may print §K's rule-of-three bound, a `--confirm-known-positive` mode that
finds the owner's own purchase in Apple's report, and an exclusion control inside every
`--calibrate`. Each of them can fail in the one way this project keeps paying for: by printing the
same words as the version that works. A bound printed from an unproven instrument reads exactly like
a bound; a subtraction that subtracts nothing reads exactly like no owner rows; a classifier that
disagrees with itself reads exactly like two correct totals.

SO EVERY GUARD HERE IS PAIRED. Each withholding reason is tested against a baseline that PRINTS the
bound with one variable changed, so a reason that fires on everything and a reason that fires on
nothing both go red. The comparators are themselves controlled: the classification differential
is run against a deliberately divergent cell tally and must report it; the exclusion control is run
against broken subtractions and must fail; the write scanner is run on a planted write and must see it.

No network, no cache, no vendor number, no `jwt`: every report is synthetic, in Apple's TSV shape,
and driven through the real `our_rows` / `classify_row` / `tally` / `cell_tally`.

    python3 scripts/test_sales_report.py
"""
import ast
import contextlib
import datetime as dt
import io
import json
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import sales_report as sr                                      # noqa: E402

JWT_IMPORTED_AT_LOAD = "jwt" in sys.modules
D = dt.date
NEWEST = D(2026, 9, 20)


# ---------------------------------------------------------------------------------------------------
# synthetic reports

def report_row(pti, units, country, route="app", proceeds="0", price="0", currency="JPY", device="Desktop",
               version="1.32"):
    """One row in `_CONTROL_HEADER`'s shape. route: app (Apple Identifier), parent (IAP), other."""
    cells = [""] * 30
    cells[5] = version
    cells[6] = pti
    cells[7] = str(units)
    cells[8] = proceeds
    cells[11] = currency
    cells[12] = country
    cells[13] = currency
    cells[14] = {"app": sr.APP_ID, "parent": "0", "other": "6761163709"}[route]
    cells[15] = price
    cells[17] = sr.APP_SKU if route == "parent" else ""
    cells[24] = device
    cells[25] = "iOS and macOS"
    return "\t".join(cells)


def iap(pti, units, country, device="Desktop"):
    return report_row(pti, units, country, route="parent", proceeds="128", price="150", device=device)


def tsv(*rows):
    return "\n".join((sr._CONTROL_HEADER,) + tuple(rows))


def cohort_extra(first_downloads=None, purchase_day="2026-09-16", add=None):
    """Cohort rows: by default N = 13 (F1 JP on each of 09-09..09-20, 1F CN on 09-10) and the
    owner's FI1 JP purchase on 09-16."""
    extra = defaultdict(list)
    if first_downloads is None:
        for key in sr._day_keys(D(2026, 9, 9), NEWEST):
            extra[key].append(report_row("F1", 1, "JP"))
        extra["2026-09-10"].append(report_row("1F", 1, "CN"))
    else:
        for key, rows in first_downloads.items():
            extra[key] += rows
    if purchase_day:
        extra[purchase_day].append(iap("FI1", 1, "JP"))
    for key, rows in (add or {}).items():
        extra[key] += rows
    return extra


def window(end=NEWEST, extra=None, flat_updates=False, states=None):
    """LAUNCH_DATE..end, shaped so calibration passes: F1/1F/F7 all occur, release days elevated.
    Background downloads stop before 2026-09-08, so the eve and the cohort hold only `extra`.
    Updates are elevated on `RELEASE_DAYS` (calibrate's control) AND on the second release-day
    control's exposure days, so --checkpoint's bound is not withheld by a fixture that only one of the
    two controls was ever asked to read; section E2 builds its own reports for that control."""
    exposure, _uncertain = sr.release_day_groups()
    days = {}
    for key in sr._day_keys(sr.LAUNCH_DATE, end):
        elevated = key in sr.RELEASE_DAYS or key in exposure
        rows = [report_row("F7", 5 if elevated and not flat_updates else 1, "JP"),
                report_row("F1", 9, "US", route="other")]           # another app's row: filtered
        if key < "2026-09-08":
            rows += [report_row("F1", 1, "US"), report_row("1F", 1, "US")]
        rows += (extra or {}).get(key, [])
        days[key] = ("data", tsv(*rows))
    for key, state in (states or {}).items():
        days[key] = (state, "")
    return days


class FakeFetch:
    """`fetch(start, end, use_cache)`. A no-cache call sees `refetched` over the cached days."""

    def __init__(self, cached, refetched=None):
        self.cached, self.refetched, self.calls = cached, refetched or {}, []

    def __call__(self, start, end, use_cache):
        self.calls.append((start, end, use_cache))
        source = self.cached if use_cache else {**self.cached, **self.refetched}
        return {k: source.get(k, ("pending", "")) for k in sr._day_keys(start, end)}


def registry(decision=None, entries=(), refund_decision=None):
    return {"schema": 1, "day0": "2026-09-09",
            "decisions": {"exclude_walk_first_downloads_from_N": decision,
                          "exclude_owner_refund_from_refund_ceiling": refund_decision},
            "entries": [dict(e) for e in entries]}


def entry(eid, kind="purchase", day="2026-09-16", platform="macOS", country="JP", units=1,
          status="matched", code="FI1", stamp="2026-09-17T10:00:00+09:00", evidence=()):
    return {"id": eid, "kind": kind, "report_day_pt": day, "platform": platform,
            "country_code": country, "units": units, "status": status,
            "matched_product_type": code, "local_timestamp": stamp,
            "walk_step": "§K day-0 known-positive", "evidence": list(evidence), "notes": ""}


OWNER_BUY = entry("owner-buy")


def capture(fn, *args, **kwargs):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = fn(*args, **kwargs)
        except SystemExit as e:
            rc = e.code
        except Exception as e:         # reported as a failed exit, so the rest of the suite still runs
            rc = f"EXCEPTION {e!r}"
    return rc, out.getvalue() + err.getvalue()


@contextlib.contextmanager
def patched(**attrs):
    old = {k: getattr(sr, k) for k in attrs}
    for k, v in attrs.items():
        setattr(sr, k, v)
    try:
        yield
    finally:
        for k, v in old.items():
            setattr(sr, k, v)


class Checks:
    def __init__(self):
        self.problems, self.count = [], 0

    def __call__(self, ok, message):
        self.count += 1
        if not ok:
            self.problems.append(message)
        return ok

    def rc_and_text(self, label, got, want_rc, output, must=(), must_not=()):
        self(got == want_rc, f"{label}: exit {got}, expected {want_rc}\n{output}")
        for s in must:
            self(s in output, f"{label}: output lacks {s!r}\n{output}")
        for s in must_not:
            self(s not in output, f"{label}: output carries {s!r}\n{output}")


# ---------------------------------------------------------------------------------------------------
# A. one classification rule

KIND_FIELD = {"first_download": "dl", "update": "upd", "redownload": "redl", "purchase": "buy",
              "refund": "refund", "unclassified": "unclassified"}


def tally_vs_cells(days, cell_fn):
    """Every disagreement between `tally` and a cell tally over the same report."""
    per_day, _seen, _unc, terr, _plat, buy_terr, _proceeds = sr.tally(days)
    cells, _codes = cell_fn(days)
    diffs = []
    agg = defaultdict(lambda: defaultdict(int))
    cell_terr, cell_buy_terr = defaultdict(int), defaultdict(int)
    for (day, kind, platform, country), u in cells.items():
        if kind not in KIND_FIELD:
            diffs.append(f"cell kind {kind!r} is not a kind tally knows")
            continue
        field = KIND_FIELD[kind]
        agg[day][field] += u
        if kind in ("first_download", "purchase"):
            agg[day][f"{field}_{platform}"] += u
        if kind == "first_download":
            cell_terr[country] += u
        if kind in ("purchase", "refund"):
            cell_buy_terr[country] += u if kind == "purchase" else -u
    for day in sorted(set(per_day) | set(agg)):
        if day in per_day and per_day[day]["_state"] != "data":
            if agg.get(day):
                diffs.append(f"{day}: cells hold units for a day tally reads as {per_day[day]['_state']}")
            continue
        for field in ("dl", "dl_macOS", "dl_iOS", "upd", "redl", "buy", "buy_macOS", "buy_iOS",
                      "refund", "unclassified"):
            t = per_day[day][field] if day in per_day else 0
            if t != agg[day][field]:
                diffs.append(f"{day} {field}: tally {t}, cells {agg[day][field]}")
    nz = lambda d: {k: v for k, v in d.items() if v}                   # noqa: E731
    if nz(terr) != nz(cell_terr):
        diffs.append(f"download territory: tally {nz(terr)}, cells {nz(cell_terr)}")
    if nz(buy_terr) != nz(cell_buy_terr):
        diffs.append(f"purchase territory: tally {nz(buy_terr)}, cells {nz(cell_buy_terr)}")
    return diffs


MIXED = {
    "2026-09-01": ("data", tsv(
        report_row("F1", 2, "JP"), report_row("1F", 1, "CN"), report_row("F7", 5, "US"),
        report_row("3F", 1, "JP"), report_row("F3", 2, "DE"),
        iap("IA1", 1, "CN"), iap("IA9", 1, "JP"), iap("FI1", 1, "JP"), iap("FI1", -1, "JP"),
        iap("IA1", 0, "CN"), report_row("XX9", 1, "JP"), iap("IAY", 1, "US"),
        report_row("F1", 7, "US", route="other"))),
    "2026-09-02": ("data", tsv(report_row("F1", -1, "JP"), iap("IA1", -2, "CN"),
                               report_row("1F", 3, "BR"))),
    "2026-09-03": ("pending", ""),
    "2026-09-04": ("nosales", "no sales"),
}


def divergent_cell_tally(days):
    """A second classification rule, as someone might write it inline: F3 read as a download."""
    cells, codes = defaultdict(int), defaultdict(set)
    for key, (state, payload) in sorted(days.items()):
        if state != "data":
            continue
        for row in sr.our_rows(payload):
            kind, platform = sr.classify_row(row["pti"], row["units"])
            if row["pti"] == "F3":
                kind, platform = "first_download", "macOS"
            cell = (key, kind, platform, row["country"])
            cells[cell] += -row["units"] if kind == "refund" else row["units"]
            codes[cell].add(row["pti"])
    return cells, codes


def test_classification(check):
    table = [("F1", 1, ("first_download", "macOS")), ("1F", 1, ("first_download", "iOS")),
             ("F7", 3, ("update", None)), ("3F", 1, ("redownload", None)),
             ("F3", 1, ("redownload", None)), ("IA1", 1, ("purchase", "iOS")),
             ("IA9", 2, ("purchase", "iOS")), ("FI1", 1, ("purchase", "macOS")),
             ("FI1", 0, ("purchase", "macOS")), ("FI1", -1, ("refund", "macOS")),
             ("IA1", -3, ("refund", "iOS")), ("IAY", 1, ("unclassified", None)),
             ("", 1, ("unclassified", None)), ("F1 ", 1, ("unclassified", None))]
    for pti, units, want in table:
        got = sr.classify_row(pti, units)
        check(got == want, f"classify_row({pti!r}, {units}) = {got}, expected {want}")

    cells, _codes = sr.cell_tally(MIXED)
    kinds = {k for (_d, k, _p, _c) in cells}
    check(kinds == set(KIND_FIELD),
          f"the differential's report must exercise every kind, exercised {sorted(kinds)}")
    diffs = tally_vs_cells(MIXED, sr.cell_tally)
    check(not diffs, "tally() and cell_tally() disagree:\n  " + "\n  ".join(diffs))
    diffs = tally_vs_cells(MIXED, divergent_cell_tally)
    check(bool(diffs), "CONTROL: a cell tally with its own F3 rule was not caught by the differential")
    print(f"  classify_row table {len(table)} rows · tally vs cell_tally: {len(diffs)} "
          f"disagreement(s) reported for the planted second rule")

    # Structural: the rule has one home. A `pti in PURCHASE` anywhere else is a second rule.
    source = Path(sr.__file__).read_text(encoding="utf-8")
    tree = ast.parse(source)
    offenders = []
    code_sets = ("DOWNLOAD", "UPDATE", "REDOWNLOAD", "PURCHASE")
    for fn in tree.body:
        if not isinstance(fn, ast.FunctionDef) or fn.name == "classify_row":
            continue
        for node in ast.walk(fn):
            if not (isinstance(node, ast.Compare)
                    and any(isinstance(op, (ast.In, ast.NotIn)) for op in node.ops)
                    and any(isinstance(c, ast.Name) and c.id in code_sets for c in node.comparators)):
                continue
            if "pti" in (ast.get_source_segment(source, node.left) or ""):
                offenders.append(f"{fn.name}:{node.lineno}")    # a ROW's code tested: a second rule
    check(not offenders, f"product-type membership tested outside classify_row: {offenders}")
    for name in ("tally", "cell_tally", "run_confirm"):
        body = ast.get_source_segment(source, next(f for f in tree.body
                                                   if isinstance(f, ast.FunctionDef) and f.name == name))
        check("classify_row(" in body, f"{name} does not call classify_row")


# ---------------------------------------------------------------------------------------------------
# B. Pacific report day

def test_pacific_day(check):
    cases = [
        ("2026-09-17T10:00+09:00", D(2026, 9, 16)),         # 18:00 PDT the day before
        ("2026-09-17T17:00+09:00", D(2026, 9, 17)),         # 01:00 PDT
        ("2026-09-17T16:30:00+09:00", D(2026, 9, 17)),      # 00:30 PDT — would be 09-16 under PST
        ("2026-12-10T16:30:00+09:00", D(2026, 12, 9)),      # PST season: 23:30 PST the day before
        ("2026-12-10T17:00:00+09:00", D(2026, 12, 10)),     # 00:00 PST
        ("2026-09-14T12:00-07:00", D(2026, 9, 14)),
        ("2026-09-15T07:30:00Z", D(2026, 9, 15)),
        ("2026-09-15T06:30:00Z", D(2026, 9, 14)),
        ("2026-09-17T10:00:00.250000+09:00", D(2026, 9, 16)),
        ("2026-11-01T08:30:00Z", D(2026, 11, 1)),           # 01:30 PDT on the day DST ends
        ("2027-03-14T07:59:00Z", D(2027, 3, 13)),           # 23:59 PST, the eve DST starts
    ]
    for stamp, want in cases:
        try:
            got = sr.pacific_report_day(stamp)
        except ValueError as e:
            got = f"ValueError({e})"
        check(got == want, f"pacific_report_day({stamp!r}) = {got}, expected {want}")
    # The winter case discriminates: a fixed UTC−7 reading of it lands on a different day.
    fixed_pdt = dt.datetime.fromisoformat("2026-12-10T16:30:00+09:00").astimezone(
        dt.timezone(dt.timedelta(hours=-7))).date()
    check(fixed_pdt != D(2026, 12, 9), "CONTROL: the PST case does not tell PST from PDT")
    rejects = ["2026-09-17T10:00:00", "2026-09-17", "2026-09-17 10:00:00+09:00",
               "2026-09-17T10:00:00+0900", "2026-09-17T10:00:00+09", "2026-13-17T10:00:00+09:00",
               "2026-09-17T10:00:00+24:00", "", None, 1726534800, "2026-09-17t10:00:00+09:00"]
    for stamp in rejects:
        try:
            got = sr.pacific_report_day(stamp)
            check(False, f"pacific_report_day({stamp!r}) accepted it as {got}")
        except ValueError:
            check(True, "")
    print(f"  {len(cases)} conversions · {len(rejects)} rejections")


# ---------------------------------------------------------------------------------------------------
# C. registry validation

SHA = "0" * 63 + "a"


def valid_registry():
    return registry(True, [
        entry("buy", evidence=[{"file": "receipt.png", "sha256": SHA}]),
        entry("refund", kind="refund", day="2026-09-30", code="FI1"),
        entry("mac-install", kind="first_download", code="F1"),
        entry("ios-install", kind="first_download", platform="iOS", code="1F"),
        entry("ios-redl", kind="redownload", platform="iOS", code="3F"),
        entry("pending", status="awaiting-report", code=None, stamp="2026-09-17T10:00:00Z"),
    ], refund_decision=False)


def live_registry_failures(path):
    """Everything this suite holds against the owner-maintained registry at `path`: that it validates,
    and NOTHING about what it holds. The owner is told to record the walk in that file, so a check that
    pinned its content would turn run_all_gates.sh red on the owner's legitimate record, and the only
    edit that restores green without touching a gate would be deleting that record. Whether any tool
    writes the file is `test_writes`'s question, answered by scanning the source."""
    _obj, problems = sr.load_registry(path)
    return [f"the live registry {path} does not validate: {p}" for p in problems]


def test_registry(check):
    failures = live_registry_failures(sr.REGISTRY_PATH)
    check(not failures, "\n  ".join(failures))
    with tempfile.TemporaryDirectory() as tmp:
        recorded = Path(tmp) / "owner-recorded.json"         # what the walk card has the owner write
        recorded.write_text(json.dumps(valid_registry(), indent=2), encoding="utf-8")
        check(not live_registry_failures(recorded),
              f"CONTROL: an owner's valid record (matched purchase, refund, walk installs, both decisions "
              f"filled) fails the live-registry check, so recording the walk would break the gate: "
              f"{live_registry_failures(recorded)}")
        invalid = Path(tmp) / "owner-typo.json"
        bad = valid_registry()
        bad["entries"][0]["country_code"] = "JPN"
        invalid.write_text(json.dumps(bad), encoding="utf-8")
        check(bool(live_registry_failures(invalid)),
              "CONTROL: an invalid registry passes the live-registry check")
    check(not sr.validate_registry(valid_registry()),
          f"POSITIVE CONTROL: a registry using every kind does not validate: "
          f"{sr.validate_registry(valid_registry())}")

    def set_entry(i, **kv):
        return lambda r: r["entries"][i].update(kv)

    cases = [
        ("kind 'sale'", set_entry(0, kind="sale"), "kind must be"),
        ("platform 'macos'", set_entry(0, platform="macos"), "platform must be"),
        ("status 'done'", set_entry(0, status="done"), "status must be"),
        ("country JPN", set_entry(0, country_code="JPN"), "country_code must be"),
        ("country jp", set_entry(0, country_code="jp"), "country_code must be"),
        ("units 0", set_entry(0, units=0), "units must be"),
        ("units -1", set_entry(0, units=-1), "units must be"),
        ("units 1.0", set_entry(0, units=1.0), "units must be"),
        ("units true", set_entry(0, units=True), "units must be"),
        ("report day 2026/09/16", set_entry(0, report_day_pt="2026/09/16"), "report_day_pt must be"),
        ("report day 2026-09-31", set_entry(0, report_day_pt="2026-09-31"), "report_day_pt must be"),
        ("naive local_timestamp", set_entry(0, local_timestamp="2026-09-17T10:00:00"), "local_timestamp"),
        ("duplicate id", set_entry(1, id="buy"), "duplicate id"),
        ("empty id", set_entry(0, id=""), "id must be"),
        ("unknown decision", lambda r: r["decisions"].update(exclude_everything=True), "unknown decision key"),
        ("decision 'true'", lambda r: r["decisions"].update(exclude_walk_first_downloads_from_N="true"),
         "must be true, false or null"),
        ("decision 1", lambda r: r["decisions"].update(exclude_owner_refund_from_refund_ceiling=1),
         "must be true, false or null"),
        ("decision 0", lambda r: r["decisions"].update(exclude_walk_first_downloads_from_N=0),
         "must be true, false or null"),
        ("missing decision", lambda r: r["decisions"].pop("exclude_owner_refund_from_refund_ceiling"),
         "missing decision"),
        ("unknown entry key", set_entry(0, order_id="MX123"), "unknown key"),
        ("missing entry key", lambda r: r["entries"][0].pop("notes"), "missing key 'notes'"),
        ("schema 2", lambda r: r.update(schema=2), "schema must be 1"),
        ("schema true", lambda r: r.update(schema=True), "schema must be 1"),
        ("day0 09-08", lambda r: r.update(day0="2026-09-08"), "day0 must be"),
        ("unknown top-level", lambda r: r.update(bound="3/N"), "unknown top-level key"),
        ("missing entries", lambda r: r.pop("entries"), "missing top-level key 'entries'"),
        ("entries not a list", lambda r: r.update(entries={}), "entries must be a list"),
        ("matched without code", set_entry(0, matched_product_type=None), "needs its matched_product_type"),
        ("purchase with F1", set_entry(0, matched_product_type="F1"), "is not a purchase code"),
        ("macOS purchase with IA1", set_entry(0, matched_product_type="IA1"), "is not a purchase code"),
        ("iOS install with F1", set_entry(3, matched_product_type="F1"), "is not a first_download code"),
        ("redownload with F7", set_entry(4, matched_product_type="F7"), "is not a redownload code"),
        ("awaiting with code", set_entry(5, matched_product_type="FI1"), "awaiting-report entry cannot"),
        ("bad sha256", set_entry(0, evidence=[{"file": "x.png", "sha256": "ABC"}]), "evidence[0]"),
        ("evidence extra key", set_entry(0, evidence=[{"file": "x", "sha256": SHA, "url": "u"}]),
         "evidence[0]"),
        ("walk_step not str", set_entry(0, walk_step=3), "walk_step must be"),
    ]
    for label, fn, needle in cases:
        reg = valid_registry()
        fn(reg)
        found = sr.validate_registry(reg)
        check(any(needle in p for p in found), f"registry mutation {label!r}: expected a problem "
                                               f"containing {needle!r}, got {found}")
    check(sr.validate_registry([]) and "JSON object" in sr.validate_registry([])[0],
          "a list is accepted as a registry")

    many = valid_registry()
    many["entries"][0].update(kind="sale", country_code="JPN", units=0)
    many["entries"][1].update(local_timestamp="2026-09-30T09:00:00")
    many["decisions"]["exclude_walk_first_downloads_from_N"] = "yes"
    found = sr.validate_registry(many)
    for needle in ("kind must be", "country_code must be", "units must be", "local_timestamp",
                   "must be true, false or null"):
        check(any(needle in p for p in found), f"a five-defect registry did not report {needle!r}: {found}")

    with tempfile.TemporaryDirectory() as tmp:
        dup = Path(tmp) / "dup.json"
        dup.write_text('{"schema": 1, "day0": "2026-09-09", "decisions": '
                       '{"exclude_walk_first_downloads_from_N": true, '
                       '"exclude_walk_first_downloads_from_N": false, '
                       '"exclude_owner_refund_from_refund_ceiling": null}, "entries": []}')
        _obj, found = sr.load_registry(dup)
        check(any("duplicate JSON key" in p for p in found), f"a duplicated JSON key was accepted: {found}")
        broken = Path(tmp) / "broken.json"
        broken.write_text('{"schema": 1,')
        _obj, found = sr.load_registry(broken)
        check(any("not valid JSON" in p for p in found), f"malformed JSON was accepted: {found}")
        _obj, found = sr.load_registry(Path(tmp) / "absent.json")
        check(any("cannot read" in p for p in found), f"a missing registry was accepted: {found}")
    print(f"  {len(cases)} single-defect mutations against a registry that validates")


# ---------------------------------------------------------------------------------------------------
# D. exclusion

def test_exclusion(check):
    fails = sr.exclusion_control()
    check(not fails, f"the exclusion control fails on the shipped code: {fails}")

    def identity(cells, reg, start, end):          # subtracts nothing
        r = sr.apply_registry(cells, reg, start, end)
        r["adjusted"] = dict(r["raw"])
        return r

    def ignores_decision(cells, reg, start, end):  # subtracts walk installs whatever was decided
        forced = json.loads(json.dumps(reg))
        forced["decisions"]["exclude_walk_first_downloads_from_N"] = True
        r = sr.apply_registry(cells, forced, start, end)
        r["decision"] = reg["decisions"]["exclude_walk_first_downloads_from_N"]
        return r

    def silent(cells, reg, start, end):            # never reports an orphan entry
        r = sr.apply_registry(cells, reg, start, end)
        r["problems"] = []
        return r

    def refund_as_purchase(cells, reg, start, end):
        r = sr.apply_registry(cells, reg, start, end)
        for x in r["in_window"]:
            if x["kind"] == "refund":
                r["adjusted"]["refund"] += x["units"]
                r["adjusted"]["buy"] -= x["units"]
        r["adjusted"]["net"] = r["adjusted"]["buy"] - r["adjusted"]["refund"]
        return r

    def uncapped(cells, reg, start, end):          # subtracts every claimed unit, held or not
        r = sr.apply_registry(cells, reg, start, end)
        adj = r["adjusted"] = dict(r["raw"])
        for x in r["in_window"]:
            if x["kind"] == "purchase":
                adj["buy"] -= x["units"]
                adj["buy_" + x["platform"]] -= x["units"]
            elif x["kind"] == "refund":
                adj["refund"] -= x["units"]
            elif x["kind"] == "first_download" and r["decision"] is True:
                adj["dl"] -= x["units"]
                adj["dl_" + x["platform"]] -= x["units"]
        adj["net"] = adj["buy"] - adj["refund"]
        return r

    for broken in (identity, ignores_decision, silent, refund_as_purchase, uncapped):
        check(bool(sr.exclusion_control(apply=broken)),
              f"CONTROL: the exclusion control passed a broken subtraction ({broken.__name__})")

    # A cell gives up at most what it holds; the excess is a problem, never a subtraction.
    one_install = {"2026-09-16": ("data", tsv(report_row("F1", 1, "JP")))}
    cells, _ = sr.cell_tally(one_install)
    window_ = (D(2026, 9, 9), D(2026, 9, 20))
    for label, reg in (
            ("awaiting purchase, no row", registry(None, [entry("b", status="awaiting-report", code=None,
                                                                 day="2026-09-19")])),
            ("awaiting refund, no row", registry(None, [entry("r", kind="refund", status="awaiting-report",
                                                               code=None, day="2026-09-19")])),
            ("walk install, decision true, no row", registry(True, [entry("w", kind="first_download",
                                                                          platform="iOS", code="1F")]))):
        r = sr.apply_registry(cells, reg, *window_)
        check(r["adjusted"] == r["raw"] and r["problems"],
              f"{label}: an entry whose row is not in the report must subtract nothing and be a problem — "
              f"raw {r['raw']} adjusted {r['adjusted']} problems {r['problems']}")
    two_buys, _ = sr.cell_tally({"2026-09-16": ("data", tsv(iap("FI1", 2, "JP"), iap("IA1", 1, "CN")))})
    r = sr.apply_registry(two_buys, registry(None, [entry("b", units=3)]), *window_)
    check(r["adjusted"]["buy"] == 1 and r["adjusted"]["buy_macOS"] == 0
          and r["adjusted_territory"] == {"CN": 1} and r["problems"],
          f"an entry claiming 3 of a cell's 2 units must take the 2 and report the 1: {r}")
    r = sr.apply_registry(two_buys, registry(None, [entry("b", units=2)]), *window_)
    check(r["adjusted"]["buy"] == 1 and r["adjusted_territory"] == {"CN": 1} and not r["problems"],
          f"CONTROL: an entry claiming exactly the cell's 2 units must take both, with no problem: {r}")
    r = sr.apply_registry(two_buys, registry(True, [entry("w", kind="first_download", code="F1")]), *window_)
    check(r["walk_install_units_unheld"] == 1 and r["problem_kinds"] == {"first_download"},
          f"a walk install with no row must count as 1 unheld walk unit: {r}")

    planted = "exclusion control: planted"
    per_day = sr.tally(window(end=D(2026, 9, 1)))[0]
    seen = {"F1": 1, "1F": 1, "F7": 1}
    with patched(exclusion_control=lambda apply=None: [planted]):
        fails, _out = capture(sr.calibrate, per_day, seen, [])
    check(planted in fails, f"calibrate() does not run exclusion_control(): {fails}")
    fails, _out = capture(sr.calibrate, per_day, seen, [])
    check(not any("exclusion" in f for f in fails),
          f"calibrate() reports exclusion failures on the shipped code: {fails}")

    # Semantics the control does not cover: the window edge and redownloads.
    cells, _ = sr.cell_tally({"2026-09-10": ("data", tsv(iap("FI1", 1, "JP"), report_row("3F", 2, "JP"),
                                                         report_row("F1", 1, "JP")))})
    outside = entry("late", day="2026-09-25")
    redl = entry("redl", kind="redownload", day="2026-09-10", platform="iOS", code="3F", units=5)
    r = sr.apply_registry(cells, registry(True, [outside, redl]), D(2026, 9, 9), D(2026, 9, 20))
    check(r["adjusted"] == r["raw"], f"an out-of-window purchase or a redownload changed a number: {r}")
    check(r["notes"] and not r["problems"], f"a redownload claiming 5 of 2 units should be a note only: {r}")


# ---------------------------------------------------------------------------------------------------
# E. --checkpoint

def checkpoint(reg, days, newest=NEWEST, **kw):
    fetch = FakeFetch(days)
    rc, out = capture(sr.run_checkpoint, reg, fetch, newest, **kw)
    return rc, out, fetch


def test_checkpoint(check):
    base = window(extra=cohort_extra())
    rc, out, fetch = checkpoint(registry(None, [OWNER_BUY]), base)
    check.rc_and_text("checkpoint baseline (every condition holds)", rc, 0, out,
                      must=("BOUND (rule of three, 95%)", "N = 13 first-time downloads",
                            "3/13 = 23.08%", "N + 114 = 127", "3/127 = 2.36%",
                            "2026-09-08 first-time downloads (F1/1F): 0 — N is the same",
                            "ADJUSTED PURCHASES  gross 0", "PURCHASES  raw gross 1",
                            "OK — the instrument responds"),
                      must_not=("BOUND WITHHELD",))
    check(fetch.calls == [(sr.LAUNCH_DATE, NEWEST, True)], f"checkpoint fetched {fetch.calls}")

    # Each withholding reason, against the baseline with one thing changed.
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=cohort_extra(), flat_updates=True))
    check.rc_and_text("calibration fails", rc, 4, out,
                      must=("BOUND WITHHELD", "calibration failed", "CALIBRATION-FAIL"),
                      must_not=("BOUND (rule",))

    awaiting = entry("owner-buy", status="awaiting-report", code=None)
    rc, out, _ = checkpoint(registry(None, [awaiting]), base)
    check.rc_and_text("purchase entry awaiting-report", rc, 5, out,
                      must=("no matched day-0 known-positive purchase",), must_not=("BOUND (rule",))
    rc, out, _ = checkpoint(registry(None, []), base)
    check.rc_and_text("no entries at all", rc, 5, out,
                      must=("no matched day-0 known-positive purchase",
                            "would not apply anyway: adjusted net purchases = 1"),
                      must_not=("BOUND (rule",))
    later = entry("owner-buy", day="2026-09-25")
    rc, out, _ = checkpoint(registry(None, [later]), base)
    check.rc_and_text("matched purchase outside the window", rc, 5, out,
                      must=("no matched day-0 known-positive purchase", "owner-buy reports outside"))

    walk = entry("walk-mac", kind="first_download", day="2026-09-12", code="F1")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY, walk]), base)
    check.rc_and_text("walk install, decision null", rc, 5, out,
                      must=("owner decision pending", "UNADJUSTED — 1 undecided walk unit",
                            "N = 13 (macOS 12"), must_not=("BOUND (rule",))
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY, walk]), base)
    check.rc_and_text("walk install, decision true", rc, 0, out,
                      must=("N = 12 first-time downloads", "3/12 = 25.00%", "walk installs subtracted",
                            "3/126 = 2.38%"), must_not=("BOUND WITHHELD", "NOT SETTLED", "NOT PRINTED"))
    rc, out, _ = checkpoint(registry(False, [OWNER_BUY, walk]), base)
    check.rc_and_text("walk install, decision false", rc, 0, out,
                      must=("N = 13 first-time downloads", "walk installs counted"),
                      must_not=("BOUND WITHHELD",))

    wrong_country = entry("owner-buy", country="US")
    rc, out, _ = checkpoint(registry(None, [wrong_country]), base)
    check.rc_and_text("entry whose cell is empty", rc, 5, out,
                      must=("the registry and the report disagree", "purchase macOS US",
                            "ADJUSTED PURCHASES  NOT PRINTED"),
                      must_not=("BOUND (rule", "ADJUSTED PURCHASES  gross", "US=-1", "would not apply anyway"))
    walk_wrong = entry("walk-ios", kind="first_download", day="2026-09-12", platform="iOS", code="1F")
    # The listing of a SHORT walk install must say what was actually done with N, which the decision
    # decides — not "only what the cell holds is subtracted" when nothing was (review 2026-09-16).
    for decision, said, not_said in (
            (False, "nothing is subtracted from N (decision false)", "only what the cell holds is subtracted"),
            (None, "nothing is subtracted from N (decision pending)", "only what the cell holds is subtracted"),
            (True, "only what the cell holds is subtracted", "nothing is subtracted from N")):
        rc, out, _ = checkpoint(registry(decision, [OWNER_BUY, walk_wrong]), base)
        check.rc_and_text(f"short walk install listing, decision {decision}", rc, 5, out,
                          must=(said,), must_not=(not_said,))
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY, walk_wrong]), base)
    check.rc_and_text("walk install whose cell is empty", rc, 5, out,
                      must=("first_download iOS JP: the registry claims 1 unit(s), the report holds 0",
                            "N = 13 (macOS 12 · iOS 1)", "NOT SETTLED — 1 registered walk unit(s)",
                            "or 12 if the registered walk units the report does not hold",
                            "ADJUSTED PURCHASES  gross 0"),
                      must_not=("N = 12", "iOS 0)  first-time", "BOUND (rule"))

    # An awaiting-report entry sits in the window before its row exists (the drafts tell the owner to
    # record it that way). It must subtract nothing, and no adjusted purchase figure may be printed.
    refund_awaiting = entry("owner-refund", kind="refund", day="2026-09-19", status="awaiting-report",
                            code=None, stamp="2026-09-19T12:00:00-07:00")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY, refund_awaiting]), base)
    check.rc_and_text("refund entry awaiting its row", rc, 5, out,
                      must=("2026-09-19 refund macOS JP: the registry claims 1 unit(s), the report holds 0",
                            "ADJUSTED PURCHASES  NOT PRINTED",
                            "owner-refund  refund macOS JP units=1 report day 2026-09-19 status=awaiting-report "
                            "— its cell holds fewer units"),
                      must_not=("refunded -1", "would not apply anyway", "BOUND (rule"))
    buy_awaiting = entry("owner-buy", status="awaiting-report", code=None, day="2026-09-20")
    customer_only = window(extra=cohort_extra(purchase_day=None, add={"2026-09-17": [iap("IA1", 1, "CN")]}))
    rc, out, _ = checkpoint(registry(None, [buy_awaiting]), customer_only)
    check.rc_and_text("purchase entry awaiting its row, a customer bought", rc, 5, out,
                      must=("PURCHASES  raw gross 1 (macOS 0 · iOS 1) · refunded 0 · net 1",
                            "ADJUSTED PURCHASES  NOT PRINTED"),
                      must_not=("net 0", "JP=-1", "macOS -1", "BOUND (rule"))
    rc, out, _ = checkpoint(registry(None, [buy_awaiting]), window(extra=cohort_extra(purchase_day=None)))
    check.rc_and_text("purchase entry awaiting its row, nothing bought", rc, 5, out,
                      must=("ADJUSTED PURCHASES  NOT PRINTED",),
                      must_not=("gross -1", "more refunds than purchases", "BOUND (rule"))
    refund_row = window(extra=cohort_extra(add={"2026-09-19": [iap("FI1", -1, "JP")]}))
    refund_wrong_day = entry("owner-refund", kind="refund", day="2026-09-18", stamp="2026-09-18T12:00:00-07:00")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY, refund_wrong_day]), refund_row)
    check.rc_and_text("refund entry on the wrong Pacific day", rc, 5, out,
                      must=("2026-09-18 refund macOS JP: the registry claims 1 unit(s), the report holds 0",
                            "ADJUSTED PURCHASES  NOT PRINTED"),
                      must_not=("adjusted net purchases is -1", "more refunds than purchases", "BOUND (rule"))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), refund_row)
    check.rc_and_text("CONTROL: an unregistered refund with no disagreement still reads net -1", rc, 5, out,
                      must=("ADJUSTED PURCHASES  gross 0 (macOS 0 · iOS 0) · refunded 1 · net -1",
                            "more refunds than purchases"), must_not=("NOT PRINTED",))

    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=cohort_extra(),
                                                                 states={"2026-09-18": "pending"}))
    check.rc_and_text("a cohort day not built", rc, 5, out,
                      must=("cohort report day(s) not built: 2026-09-18",), must_not=("BOUND (rule",))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=cohort_extra(),
                                                                 states={"2026-09-18": "nosales"}))
    check.rc_and_text("a cohort day with no sales (a built report)", rc, 0, out,
                      must=("N = 12 first-time downloads",), must_not=("BOUND WITHHELD",))

    customer = cohort_extra(add={"2026-09-19": [iap("IA1", 1, "CN")]})
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=customer))
    check.rc_and_text("a customer purchase", rc, 0, out,
                      must=("ZERO-PURCHASE BOUND DOES NOT APPLY: adjusted net purchases = 1",
                            "adjusted purchase territory: CN=1"),
                      must_not=("BOUND (rule", "BOUND WITHHELD"))

    refunded = cohort_extra(add={"2026-09-19": [iap("FI1", -1, "JP")]})
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=refunded))
    check.rc_and_text("owner refund not registered", rc, 5, out,
                      must=("adjusted net purchases is -1",), must_not=("BOUND (rule",))
    owner_refund = entry("owner-refund", kind="refund", day="2026-09-19",
                         stamp="2026-09-19T12:00:00-07:00")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY, owner_refund]), window(extra=refunded))
    check.rc_and_text("owner refund registered", rc, 0, out,
                      must=("ADJUSTED PURCHASES  gross 0 (macOS 0 · iOS 0) · refunded 0 · net 0",
                            "BOUND (rule of three"), must_not=("BOUND WITHHELD",))

    no_installs = window(extra=cohort_extra(first_downloads={}))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), no_installs)
    check.rc_and_text("N = 0", rc, 5, out, must=("N = 0: 3/N is undefined",), must_not=("BOUND (rule",))

    bad = registry(None, [entry("owner-buy", country="JPN")])
    fetch = FakeFetch(base)
    rc, out = capture(sr.run_checkpoint, bad, fetch, NEWEST)
    check.rc_and_text("invalid registry", rc, 4, out, must=("REGISTRY-INVALID", "country_code must be"))
    check(fetch.calls == [], f"an invalid registry still fetched: {fetch.calls}")

    # The eve of day 0.
    eve = cohort_extra(add={"2026-09-08": [report_row("1F", 2, "CN")]})
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=eve))
    check.rc_and_text("first downloads on 2026-09-08", rc, 0, out,
                      must=("⚠️  2026-09-08 first-time downloads (F1/1F): 2 — N counts from 2026-09-09; "
                            "had day 0 been 2026-09-08, N would be 15",))

    # Which pre-registered rows are reached.
    at35 = cohort_extra(first_downloads={"2026-09-09": [report_row("F1", 35, "JP")]})
    at34 = cohort_extra(first_downloads={"2026-09-09": [report_row("F1", 34, "JP")]})
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=at35))
    check.rc_and_text("N = 35", rc, 0, out, must=("REACHED      N = 35", "not reached  N = 100"))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=at34))
    check.rc_and_text("N = 34", rc, 0, out, must=("not reached  N = 35",), must_not=("REACHED      N = 35",))
    walk35 = entry("walk-mac", kind="first_download", day="2026-09-09", code="F1")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY, walk35]), window(extra=at35))
    check.rc_and_text("N = 35 with one undecided walk unit", rc, 5, out,
                      must=("UNDECIDED    N = 35", "or 34 if the undecided walk units are subtracted"))
    at200 = cohort_extra(first_downloads={"2026-09-09": [report_row("F1", 200, "JP")]})
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), window(extra=at200))
    check.rc_and_text("N = 200", rc, 0, out, must=("REACHED      N = 200, or 2027-03-08",))
    # One first download a day past NEWEST as well: a report whose downloads stop on 09-20 while it runs to
    # 12-08 reads as downloads 9x release-locked, and the second release-day control rightly withholds on it.
    long_window = window(end=D(2026, 12, 8), extra=cohort_extra(
        add={key: [report_row("F1", 1, "JP")] for key in sr._day_keys(NEWEST + dt.timedelta(days=1),
                                                                        D(2026, 12, 8))}))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), long_window, newest=D(2026, 12, 10),
                            until=D(2026, 12, 8))
    check.rc_and_text("until 2026-12-08", rc, 0, out,
                      must=("REACHED      2026-12-08 (day 90)", "not reached  2027-03-08 (day 180)  refunds"))
    rc, out, fetch = checkpoint(registry(None, [OWNER_BUY]), long_window, newest=D(2026, 12, 10),
                                until=D(2026, 12, 7))
    check.rc_and_text("until 2026-12-07", rc, 0, out, must=("not reached  2026-12-08 (day 90)",))
    check(fetch.calls == [(sr.LAUNCH_DATE, D(2026, 12, 7), True)], f"--until not honoured: {fetch.calls}")


# ---------------------------------------------------------------------------------------------------
# E1. registered session participants (PLAN-STAGE1 §K "REGISTERED 2026-09-24" box; PLAN-V1.34 §D1)
#
# A recruited participant's install is a walk install: the owner registers it as `first_download` with
# its real platform, country and Pacific report day, and the existing decision subtracts it (box item
# 1); the reconciliation rule is not relaxed for it (item 5). Nothing in the instrument changed for
# this — the case exists so the subtraction is SEEN to land on five cells at once (five entries in five
# distinct (day, platform, country) cells across four countries, four days and both platforms), on the
# right platform and country, and to stop where a cell runs short, before the first participant installs.
#
# Every expected number below is worked out by hand from PARTICIPANT_DOWNLOADS and PARTICIPANTS and
# written beside them; none is read back from apply_registry (a test that grades itself survives the
# mutation it exists to catch).

PARTICIPANT_DOWNLOADS = {           # cohort first-time downloads, Pacific day -> rows (F1 macOS, 1F iOS)
    "2026-09-10": [report_row("F1", 3, "JP"), report_row("1F", 2, "CN")],      # macOS 3 · iOS 2
    "2026-09-13": [report_row("1F", 4, "DE"), report_row("F1", 1, "CN")],      # macOS 1 · iOS 4
    "2026-09-15": [report_row("F1", 2, "US"), report_row("1F", 1, "JP")],      # macOS 2 · iOS 1
    "2026-09-18": [report_row("F1", 5, "JP"), report_row("1F", 3, "US")],      # macOS 5 · iOS 3
}
RAW_N, RAW_MAC, RAW_IOS = 21, 11, 10                # 3+2+4+1+2+1+5+3 · 3+1+2+5 · 2+4+1+3


def participant(eid, day, platform, country, units=1):
    """A `first_download` entry as the 2026-09-24 box has the owner record one."""
    x = entry(eid, kind="first_download", day=day, platform=platform, country=country, units=units,
              code={"macOS": "F1", "iOS": "1F"}[platform], stamp=f"{day}T12:00:00-07:00")
    x["walk_step"] = "PLAN-STAGE1 §K 2026-09-24 box, item 1"
    x["notes"] = "session participant"
    return x


PARTICIPANTS = [                    # five entries · six units · four countries · four days · both platforms
    participant("p-jp-mac-0910", "2026-09-10", "macOS", "JP"),              # its cell holds 3
    participant("p-cn-ios-0910", "2026-09-10", "iOS", "CN", units=2),       # its cell holds exactly 2
    participant("p-de-ios-0913", "2026-09-13", "iOS", "DE"),                # its cell holds 4
    participant("p-us-mac-0915", "2026-09-15", "macOS", "US"),              # its cell holds 2
    participant("p-us-ios-0918", "2026-09-18", "iOS", "US"),                # its cell holds 3
]
SUBTRACTED, SUBTRACTED_MAC, SUBTRACTED_IOS = 6, 2, 4                        # 1+2+1+1+1 · 1+1 · 2+1+1
N_ADJ, N_ADJ_MAC, N_ADJ_IOS = 15, 9, 6                                      # 21-6 · 11-2 · 10-4


def test_participants(check):
    # The fixture is exactly what its comment says: five entries in five distinct (day, platform,
    # country) cells, across four countries, four report days and both platforms, with the arithmetic
    # written beside it. A fixture that drifted would grade the wrong claim.
    cells_planted = {(x["report_day_pt"], x["platform"], x["country_code"]) for x in PARTICIPANTS}
    check(len(PARTICIPANTS) == 5 and len(cells_planted) == 5
          and {x["country_code"] for x in PARTICIPANTS} == {"JP", "CN", "DE", "US"}
          and len({x["report_day_pt"] for x in PARTICIPANTS}) == 4
          and {x["platform"] for x in PARTICIPANTS} == {"macOS", "iOS"},
          "the participant fixture is no longer five entries in five distinct (day, platform, country) cells "
          "across four countries, four days and both platforms")
    check(sum(x["units"] for x in PARTICIPANTS) == SUBTRACTED
          and sum(x["units"] for x in PARTICIPANTS if x["platform"] == "macOS") == SUBTRACTED_MAC
          and sum(x["units"] for x in PARTICIPANTS if x["platform"] == "iOS") == SUBTRACTED_IOS
          and (RAW_N - SUBTRACTED, RAW_MAC - SUBTRACTED_MAC, RAW_IOS - SUBTRACTED_IOS)
          == (N_ADJ, N_ADJ_MAC, N_ADJ_IOS),
          "the hand-written participant arithmetic does not add up")
    check(not sr.validate_registry(registry(True, [OWNER_BUY] + PARTICIPANTS)),
          f"participant entries in the box's shape do not validate: "
          f"{sr.validate_registry(registry(True, [OWNER_BUY] + PARTICIPANTS))}")

    base = window(extra=cohort_extra(first_downloads=PARTICIPANT_DOWNLOADS))
    cells, _codes = sr.cell_tally(base)
    cohort = (sr.DAY0, NEWEST)

    # (a) N is the raw first-time downloads minus exactly the registered units; (b) each on its platform.
    r = sr.apply_registry(cells, registry(True, [OWNER_BUY] + PARTICIPANTS), *cohort)
    check((r["raw"]["dl"], r["raw"]["dl_macOS"], r["raw"]["dl_iOS"]) == (RAW_N, RAW_MAC, RAW_IOS),
          f"CONTROL: the planted rows do not tally to raw {RAW_N} ({RAW_MAC} · {RAW_IOS}): {r['raw']}")
    check((r["adjusted"]["dl"], r["adjusted"]["dl_macOS"], r["adjusted"]["dl_iOS"])
          == (N_ADJ, N_ADJ_MAC, N_ADJ_IOS),
          f"participants: five entries in five cells across four countries must leave N = {N_ADJ} "
          f"({N_ADJ_MAC} · {N_ADJ_IOS}), "
          f"got {r['adjusted']}")
    check(r["walk_install_units"] == SUBTRACTED and r["walk_install_units_unheld"] == 0
          and not r["problems"] and not r["notes"],
          f"participants: {SUBTRACTED} units all held by their cells must leave no problem: {r}")
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY] + PARTICIPANTS), base)
    check.rc_and_text("participants: checkpoint, decision true", rc, 0, out,
                      must=(f"FIRST-TIME DOWNLOADS  raw {RAW_N} (macOS {RAW_MAC} · iOS {RAW_IOS})",
                            f"registered walk first_download: 5 entries · {SUBTRACTED} unit(s) · SUBTRACTED "
                            f"(decision true)",
                            f"N = {N_ADJ} (macOS {N_ADJ_MAC} · iOS {N_ADJ_IOS})  first-time downloads F1+1F "
                            f"since 2026-09-09\n",
                            f"BOUND (rule of three, 95%) — zero adjusted net purchases in N = {N_ADJ} "
                            f"first-time downloads (F1+1F) since 2026-09-09, walk installs subtracted, "
                            f"decision true:",
                            "3/15 = 20.00%", "N + 114 = 129", "3/129 = 2.33%",
                            f"(read at N = {N_ADJ}, with 2026-09-20 the newest report day read)")
                      + tuple(f"{x['id']}  first_download {x['platform']} {x['country_code']} units={x['units']} "
                              f"report day {x['report_day_pt']} status=matched — subtracted from N"
                              for x in PARTICIPANTS),
                      must_not=("BOUND WITHHELD", "NOT SETTLED", "UNADJUSTED", f"N = {RAW_N}",
                                "disagree", "fewer units"))

    # (c) The reconciliation rule holds for participants (box item 5). One entry claims 3 of the 2 units
    # its cell holds: the cell gives up its 2, the third is a disagreement that withholds the bound, and
    # N is printed as the ceiling it now is — not silently as 14. Paired with the baseline above, where
    # the same entry claims exactly the 2 the cell holds and the bound is printed.
    over = [participant("p-cn-ios-0910", "2026-09-10", "iOS", "CN", units=3) if x["id"] == "p-cn-ios-0910"
            else x for x in PARTICIPANTS]
    short = "2026-09-10 first_download iOS CN: the registry claims 3 unit(s), the report holds 2"
    r = sr.apply_registry(cells, registry(True, [OWNER_BUY] + over), *cohort)
    check((r["adjusted"]["dl"], r["adjusted"]["dl_macOS"], r["adjusted"]["dl_iOS"]) == (N_ADJ, N_ADJ_MAC, N_ADJ_IOS)
          and r["walk_install_units_unheld"] == 1 and r["problems"] == [short]
          and r["problem_kinds"] == {"first_download"},
          f"participants: a claim of 3 on a cell of 2 must take the 2, report the 1 as {short!r}, and leave "
          f"N = {N_ADJ}: {r}")
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY] + over), base)
    check.rc_and_text("participants: one entry claims more than its cell holds", rc, 5, out,
                      must=("BOUND WITHHELD:", f"  - the registry and the report disagree — {short}",
                            f"N = {N_ADJ} (macOS {N_ADJ_MAC} · iOS {N_ADJ_IOS})  first-time downloads F1+1F since "
                            f"2026-09-09, NOT SETTLED — 1 registered walk unit(s) are not in the cell the "
                            f"registry names, so they were not subtracted (see BOUND WITHHELD)",
                            f"(read at N = {N_ADJ}, or {N_ADJ - 1} if the registered walk units the report does "
                            f"not hold where the registry says are in N elsewhere",
                            "p-cn-ios-0910  first_download iOS CN units=3 report day 2026-09-10 status=matched — "
                            "its cell holds fewer units than the registry claims there — only what the cell "
                            "holds is subtracted, and the bound is withheld",
                            "p-jp-mac-0910  first_download macOS JP units=1 report day 2026-09-10 status=matched "
                            "— subtracted from N",
                            "ADJUSTED PURCHASES  gross 0"),
                      must_not=("BOUND (rule", f"N = {N_ADJ - 1} (", f"N = {RAW_N}", "NOT PRINTED"))
    # The same rule when the owner records the wrong platform: a cell that holds nothing gives nothing.
    # This entry is also the section's one near-miss on the country dimension: on 2026-09-13 the report
    # holds macOS 1 (CN) and iOS 4 (DE), so (macOS, DE) is wrong-platform relative to the DE row and
    # wrong-country relative to the macOS row at once. A country-blind subtraction would take the CN
    # unit and print macOS 11-3 = 8 — the must_not "macOS 8" below is what catches it.
    wrong = PARTICIPANTS + [participant("p-de-mac-0913", "2026-09-13", "macOS", "DE")]
    empty = "2026-09-13 first_download macOS DE: the registry claims 1 unit(s), the report holds 0"
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY] + wrong), base)
    check.rc_and_text("participants: one entry names a cell the report has empty", rc, 5, out,
                      must=(f"  - the registry and the report disagree — {empty}",
                            f"N = {N_ADJ} (macOS {N_ADJ_MAC} · iOS {N_ADJ_IOS})  first-time downloads F1+1F since "
                            f"2026-09-09, NOT SETTLED — 1 registered walk unit(s)",
                            f"registered walk first_download: 6 entries · {SUBTRACTED + 1} unit(s) · SUBTRACTED"),
                      must_not=("BOUND (rule", f"N = {N_ADJ - 1} (", "macOS 8"))

    # (d) The decision, not the entries, is what subtracts: false leaves N raw and says so; null leaves
    # it raw, says it is unadjusted, and withholds.
    r = sr.apply_registry(cells, registry(False, [OWNER_BUY] + PARTICIPANTS), *cohort)
    check((r["adjusted"]["dl"], r["adjusted"]["dl_macOS"], r["adjusted"]["dl_iOS"]) == (RAW_N, RAW_MAC, RAW_IOS)
          and r["adjusted"]["buy"] == 0 and r["walk_install_units"] == SUBTRACTED and not r["problems"],
          f"participants, decision false: N must stay raw ({RAW_N} · {RAW_MAC} · {RAW_IOS}) with the {SUBTRACTED} "
          f"units still listed, while the owner's purchase is still subtracted: {r}")
    rc, out, _ = checkpoint(registry(False, [OWNER_BUY] + PARTICIPANTS), base)
    check.rc_and_text("participants: checkpoint, decision false", rc, 0, out,
                      must=(f"registered walk first_download: 5 entries · {SUBTRACTED} unit(s) · not subtracted "
                            f"(decision false)",
                            f"N = {RAW_N} (macOS {RAW_MAC} · iOS {RAW_IOS})  first-time downloads F1+1F since "
                            f"2026-09-09\n",
                            f"BOUND (rule of three, 95%) — zero adjusted net purchases in N = {RAW_N} first-time "
                            f"downloads (F1+1F) since 2026-09-09, walk installs counted, decision false:",
                            "3/21 = 14.29%", "N + 114 = 135", "3/135 = 2.22%",
                            "p-us-ios-0918  first_download iOS US units=1 report day 2026-09-18 status=matched — "
                            "counted in N (decision false)"),
                      must_not=(f"N = {N_ADJ}", "subtracted from N", "BOUND WITHHELD"))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY] + PARTICIPANTS), base)
    check.rc_and_text("participants: checkpoint, decision null", rc, 5, out,
                      must=(f"N = {RAW_N} (macOS {RAW_MAC} · iOS {RAW_IOS})  first-time downloads F1+1F since "
                            f"2026-09-09, UNADJUSTED — {SUBTRACTED} undecided walk unit(s) inside it",
                            f"owner decision pending: decisions.exclude_walk_first_downloads_from_N is null while "
                            f"the cohort window holds 5 first_download entries ({SUBTRACTED} unit(s))",
                            f"(read at N = {RAW_N}, or {N_ADJ} if the undecided walk units are subtracted"),
                      must_not=("BOUND (rule", f"N = {N_ADJ} ("))

    # (e) A participant dated outside the cohort window — after the newest report day, or on the eve of
    # day 0 — is neither subtracted nor a reason to withhold, whether or not the report holds a row there.
    outside = PARTICIPANTS + [participant("p-late", "2026-09-25", "macOS", "JP"),
                              participant("p-eve", "2026-09-08", "iOS", "CN")]
    with_eve = window(extra=cohort_extra(first_downloads=PARTICIPANT_DOWNLOADS,
                                         add={"2026-09-08": [report_row("1F", 1, "CN")]}))
    r = sr.apply_registry(sr.cell_tally(with_eve)[0], registry(True, [OWNER_BUY] + outside), *cohort)
    check(r["adjusted"]["dl"] == N_ADJ and r["walk_install_units"] == SUBTRACTED and not r["problems"]
          and {x["id"] for x in r["in_window"]} == {"owner-buy"} | {x["id"] for x in PARTICIPANTS},
          f"participants outside the window changed N or entered the window: {r}")
    rc, out, _ = checkpoint(registry(True, [OWNER_BUY] + outside), with_eve)
    check.rc_and_text("participants: two entries outside the cohort window", rc, 0, out,
                      must=(f"registered walk first_download: 5 entries · {SUBTRACTED} unit(s) · SUBTRACTED",
                            f"N = {N_ADJ} (macOS {N_ADJ_MAC} · iOS {N_ADJ_IOS})  first-time downloads F1+1F since "
                            f"2026-09-09\n",
                            "p-late  first_download macOS JP units=1 report day 2026-09-25 status=matched — "
                            "outside the cohort window 2026-09-09 .. 2026-09-20, not subtracted",
                            "p-eve  first_download iOS CN units=1 report day 2026-09-08 status=matched — "
                            "outside the cohort window 2026-09-09 .. 2026-09-20, not subtracted",
                            "⚠️  2026-09-08 first-time downloads (F1/1F): 1 — N counts from 2026-09-09; had day 0 "
                            f"been 2026-09-08, N would be {N_ADJ + 1}",
                            f"BOUND (rule of three, 95%) — zero adjusted net purchases in N = {N_ADJ} "),
                      must_not=("BOUND WITHHELD", "disagree", "7 entries", f"N = {N_ADJ - 1} ",
                                f"N = {N_ADJ - 2} "))
    print(f"  {len(PARTICIPANTS)} participant entries · {SUBTRACTED} units in {len(cells_planted)} cells, "
          f"{len({x['country_code'] for x in PARTICIPANTS})} countries, both platforms: "
          f"N {RAW_N} → {N_ADJ} ({RAW_MAC} → {N_ADJ_MAC} · {RAW_IOS} → {N_ADJ_IOS}) · an "
          f"over-claim and an empty cell withhold with N unmoved · decision false and null leave N raw · "
          f"entries outside the window do nothing")


# ---------------------------------------------------------------------------------------------------
# E2. the second release-day control (--checkpoint only)
#
# The groups below are typed from PLAN-STAGE1 §K's "DECIDED 2026-09-17" box, item 11, where they are
# written out; none is computed by `release_day_groups`. A report built from the function under test's
# own groups would move with any mutation of that function and grade itself.
#
# FIRM_RELEASE_DATES_PT as the box sorted days against it, frozen. The live tuple gains one line per release
# (its own comment says so), and every list below is typed from these five dates: 09-13..09-20 are other days
# to `control_days`, and 09-19 is a day no firm date reaches to the registry cases. Against the live tuple
# they would move with every release — measured 2026-09-24, appending the 09-17 line turned 21 checks red
# with nothing wrong, the shape of a suite that gets edited to pass — so `test_second_control` runs them
# under patched(FIRM_RELEASE_DATES_PT=FIRM_BASE) and pins the live tuple by value on its own, where a release
# line is a deliberate one-line diff. The "with the line added" cases build on FIRM_BASE for the same reason.
FIRM_BASE = ("2026-08-11", "2026-08-15", "2026-08-17", "2026-08-31", "2026-09-11")

BOX_EXPOSURE = ["2026-08-11", "2026-08-12", "2026-08-15", "2026-08-16", "2026-08-17", "2026-08-18",
                "2026-08-31", "2026-09-01", "2026-09-11", "2026-09-12"]
BOX_EXCLUDED = ([f"2026-08-{d:02d}" for d in range(1, 11)] + ["2026-08-13"]
                + [f"2026-08-{d:02d}" for d in range(19, 31)] + [f"2026-09-{d:02d}" for d in range(5, 10)])
BOX_OTHER_TO_0914 = ["2026-08-14", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-10", "2026-09-13",
                     "2026-09-14"]
# docs/measurements/2026-09-16-release-day-control.md §6, "Per-day values", as recorded there: (F7, F1/1F).
RECORDED_0916 = {"2026-08-11": (20, 5), "2026-08-12": (20, 4), "2026-08-14": (4, 4), "2026-08-15": (3, 3),
                 "2026-08-16": (19, 4), "2026-08-17": (4, 1), "2026-08-18": (23, 3), "2026-08-31": (23, 5),
                 "2026-09-01": (14, 1), "2026-09-02": (10, 3), "2026-09-03": (3, 1), "2026-09-04": (7, 0),
                 "2026-09-10": (10, 3), "2026-09-11": (6, 5), "2026-09-12": (29, 2), "2026-09-13": (11, 1),
                 "2026-09-14": (3, 3)}
# calibrate()'s control is satisfied on three RELEASE_DAYS the second control excludes, in BOTH code sets,
# so it passes whichever way updates and downloads are assigned and cannot be what withholds a bound.
V1_SPIKE_DAYS = ("2026-08-20", "2026-08-22", "2026-08-24")
SWAPPED = dict(UPDATE={"F1", "1F"}, DOWNLOAD={"F7": "macOS"})       # measurement document §3, M4


def control_days(upd=(8, 2), dl=(4, 2), end=NEWEST, add=None, states=None):
    """LAUNCH_DATE..end: F7 and F1 units per exposure / other day as given, 1 of each on excluded days
    and before 2026-08-01, the owner's FI1 JP purchase on 2026-09-16 (an other day)."""
    days = {}
    for key in sr._day_keys(sr.LAUNCH_DATE, end):
        if key in V1_SPIKE_DAYS:
            u, d = 50, 50
        elif key in BOX_EXPOSURE:
            u, d = upd[0], dl[0]
        elif key in BOX_EXCLUDED or key < "2026-08-01":
            u, d = 1, 1
        else:
            u, d = upd[1], dl[1]
        rows = [report_row("F7", u, "JP"), report_row("F1", d, "JP")]
        if key == "2026-07-01":
            rows.append(report_row("1F", 1, "CN"))
        if key == "2026-09-16":
            rows.append(iap("FI1", 1, "JP"))
        rows += (add or {}).get(key, [])
        days[key] = ("data", tsv(*rows))
    for key, state in (states or {}).items():
        days[key] = (state, "")
    return days


def second(days):
    return sr.second_release_day_control(sr.tally(days)[0])


def second_control_fixtures(check):
    """Every fixture-based check of the second control and the release registry.

    The groups these reports are graded against are typed from the box, which sorted days against FIRM_BASE,
    so this runs under patched(FIRM_RELEASE_DATES_PT=FIRM_BASE) from `test_second_control` and grades nothing
    against another tuple: the guard fails first, with the reason, rather than 21 checks failing with numbers.
    It asks the module for its derived exposure days rather than reading the tuple by name — that is the
    precondition the fixtures actually rest on, it is what `test_second_control`'s scanner keeps out of here,
    and it also fails if the module ever binds its groups at import, where a patch of the tuple would not reach.
    """
    grouped = sorted(sr.release_day_groups()[0])
    check(grouped == BOX_EXPOSURE,
          f"the second-control fixtures are grouping days by {grouped}, not the box's exposure days — they must "
          f"run inside patched(FIRM_RELEASE_DATES_PT=FIRM_BASE)")
    Fr = sr.fractions.Fraction

    # 1. The definition, against the box's written-out lists.
    every = {k: ("data", tsv(report_row("F7", 1, "JP"))) for k in sr._day_keys(D(2026, 8, 1), D(2026, 9, 14))}
    r = second(every)
    check(r["exposure"] == BOX_EXPOSURE, f"exposure days {r['exposure']}, the box says {BOX_EXPOSURE}")
    check(r["other"] == BOX_OTHER_TO_0914, f"other days {r['other']}, the box says {BOX_OTHER_TO_0914}")
    neither = sorted(set(every) - set(r["exposure"]) - set(r["other"]))
    check(neither == BOX_EXCLUDED, f"days in neither group {neither}, the box writes out {BOX_EXCLUDED}")
    exposure, uncertain = sr.release_day_groups()
    check("2026-08-12" in exposure and "2026-08-12" not in uncertain and "2026-08-31" not in uncertain,
          "a day that is both exposure and 'the day after an uncertain date' must be exposure")

    # 2. The recorded 2026-09-16 cache values reproduce §6's figures. Every day §6 does not list carries
    #    97 of each, so any excluded day, or any day before 08-01, that leaks into a group moves a mean.
    recorded = {}
    for key in sr._day_keys(sr.LAUNCH_DATE, D(2026, 9, 14)):
        u, d = RECORDED_0916.get(key, (97, 97))
        recorded[key] = ("data", tsv(report_row("F7", u, "JP"), report_row("F1", d, "JP")))
    per_day = sr.tally(recorded)[0]
    r = sr.second_release_day_control(per_day)
    check((r["upd_exposure"], r["upd_other"], r["dl_exposure"], r["dl_other"])
          == (Fr(161, 10), Fr(48, 7), Fr(33, 10), Fr(15, 7)),
          f"§6's recorded means (16.10, 6.86, 3.30, 2.14 per day) do not reproduce: {r}")
    check(r["check_a"] and r["check_b"] and not r["failures"], f"§6 recorded PASS / PASS: {r}")
    # Other days before 2026-09-09: 08-14 (4), 09-02 (3), 09-03 (1), 09-04 (0) = 8 / 4; from it: 09-10 (3),
    # 09-13 (1), 09-14 (3) = 7 / 3 — worked out by hand from the table above.
    check((r["other_before_day0"], r["other_from_day0"], r["dl_other_before_day0"], r["dl_other_from_day0"])
          == (BOX_OTHER_TO_0914[:4], BOX_OTHER_TO_0914[4:], Fr(2), Fr(7, 3)),
          f"other-day first-time downloads split at 2026-09-09 should be 2.00/d over 4 days, 2.33/d over 3: {r}")
    rc, out = capture(sr.report_second_release_day_control, per_day, recorded)
    for s in ("exposure days (10): " + ", ".join(BOX_EXPOSURE), "other days (7): " + ", ".join(BOX_OTHER_TO_0914),
              "updates (F7)                  exposure 16.10/d vs other 6.86/d = 2.35x",
              "first-time downloads (F1/1F)  exposure 3.30/d vs other 2.14/d = 1.54x",
              "    other-day first-time downloads 2.00/d before 2026-09-09 over 4 day(s), 2.33/d from 2026-09-09 "
              "over 3 day(s)\n",
              "OK — check A: updates elevated on exposure days · check B: update ratio 2.35x > first-time "
              "download ratio 1.54x"):
        check(s in out, f"the printed control lacks {s!r}:\n{out}")
    check(rc == ([], []) and "SECOND-CONTROL-FAIL" not in out and "WARNING" not in out,
          f"§6's values printed a failure or a registry warning: {rc}\n{out}")
    with patched(**SWAPPED):
        r = second(recorded)
    check(r["check_a"] and not r["check_b"] and _approx(r["upd_ratio"], 1.54) and _approx(r["dl_ratio"], 2.35),
          f"§6: the M4 swap should read updates 1.54x / downloads 2.35x and fail check B only: {r}")

    # 3. A fails alone; B fails alone (the M4 swap, and a tie); both pass; the conservative edges.
    both = second(control_days())
    check(both["check_a"] and both["check_b"] and not both["failures"]
          and (both["upd_ratio"], both["dl_ratio"]) == (4, 2), f"both pass: {both}")
    a_only = second(control_days(upd=(2, 2), dl=(1, 2)))
    check(not a_only["check_a"] and a_only["check_b"] and len(a_only["failures"]) == 1
          and a_only["failures"][0].startswith("check A"), f"A fails (a tie), B passes: {a_only}")
    with patched(**SWAPPED):
        m4 = second(control_days())
    check(m4["check_a"] and not m4["check_b"] and len(m4["failures"]) == 1
          and m4["failures"][0].startswith("check B") and (m4["upd_ratio"], m4["dl_ratio"]) == (2, 4),
          f"the M4 swap: A passes, B fails: {m4}")
    tie = second(control_days(upd=(4, 2), dl=(4, 2)))
    check(tie["check_a"] and not tie["check_b"], f"B is strict — equal ratios fail it: {tie}")
    for label, kw in (("no other-day downloads", dict(dl=(2, 0))), ("no other-day updates", dict(upd=(3, 0)))):
        r = second(control_days(**kw))
        check(not r["check_b"] and any("undefined" in f for f in r["failures"]),
              f"{label}: a ratio against zero must fail check B, not pass as infinite: {r}")
    r = second(control_days(end=D(2026, 8, 10)))
    check(r["failures"] and "cannot run" in r["failures"][0], f"no exposure day in the window must fail: {r}")
    r = second(control_days(states={"2026-09-12": "pending"}))
    check(len(r["exposure"]) == 9 and r["exposure_unread"] == ["2026-09-12"],
          f"an exposure day that is not a data day is not counted and is listed: {r}")

    # 4. A spike on an EXCLUDED day changes nothing; the same spike on an OTHER day does.
    spike = [report_row("F7", 300, "JP")]
    on_excluded = control_days(add={"2026-08-13": spike})
    check(sr.tally(on_excluded)[0]["2026-08-13"]["upd"] == 301,
          "CONTROL: the excluded-day spike did not land in the report")
    check(second(on_excluded) == both, f"a spike on excluded 2026-08-13 changed the result: {second(on_excluded)}")
    on_other = second(control_days(add={"2026-08-14": spike}))
    check(on_other != both and not on_other["check_a"],
          f"the same spike on other day 2026-08-14 must change the result and fail check A: {on_other}")

    # 5. --checkpoint: prints the bound when it passes, withholds with the new reason when it fails.
    withheld = "the second release-day control failed (PLAN-STAGE1 §K \"DECIDED 2026-09-17\" item 11)"
    passing = ("BOUND (rule of three, 95%)", "OK — the instrument responds",
               "second release-day control (PLAN-STAGE1 §K \"DECIDED 2026-09-17\" item 11 — gates the bound only",
               "updates (F7)                  exposure 8.00/d vs other 2.00/d = 4.00x",
               "first-time downloads (F1/1F)  exposure 4.00/d vs other 2.00/d = 2.00x", "OK — check A")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), control_days())
    check.rc_and_text("E2 checkpoint: second control passes", rc, 0, out, must=passing,
                      must_not=("BOUND WITHHELD", "SECOND-CONTROL-FAIL", withheld))
    for label, days, needle in (
            ("check A fails", control_days(upd=(2, 2), dl=(1, 2)), "SECOND-CONTROL-FAIL: check A"),
            ("check B fails (the M4 shape: updates 2x, downloads 4x)", control_days(upd=(4, 2), dl=(8, 2)),
             "SECOND-CONTROL-FAIL: check B"),
            ("spike on an other day", control_days(add={"2026-08-14": spike}), "SECOND-CONTROL-FAIL: check A")):
        rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), days)
        check.rc_and_text(f"E2 checkpoint: {label}", rc, 5, out,
                          must=("BOUND WITHHELD:", withheld, needle, "OK — the instrument responds"),
                          must_not=("BOUND (rule", "CALIBRATION-FAIL", "no matched day-0"))
    # The literal swap also breaks exclusion_control (it drives F1/1F as downloads), so calibration fails
    # and the exit is 4 — with the second control's reason listed beside it, not hidden behind it.
    with patched(**SWAPPED):
        rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), control_days())
    check.rc_and_text("E2 checkpoint: the literal M4 swap", rc, 4, out,
                      must=("BOUND WITHHELD:", "calibration failed", withheld, "SECOND-CONTROL-FAIL: check B"),
                      must_not=("BOUND (rule",))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), on_excluded)
    check.rc_and_text("E2 checkpoint: spike on an excluded day", rc, 0, out, must=("BOUND (rule of three",),
                      must_not=("BOUND WITHHELD", withheld))

    # 6. --calibrate and --confirm-known-positive do not run it: on a report where it fails, both still pass
    #    and print none of it — paired with the checkpoint above withholding on the same report.
    a_fails = control_days(upd=(2, 2), dl=(1, 2))
    per_day, seen, unclassified, *_ = sr.tally(a_fails)
    fails, out = capture(sr.calibrate, per_day, seen, unclassified)
    check(fails == [] and "second release-day" not in out and "SECOND-CONTROL" not in out,
          f"calibrate() ran the second control or failed on it: {fails}\n{out}")
    rc, out, _ = confirm(a_fails)
    check.rc_and_text("E2 confirm on a report the second control fails", rc, 0, out, must=(sr.DRAFT_LABEL,),
                      must_not=("second release-day", "SECOND-CONTROL"))
    with patched(resolve_vendor_number=lambda v: "12345678", make_jwt=lambda: "token",
                 collect=fake_collect(a_fails), pacific_today=lambda: D(2026, 9, 21)):
        rc, out = capture(sr.main, ["--calibrate"])
    check.rc_and_text("E2 main --calibrate on a report the second control fails", rc, 0, out,
                      must=("OK — the instrument responds",), must_not=("second release-day", "SECOND-CONTROL"))
    # calibrate()'s own input, typed from 2ec5786. The scan below reads function bodies only, so a module-level
    # `RELEASE_DAYS = RELEASE_DAYS | {firm dates and next days}` passes it and every report above (V1_SPIKE_DAYS
    # keep calibrate passing either way) while moving real --calibrate from 1.65x / 1.24x to 1.80x / 1.38x.
    check(sr.RELEASE_DAYS == {"2026-08-11", "2026-08-16", "2026-08-18", "2026-08-20", "2026-08-22", "2026-08-24"},
          f"RELEASE_DAYS, calibrate()'s known-positive days, changed: {sorted(sr.RELEASE_DAYS)} — '--calibrate still "
          f"passes' would compare two instruments")
    # Structural, because a report on which calibrate() passes cannot show that it never READS the
    # definition (it could fold the exposure days into its own groups and still pass here).
    source = Path(sr.__file__).read_text(encoding="utf-8")
    names = {"FIRM_RELEASE_DATES_PT", "UNCERTAIN_RELEASE_DATES_PT", "EXPOSURE_CONTROL_START", "OTHER_DAYS_START",
             "SECOND_CONTROL_SOURCE", "release_day_groups", "second_release_day_control",
             "report_second_release_day_control", "unregistered_versions", "REGISTRY_WATCHED_AFTER",
             "FIRST_SEEN_LAG_DAYS"}
    readers = second_control_readers(source, names)
    guarded = ("calibrate", "report_calibration", "purchase_path_control", "exclusion_control", "run_confirm", "main")
    check(not set(readers) & set(guarded),
          f"the second control's definition is read by {sorted(set(readers) & set(guarded))}, which --calibrate or "
          f"--confirm-known-positive run")
    check("run_checkpoint" in readers, f"POSITIVE CONTROL: the scanner does not see run_checkpoint read it: {readers}")
    planted = source.replace("    fails = purchase_path_control()\n",
                             "    fails = purchase_path_control()\n    _ = FIRM_RELEASE_DATES_PT\n", 1)
    check("calibrate" in second_control_readers(planted, names),
          "CONTROL: the scanner missed a planted read of the definition inside calibrate()")

    # 7. Check B failing with no swap: first-time downloads are not release-locked at all (4 on exposure days
    #    and on the other days before 2026-09-09) and fall to 1 from 2026-09-09. Other-day mean 25/13, so the
    #    download ratio is 52/25 = 2.08x against updates 4/2 = 2.00x. The failure must name both causes and
    #    carry both means, 4.00/d over 4 days (08-14, 09-02..09-04) and 1.00/d over 9 (09-10, 09-13..09-20).
    early_other = {d: [report_row("F1", 3, "JP")] for d in BOX_OTHER_TO_0914[:4]}
    fall = control_days(upd=(4, 2), dl=(4, 1), add=early_other)
    r = second(fall)
    check((r["dl_other_before_day0"], r["dl_other_from_day0"], len(r["other_before_day0"]), len(r["other_from_day0"]),
           r["dl_ratio"]) == (4, 1, 4, 9, Fr(52, 25)) and r["check_a"] and not r["check_b"],
          f"the falling-downloads fixture should read 4.00/d over 4, 1.00/d over 9, 2.08x, A pass, B fail: {r}")
    b_text = ("check B: the update ratio 2.00x does NOT exceed the first-time download ratio 2.08x — either the shape "
              "a swapped classification produces, OR first-time downloads falling on other days after Aug–Sep, "
              "which needs no swap (other-day first-time downloads 4.00/d before 2026-09-09 over 4 day(s), 1.00/d "
              "from 2026-09-09 over 9 day(s))")
    check(r["failures"] == [b_text], f"check B's failure text: {r['failures']}")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), fall)
    check.rc_and_text("E2 checkpoint: check B fails on falling downloads alone", rc, 5, out,
                      must=("SECOND-CONTROL-FAIL: " + b_text, withheld + " — " + b_text,
                            "    other-day first-time downloads 4.00/d before 2026-09-09 over 4 day(s), 1.00/d from "
                            "2026-09-09 over 9 day(s)\n"),
                      must_not=("BOUND (rule", "WARNING"))

    # 8. The release registry. Every row in these reports carries version 1.32 from 2026-06-06 unless given
    #    another, so the only first appearances are the rows added here. Each case is paired with the passing
    #    report above (exit 0, bound printed), with one row added — one F7 unit on an other day, which leaves
    #    both checks passing, so a withheld bound can only be the registry's doing.
    registry_withheld = "release registry incomplete: version 1.33 first seen 2026-09-19 — no FIRM_RELEASE_DATES_PT"
    warning_1919 = ("  WARNING: version 1.33 first seen 2026-09-19 — its Pacific release date is not in "
                    "FIRM_RELEASE_DATES_PT\n")

    def new_version(*day_version):
        return control_days(add={d: [report_row("F7", 1, "JP", version=v)] for d, v in day_version})

    check(sr.REGISTRY_WATCHED_AFTER == "2026-09-12" and sr.FIRST_SEEN_LAG_DAYS == 3,
          f"the registry check's constants moved: {sr.REGISTRY_WATCHED_AFTER}, {sr.FIRST_SEEN_LAG_DAYS}")
    unreg = new_version(("2026-09-19", "1.33"))
    check(sr.unregistered_versions(unreg) == [("1.33", "2026-09-19")] and not second(unreg)["failures"],
          f"a version first seen 09-19 with no firm date must be named, with both checks still passing: "
          f"{sr.unregistered_versions(unreg)} {second(unreg)['failures']}")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), unreg)
    check.rc_and_text("E2 registry: 1.33 first seen 2026-09-19, no firm date", rc, 5, out,
                      must=(warning_1919, "BOUND WITHHELD:", registry_withheld,
                            "OK — check A: updates elevated on exposure days"),
                      must_not=("BOUND (rule", "SECOND-CONTROL-FAIL", withheld, "calibration failed"))
    with patched(FIRM_RELEASE_DATES_PT=FIRM_BASE + ("2026-09-19",)):
        rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), unreg)
        grouped = second(unreg)["exposure"]
    check.rc_and_text("E2 registry: the same, with 2026-09-19 added to FIRM_RELEASE_DATES_PT", rc, 0, out,
                      must=("BOUND (rule of three",), must_not=("WARNING", "release registry", "BOUND WITHHELD"))
    check(grouped[-2:] == ["2026-09-19", "2026-09-20"], f"CONTROL: the added line did not move 09-19/20: {grouped}")
    # The lag's edge on both sides: 3 days after firm 09-11 is covered, 4 is not. The watched-after edge (09-12 /
    # 09-13) cannot be seen from here, because the lag covers 09-13 as well — so the constant is pinned by hand above.
    for day, want in (("2026-09-12", []), ("2026-09-13", []), ("2026-09-14", []),
                      ("2026-09-15", [("1.33", "2026-09-15")])):
        got = sr.unregistered_versions(new_version((day, "1.33")))
        check(got == want, f"1.33 first seen {day} ({(D.fromisoformat(day) - D(2026, 9, 11)).days} days after firm "
                           f"09-11): expected {want}, got {got}")
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), new_version(("2026-09-13", "1.33")))
    check.rc_and_text("E2 registry: first seen 2 days after firm 2026-09-11", rc, 0, out,
                      must=("BOUND (rule of three",), must_not=("WARNING", "release registry"))
    # A release the box already sorted (1.31's rows begin 09-06, no firm date in the three days before) is not
    # the registry's to report, and an old version reappearing after a newer one is not a first appearance.
    check(sr.unregistered_versions(new_version(("2026-09-06", "1.31"))) == [],
          "a version first seen by 2026-09-12 was reported, although the box sorted its days")
    reappear = control_days(add={"2026-09-06": [report_row("F7", 1, "JP", version="1.31")],
                                 "2026-09-19": [report_row("F1", 1, "JP", version="1.31")]})
    check(sr.unregistered_versions(reappear) == [], "1.31 reappearing on 09-19 was taken for a new release")
    # A later line must not silence an earlier missed one: 09-19 missed, 09-29 registered.
    with patched(FIRM_RELEASE_DATES_PT=FIRM_BASE + ("2026-09-29",)):
        got = sr.unregistered_versions(control_days(end=D(2026, 9, 30), add={
            "2026-09-19": [report_row("F7", 1, "JP", version="1.33")],
            "2026-09-29": [report_row("F7", 1, "JP", version="1.34")]}))
    check(got == [("1.33", "2026-09-19")], f"registering 09-29 silenced the missed 09-19 release: {got}")
    # Only first-time download and update rows count: 1.33 in a redownload row on 09-13 (2 days after firm 09-11)
    # does not make its F7 rows on 09-19 a covered release.
    early_redownload = control_days(add={"2026-09-13": [report_row("F3", 1, "JP", version="1.33")],
                                         "2026-09-19": [report_row("F7", 1, "JP", version="1.33")]})
    check(sr.unregistered_versions(early_redownload) == [("1.33", "2026-09-19")],
          f"a redownload row decided a first appearance: {sr.unregistered_versions(early_redownload)}")
    # A Version column that goes blank reads as a new version, so a format change withholds rather than blinds.
    blank = sr.unregistered_versions(new_version(("2026-09-19", "")))
    rc, out, _ = checkpoint(registry(None, [OWNER_BUY]), new_version(("2026-09-19", "")))
    check(blank == [("", "2026-09-19")] and rc == 5 and "WARNING: version (blank) first seen 2026-09-19" in out,
          f"a blank Version column from 09-19 must withhold, not blind: {blank} exit {rc}\n{out}")
    print("  groups pinned to the box's written-out days · §6's recorded figures reproduced · A alone, B alone "
          "(M4, tie, zero), both · excluded-day spike paired with an other-day spike · --calibrate and "
          "--confirm-known-positive untouched, RELEASE_DAYS pinned · check B names both causes with both means · "
          "an unregistered version withholds, paired with its line added and with every edge · all of it graded "
          "under FIRM_BASE")


def test_second_control(check):
    # The live tuple, by value — as RELEASE_DAYS is pinned in section 6. The release step appends one line to it
    # in sales_report.py; that line is a deliberate one-line diff HERE too, and must change nothing else in this
    # file: every fixture-based check in `second_control_fixtures` types its groups from FIRM_BASE and runs
    # under it. So a red check here means one of two things — a release was registered (pin the new line, from
    # the store's timestamp as the tuple's comment says) or a fixture is reading the live tuple (fix the
    # fixture) — and never that the documented release step broke the suite.
    check(sr.FIRM_RELEASE_DATES_PT == FIRM_BASE + ("2026-09-17",),
          f"FIRM_RELEASE_DATES_PT changed: {sr.FIRM_RELEASE_DATES_PT} — if a release was registered, pin its line "
          f"here; no fixture-based check should have moved with it")
    # The patch is load-bearing, and shown to be. Unpatched, control_days() is grouped by the live tuple, which
    # is NOT the box's grouping — the 09-17 line moves 09-17 and 09-18 into exposure, and the lists in this file
    # do not know that; patched, it is the box's grouping. A patch of the wrong name, or a module that bound its
    # groups at import so setattr no longer reaches them, would fail one side or the other.
    live = second(control_days())["exposure"]
    with patched(FIRM_RELEASE_DATES_PT=FIRM_BASE):
        base = second(control_days())["exposure"]
    check(base == BOX_EXPOSURE, f"under FIRM_BASE the fixture is not grouped as the box wrote it: {base}")
    moved = sorted(set(live) ^ set(base))
    check(set(live) > set(base) and {"2026-09-17", "2026-09-18"} <= set(moved) and min(moved) > "2026-09-12",
          f"CONTROL: unpatched, the live tuple should move 09-17/09-18, and only days after 09-12, into exposure "
          f"— the patch is what holds the fixtures still: moved {moved}")
    # Structural: `sr.FIRM_RELEASE_DATES_PT` is read by this function alone, so what each fixture asserts is fixed
    # by the text of this file, not by which patch is active when it runs. Paired with a planted read.
    source = Path(__file__).read_text(encoding="utf-8")
    check(live_tuple_readers(source) == ["test_second_control"],
          f"sr.FIRM_RELEASE_DATES_PT is read outside the pin: {live_tuple_readers(source)}")
    planted = source.replace("def second_control_fixtures(check):\n",
                             "def second_control_fixtures(check):\n    _ = sr.FIRM_RELEASE_DATES_PT\n", 1)
    check("second_control_fixtures" in live_tuple_readers(planted),
          "CONTROL: the scanner missed a planted read of the live tuple inside the fixtures")
    with patched(FIRM_RELEASE_DATES_PT=FIRM_BASE):
        second_control_fixtures(check)


def live_tuple_readers(source):
    """Top-level functions of this file whose body reads `sr.FIRM_RELEASE_DATES_PT` — the attribute, not the
    name inside a string or a `patched(FIRM_RELEASE_DATES_PT=...)` keyword."""
    return sorted(fn.name for fn in ast.parse(source).body if isinstance(fn, ast.FunctionDef)
                  and any(isinstance(n, ast.Attribute) and n.attr == "FIRM_RELEASE_DATES_PT"
                          and isinstance(n.value, ast.Name) and n.value.id == "sr" for n in ast.walk(fn)))


def second_control_readers(source, names):
    """Top-level functions whose body mentions any of `names`."""
    return sorted({fn.name for fn in ast.parse(source).body if isinstance(fn, ast.FunctionDef)
                   for node in ast.walk(fn) if isinstance(node, ast.Name) and node.id in names})


def _approx(value, want):
    return value is not None and f"{float(value):.2f}" == f"{want:.2f}"


# ---------------------------------------------------------------------------------------------------
# F. --confirm-known-positive

AT = "2026-09-17T10:00:00+09:00"                    # → Pacific 2026-09-16


def confirm(days, kind="purchase", at=AT, platform="macOS", country="JP", reg=None, refetched=None,
            newest=NEWEST):
    fetch = FakeFetch(days, refetched)
    rc, out = capture(sr.run_confirm, reg or registry(), fetch, newest, kind, at, platform, country,
                      today=D(2026, 9, 21))
    return rc, out, fetch


def draft_entry(out):
    marker = f"{sr.DRAFT_LABEL}. Registry entry:\n"
    if marker not in out:
        return None
    body = out.split(marker, 1)[1].split(f"\n{sr.DRAFT_LABEL}. §K sentence:", 1)[0]
    return json.loads(body)


def sentence(out):
    marker = f"{sr.DRAFT_LABEL}. §K sentence:\n"
    return out.split(marker, 1)[1].strip() if marker in out else ""


def test_confirm(check):
    base = window(extra=cohort_extra())
    rc, out, fetch = confirm(base)
    check.rc_and_text("confirm: the owner's purchase is on D", rc, 0, out,
                      must=("Pacific report day D = 2026-09-16", "MATCH on 2026-09-16",
                            "purchase-class rows on 2026-09-15 .. 2026-09-17: 1",
                            "2026-09-16  FI1 → purchase/macOS  units=1  country=JP",
                            "price=150 JPY", "UNCLASSIFIED rows on 2026-09-15 .. 2026-09-17: none",
                            "DRAFT — not recorded; the owner confirms. Registry entry:",
                            "DRAFT — not recorded; the owner confirms. §K sentence:",
                            "appears in the 2026-09-16 (Pacific) daily sales report as FI1 units=1"),
                      must_not=("WARNING", "NO MATCHING ROW"))
    check(fetch.calls == [(D(2026, 9, 15), D(2026, 9, 17), False), (sr.LAUNCH_DATE, NEWEST, True)],
          f"confirm fetched {fetch.calls}, expected D-1..D+1 without cache, then the full window")
    drafted = draft_entry(out)
    check(drafted is not None and drafted["report_day_pt"] == "2026-09-16"
          and drafted["matched_product_type"] == "FI1" and drafted["local_timestamp"] == AT
          and drafted["status"] == "matched",
          f"the draft entry is wrong: {drafted}")
    check(drafted is not None and not sr.validate_registry(registry(None, [drafted])),
          f"the draft entry does not validate: {drafted and sr.validate_registry(registry(None, [drafted]))}")

    # The §K sentence: late is said to be late, and nothing is said to be registered.
    said = sentence(out)
    for needle in ("made 2026-09-17T10:00:00+09:00, 8 days after day 0 (2026-09-09)",
                   "§K's \"before the SKU goes on sale\" was not met",
                   "To be registered as `purchase-2026-09-16-macOS-JP`", "once registered it is excluded",
                   "reported for macOS, the platform PURCHASE maps that code to; Device column: Desktop"):
        check(needle in said, f"the §K draft sentence lacks {needle!r}: {said}")
    for needle in ("Day-0", "day-0 known-positive purchase:", "Registered as", "made 2026-09-17T10:00:00+09:00 on"):
        check(needle not in said, f"the §K draft sentence carries {needle!r}: {said}")
    on_day0 = window(extra=cohort_extra(purchase_day="2026-09-08"))
    rc, out, _ = confirm(on_day0, at="2026-09-09T09:00:00+09:00")           # Pacific 2026-09-08
    check.rc_and_text("CONTROL confirm: a purchase made on day 0", rc, 0, out,
                      must=("on day 0 (2026-09-09); whether that was before the SKU went on sale is not "
                            "something a sales report can show",), must_not=("was not met", "days after day 0"))
    check(sr.days_after_day0("2026-09-10T08:59:00+09:00") == 1
          and sr.days_after_day0("2026-09-09T23:59:00-07:00") == 0,
          "days_after_day0 does not count the date on the buyer's own clock")

    rc, out, fetch = confirm(base, at="2026-09-21T17:00:00+09:00")          # Pacific 09-21 > newest
    check.rc_and_text("confirm: D after the newest report day", rc, 6, out, must=("PENDING",),
                      must_not=("DRAFT",))
    check(fetch.calls == [], f"a pending confirm fetched {fetch.calls}")
    pending_d = window(extra=cohort_extra(purchase_day=None))
    rc, out, _ = confirm(pending_d, at="2026-09-20T12:00:00-07:00",
                         refetched={"2026-09-20": ("pending", "")})
    check.rc_and_text("confirm: D is today's newest but not built", rc, 6, out,
                      must=("PENDING: Apple has not built the 2026-09-20 report",))

    rc, out, _ = confirm(base, platform="iOS")
    check.rc_and_text("confirm: wrong platform", rc, 7, out,
                      must=("NO MATCHING ROW", "2026-09-16  FI1 → purchase/macOS"), must_not=("DRAFT",))

    # A Mac purchase Apple reports under a code PURCHASE maps to iOS: exit 7, but never a flat "no row".
    mac_as_ia1 = window(extra=cohort_extra(purchase_day=None, add={"2026-09-16": [iap("IA1", 1, "JP")]}))
    rc, out, _ = confirm(mac_as_ia1, platform="macOS")
    check.rc_and_text("confirm: a macOS purchase reported under IA1", rc, 7, out,
                      must=("NOT A MATCH: the 2026-09-16 report holds 1 purchase unit(s) for iOS · JP",
                            "    2026-09-16  IA1 → purchase/iOS  units=1  country=JP  device=Desktop",
                            "(Device 'Desktop' → macOS)", "what is in question is PURCHASE's platform map",
                            "Re-running with --platform iOS to get a match is the wrong response",
                            "NO MATCHING ROW for macOS · JP", "the question is PURCHASE's platform map."),
                      must_not=("DRAFT", "NO MATCHING ROW: the"))
    rc, out, _ = confirm(window(extra=cohort_extra(purchase_day=None)), platform="macOS")
    check.rc_and_text("CONTROL confirm: no purchase on either platform", rc, 7, out,
                      must=("NO MATCHING ROW: the 2026-09-16 report holds no purchase units for macOS · JP.",),
                      must_not=("NOT A MATCH", "PURCHASE's platform map"))
    ios_other_day = window(extra=cohort_extra(purchase_day=None, add={"2026-09-17": [iap("IA1", 1, "JP")]}))
    rc, out, _ = confirm(ios_other_day, platform="macOS")
    check.rc_and_text("CONTROL confirm: the other platform's row on D+1 is not D", rc, 7, out,
                      must=("NO MATCHING ROW: the",), must_not=("NOT A MATCH",))
    ios_other_country = window(extra=cohort_extra(purchase_day=None, add={"2026-09-16": [iap("IA1", 1, "CN")]}))
    rc, out, _ = confirm(ios_other_country, platform="macOS")
    check.rc_and_text("CONTROL confirm: the other platform's row in another country", rc, 7, out,
                      must=("NO MATCHING ROW: the",), must_not=("NOT A MATCH",))
    refund_as_ia1 = window(extra=cohort_extra(add={"2026-09-19": [iap("IA1", -1, "JP", device="iPhone")]}))
    rc, out, _ = confirm(refund_as_ia1, kind="refund", at="2026-09-19T12:00:00-07:00")
    check.rc_and_text("confirm: a refund under the other platform's code", rc, 7, out,
                      must=("NOT A MATCH: the 2026-09-19 report holds 1 refund unit(s) for iOS · JP",
                            "(Device 'iPhone' → iOS)", "NO MATCHING ROW for macOS · JP"))

    # A match whose Device contradicts --platform: the draft carries a WARNING, in print and in its notes.
    rc, out, _ = confirm(mac_as_ia1, platform="iOS")
    warning = ("WARNING: a matched row's Device is 'Desktop' (macOS), which contradicts --platform iOS: the "
               "draft's platform is PURCHASE's reading of IA1, not the device's")
    check.rc_and_text("confirm: matched under iOS, Device Desktop", rc, 0, out, must=(warning,))
    drafted = draft_entry(out)
    check(warning in out and out.index(warning) < out.index(f"{sr.DRAFT_LABEL}. Registry entry:")
          and drafted is not None and "WARNING: a matched row's Device is 'Desktop' (macOS)" in drafted["notes"],
          f"the Device warning is not on the draft: notes {drafted and drafted['notes']}")
    check("reported for iOS" in sentence(out) and "Device column: Desktop" in sentence(out),
          f"the §K draft sentence hides the device: {sentence(out)}")
    iphone = window(extra=cohort_extra(purchase_day=None,
                                       add={"2026-09-16": [iap("IA1", 1, "JP", device="iPhone")]}))
    rc, out, _ = confirm(iphone, platform="iOS")
    check.rc_and_text("CONTROL confirm: matched under iOS, Device iPhone", rc, 0, out,
                      must=(sr.DRAFT_LABEL, "Device column: iPhone"), must_not=("WARNING",))
    rc, out, _ = confirm(base, platform="macOS")
    check.rc_and_text("CONTROL confirm: matched under macOS, Device Desktop", rc, 0, out,
                      must=(sr.DRAFT_LABEL,), must_not=("WARNING",))
    watch = window(extra=cohort_extra(purchase_day=None,
                                      add={"2026-09-16": [iap("FI1", 1, "JP", device="Apple Watch")]}))
    rc, out, _ = confirm(watch, platform="macOS")
    check.rc_and_text("confirm: a Device value this tool does not read", rc, 0, out,
                      must=("WARNING: a matched row's Device is 'Apple Watch', which this tool does not read as "
                            "a platform",))
    rc, out, _ = confirm(base, country="CN")
    check.rc_and_text("confirm: wrong country", rc, 7, out, must=("NO MATCHING ROW",))
    rc, out, _ = confirm(base, at="2026-09-16T08:00:00+09:00")               # Pacific 09-15
    check.rc_and_text("confirm: the row is on D+1", rc, 7, out,
                      must=("note: 2026-09-16 (not D) holds 1 purchase unit(s)",))

    odd = window(extra=cohort_extra(add={"2026-09-17": [iap("IA7", 1, "JP")]}))
    rc, out, _ = confirm(odd)
    check.rc_and_text("confirm: an unknown code beside the purchase", rc, 4, out,
                      must=("UNCLASSIFIED 2026-09-17  IA7 → unclassified", "NOT CONFIRMED"),
                      must_not=("DRAFT",))

    rc, out, _ = confirm(window(extra=cohort_extra(), flat_updates=True))
    check.rc_and_text("confirm: calibration fails", rc, 4, out, must=("NOT CONFIRMED",),
                      must_not=("DRAFT",))
    rc, out, _ = confirm(window(extra=cohort_extra(), flat_updates=True), platform="iOS")
    check.rc_and_text("confirm: calibration fails AND no row (4 wins over 7)", rc, 4, out,
                      must=("NOT CONFIRMED",), must_not=("NO MATCHING ROW:",))
    odd_d = window(extra=cohort_extra(add={"2026-09-16": [iap("IA7", 1, "JP")]}))["2026-09-16"]
    rc, out, _ = confirm(base, refetched={"2026-09-16": odd_d})
    check.rc_and_text("confirm: an unknown code only in the refetched D reaches calibration", rc, 4, out,
                      must=("CALIBRATION-FAIL: 1 row(s) carry a code this classifier does not know: IA7",))

    shared = window(extra=cohort_extra(add={"2026-09-16": [iap("FI1", 1, "JP")]}))
    rc, out, _ = confirm(shared)
    check.rc_and_text("confirm: a customer in the same cell", rc, 0, out,
                      must=("WARNING: the matched cell holds 2 units",))

    refund = window(extra=cohort_extra(add={"2026-09-19": [iap("FI1", -1, "JP")]}))
    rc, out, _ = confirm(refund, kind="refund", at="2026-09-19T12:00:00-07:00")
    check.rc_and_text("confirm: the owner's refund", rc, 0, out,
                      must=("MATCH on 2026-09-19: refund", "as FI1 units=-1"))
    drafted = draft_entry(out)
    check(drafted is not None and drafted["kind"] == "refund"
          and not sr.validate_registry(registry(None, [drafted])), f"the refund draft is wrong: {drafted}")
    said = sentence(out)
    check("which purchase is not recorded yet: the registry holds no matched purchase entry for macOS · JP"
          in said and "To be registered as `refund-2026-09-19-macOS-JP`" in said
          and "Registered as" not in said and "day-0 known-positive:" not in said,
          f"the refund draft sentence, with no purchase registered: {said}")
    rc, out, _ = confirm(refund, kind="refund", at="2026-09-19T12:00:00-07:00", reg=registry(None, [OWNER_BUY]))
    said = sentence(out)
    check(rc == 0 and "the purchase registered as `owner-buy`, made 2026-09-17T10:00:00+09:00, 8 days after "
          "day 0 (2026-09-09); the SKU was on sale by day 0, so §K's \"before the SKU goes on sale\" was not "
          "met" in said and "Registered as" not in said,
          f"the refund draft sentence, with the purchase registered: rc {rc}: {said}")

    fetch = FakeFetch(base)
    rc, out = capture(sr.run_confirm, registry(None, [entry("x", units=0)]), fetch, NEWEST, "purchase",
                      AT, "macOS", "JP")
    check.rc_and_text("confirm: invalid registry", rc, 4, out, must=("REGISTRY-INVALID",))
    check(fetch.calls == [], f"an invalid registry still fetched: {fetch.calls}")

    # D-1..D+1 are read from the no-cache fetch, and calibration sees that same report.
    stale = window(extra=cohort_extra(purchase_day=None))
    rc, out, _ = confirm(stale, refetched={"2026-09-16": base["2026-09-16"]})
    check.rc_and_text("confirm: the row exists only in the refetched report", rc, 0, out,
                      must=("MATCH on 2026-09-16",))
    rc, out, _ = confirm(stale)
    check.rc_and_text("CONTROL confirm: the same, with no row anywhere", rc, 7, out, must=("NO MATCHING ROW",))

    taken = registry(None, [entry("purchase-2026-09-16-macOS-JP")])
    rc, out, _ = confirm(base, reg=taken)
    drafted = draft_entry(out)
    check(drafted is not None and drafted["id"] == "purchase-2026-09-16-macOS-JP-2",
          f"the draft reused an existing id: {drafted}")
    check("the registry already holds 1 unit(s) for this cell" in out, "an already-registered cell is not noted")


# ---------------------------------------------------------------------------------------------------
# G. the command line

def fake_collect(days_by_call):
    calls = []

    def collect(token, vendor, start, end, use_cache=True):
        calls.append((start, end, use_cache))
        if isinstance(days_by_call, Exception):
            raise days_by_call
        return {k: days_by_call.get(k, ("pending", "")) for k in sr._day_keys(start, end)}
    collect.calls = calls
    return collect


def test_collect_cache(check):
    """collect() is where use_cache is honoured. The --confirm refetch is only as fresh as these two
    guards: dropping either `use_cache and` makes a confirm read a day cached before the owner's row
    existed, and every seam-level test above would stay green (review 2026-09-16)."""
    day = D(2026, 9, 16)
    with tempfile.TemporaryDirectory() as tmp:
        saved = (sr.CACHE_DIR, sr.fetch_day)
        calls = []

        def fake_fetch(token, vendor, d):
            calls.append(d)
            return "data", f"FRESH {d.isoformat()}"
        try:
            sr.CACHE_DIR = Path(tmp)
            sr.fetch_day = fake_fetch
            (Path(tmp) / f"{day.isoformat()}.tsv").write_text("STALE tsv", encoding="utf-8")
            (Path(tmp) / f"{(day + dt.timedelta(days=1)).isoformat()}.nosales").write_text(
                "STALE nosales", encoding="utf-8")
            fresh = sr.collect(None, None, day, day + dt.timedelta(days=1), use_cache=False)
            check(calls == [day, day + dt.timedelta(days=1)],
                  f"collect(use_cache=False) must fetch every day, fetched {calls}")
            check(fresh[day.isoformat()] == ("data", f"FRESH {day.isoformat()}") and
                  fresh[(day + dt.timedelta(days=1)).isoformat()][1].startswith("FRESH"),
                  f"collect(use_cache=False) returned cached payloads: {fresh}")
            # Paired control: with the cache, the planted files answer and nothing is fetched.
            for f in Path(tmp).iterdir():
                f.unlink()
            (Path(tmp) / f"{day.isoformat()}.tsv").write_text("STALE tsv", encoding="utf-8")
            (Path(tmp) / f"{(day + dt.timedelta(days=1)).isoformat()}.nosales").write_text(
                "STALE nosales", encoding="utf-8")
            calls.clear()
            cached = sr.collect(None, None, day, day + dt.timedelta(days=1), use_cache=True)
            check(calls == [] and cached[day.isoformat()] == ("data", "STALE tsv") and
                  cached[(day + dt.timedelta(days=1)).isoformat()] == ("nosales", "STALE nosales"),
                  f"CONTROL: collect(use_cache=True) must answer from the planted cache: {calls} {cached}")
        finally:
            sr.CACHE_DIR, sr.fetch_day = saved


def test_cli(check):
    usage = [
        ["--checkpoint", "--calibrate"], ["--checkpoint", "--json", "x.json"], ["--checkpoint", "--no-cache"],
        ["--checkpoint", "--since", "2026-09-09"], ["--checkpoint", "--confirm-known-positive"],
        ["--kind", "purchase"], ["--calibrate", "--country", "JP"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS", "--country", "JPN"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS", "--country", "jp"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", "2026-09-17T10:00:00", "--platform",
         "macOS", "--country", "JP"],
        ["--confirm-known-positive", "--kind", "sale", "--at", AT, "--platform", "macOS", "--country", "JP"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS", "--country",
         "JP", "--until", "2026-09-14"],
        ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS", "--country",
         "JP", "--daily"],
    ]
    base = window(extra=cohort_extra())
    collect = fake_collect(base)
    with tempfile.TemporaryDirectory() as tmp:
        reg_path = Path(tmp) / "registry.json"
        reg_path.write_text(json.dumps(registry(None, [OWNER_BUY])), encoding="utf-8")
        before = reg_path.read_bytes()
        env = dict(resolve_vendor_number=lambda v: "12345678", make_jwt=lambda: "token",
                   collect=collect, REGISTRY_PATH=reg_path, pacific_today=lambda: D(2026, 9, 21))
        with patched(**env):
            for argv in usage:
                rc, out = capture(sr.main, argv)
                check(rc == 2, f"usage error {argv} exited {rc}, expected 2\n{out}")
            check(collect.calls == [], f"a usage error reached the report: {collect.calls}")

            rc, out = capture(sr.main, ["--confirm-known-positive", "--kind", "purchase", "--at", AT,
                                        "--platform", "macOS", "--country", "JP"])
            check.rc_and_text("POSITIVE CONTROL main confirm", rc, 0, out, must=(sr.DRAFT_LABEL,))
            # Through the REAL fetcher, not the injected seam: D-1..D+1 must reach collect() with the
            # cache off, or confirm reads D from a TSV an earlier baseline or checkpoint run cached.
            check(collect.calls == [(D(2026, 9, 15), D(2026, 9, 17), False), (sr.LAUNCH_DATE, NEWEST, True)],
                  f"main --confirm-known-positive reached collect() as {collect.calls}, expected D-1..D+1 "
                  f"with use_cache False, then the full window with the cache")
            calls_before = len(collect.calls)
            rc, out = capture(sr.main, ["--checkpoint", "--until", "2026-09-20", "--daily"])
            check.rc_and_text("main checkpoint", rc, 0, out,
                              must=("BOUND (rule of three", "2026-09-16  dl=  1 (mac  1 ios  0)  buy=1"))
            check(collect.calls[calls_before:] == [(sr.LAUNCH_DATE, NEWEST, True)],
                  f"main --checkpoint reached collect() as {collect.calls[calls_before:]}, expected the full "
                  f"window once, with the cache")
            check(reg_path.read_bytes() == before, "a mode wrote the registry")

            reg_path.write_text('{"schema": 1}', encoding="utf-8")
            with patched(resolve_vendor_number=lambda v: None):
                rc, out = capture(sr.main, ["--checkpoint"])
                check.rc_and_text("main checkpoint, invalid registry, no vendor", rc, 4, out,
                                  must=("--checkpoint: REGISTRY-INVALID", "missing top-level key 'entries'"))
                reg_path.write_text(json.dumps(registry()), encoding="utf-8")
                rc, out = capture(sr.main, ["--checkpoint"])
                check.rc_and_text("main checkpoint, valid registry, no vendor", rc, 2, out,
                                  must=("VENDOR-NUMBER-MISSING",))
                rc, out = capture(sr.main, [])
                check.rc_and_text("main default, no vendor", rc, 2, out, must=("VENDOR-NUMBER-MISSING",))

        with patched(**dict(env, collect=fake_collect(RuntimeError("auth failed (401): planted")))):
            for argv in (["--checkpoint"], ["--calibrate"],
                         ["--confirm-known-positive", "--kind", "purchase", "--at", AT, "--platform", "macOS",
                          "--country", "JP"]):
                rc, out = capture(sr.main, argv)
                check.rc_and_text(f"API failure {argv}", rc, 3, out, must=("API-FAILURE: auth failed",))

        # The existing path is unchanged in shape: no new-mode text, same exit codes.
        with patched(**dict(env, collect=fake_collect(base))):
            rc, out = capture(sr.main, ["--calibrate", "--until", "2026-09-20"])
            check.rc_and_text("main --calibrate", rc, 0, out,
                              must=("window 2026-06-06 .. 2026-09-20  (107 days)", "calibration:\n",
                                    "OK — the instrument responds"),
                              must_not=("checkpoint", "DRAFT", "BOUND", "cohort"))
        with patched(**dict(env, collect=fake_collect(window(extra=cohort_extra(), flat_updates=True)))):
            rc, out = capture(sr.main, ["--calibrate"])
            check.rc_and_text("main --calibrate on a broken report", rc, 4, out, must=("CALIBRATION-FAIL",))


# ---------------------------------------------------------------------------------------------------
# H. what the file may write, and what it may import

WRITE_CALLS = {"write_text", "write_bytes", "replace", "rename", "unlink", "mkdir", "rmdir", "open",
               "dump", "touch", "symlink_to"}


def write_sites(source):
    sites = []
    for fn in ast.parse(source).body:
        if not isinstance(fn, ast.FunctionDef):
            continue
        for node in ast.walk(fn):
            if isinstance(node, ast.Call):
                name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
                if name in WRITE_CALLS:
                    sites.append((fn.name, name))
    return sites


def test_writes(check):
    source = Path(sr.__file__).read_text(encoding="utf-8")
    sites = write_sites(source)
    outside = sorted({s for s in sites if s[0] not in ("collect", "main")})
    check(not outside, f"file writes outside collect (the cache) and main (--json): {outside}")
    check(("collect", "write_text") in sites and ("main", "replace") in sites,
          f"POSITIVE CONTROL: the scanner no longer sees the two writes that exist: {sites}")
    planted = source + "\n\ndef run_confirm_planted():\n    REGISTRY_PATH.write_text('{}')\n"
    check(("run_confirm_planted", "write_text") in write_sites(planted),
          "CONTROL: the write scanner missed a planted registry write")
    check(not JWT_IMPORTED_AT_LOAD, "importing sales_report imported jwt — CI installs nothing")
    imports = [(fn.name if isinstance(fn, ast.FunctionDef) else "<module>")
               for fn in ast.parse(source).body for node in ast.walk(fn)
               if isinstance(node, (ast.Import, ast.ImportFrom))
               and any(a.name.split(".")[0] == "jwt" for a in node.names)]
    check(imports == ["make_jwt"], f"jwt is imported somewhere other than make_jwt: {imports}")


def main():
    check = Checks()
    print("A. ONE CLASSIFICATION RULE")
    test_classification(check)
    print("B. PACIFIC REPORT DAY")
    test_pacific_day(check)
    print("C. REGISTRY VALIDATION")
    test_registry(check)
    print("D. EXCLUSION")
    test_exclusion(check)
    print("E. --checkpoint")
    test_checkpoint(check)
    print("E1. REGISTERED SESSION PARTICIPANTS (§K box 2026-09-24)")
    test_participants(check)
    print("E2. THE SECOND RELEASE-DAY CONTROL (--checkpoint only)")
    test_second_control(check)
    print("F. --confirm-known-positive")
    test_confirm(check)
    print("G. COMMAND LINE")
    test_cli(check)
    print("G2. collect() HONOURS use_cache")
    test_collect_cache(check)
    print("H. WRITES AND IMPORTS")
    test_writes(check)

    if check.problems:
        print(f"\n{len(check.problems)} FAILURE(S) of {check.count} checks:")
        for p in check.problems:
            print(f"\nFAIL  {p}")
        return 1
    print(f"\n{check.count} checks: one classification rule, Pacific days, a strict registry, a "
          f"subtraction that is shown able to fail, every withholding reason paired, and no writes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
