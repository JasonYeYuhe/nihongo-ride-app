#!/usr/bin/env python3
"""Stage 1 owner walk: read-only preflight and state snapshots for docs/PLAN-STAGE1.md §K and §L.

WHAT THIS IS FOR
----------------
The three manual purchase gates (§L) and the day-0 known-positive purchase (§K) are walked by the
owner, on the owner's own Mac, iPhone and a family member's device. Every one of them can be
walked on the wrong thing and still produce a clean-looking answer: an old local build launched
by LaunchServices instead of the App Store binary, a container that already holds a verified
record (so "Opened" proves nothing), a device whose installed copy came from Xcode. This script
asks those questions of the machine before and during the walk, and saves what it saw.

WHAT IT NEVER DOES (and `scripts/test_stage1_walk.py` scans this file to keep it that way)
-----------------------------------------------------------------------------------------
It never opens the App Store, never installs or removes anything, never signs in or out of any
Apple Account, never purchases or restores, never writes any defaults domain or container
(`defaults write` / `defaults delete` / `defaults import` are refused by the runner and by the
source scan), never sends anything but GET to App Store Connect, and never writes the
known-positive registry. Every external command goes through `_run_readonly`, which refuses any
argv that is not on a short allowlist of read-only forms. The only files it writes are snapshots
under "$HOME/Library/Application Support/NihongoRide-Stats/walk/<UTC timestamp>/", outside the
repo; `baseline` additionally lets `sales_report.py` write its `--json` output into that snapshot
(and `sales_report.py` keeps its own download cache, as it always has).

SUBCOMMANDS AND EXIT CODES
--------------------------
    python3 scripts/stage1_walk.py preflight      0 no FAIL · 1 any FAIL · 3 ASC/API failure
                                                  (3 wins over 1: a preflight whose ASC half did
                                                  not run is incomplete, whatever else it found)
    python3 scripts/stage1_walk.py mac-state      0
    python3 scripts/stage1_walk.py ios-state      0 · 2 no paired iOS device could be read
    python3 scripts/stage1_walk.py baseline       0 both runs saved, --calibrate exited 0 and
                                                  --checkpoint exited 0 or 5 (5 = bound withheld,
                                                  the expected state before a matched
                                                  known-positive) · otherwise the first
                                                  unexpected exit code of the two runs
    python3 scripts/stage1_walk.py manifest DIR   0 · 2 DIR is not a directory

MEASURED WHILE WRITING THIS (2026-09-16, Xcode 27.0, macOS 27.0) — each one changed the code
------------------------------------------------------------------------------------------
* `xcrun devicectl device info apps` WITHOUT `--include-all-apps` lists only what devicectl calls
  developer apps ("By default, only developer apps are included", its own --help). On the paired
  iPhone "js" the default listing returned 6 apps, every one `builtByDeveloper: true`; with
  `--include-all-apps` it returned 195, of which 116 removable apps were `builtByDeveloper: false`
  (1Password, Alipay, Amazon…). So the obvious command would report an App Store install of
  Nihongo Ride as NOT INSTALLED. This script always passes `--include-all-apps`, filters by
  bundle id itself, and treats an empty listing as "not readable", never as "not installed".
  `builtByDeveloper` is printed raw; that an App Store copy of THIS app reads `false` is not
  verified (no App Store copy was installed on any device at the time).
* On a locked device devicectl fails with CoreDeviceError 12040 wrapping 10003 ("The device is
  currently locked."), after trying to mount the developer disk image. On an UNLOCKED device it
  succeeds by mounting it: `devicectl list devices` showed `ddiServicesAvailable: false` and tunnel
  `disconnected` for both unlocked iPhones before the first `device info apps`, and `true` /
  `connected` after. So listing apps is NOT free of device-side effects: it mounts the developer
  disk image and opens a CoreDevice tunnel. It installs, removes and changes no app, account,
  purchase or app data. Every run that queries a device says so on screen.
* `defaults read <domain> <key>` prints a data value in full only up to 24 bytes
  (`{length = 24, bytes = 0x…}`); from 25 bytes it prints `{length = N, bytes = 0x… ... …}`,
  truncated. The entitlement record is always longer than that. So PRESENCE is taken from
  `defaults read` (which distinguishes "key not found" from "domain not found"), and the VALUE
  from `defaults export <domain> -` (complete, base64 in XML); the on-disk plist is the fallback,
  and every line says which source answered. `defaults export` of a domain that does not exist
  exits 0 with an empty dict, so an export alone is never used to conclude "absent". Whether
  cfprefsd serves a running sandboxed app's not-yet-flushed values to a path-domain read from
  outside the sandbox is NOT verified here.
* Swift's default `JSONEncoder` (Entitlement.swift uses `JSONEncoder()` / `JSONDecoder()` with no
  date strategy) writes `Date` as seconds since 2001-01-01T00:00:00Z, a JSON number, omits nil
  optionals, and writes an integral Double as an integer. Measured by compiling the shipped
  Sources/EntitlementKit/Entitlement.swift with swiftc and saving records through
  `EntitlementLedger.save(to:)`; `Date(timeIntervalSinceReferenceDate: 811180000.25)` printed
  2026-09-15T15:46:40Z, and `date -r 1789487200 -u` agrees. The test embeds those exact bytes.
* `ps -axww -o pid=,comm=` prints the full executable path (observed up to 326 characters).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parent.parent
ASC_API = REPO / "scripts" / "asc_api.sh"
SALES_REPORT = REPO / "scripts" / "sales_report.py"
ASC_BASE = "https://api.appstoreconnect.apple.com"

# --- Expected App Store state ---------------------------------------------------------------
# These describe RELEASE 1.32 as measured on 2026-09-16 (macOS 1.32 build 56 and iOS 1.32 build 57,
# both READY_FOR_SALE; the purchase APPROVED and not family-sharable). If a newer version ships
# before the walk, UPDATE THEM in the same change — a preflight that expects a superseded build
# fails for the right reason, but only if somebody reads why.
EXPECTED_VERSION = "1.32"
EXPECTED_MAC_BUILD = "56"
EXPECTED_IOS_BUILD = "57"
EXPECTED_VERSION_STATE = "READY_FOR_SALE"
APP_ID = "6777469778"
IAP_ID = "6806755720"
PRODUCT_ID = "com.jasonye.nihongoride.scenery.lifetime"
EXPECTED_IAP_STATE = "APPROVED"
EXPECTED_FAMILY_SHARABLE = False
# A review submission in any state other than this one is counted as OPEN, including states this
# script has never seen: an unknown state must not be able to pass as "nothing open".
TERMINAL_SUBMISSION_STATE = "COMPLETE"

# --- This Mac --------------------------------------------------------------------------------
BUNDLE_ID = "com.jasonye.nihongoride"
MAC_APP = Path("/Applications/Nihongo Ride.app")
CONTAINER_PREFS = (Path.home() / "Library/Containers" / BUNDLE_ID /
                   "Data/Library/Preferences" / (BUNDLE_ID + ".plist"))
SNAPSHOT_ROOT = Path.home() / "Library/Application Support/NihongoRide-Stats/walk"

# The keys EntitlementKit writes (Entitlement.swift, UnlockOfferLedger.swift).
ENTITLEMENT_KEY = "NihongoRide.entitlement.v1"
QUARANTINE_KEY = ENTITLEMENT_KEY + ".unreadable"
OFFER_KEY = "NihongoRide.unlockOffer.v1"
# RoadBucket raw values 0…7 (UnlockOfferLedger.swift).
ROAD_BUCKETS = ("nihonbashi", "kawasaki", "hakone", "fuji", "hamanako", "nagoya", "suzuka", "kyoto")

# Swift `Date` encodes as seconds since this instant (Foundation's reference date).
REFERENCE_DATE = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)

# The only programs this script runs, by absolute path.
DEFAULTS = "/usr/bin/defaults"
CODESIGN = "/usr/bin/codesign"
MDFIND = "/usr/bin/mdfind"
PS = "/bin/ps"
XCRUN = "/usr/bin/xcrun"
BASH = "/bin/bash"

LAUNCH_ADVICE = 'launch only via `open "/Applications/Nihongo Ride.app"`'


# =============================================================================================
# The one door to the outside
# =============================================================================================

@dataclass
class Completed:
    argv: List[str]
    returncode: Optional[int]  # None: the command did not run to completion (missing, timed out)
    stdout: str
    stderr: str
    error: str = ""


class ReadOnlyViolation(Exception):
    """An argv that is not one of the read-only forms below. Raised before anything runs."""


def _inside(path: Path, root: Path) -> bool:
    real_path = os.path.realpath(str(path))
    real_root = os.path.realpath(str(root))
    return os.path.commonpath([real_path, real_root]) == real_root


def _flags_only(rest: List[str], spec: Dict[str, int]) -> bool:
    """True if `rest` is made only of flags in `spec`, each followed by its declared arity, and
    any `--json-output` path lies inside the temporary directory."""
    i = 0
    while i < len(rest):
        arity = spec.get(rest[i])
        if arity is None or i + arity >= len(rest) + (1 if arity == 0 else 0):
            return False
        if rest[i] == "--json-output" and not _inside(Path(rest[i + 1]),
                                                      Path(tempfile.gettempdir())):
            return False
        i += 1 + arity
    return True


def _assert_readonly_argv(argv: List[str], snapshot_root: Path) -> None:
    """Refuse anything but the read-only command forms this script needs.

    An allowlist, not a denylist: a new command has to be added here on purpose, where a reviewer
    will see it, rather than slipping past a list of verbs somebody remembered to forbid.
    """
    argv = [str(a) for a in argv]
    prog = argv[0] if argv else ""
    rest = argv[1:]
    ok = False
    if prog == DEFAULTS:
        ok = (len(rest) == 3 and rest[0] == "read") or \
             (len(rest) == 3 and rest[0] == "export" and rest[2] == "-")
    elif prog == CODESIGN:
        ok = len(rest) == 3 and rest[:2] == ["-dv", "--verbose=2"]
    elif prog == MDFIND:
        ok = len(rest) == 1 and not rest[0].startswith("-")
    elif prog == PS:
        ok = rest == ["-axww", "-o", "pid=,comm="]
    elif prog == XCRUN:
        if rest[:3] == ["devicectl", "list", "devices"]:
            ok = _flags_only(rest[3:], {"--timeout": 1, "--json-output": 1})
        elif rest[:4] == ["devicectl", "device", "info", "apps"]:
            ok = _flags_only(rest[4:], {"--device": 1, "--include-all-apps": 0,
                                        "--timeout": 1, "--json-output": 1})
    elif prog == BASH:
        ok = (len(rest) == 3 and rest[0] == str(ASC_API) and rest[1] == "GET"
              and rest[2].startswith("/v"))
    elif prog == sys.executable and rest[:1] == [str(SALES_REPORT)]:
        tail = rest[1:]
        ok = tail == ["--checkpoint"] or (
            len(tail) == 3 and tail[:2] == ["--calibrate", "--json"]
            and _inside(Path(tail[2]), snapshot_root))
    if not ok:
        raise ReadOnlyViolation(f"refusing to run a command that is not on the read-only "
                                f"allowlist: {argv!r}")


def _run_readonly(argv: List[str], timeout: float, cwd: Optional[str] = None,
                  snapshot_root: Optional[Path] = None) -> Completed:
    argv = [str(a) for a in argv]
    _assert_readonly_argv(argv, snapshot_root if snapshot_root is not None else SNAPSHOT_ROOT)
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=timeout, cwd=cwd,
                              stdin=subprocess.DEVNULL)
    except FileNotFoundError as exc:
        return Completed(argv, None, "", "", f"not found: {exc}")
    except subprocess.TimeoutExpired:
        return Completed(argv, None, "", "", f"timed out after {timeout:.0f}s")
    return Completed(argv, proc.returncode, proc.stdout or "", proc.stderr or "")


# =============================================================================================
# Snapshots — the only files this script writes
# =============================================================================================

def _snapshot_dir(root: Path, now: dt.datetime) -> Path:
    path = root / now.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if not _inside(path, root) or _inside(path, REPO):
        raise ReadOnlyViolation(f"snapshot directory {path} is not inside {root} or is inside "
                                f"the repo")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _snapshot_write(snap: Path, root: Path, name: str, content: Any) -> Path:
    # A bare file name only: "../x" would still land under the walk root, but outside THIS
    # snapshot, where it could overwrite another run's evidence.
    if os.path.basename(name) != name or name in ("", ".", ".."):
        raise ReadOnlyViolation(f"refusing snapshot file name {name!r}: not a bare file name")
    target = snap / name
    if not (_inside(snap, root) and _inside(target, snap)) or _inside(target, REPO):
        raise ReadOnlyViolation(f"refusing to write {target}: not inside a snapshot under {root}, "
                                f"or inside the repo")
    stem, suffix = os.path.splitext(name)
    n = 1
    while target.exists():
        n += 1
        target = snap / f"{stem}-{n}{suffix}"
    if isinstance(content, bytes):
        target.write_bytes(content)
    else:
        target.write_text(content, encoding="utf-8")
    return target


# =============================================================================================
# Output
# =============================================================================================

LEVELS = ("PASS", "WARN", "FAIL", "INFO")


class Report:
    def __init__(self, out=None):
        self.out = out if out is not None else sys.stdout
        self.lines: List[str] = []
        self.counts = {level: 0 for level in LEVELS}
        self.api_failures: List[str] = []
        self.facts: Dict[str, Any] = {}

    def _emit(self, line: str) -> None:
        print(line, file=self.out, flush=True)
        self.lines.append(line)

    def add(self, level: str, text: str) -> None:
        self.counts[level] += 1
        first, *more = text.split("\n")
        self._emit(f"{level}  {first}")
        for extra in more:
            self._emit(f"      {extra}")

    def passed(self, text):
        self.add("PASS", text)

    def warn(self, text):
        self.add("WARN", text)

    def fail(self, text):
        self.add("FAIL", text)

    def info(self, text):
        self.add("INFO", text)

    def api(self, text: str) -> None:
        self.api_failures.append(text)
        self._emit(f"API   {text}")

    def heading(self, text: str) -> None:
        self._emit("")
        self._emit(f"== {text}")

    def plain(self, text: str) -> None:
        self._emit(text)

    def transcript(self) -> str:
        return "\n".join(self.lines) + "\n"


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


@dataclass
class Context:
    app_path: Path = MAC_APP
    container_prefs: Path = CONTAINER_PREFS
    snapshot_root: Path = SNAPSHOT_ROOT
    run: Optional[Callable[..., Completed]] = None
    asc_get: Optional[Callable[[str], dict]] = None
    own_pid: int = field(default_factory=os.getpid)
    now: Callable[[], dt.datetime] = _utcnow

    def __post_init__(self):
        if self.run is None:
            root = self.snapshot_root

            def run(argv, timeout, cwd=None):
                return _run_readonly(argv, timeout, cwd, snapshot_root=root)
            self.run = run
        if self.asc_get is None:
            runner = self.run

            def get(endpoint):
                return asc_get(endpoint, runner)
            self.asc_get = get


# =============================================================================================
# App Store Connect (GET only)
# =============================================================================================

class AscError(Exception):
    pass


def asc_get(endpoint: str, run: Callable[..., Completed]) -> dict:
    """One GET. A non-zero exit, an empty body, non-JSON or an `errors` payload is a failure."""
    r = run([BASH, str(ASC_API), "GET", endpoint], timeout=120, cwd=str(REPO))
    if r.returncode != 0:
        raise AscError(f"GET {endpoint}: asc_api.sh exit {r.returncode} {r.error} "
                       f"{r.stderr.strip()[:300]}".strip())
    if not r.stdout.strip():
        raise AscError(f"GET {endpoint}: empty body")
    try:
        payload = json.loads(r.stdout)
    except ValueError:
        raise AscError(f"GET {endpoint}: non-JSON body {r.stdout[:200]!r}")
    if not isinstance(payload, dict):
        raise AscError(f"GET {endpoint}: body is not a JSON object")
    if payload.get("errors"):
        first = payload["errors"][0] if isinstance(payload["errors"], list) else payload["errors"]
        raise AscError(f"GET {endpoint}: {json.dumps(first)[:300]}")
    return payload


def asc_get_all(endpoint: str, get: Callable[[str], dict]) -> List[dict]:
    items: List[dict] = []
    current: Optional[str] = endpoint
    pages = 0
    while current:
        payload = get(current)
        data = payload.get("data")
        if not isinstance(data, list):
            raise AscError(f"GET {current}: `data` is not a list")
        items.extend(data)
        pages += 1
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        if not str(nxt).startswith(ASC_BASE) or pages >= 20:
            raise AscError(f"GET {current}: unexpected paging link {nxt!r} after {pages} pages")
        current = str(nxt)[len(ASC_BASE):]
    return items


def parse_iso(text: str) -> dt.datetime:
    """ISO-8601 with an offset or Z and 0–6 fraction digits, on python 3.9 as well."""
    s = str(text).strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?([+-]\d\d:\d\d)?$", s)
    if not m:
        raise ValueError(f"not an ISO-8601 timestamp: {text!r}")
    base, frac, offset = m.groups()
    digits = ((frac or ".")[1:] + "000000")[:6]
    return dt.datetime.fromisoformat(f"{base}.{digits}{offset or '+00:00'}")


def check_asc(report: Report, ctx: Context) -> None:
    report.heading("App Store Connect (GET only, via scripts/asc_api.sh)")
    get = ctx.asc_get
    facts: Dict[str, Any] = {}
    try:
        for platform, label, build_expected in (("MAC_OS", "macOS", EXPECTED_MAC_BUILD),
                                                ("IOS", "iOS", EXPECTED_IOS_BUILD)):
            versions = asc_get_all(
                f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}&limit=200"
                f"&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate", get)
            if not versions:
                report.api(f"{label}: App Store Connect returned no versions at all — this app "
                           f"has shipped dozens, so an empty list is a broken read, not a state")
                continue
            try:
                newest = max(versions, key=lambda v: parse_iso(v["attributes"]["createdDate"]))
            except (KeyError, TypeError, ValueError) as exc:
                report.api(f"{label}: a version has no usable createdDate ({exc})")
                continue
            attrs = newest.get("attributes") or {}
            vstr, state = attrs.get("versionString"), attrs.get("appStoreState")
            facts[label] = {"version": vstr, "state": state, "id": newest.get("id"),
                            "createdDate": attrs.get("createdDate")}
            if attrs.get("platform") not in (None, platform):
                report.api(f"{label}: asked for {platform} and got platform "
                           f"{attrs.get('platform')!r}")
                continue
            if vstr == EXPECTED_VERSION and state == EXPECTED_VERSION_STATE:
                report.passed(f"ASC {label}: newest version {vstr} {state} "
                              f"(created {attrs.get('createdDate')})")
            else:
                report.fail(f"ASC {label}: newest version is {vstr} {state}, expected "
                            f"{EXPECTED_VERSION} {EXPECTED_VERSION_STATE}. If a newer release "
                            f"shipped, update the EXPECTED_* constants in this file first.")
            build = get(f"/v1/appStoreVersions/{newest.get('id')}/build?fields[builds]=version")
            bdata = build.get("data")
            bver = (bdata.get("attributes") or {}).get("version") if isinstance(bdata, dict) \
                else None
            facts[label]["build"] = bver
            if bver == build_expected:
                report.passed(f"ASC {label}: {vstr} carries build {bver}")
            else:
                report.fail(f"ASC {label}: {vstr} carries build {bver!r}, expected "
                            f"{build_expected}")

        subs = asc_get_all(f"/v1/reviewSubmissions?filter[app]={APP_ID}&limit=200"
                           f"&fields[reviewSubmissions]=state,platform,submittedDate", get)
        if not subs:
            report.api("reviewSubmissions returned an empty list — this app has been submitted "
                       "many times, so '0 open' from an empty read would not be evidence")
        else:
            histogram: Dict[str, int] = {}
            open_subs = []
            for sub in subs:
                sattrs = sub.get("attributes") or {}
                state = sattrs.get("state")
                histogram[str(state)] = histogram.get(str(state), 0) + 1
                if state != TERMINAL_SUBMISSION_STATE:
                    open_subs.append(sub)
            facts["reviewSubmissions"] = histogram
            report.info("ASC review submissions by state: " +
                        ", ".join(f"{k} {v}" for k, v in sorted(histogram.items())))
            if open_subs:
                report.fail(f"ASC: {len(open_subs)} review submission(s) not "
                            f"{TERMINAL_SUBMISSION_STATE}: " + "; ".join(
                                f"{s.get('id')} {(s.get('attributes') or {}).get('platform')} "
                                f"{(s.get('attributes') or {}).get('state')}" for s in open_subs))
            else:
                report.passed(f"ASC: 0 open review submissions (of {len(subs)})")

        iap = get(f"/v2/inAppPurchases/{IAP_ID}"
                  f"?fields[inAppPurchases]=state,productId,inAppPurchaseType,familySharable")
        iattrs = (iap.get("data") or {}).get("attributes") or {}
        facts["iap"] = iattrs
        if iattrs.get("productId") != PRODUCT_ID:
            report.fail(f"ASC IAP {IAP_ID}: productId {iattrs.get('productId')!r}, expected "
                        f"{PRODUCT_ID}")
        report.info(f"ASC IAP {IAP_ID}: type {iattrs.get('inAppPurchaseType')}")
        if iattrs.get("state") == EXPECTED_IAP_STATE:
            report.passed(f"ASC IAP {iattrs.get('productId')}: state {iattrs.get('state')}")
        else:
            report.fail(f"ASC IAP: state {iattrs.get('state')!r}, expected {EXPECTED_IAP_STATE}")
        if "familySharable" not in iattrs:
            report.fail("ASC IAP: familySharable was not returned — cannot confirm it is false")
        elif iattrs["familySharable"] is EXPECTED_FAMILY_SHARABLE:
            report.passed(f"ASC IAP: familySharable {str(iattrs['familySharable']).lower()}")
        else:
            report.fail(f"ASC IAP: familySharable {iattrs['familySharable']!r}, expected "
                        f"{str(EXPECTED_FAMILY_SHARABLE).lower()}")
    except AscError as exc:
        report.api(str(exc))
    report.facts["asc"] = facts


# =============================================================================================
# The Mac: binary identity, other copies, running processes
# =============================================================================================

def read_bundle_info(bundle: Path) -> Optional[dict]:
    """Info.plist of a macOS (Contents/Info.plist) or iOS (Info.plist at the root) bundle."""
    for rel in ("Contents/Info.plist", "Info.plist"):
        candidate = bundle / rel
        if candidate.is_file():
            try:
                with candidate.open("rb") as handle:
                    loaded = plistlib.load(handle)
                return loaded if isinstance(loaded, dict) else None
            except Exception:
                return None
    return None


def has_mas_receipt(bundle: Path) -> bool:
    return (bundle / "Contents" / "_MASReceipt" / "receipt").is_file()


def check_mac_binary(report: Report, ctx: Context, verdicts: bool = True) -> None:
    """`verdicts=False` (mac-state) reports the same facts as INFO."""
    report.heading(f"Mac binary: {ctx.app_path}")
    ok, bad = (report.passed, report.fail) if verdicts else (report.info, report.info)
    facts: Dict[str, Any] = {"path": str(ctx.app_path), "exists": ctx.app_path.is_dir()}
    report.facts["mac_binary"] = facts
    if not ctx.app_path.is_dir():
        bad(f"{ctx.app_path} does not exist — install Nihongo Ride from the Mac App Store "
            f"(walk step 1)")
        return
    info = read_bundle_info(ctx.app_path)
    if info is None:
        bad(f"{ctx.app_path}: Info.plist missing or unreadable")
        return
    bid = info.get("CFBundleIdentifier")
    short = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    receipt = has_mas_receipt(ctx.app_path)
    facts.update(bundleID=bid, version=short, build=build, receipt=receipt)
    (ok if bid == BUNDLE_ID else bad)(f"CFBundleIdentifier {bid} (expected {BUNDLE_ID})")
    (ok if short == EXPECTED_VERSION else bad)(
        f"CFBundleShortVersionString {short} (expected {EXPECTED_VERSION})")
    (ok if build == EXPECTED_MAC_BUILD else bad)(
        f"CFBundleVersion {build} (expected {EXPECTED_MAC_BUILD})")
    (ok if receipt else bad)(
        "Contents/_MASReceipt/receipt " + ("present" if receipt else
                                           "ABSENT — this is not a Mac App Store install"))
    signed = ctx.run([CODESIGN, "-dv", "--verbose=2", str(ctx.app_path)], timeout=60)
    lines = [ln for ln in (signed.stderr + signed.stdout).splitlines()
             if ln.startswith(("Authority=", "TeamIdentifier="))]
    facts["codesign"] = lines
    if signed.returncode is None:
        report.info(f"codesign did not run: {signed.error}")
    elif not lines:
        report.info(f"codesign printed no Authority lines (exit {signed.returncode})")
    for line in lines:
        report.info(f"codesign {line}")


def check_other_copies(report: Report, ctx: Context) -> None:
    report.heading(f"Other bundles with identifier {BUNDLE_ID} (Spotlight)")
    r = ctx.run([MDFIND, f"kMDItemCFBundleIdentifier == '{BUNDLE_ID}'"], timeout=60)
    if r.returncode != 0:
        report.warn(f"mdfind did not run ({r.returncode} {r.error} {r.stderr.strip()[:200]}) — "
                    f"other copies were NOT checked")
        return
    paths = [p.strip() for p in r.stdout.splitlines() if p.strip()]
    expected_real = os.path.realpath(str(ctx.app_path))
    found_expected = any(os.path.realpath(p) == expected_real for p in paths)
    others = [p for p in paths if os.path.realpath(p) != expected_real]
    report.facts["other_copies"] = others
    if not paths:
        report.warn("mdfind returned no bundle with this identifier at all, not even a build "
                    "folder — that absence is not established (Spotlight may not index them)")
    elif ctx.app_path.is_dir() and not found_expected:
        report.warn(f"mdfind did not return {ctx.app_path} although it exists — the index is "
                    f"incomplete, so the list below may be too")
    for p in others:
        info = read_bundle_info(Path(p)) or {}
        platforms = ",".join(info.get("CFBundleSupportedPlatforms") or []) or "?"
        report.warn(f"other copy: {p}\n"
                    f"{info.get('CFBundleShortVersionString')} ({info.get('CFBundleVersion')}), "
                    f"platforms {platforms}, _MASReceipt "
                    f"{'present' if has_mas_receipt(Path(p)) else 'absent'}")
    if others:
        report.warn(f"{len(others)} other copy/copies share the bundle id; LaunchServices may "
                    f"pick one of them — {LAUNCH_ADVICE}")
    elif paths:
        report.passed("no other bundle with this identifier is indexed")


def owning_bundle(executable: str, cache: Dict[str, Optional[dict]]) -> Optional[str]:
    """The outermost `.app` on the executable's path whose CFBundleIdentifier is ours."""
    start = 0
    while True:
        idx = executable.find(".app/", start)
        if idx < 0:
            return None
        prefix = executable[:idx + 4]
        if prefix not in cache:
            cache[prefix] = read_bundle_info(Path(prefix))
        info = cache[prefix]
        if info and info.get("CFBundleIdentifier") == BUNDLE_ID:
            return prefix
        start = idx + 5


def bundle_processes(ctx: Context) -> Tuple[Optional[List[dict]], bool, str]:
    r = ctx.run([PS, "-axww", "-o", "pid=,comm="], timeout=30)
    if r.returncode != 0:
        return None, False, f"ps exit {r.returncode} {r.error} {r.stderr.strip()[:200]}"
    rows: List[dict] = []
    saw_self = False
    cache: Dict[str, Optional[dict]] = {}
    for line in r.stdout.splitlines():
        m = re.match(r"^\s*(\d+)\s+(.+?)\s*$", line)
        if not m:
            continue
        pid, exe = int(m.group(1)), m.group(2)
        if pid == ctx.own_pid:
            saw_self = True
        bundle = owning_bundle(exe, cache)
        if bundle:
            rows.append({"pid": pid, "executable": exe, "bundle": bundle})
    return rows, saw_self, ""


def check_processes(report: Report, ctx: Context) -> None:
    report.heading("Running Nihongo Ride processes")
    rows, saw_self, problem = bundle_processes(ctx)
    report.facts["processes"] = rows
    if rows is None:
        report.warn(f"could not list processes ({problem}) — not checked")
        return
    if not saw_self:
        # A listing that misses this very process cannot establish that nothing else is running.
        # What it DID show is still judged below: a wrong process it saw is still wrong.
        report.warn("the process listing did not include this script's own pid, so 'no other "
                    "Nihongo Ride process' is NOT established")
    elif not rows:
        report.info("no Nihongo Ride process is running")
    for row in rows:
        if _inside(Path(row["executable"]), ctx.app_path):
            report.passed(f"running from the App Store location: pid {row['pid']} "
                          f"{row['executable']}")
        else:
            hint = " (an iOS Simulator process)" if "/CoreSimulator/" in row["executable"] else ""
            report.fail(f"running OUTSIDE {ctx.app_path}: pid {row['pid']} "
                        f"{row['executable']}{hint}\n"
                        f"quit it; {LAUNCH_ADVICE}")


# =============================================================================================
# The container's defaults
# =============================================================================================

@dataclass
class KeyReading:
    key: str
    present: Optional[bool]  # None: could not be established
    data: Optional[bytes] = None
    presence_source: str = ""
    value_source: str = ""
    notes: List[str] = field(default_factory=list)


def parse_defaults_data(stdout: str) -> Tuple[Optional[bytes], bool]:
    """(bytes, truncated) from `defaults read` output for a data value; (None, False) otherwise.

    Two printed forms: `{length = N, bytes = 0x…}` (complete up to 24 bytes, elided with ` ... `
    from 25 — measured) and the older `<0102 0304>`.
    """
    s = stdout.strip()
    m = re.match(r"^\{length = (\d+), bytes = 0x(.*)\}$", s, re.S)
    if m:
        body = m.group(2)
        if "..." in body:
            return None, True
        hexdigits = re.sub(r"\s", "", body)
        try:
            data = bytes.fromhex(hexdigits)
        except ValueError:
            return None, False
        return (data, False) if len(data) == int(m.group(1)) else (None, True)
    m = re.match(r"^<([0-9a-fA-F\s]*)>$", s)
    if m:
        try:
            return bytes.fromhex(re.sub(r"\s", "", m.group(1))), False
        except ValueError:
            return None, False
    return None, False


def read_container_keys(prefs: Path, keys: List[str], run: Callable[..., Completed]
                        ) -> Dict[str, KeyReading]:
    domain = str(prefs)[:-len(".plist")] if str(prefs).endswith(".plist") else str(prefs)
    readings: Dict[str, KeyReading] = {}
    file_dict: Optional[dict] = None
    file_note = ""
    if prefs.is_file():
        try:
            with prefs.open("rb") as handle:
                loaded = plistlib.load(handle)
            file_dict = loaded if isinstance(loaded, dict) else None
        except Exception as exc:
            file_note = f"the plist file exists but could not be read ({exc})"
    if not prefs.parent.is_dir() and not prefs.is_file():
        for key in keys:
            readings[key] = KeyReading(key, False, presence_source=(
                "filesystem: the container's Preferences directory does not exist, so the app "
                "has never stored defaults here as this user"))
        return readings

    export_dict: Optional[dict] = None
    exported = run([DEFAULTS, "export", domain, "-"], timeout=30)
    if exported.returncode == 0 and exported.stdout.strip():
        try:
            loaded = plistlib.loads(exported.stdout.encode("utf-8"))
            export_dict = loaded if isinstance(loaded, dict) else None
        except Exception:
            export_dict = None

    for key in keys:
        reading = KeyReading(key, None)
        r = run([DEFAULTS, "read", domain, key], timeout=30)
        if r.returncode == 0:
            reading.present = True
            reading.presence_source = "defaults read (cfprefsd)"
            data, truncated = parse_defaults_data(r.stdout)
            if data is not None:
                reading.data, reading.value_source = data, "defaults read (complete hex)"
            elif export_dict is not None and isinstance(export_dict.get(key), bytes):
                reading.data = export_dict[key]
                reading.value_source = ("defaults export (cfprefsd)" +
                                        (": `defaults read` truncates data over 24 bytes"
                                         if truncated else ""))
            elif file_dict is not None and isinstance(file_dict.get(key), bytes):
                reading.data = file_dict[key]
                reading.value_source = "plist file on disk (may lag cfprefsd)"
            else:
                reading.notes.append("present, but no source returned its data bytes")
        elif "Could not find key" in r.stderr:
            reading.present = False
            reading.presence_source = "defaults read (cfprefsd): key not found in the domain"
        elif "Domain" in r.stderr and "not found" in r.stderr and file_dict is None \
                and not prefs.is_file():
            reading.present = False
            reading.presence_source = "defaults read: domain not found, and no plist file exists"
        elif file_dict is not None:
            reading.present = key in file_dict
            reading.presence_source = (f"plist file on disk (defaults read failed: exit "
                                       f"{r.returncode} {r.error} {r.stderr.strip()[:160]})")
            if reading.present and isinstance(file_dict.get(key), bytes):
                reading.data = file_dict[key]
                reading.value_source = "plist file on disk"
        else:
            reading.notes.append(f"defaults read failed (exit {r.returncode} {r.error} "
                                 f"{r.stderr.strip()[:160]})" + (f"; {file_note}" if file_note
                                                                 else ""))
        if file_dict is not None and reading.present is not None \
                and reading.presence_source.startswith("defaults"):
            on_disk = key in file_dict
            if on_disk != reading.present or (
                    reading.data is not None and on_disk and file_dict.get(key) != reading.data):
                reading.notes.append("the plist file on disk disagrees with cfprefsd (the app may "
                                     "be running, or has not flushed); the cfprefsd answer is used")
        readings[key] = reading
    return readings


def swift_date(seconds: float) -> dt.datetime:
    return REFERENCE_DATE + dt.timedelta(seconds=seconds)


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def decode_entitlement(data: bytes) -> Dict[str, Any]:
    """The stored EntitlementRecord, judged the way EntitlementLedger.load and isEntitled judge it."""
    out: Dict[str, Any] = {"decodable": False, "problem": None, "productID": None,
                           "lastVerifiedAt": None, "revokedAt": None,
                           "verifiedTransactionID": None, "isEntitled": None,
                           "honouredByApp": False}
    try:
        obj = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        out["problem"] = f"not JSON ({exc})"
        return out
    if not isinstance(obj, dict):
        out["problem"] = "not a JSON object"
        return out
    if not isinstance(obj.get("productID"), str):
        out["problem"] = "productID missing or not a string"
        return out
    for key in ("lastVerifiedAt", "revokedAt"):
        if obj.get(key) is not None and not _is_number(obj.get(key)):
            out["problem"] = f"{key} is not a number"
            return out
    tid = obj.get("verifiedTransactionID")
    if tid is not None and not (isinstance(tid, int) and not isinstance(tid, bool)
                                and 0 <= tid < 2 ** 64):
        out["problem"] = "verifiedTransactionID is not a UInt64"
        return out
    verified = obj.get("lastVerifiedAt")
    revoked = obj.get("revokedAt")
    # EntitlementRecord.isEntitled: verified != nil && (revoked == nil || verified > revoked).
    # `is not None`, never truthiness: a verification at the reference date is 0 and still counts.
    is_entitled = verified is not None and (revoked is None or verified > revoked)
    out.update(decodable=True, productID=obj["productID"], lastVerifiedAt=verified,
               revokedAt=revoked, verifiedTransactionID=tid, isEntitled=is_entitled,
               honouredByApp=is_entitled and obj["productID"] == PRODUCT_ID)
    return out


def _date_text(seconds: Optional[float]) -> str:
    if seconds is None:
        return "none"
    when = swift_date(seconds)
    return (f"{seconds!r} = {when.isoformat()} "
            f"(local {when.astimezone().isoformat(timespec='seconds')})")


def entitlement_lines(decoded: Dict[str, Any]) -> List[str]:
    if not decoded["decodable"]:
        return [f"UNDECODABLE ({decoded['problem']}) — EntitlementLedger.load would quarantine it "
                f"under {QUARANTINE_KEY} and treat the device as never established"]
    match = "matches" if decoded["productID"] == PRODUCT_ID else \
        "DIFFERS — EntitlementLedger.load would discard it as never established"
    return [
        f"productID {decoded['productID']} ({match})",
        f"lastVerifiedAt {_date_text(decoded['lastVerifiedAt'])}",
        f"revokedAt {_date_text(decoded['revokedAt'])}",
        f"verifiedTransactionID {decoded['verifiedTransactionID']}",
        f"isEntitled (EntitlementRecord.isEntitled predicate) {decoded['isEntitled']}",
        f"honoured by the app (decodable, productID matches, isEntitled) "
        f"{decoded['honouredByApp']}",
    ]


def decode_offer(data: bytes) -> Tuple[Optional[dict], List[str]]:
    try:
        obj = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        return None, [f"UNDECODABLE ({exc})"]
    if not isinstance(obj, dict) or not isinstance(obj.get("counts"), dict):
        return None, [f"unexpected shape: {data[:200]!r}"]
    furthest = obj.get("furthestBucket")
    name = ROAD_BUCKETS[furthest] if isinstance(furthest, int) and \
        0 <= furthest < len(ROAD_BUCKETS) else f"?{furthest!r}"
    lines = [f"launches {obj.get('launches')} · furthest {name}"]
    totals = []
    at_kyoto = []
    for event, row in sorted(obj["counts"].items()):
        values = [v for v in row if isinstance(v, int)] if isinstance(row, list) else []
        totals.append(f"{event} {sum(values)}")
        kyoto = ROAD_BUCKETS.index("kyoto")
        if isinstance(row, list) and len(row) > kyoto and isinstance(row[kyoto], int) \
                and row[kyoto] > 0:
            at_kyoto.append(f"{event} {row[kyoto]}")
    lines.append("counts: " + (" · ".join(totals) if totals else "none recorded"))
    lines.append("at kyoto: " + (" · ".join(at_kyoto) if at_kyoto else "none"))
    lines.append(f"raw {data.decode('utf-8', 'replace')}")
    return obj, lines


def check_container(report: Report, ctx: Context, gate1: bool = True) -> None:
    report.heading(f"Container defaults: {ctx.container_prefs}")
    readings = read_container_keys(ctx.container_prefs,
                                   [ENTITLEMENT_KEY, QUARANTINE_KEY, OFFER_KEY], ctx.run)
    facts: Dict[str, Any] = {}
    report.facts["container"] = facts

    ent = readings[ENTITLEMENT_KEY]
    for note in ent.notes:
        report.warn(f"{ENTITLEMENT_KEY}: {note}")
    facts[ENTITLEMENT_KEY] = {"present": ent.present, "presence_source": ent.presence_source,
                              "value_source": ent.value_source}
    if ent.present is None:
        (report.fail if gate1 else report.warn)(
            f"{ENTITLEMENT_KEY}: could not establish whether it exists — "
            + ("§L gate 1 precondition UNKNOWN" if gate1 else "state unknown"))
    elif not ent.present:
        (report.passed if gate1 else report.info)(
            f"{ENTITLEMENT_KEY} absent" +
            (" — §L gate 1 precondition holds (this Mac's container stores no entitlement "
             "record)" if gate1 else "") + f"\n[source: {ent.presence_source}]")
    else:
        headline = (f"{ENTITLEMENT_KEY} PRESENT — a Mac that stores a record shows 'Opened' by "
                    f"design (Entitlement.swift never revokes on silence), so it cannot walk "
                    f"§L gate 1" if gate1 else f"{ENTITLEMENT_KEY} present")
        detail = [f"[presence: {ent.presence_source}; value: {ent.value_source or 'none'}]"]
        if ent.data is not None:
            decoded = decode_entitlement(ent.data)
            facts[ENTITLEMENT_KEY]["decoded"] = decoded
            detail += entitlement_lines(decoded)
        (report.fail if gate1 else report.info)("\n".join([headline] + detail))

    quarantine = readings[QUARANTINE_KEY]
    facts[QUARANTINE_KEY] = {"present": quarantine.present}
    if quarantine.present:
        report.warn(f"{QUARANTINE_KEY} present — an unreadable entitlement record was stored on "
                    f"this Mac at some point [source: {quarantine.presence_source}]")
    elif quarantine.present is False:
        report.info(f"{QUARANTINE_KEY} absent")
    else:
        report.warn(f"{QUARANTINE_KEY}: could not establish whether it exists")

    offer = readings[OFFER_KEY]
    facts[OFFER_KEY] = {"present": offer.present}
    if offer.present and offer.data is not None:
        decoded_offer, lines = decode_offer(offer.data)
        facts[OFFER_KEY]["decoded"] = decoded_offer
        report.info("\n".join([f"{OFFER_KEY} [value: {offer.value_source}]"] + lines))
    elif offer.present:
        report.info(f"{OFFER_KEY} present but its bytes could not be read: {offer.notes}")
    elif offer.present is False:
        report.info(f"{OFFER_KEY} absent [source: {offer.presence_source}]")
    else:
        report.warn(f"{OFFER_KEY}: could not be read: {offer.notes}")


# =============================================================================================
# Paired iOS devices (devicectl)
# =============================================================================================

def _devicectl_json(run: Callable[..., Completed], args: List[str], timeout: float
                    ) -> Tuple[Completed, Optional[dict], str]:
    with tempfile.TemporaryDirectory(prefix="stage1-walk-devicectl-") as tmp:
        target = Path(tmp) / "out.json"
        r = run([XCRUN, "devicectl"] + args + ["--json-output", str(target)], timeout=timeout)
        if not target.is_file():
            return r, None, "devicectl wrote no JSON"
        try:
            return r, json.loads(target.read_text(encoding="utf-8")), ""
        except ValueError as exc:
            return r, None, f"devicectl JSON unreadable ({exc})"


def _dig(obj: Any, *path: str) -> Any:
    for part in path:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(part)
    return obj


def physical_ios_devices(listing: Optional[dict]) -> Tuple[List[dict], int]:
    devices = _dig(listing, "result", "devices")
    if not isinstance(devices, list):
        return [], 0
    chosen, skipped = [], 0
    for d in devices:
        if not isinstance(d, dict):
            skipped += 1
            continue
        reality = _dig(d, "properties", "hardware", "reality") or \
            _dig(d, "hardwareProperties", "reality")
        platform = _dig(d, "properties", "hardware", "platform") or \
            _dig(d, "hardwareProperties", "platform")
        provider = _dig(d, "deviceProperties", "provider") or ""
        if reality == "simulated" or "Simulator" in str(provider) or \
                platform not in ("iOS", "iPadOS"):
            skipped += 1
            continue
        chosen.append({
            "identifier": d.get("identifier"),
            "name": _dig(d, "properties", "state", "name") or _dig(d, "deviceProperties", "name"),
            "model": _dig(d, "properties", "hardware", "marketingName") or
            _dig(d, "hardwareProperties", "marketingName"),
            "productType": _dig(d, "properties", "hardware", "productType") or
            _dig(d, "hardwareProperties", "productType"),
            "os": _dig(d, "deviceProperties", "osVersionNumber") or
            _dig(d, "properties", "software", "osVersionNumber", "stringValue"),
            "pairingState": _dig(d, "properties", "connection", "pairingState") or
            _dig(d, "connectionProperties", "pairingState"),
            "connection": _dig(d, "properties", "connection", "state") or
            _dig(d, "connectionProperties", "tunnelState"),
        })
    return chosen, skipped


def _error_chain(error: Any) -> List[dict]:
    chain = []
    while isinstance(error, dict):
        chain.append(error)
        error = _dig(error, "userInfo", "NSUnderlyingError", "error")
    return chain


def _error_text(error: dict, key: str) -> str:
    return str(_dig(error, "userInfo", key, "string") or "")


def read_device_apps(ctx: Context, device: dict) -> Dict[str, Any]:
    """One device's listing, reduced to what the walk needs. The full app list is NOT kept."""
    r, payload, problem = _devicectl_json(
        ctx.run, ["device", "info", "apps", "--device", str(device["identifier"]),
                  "--include-all-apps", "--timeout", "45"], timeout=120)
    outcome = _dig(payload, "info", "outcome")
    result: Dict[str, Any] = {"readable": False, "locked": False, "outcome": outcome,
                              "matches": [], "total_apps": None, "problem": ""}
    if outcome == "success":
        apps = _dig(payload, "result", "apps")
        if not isinstance(apps, list) or not apps:
            result["problem"] = ("the listing came back with no apps at all, which no readable "
                                 "phone produces — 'not installed' is not established")
            return result
        result["readable"] = True
        result["total_apps"] = len(apps)
        result["not_built_by_developer"] = sum(
            1 for a in apps if isinstance(a, dict) and a.get("builtByDeveloper") is False)
        result["matches"] = [a for a in apps
                             if isinstance(a, dict) and a.get("bundleIdentifier") == BUNDLE_ID]
        return result
    chain = _error_chain(payload.get("error") if isinstance(payload, dict) else None)
    texts = []
    for err in chain:
        text = " ".join(t for t in (_error_text(err, "NSLocalizedDescription"),
                                    _error_text(err, "NSLocalizedFailureReason")) if t)
        if text and text not in texts:
            texts.append(text)
        if err.get("code") == 10003 or "locked" in text.lower():
            result["locked"] = True
    result["problem"] = " / ".join(texts) or problem or \
        f"devicectl exit {r.returncode} {r.error} {r.stderr.strip()[-200:]}"
    return result


def check_ios(report: Report, ctx: Context, verdicts: bool = True) -> int:
    """Returns how many physical iOS devices were read."""
    report.heading("Paired iOS devices (xcrun devicectl, read-only listings)")
    r, listing, problem = _devicectl_json(ctx.run, ["list", "devices", "--timeout", "30"],
                                          timeout=90)
    facts: Dict[str, Any] = {"devices": []}
    report.facts["ios"] = facts
    if listing is None or _dig(listing, "info", "outcome") != "success":
        report.warn(f"devicectl list devices failed ({problem or _dig(listing, 'info', 'outcome')}"
                    f"; exit {r.returncode} {r.error}) — no iOS device checked")
        return 0
    devices, skipped = physical_ios_devices(listing)
    report.info(f"{len(devices)} physical iOS/iPadOS device(s); {skipped} simulator or non-iOS "
                f"entries skipped")
    if devices:
        report.info("listing an unlocked device's apps mounts its developer disk image and opens "
                    "a CoreDevice tunnel (measured 2026-09-16); it changes no app, account or "
                    "purchase")
    readable = 0
    ok = report.passed if verdicts else report.info
    for device in devices:
        label = (f"{device['name']} · {device['model']} ({device['productType']}) · iOS "
                 f"{device['os']} · {device['identifier']} · {device['pairingState']}")
        entry = {"device": device}
        facts["devices"].append(entry)
        if device.get("pairingState") not in (None, "paired"):
            report.info(f"{label}: not paired — skipped")
            continue
        apps = read_device_apps(ctx, device)
        entry["apps"] = apps
        if apps["locked"]:
            report.warn(f"{label}: locked — unlock and re-run")
            continue
        if not apps["readable"]:
            report.warn(f"{label}: could not read its apps — {apps['problem']}")
            continue
        readable += 1
        report.info(f"{label}: readable ({apps['total_apps']} apps listed, "
                    f"{apps['not_built_by_developer']} with builtByDeveloper false)")
        if not apps["matches"]:
            report.warn(f"{label}: {BUNDLE_ID} is not installed — walk step 1 installs it from "
                        f"the App Store")
            continue
        for app in apps["matches"]:
            raw = ", ".join(f"{k}={app[k]!r}" for k in sorted(app))
            version, build = app.get("version"), app.get("bundleVersion")
            if version == EXPECTED_VERSION and build == EXPECTED_IOS_BUILD:
                ok(f"{label}: installed {version} ({build})\nraw: {raw}")
            else:
                report.warn(f"{label}: installed {version} ({build}), not {EXPECTED_VERSION} "
                            f"({EXPECTED_IOS_BUILD}) — delete it and install from the App Store "
                            f"(walk step 1)\nraw: {raw}")
            if app.get("builtByDeveloper") is True:
                report.warn(f"{label}: devicectl reports builtByDeveloper=True for this install. "
                            f"Its default listing ('only developer apps') contained exactly the "
                            f"builtByDeveloper=True apps when measured; that an App Store copy "
                            f"reads False is unverified — confirm in the App Store app")
    return readable


# =============================================================================================
# Subcommands
# =============================================================================================

def _finish(report: Report, ctx: Context, name: str, exit_code: int) -> int:
    report.plain("")
    report.plain(f"SUMMARY  PASS {report.counts['PASS']} · WARN {report.counts['WARN']} · "
                 f"FAIL {report.counts['FAIL']} · INFO {report.counts['INFO']} · "
                 f"API failures {len(report.api_failures)}  →  exit {exit_code}")
    try:
        snap = _snapshot_dir(ctx.snapshot_root, ctx.now())
        report.plain(f"snapshot: {snap}")
        _snapshot_write(snap, ctx.snapshot_root, f"{name}.txt", report.transcript())
        _snapshot_write(snap, ctx.snapshot_root, f"{name}.json", json.dumps(
            {"command": name, "exit": exit_code, "counts": report.counts,
             "api_failures": report.api_failures, "facts": report.facts,
             "taken_utc": ctx.now().isoformat()}, indent=2, ensure_ascii=False, default=str))
    except (OSError, ReadOnlyViolation) as exc:
        report.plain(f"snapshot NOT written: {exc}")
    return exit_code


def cmd_preflight(ctx: Context, out=None) -> int:
    report = Report(out)
    report.plain(f"stage1_walk preflight — {ctx.now().isoformat(timespec='seconds')} · expects "
                 f"release {EXPECTED_VERSION} (macOS {EXPECTED_MAC_BUILD} / iOS "
                 f"{EXPECTED_IOS_BUILD})")
    check_asc(report, ctx)
    check_mac_binary(report, ctx)
    check_other_copies(report, ctx)
    check_processes(report, ctx)
    check_container(report, ctx, gate1=True)
    check_ios(report, ctx)
    code = 3 if report.api_failures else (1 if report.counts["FAIL"] else 0)
    return _finish(report, ctx, "preflight", code)


def cmd_mac_state(ctx: Context, out=None) -> int:
    report = Report(out)
    report.plain(f"stage1_walk mac-state — {ctx.now().isoformat(timespec='seconds')}")
    check_processes(report, ctx)
    check_mac_binary(report, ctx, verdicts=False)
    check_container(report, ctx, gate1=False)
    return _finish(report, ctx, "mac-state", 0)


def cmd_ios_state(ctx: Context, out=None) -> int:
    report = Report(out)
    report.plain(f"stage1_walk ios-state — {ctx.now().isoformat(timespec='seconds')}")
    readable = check_ios(report, ctx, verdicts=False)
    return _finish(report, ctx, "ios-state", 0 if readable else 2)


def baseline_exit(calibrate_exit: Optional[int], checkpoint_exit: Optional[int]) -> int:
    if calibrate_exit != 0:
        return calibrate_exit if isinstance(calibrate_exit, int) else 1
    if checkpoint_exit not in (0, 5):
        return checkpoint_exit if isinstance(checkpoint_exit, int) else 1
    return 0


def cmd_baseline(ctx: Context, out=None) -> int:
    report = Report(out)
    snap = _snapshot_dir(ctx.snapshot_root, ctx.now())
    report.plain(f"stage1_walk baseline — {ctx.now().isoformat(timespec='seconds')}")
    report.plain(f"snapshot: {snap}")
    runs = [("calibrate", [sys.executable, str(SALES_REPORT), "--calibrate", "--json",
                           str(snap / "sales.json")]),
            ("checkpoint", [sys.executable, str(SALES_REPORT), "--checkpoint"])]
    record = {"interpreter": sys.executable, "runs": []}
    exits: Dict[str, Optional[int]] = {}
    for name, argv in runs:
        report.plain("")
        report.plain(f"$ {' '.join(argv)}")
        started = ctx.now().isoformat()
        r = ctx.run(argv, timeout=3600, cwd=str(REPO))
        exits[name] = r.returncode
        stdout_file = _snapshot_write(snap, ctx.snapshot_root, f"{name}.stdout.txt", r.stdout)
        stderr_file = _snapshot_write(snap, ctx.snapshot_root, f"{name}.stderr.txt",
                                      r.stderr + (f"\n[{r.error}]\n" if r.error else ""))
        record["runs"].append({"name": name, "argv": argv, "exit": r.returncode,
                               "error": r.error, "started_utc": started,
                               "finished_utc": ctx.now().isoformat(),
                               "stdout_file": stdout_file.name, "stderr_file": stderr_file.name})
        for line in r.stdout.rstrip("\n").splitlines():
            report.plain(f"  | {line}")
        if r.stderr.strip():
            report.plain(f"  | [stderr] {r.stderr.strip()[-600:]}")
        report.plain(f"  exit {r.returncode}{(' ' + r.error) if r.error else ''}")
    code = baseline_exit(exits.get("calibrate"), exits.get("checkpoint"))
    record["exit"] = code
    _snapshot_write(snap, ctx.snapshot_root, "baseline.json",
                    json.dumps(record, indent=2, ensure_ascii=False))
    _snapshot_write(snap, ctx.snapshot_root, "baseline.txt", report.transcript())
    report.plain("")
    report.plain(f"calibrate exit {exits.get('calibrate')} (0 ran · 4 calibration failed) · "
                 f"checkpoint exit {exits.get('checkpoint')} (0 bound printed or not applicable "
                 f"· 4 calibration failed · 5 bound withheld)  →  exit {code}")
    report.plain(f"snapshot: {snap}")
    return code


def manifest_entries(directory: Path) -> Tuple[List[dict], List[Tuple[str, str]]]:
    entries: List[dict] = []
    skipped: List[Tuple[str, str]] = []
    for root, dirs, files in os.walk(str(directory), followlinks=False):
        dirs.sort()
        for d in list(dirs):
            if os.path.islink(os.path.join(root, d)):
                skipped.append((Path(root, d).relative_to(directory).as_posix(),
                                "symlinked directory, not followed"))
        for name in sorted(files):
            path = Path(root) / name
            rel = path.relative_to(directory).as_posix()
            if name == ".DS_Store":
                skipped.append((rel, "Finder metadata"))
                continue
            if path.is_symlink() or not path.is_file():
                skipped.append((rel, "not a regular file"))
                continue
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(chunk)
            st = path.stat()
            entries.append({
                "file": f"{directory.name}/{rel}",
                "sha256": digest.hexdigest(),
                "size": st.st_size,
                "mtime": dt.datetime.fromtimestamp(st.st_mtime, dt.timezone.utc)
                .astimezone().isoformat(timespec="seconds"),
            })
    return entries, skipped


def cmd_manifest(ctx: Context, directory: str, out=None, err=None) -> int:
    out = out if out is not None else sys.stdout
    err = err if err is not None else sys.stderr
    target = Path(directory).expanduser()
    if not target.is_dir():
        print(f"manifest: {directory} is not a directory", file=err)
        return 2
    target = Path(os.path.abspath(str(target)))
    entries, skipped = manifest_entries(target)
    lines = [json.dumps(e, ensure_ascii=False) for e in entries]
    for line in lines:
        print(line, file=out)
    for rel, why in skipped:
        print(f"manifest: skipped {rel} ({why})", file=err)
    if not entries:
        print(f"manifest: no regular files under {target}", file=err)
    try:
        snap = _snapshot_dir(ctx.snapshot_root, ctx.now())
        _snapshot_write(snap, ctx.snapshot_root, "manifest.jsonl",
                        "".join(line + "\n" for line in lines))
        print(f"manifest: {len(entries)} file(s) from {target}; snapshot: {snap}", file=err)
    except (OSError, ReadOnlyViolation) as exc:
        print(f"manifest: snapshot NOT written: {exc}", file=err)
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only preflight and state snapshots for the Stage 1 owner walk.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("preflight", help="ASC, Mac binary, copies, processes, container, devices")
    sub.add_parser("mac-state", help="process, binary, decoded entitlement record, counters")
    sub.add_parser("ios-state", help="paired devices and the installed app, when unlocked")
    sub.add_parser("baseline", help="sales_report.py --calibrate and --checkpoint, saved")
    manifest = sub.add_parser("manifest", help="sha256/size/mtime JSON lines for a folder")
    manifest.add_argument("dir")
    args = parser.parse_args(argv)
    ctx = Context()
    if args.command == "preflight":
        return cmd_preflight(ctx)
    if args.command == "mac-state":
        return cmd_mac_state(ctx)
    if args.command == "ios-state":
        return cmd_ios_state(ctx)
    if args.command == "baseline":
        return cmd_baseline(ctx)
    return cmd_manifest(ctx, args.dir)


if __name__ == "__main__":
    sys.exit(main())
