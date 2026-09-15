#!/usr/bin/env python3
"""`stage1_walk.py` must see what is really on the Mac and the devices, and must be unable to change
any of it.

WHY THIS FILE EXISTS. The walk tool answers questions whose wrong answer looks exactly like a right
one: "the entitlement key is absent" from a reader that could not read, "not installed" from a
device listing that hides App Store apps (measured: devicectl's default listing does), "no other
process" from a process list that is broken, "isEntitled false" from a decoder that treats a date
of 0 as missing. So every verdict below is tested as a PAIR — the planted state that must pass and
the one-variable change that must not — and every "absent" is tested against a broken instrument
that must NOT produce it.

WHAT IS PLANTED, AND WHERE IT CAME FROM. Nothing here touches the network, devicectl, App Store
Connect or the real container. Bundles are fake `.app` folders in a temp dir; commands go through
an injected runner that also re-checks the tool's own read-only allowlist on every argv it builds.
The entitlement and counter bytes are NOT hand-written: they are what the shipped
Sources/EntitlementKit types wrote through `EntitlementLedger.save(to:)` / `UnlockOfferLedger.save`
when compiled with swiftc on 2026-09-16, and the expected isEntitled values are what Swift printed
for those same records — so the decoder is graded against Swift, not against itself. The one test
that runs a real program is `/usr/bin/defaults` against a plist planted in a temp dir, because
its output format (data over 24 bytes is truncated) is the thing the reader has to survive.

THE NO-SIDE-EFFECTS SCAN. The tool's source is parsed and must contain no network import, no
subprocess use outside its single guarded runner, no plist dump, no file write outside the
snapshot writer, and no string that names a write verb or a store action (`write`, `delete`,
`import`, `POST`, `install`, `Product.purchase`, `macappstore:` …). Docstrings are exempt so the
tool can say what it never does. The scan is itself controlled: each rule has a planted violation
appended to the real source that must be reported, and a docstring-only mention that must not.

    python3 scripts/test_stage1_walk.py
"""
import ast
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import sys
import tempfile
import traceback
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SCRIPT = SCRIPTS / "stage1_walk.py"

# --- Fixtures produced by the shipped Swift types (swiftc, 2026-09-16) ----------------------------
PID = "com.jasonye.nihongoride.scenery.lifetime"
SWIFT_RECORDS = {
    # label: (bytes EntitlementLedger.save wrote, isEntitled as Swift printed it)
    "never": (b'{"productID":"com.jasonye.nihongoride.scenery.lifetime"}', False),
    "verified": (b'{"productID":"com.jasonye.nihongoride.scenery.lifetime",'
                 b'"verifiedTransactionID":2000001234567890,"lastVerifiedAt":811180000.25}', True),
    "revoked-after": (b'{"productID":"com.jasonye.nihongoride.scenery.lifetime",'
                      b'"lastVerifiedAt":811180000.25,"verifiedTransactionID":2000001234567890,'
                      b'"revokedAt":811266400.5}', False),
    "repurchased": (b'{"productID":"com.jasonye.nihongoride.scenery.lifetime",'
                    b'"lastVerifiedAt":811352800,"verifiedTransactionID":2000009999999999,'
                    b'"revokedAt":811266400.5}', True),
    "zero": (b'{"productID":"com.jasonye.nihongoride.scenery.lifetime","lastVerifiedAt":0}', True),
}
SWIFT_OFFER = (b'{"launches":1,"counts":{"settingsRowAppeared":[0,0,0,0,0,0,0,1],'
               b'"offerAppeared":[0,0,0,0,0,0,0,1]},"furthestBucket":7}')
# Swift's ISO8601DateFormatter printed 2026-09-15T15:46:40Z for 811180000.25, and
# `date -r 1789487200 -u` (= 811180000 + 978307200) printed Tue Sep 15 15:46:40 UTC 2026.
EXPECTED_ISO = {
    811180000.25: "2026-09-15T15:46:40.250000+00:00",
    811266400.5: "2026-09-16T15:46:40.500000+00:00",
    811352800: "2026-09-17T15:46:40+00:00",
    0: "2001-01-01T00:00:00+00:00",
}
# NIST FIPS 180-2 test vectors, independent of hashlib.
SHA256_ABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
SHA256_MILLION_A = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"


def load():
    spec = importlib.util.spec_from_file_location("stage1_walk_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses look their module up while the class is built
    spec.loader.exec_module(module)
    return module


W = load()


class Problems(list):
    def check(self, condition, message):
        if not condition:
            self.append(message)
        return condition


# --- Planting helpers ---------------------------------------------------------------------------

def make_bundle(path, bundle_id=W.BUNDLE_ID, version="1.32", build="56", receipt=True, ios=False):
    path.mkdir(parents=True, exist_ok=True)
    info = {"CFBundleIdentifier": bundle_id, "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundleSupportedPlatforms": ["iPhoneOS"] if ios else ["MacOSX"]}
    plist = path / ("Info.plist" if ios else "Contents/Info.plist")
    plist.parent.mkdir(parents=True, exist_ok=True)
    with plist.open("wb") as handle:
        plistlib.dump(info, handle)
    if receipt and not ios:
        receipt_path = path / "Contents/_MASReceipt/receipt"
        receipt_path.parent.mkdir(parents=True, exist_ok=True)
        receipt_path.write_bytes(b"planted receipt")
    return path


def done(returncode=0, stdout="", stderr="", error=""):
    return lambda argv: W.Completed(list(argv), returncode, stdout, stderr, error)


class FakeRun:
    """Routes argv prefixes to canned results, records every call, and holds every argv the tool
    builds to the tool's own read-only allowlist — so a test also fails if the code under test
    starts constructing a command the allowlist would refuse."""

    def __init__(self, snapshot_root):
        self.routes = []
        self.calls = []
        self.snapshot_root = snapshot_root

    def on(self, prefix, handler):
        self.routes.insert(0, (list(prefix), handler))
        return self

    def __call__(self, argv, timeout, cwd=None):
        argv = [str(a) for a in argv]
        W._assert_readonly_argv(argv, self.snapshot_root)
        self.calls.append(argv)
        for prefix, handler in self.routes:
            if argv[:len(prefix)] == prefix:
                return handler(argv)
        return W.Completed(argv, None, "", "", "no route in FakeRun")


def ps_output(own_pid, *rows):
    lines = [f"{own_pid} /usr/bin/python3"] + [f"{pid} {exe}" for pid, exe in rows]
    return "\n".join(f"{line}" for line in lines) + "\n"


def lines_at(report, level):
    return [ln for ln in report.lines if ln.startswith(level)]


def context(tmp, **overrides):
    root = Path(tmp) / "snapshots"
    run = overrides.pop("run", None) or FakeRun(root)
    ctx = W.Context(app_path=overrides.pop("app_path", Path(tmp) / "Applications/Nihongo Ride.app"),
                    container_prefs=overrides.pop("container_prefs", Path(tmp) / "Containers" /
                                                  "Data/Library/Preferences/x.plist"),
                    snapshot_root=root, run=run,
                    asc_get=overrides.pop("asc_get", lambda ep: {}),
                    own_pid=4242,
                    now=lambda: dt.datetime(2026, 9, 16, 1, 2, 3, tzinfo=dt.timezone.utc))
    return ctx, run


# =================================================================================================
# 1. Mac binary identity: receipt present/absent, version match/mismatch
# =================================================================================================

def test_mac_binary(problems):
    print("MAC BINARY — receipt and version, each as a pair")
    authority = "Authority=Apple Mac OS Application Signing\nTeamIdentifier=ABC\n"
    cases = [
        ("1.32/56 with receipt", dict(version="1.32", build="56", receipt=True), []),
        ("receipt ABSENT", dict(version="1.32", build="56", receipt=False), ["_MASReceipt"]),
        ("version 1.31/55", dict(version="1.31", build="55", receipt=True),
         ["CFBundleShortVersionString 1.31", "CFBundleVersion 55"]),
        ("build mismatch only", dict(version="1.32", build="55", receipt=True),
         ["CFBundleVersion 55"]),
    ]
    for label, spec, expected_fails in cases:
        with tempfile.TemporaryDirectory() as tmp:
            ctx, run = context(tmp)
            make_bundle(ctx.app_path, **spec)
            run.on([W.CODESIGN], done(0, "", authority))
            report = W.Report(io.StringIO())
            W.check_mac_binary(report, ctx)
            fails = lines_at(report, "FAIL")
            ok = len(fails) == len(expected_fails) and all(
                any(e in f for f in fails) for e in expected_fails)
            problems.check(ok, f"mac binary [{label}]: expected FAILs {expected_fails}, got {fails}")
            problems.check(any("Authority=Apple Mac OS Application Signing" in ln
                               for ln in lines_at(report, "INFO")),
                           f"mac binary [{label}]: codesign Authority not printed as INFO")
            if not expected_fails:
                problems.check(len(lines_at(report, "PASS")) == 4,
                               f"mac binary [{label}]: expected 4 PASS lines, got {report.lines}")
            print(f"  {label:<22} FAIL {len(fails)} (expected {len(expected_fails)})")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        report = W.Report(io.StringIO())
        W.check_mac_binary(report, ctx)
        fails = lines_at(report, "FAIL")
        problems.check(len(fails) == 1 and "does not exist" in fails[0],
                       f"mac binary [absent]: expected one 'does not exist' FAIL, got {fails}")
        report = W.Report(io.StringIO())
        W.check_mac_binary(report, ctx, verdicts=False)
        problems.check(not lines_at(report, "FAIL"),
                       "mac-state must report the absent app as INFO, not FAIL")
        print(f"  {'app absent':<22} FAIL {len(fails)} (expected 1)")


# =================================================================================================
# 2. Other copies (mdfind) and running processes
# =================================================================================================

def test_other_copies(problems):
    print("OTHER COPIES — listed as WARN; an empty index is not 'no copies'")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        make_bundle(ctx.app_path)
        old = make_bundle(Path(tmp) / "build/macrel/Nihongo Ride.app", version="1.17", build="32",
                          receipt=False)
        run.on([W.MDFIND], done(0, f"{ctx.app_path}\n{old}\n"))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        warns = lines_at(report, "WARN")
        problems.check(any(str(old) in w for w in warns) and any("open \"/Applications/Nihongo "
                                                                 "Ride.app\"" in w for w in warns),
                       f"other copies: the old build and the launch advice must be WARNed: {warns}")
        problems.check(any("1.17 (32)" in ln for ln in report.lines),
                       "other copies: the copy's version/build must be printed")

        run.on([W.MDFIND], done(0, f"{ctx.app_path}\n"))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        problems.check(lines_at(report, "PASS") and not lines_at(report, "WARN"),
                       f"other copies [only /Applications]: expected PASS, got {report.lines}")

        run.on([W.MDFIND], done(0, ""))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        problems.check(not lines_at(report, "PASS") and lines_at(report, "WARN"),
                       f"other copies [empty index, app present]: must WARN, never PASS: "
                       f"{report.lines}")

        run.on([W.MDFIND], done(0, f"{old}\n"))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        problems.check(any("did not return" in w for w in lines_at(report, "WARN")),
                       f"other copies [index misses the existing /Applications copy]: must WARN "
                       f"'did not return': {report.lines}")

    with tempfile.TemporaryDirectory() as tmp:
        # Today's real shape: no /Applications copy AND an empty index. Nothing else can warn here,
        # so this is the case that proves the empty-index warning itself exists.
        ctx, run = context(tmp)
        run.on([W.MDFIND], done(0, ""))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        problems.check(not lines_at(report, "PASS") and any(
            "not established" in w for w in lines_at(report, "WARN")),
            f"other copies [empty index, app absent]: must WARN 'not established': {report.lines}")
        run.on([W.MDFIND], done(None, "", "", "timed out after 60s"))
        report = W.Report(io.StringIO())
        W.check_other_copies(report, ctx)
        problems.check(not lines_at(report, "PASS") and any(
            "NOT checked" in w for w in lines_at(report, "WARN")),
            f"other copies [mdfind failed]: must WARN 'NOT checked': {report.lines}")
        print("  two copies → WARN · only the App Store path → PASS · empty index → WARN (app "
              "present or absent) · mdfind failed → WARN")


def test_processes(problems):
    print("PROCESSES — outside /Applications is FAIL; a listing without this pid proves nothing")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        make_bundle(ctx.app_path)
        other = make_bundle(Path(tmp) / "build/Nihongo Ride.app", version="1.17", build="32")
        unrelated = make_bundle(Path(tmp) / "Applications/Other.app", bundle_id="com.example.x")
        inside = f"{ctx.app_path}/Contents/MacOS/Nihongo Ride"
        outside = f"{other}/Contents/MacOS/Nihongo Ride"
        extension = f"{other}/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget"
        unrelated_exe = f"{unrelated}/Contents/MacOS/Other"

        def judge(stdout):
            run.on([W.PS], done(0, stdout))
            report = W.Report(io.StringIO())
            W.check_processes(report, ctx)
            return report

        r = judge(ps_output(4242, (100, inside), (101, unrelated_exe)))
        problems.check(len(lines_at(r, "PASS")) == 1 and not lines_at(r, "FAIL"),
                       f"processes [inside only]: expected one PASS and no FAIL: {r.lines}")
        r = judge(ps_output(4242, (100, inside), (102, outside)))
        problems.check(any(outside in f for f in lines_at(r, "FAIL")),
                       f"processes [outside]: expected FAIL naming {outside}: {r.lines}")
        r = judge(ps_output(4242, (103, extension)))
        problems.check(any(extension in f for f in lines_at(r, "FAIL")),
                       f"processes [extension inside an outside copy]: expected FAIL: {r.lines}")
        r = judge(ps_output(4242, (101, unrelated_exe)))
        problems.check(any("no Nihongo Ride process" in i for i in lines_at(r, "INFO"))
                       and not lines_at(r, "FAIL"),
                       f"processes [none]: expected INFO 'no … process': {r.lines}")
        r = judge("100 /usr/bin/something\n")
        problems.check(not any("no Nihongo Ride process" in ln for ln in r.lines)
                       and lines_at(r, "WARN"),
                       f"processes [listing without own pid]: must WARN, never say none: {r.lines}")
        r = judge(f"100 {outside}\n")
        problems.check(lines_at(r, "WARN") and any(outside in f for f in lines_at(r, "FAIL")),
                       f"processes [broken listing showing an outside copy]: still FAIL: {r.lines}")
        print("  inside → PASS · outside → FAIL · extension of a copy → FAIL · none → INFO · "
              "no own pid → WARN")


# =================================================================================================
# 3. The entitlement record, graded against what Swift wrote and said
# =================================================================================================

def test_entitlement_decode(problems):
    print("ENTITLEMENT — decoder vs the shipped Swift encoder's bytes and isEntitled")
    for label, (data, swift_entitled) in SWIFT_RECORDS.items():
        decoded = W.decode_entitlement(data)
        problems.check(decoded["decodable"], f"entitlement [{label}]: not decodable: {decoded}")
        problems.check(decoded["isEntitled"] is swift_entitled,
                       f"entitlement [{label}]: isEntitled {decoded['isEntitled']}, Swift said "
                       f"{swift_entitled}")
        problems.check(decoded["honouredByApp"] is swift_entitled,
                       f"entitlement [{label}]: honouredByApp {decoded['honouredByApp']}")
        print(f"  {label:<14} isEntitled {decoded['isEntitled']!s:<5} (Swift: {swift_entitled})")
    for seconds, iso in EXPECTED_ISO.items():
        got = W.swift_date(seconds).isoformat()
        problems.check(got == iso, f"swift_date({seconds}) = {got}, expected {iso}")
    verified = W.decode_entitlement(SWIFT_RECORDS["verified"][0])
    problems.check(verified["verifiedTransactionID"] == 2000001234567890 and
                   verified["revokedAt"] is None, f"verified record fields: {verified}")
    text = "\n".join(W.entitlement_lines(verified))
    problems.check("2026-09-15T15:46:40.250000+00:00" in text and "isEntitled" in text,
                   f"entitlement lines must print the converted date: {text}")

    wrong_product = W.decode_entitlement(b'{"productID":"com.example.other","lastVerifiedAt":5}')
    problems.check(wrong_product["isEntitled"] is True and wrong_product["honouredByApp"] is False,
                   f"entitlement [other productID]: the app would discard it: {wrong_product}")
    for bad in (b"not json", b"[]", b'{"lastVerifiedAt":1}', b'{"productID":"x",'
                b'"lastVerifiedAt":"yesterday"}', b'{"productID":"x","verifiedTransactionID":-1}',
                b'{"productID":"x","verifiedTransactionID":true}'):
        decoded = W.decode_entitlement(bad)
        problems.check(not decoded["decodable"] and not decoded["honouredByApp"],
                       f"entitlement [{bad!r}]: must be undecodable: {decoded}")
    offer, lines = W.decode_offer(SWIFT_OFFER)
    joined = "\n".join(lines)
    problems.check(offer is not None and "launches 1 · furthest kyoto" in joined
                   and "at kyoto: offerAppeared 1 · settingsRowAppeared 1" in joined,
                   f"offer counters decoded wrongly: {joined}")


def test_defaults_parse(problems):
    print("DEFAULTS OUTPUT — complete vs truncated data (formats measured on macOS 27)")
    cases = [
        ("{length = 4, bytes = 0x01020304}\n", bytes([1, 2, 3, 4]), False),
        ("{length = 24, bytes = 0x000102030405060708090a0b0c0d0e0f1011121314151617}\n",
         bytes(range(24)), False),
        ("{length = 25, bytes = 0x00010203 04050607 08090a0b 0c0d0e0f ... 11121314 15161718 }\n",
         None, True),
        ("<01020304 05060708>\n", bytes(range(1, 9)), False),
        ("{length = 9, bytes = 0x0102}\n", None, True),
        ("hello\n", None, False),
    ]
    for stdout, expected, truncated in cases:
        got = W.parse_defaults_data(stdout)
        problems.check(got == (expected, truncated),
                       f"parse_defaults_data({stdout.strip()!r}) = {got}, expected "
                       f"{(expected, truncated)}")


# =================================================================================================
# 4. The container: absent / present-verified / present-revoked / unreadable
# =================================================================================================

def export_xml(mapping):
    return plistlib.dumps(mapping, fmt=plistlib.FMT_XML).decode("utf-8")


def truncated_read(data):
    return "{length = %d, bytes = 0x%s ... %s }\n" % (len(data), data[:4].hex(), data[-4:].hex())


def container_ctx(tmp, stored, file_bytes=None):
    """A planted container whose `defaults` answers come from `stored` (key → bytes)."""
    ctx, run = context(tmp)
    prefs = ctx.container_prefs
    prefs.parent.mkdir(parents=True, exist_ok=True)
    if file_bytes is not None:
        prefs.write_bytes(file_bytes)
    else:
        with prefs.open("wb") as handle:
            plistlib.dump(stored, handle)
    domain = str(prefs)[:-len(".plist")]
    run.on([W.DEFAULTS, "export", domain, "-"], done(0, export_xml(stored)))
    for key in (W.ENTITLEMENT_KEY, W.QUARANTINE_KEY, W.OFFER_KEY):
        if key in stored:
            run.on([W.DEFAULTS, "read", domain, key], done(0, truncated_read(stored[key])))
        else:
            run.on([W.DEFAULTS, "read", domain, key],
                   done(1, "", f"Error: Could not find key '{key}' in domain '{domain}'.\n"))
    return ctx, run


def test_container(problems):
    print("CONTAINER — gate 1 precondition, each verdict against its pair")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = container_ctx(tmp, {W.OFFER_KEY: SWIFT_OFFER})
        report = W.Report(io.StringIO())
        W.check_container(report, ctx, gate1=True)
        problems.check(any(W.ENTITLEMENT_KEY + " absent" in p for p in lines_at(report, "PASS"))
                       and not lines_at(report, "FAIL"),
                       f"container [absent]: expected PASS: {report.lines}")
        problems.check(any("launches 1 · furthest kyoto" in ln for ln in report.lines),
                       "container [absent]: counters must still be printed")
        print("  key absent            → PASS")

    for label, key, entitled in (("present-verified", "verified", True),
                                 ("present-revoked", "revoked-after", False)):
        with tempfile.TemporaryDirectory() as tmp:
            data = SWIFT_RECORDS[key][0]
            ctx, run = container_ctx(tmp, {W.ENTITLEMENT_KEY: data, W.OFFER_KEY: SWIFT_OFFER})
            report = W.Report(io.StringIO())
            W.check_container(report, ctx, gate1=True)
            fails = lines_at(report, "FAIL")
            text = "\n".join(report.lines)
            problems.check(len(fails) == 1 and "PRESENT" in fails[0],
                           f"container [{label}]: expected one PRESENT FAIL: {report.lines}")
            problems.check(f"isEntitled (EntitlementRecord.isEntitled predicate) {entitled}" in text,
                           f"container [{label}]: decoded isEntitled {entitled} not printed: {text}")
            problems.check("value: defaults export (cfprefsd)" in text,
                           f"container [{label}]: must say the value came from defaults export")
            report = W.Report(io.StringIO())
            W.check_container(report, ctx, gate1=False)
            problems.check(not lines_at(report, "FAIL"),
                           f"container [{label}, mac-state]: presence is state, not a FAIL")
            print(f"  {label:<21} → FAIL, isEntitled {entitled}")

    # macOS 26's `defaults` says "The domain/default pair of (d, k) does not exist" for a missing
    # key AND a missing domain (measured on the CI runner, 2026-09-16). With a readable plist file
    # the domain exists, so it means the key; without one it must stay unknown, never "absent".
    older = "{} defaults[1:2] \nThe domain/default pair of ({}, {}) does not exist\n"
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = container_ctx(tmp, {W.OFFER_KEY: SWIFT_OFFER})
        domain = str(ctx.container_prefs)[:-len(".plist")]
        run.on([W.DEFAULTS, "read", domain, W.ENTITLEMENT_KEY],
               done(1, "", older.format("2026-09-15 18:46:42.637", domain, W.ENTITLEMENT_KEY)))
        readings = W.read_container_keys(ctx.container_prefs, [W.ENTITLEMENT_KEY], run)
        ent = readings[W.ENTITLEMENT_KEY]
        problems.check(ent.present is False and ent.presence_source.startswith(
            "defaults read (cfprefsd): key not found"),
            f"container [older defaults wording, file exists]: {ent.present} {ent.presence_source}")
        print("  older wording + file  → absent via cfprefsd")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        ctx.container_prefs.parent.mkdir(parents=True, exist_ok=True)   # directory, but no file
        domain = str(ctx.container_prefs)[:-len(".plist")]
        run.on([W.DEFAULTS, "export", domain, "-"], done(0, export_xml({})))
        run.on([W.DEFAULTS, "read", domain],
               done(1, "", older.format("2026-09-15 18:46:42.637", domain, W.ENTITLEMENT_KEY)))
        readings = W.read_container_keys(ctx.container_prefs, [W.ENTITLEMENT_KEY], run)
        ent = readings[W.ENTITLEMENT_KEY]
        problems.check(ent.present is None,
                       f"CONTROL container [older wording, NO file]: the sentence cannot tell a "
                       f"missing domain from a missing key, so presence must stay unknown: "
                       f"{ent.present} {ent.presence_source}")
        print("  older wording, no file → unknown (not absent)")

    with tempfile.TemporaryDirectory() as tmp:
        # The broken instrument: defaults cannot run and the file is garbage. This must NOT PASS.
        ctx, run = context(tmp)
        ctx.container_prefs.parent.mkdir(parents=True, exist_ok=True)
        ctx.container_prefs.write_bytes(b"\x00 not a plist")
        run.on([W.DEFAULTS], done(None, "", "", "not found: /usr/bin/defaults"))
        report = W.Report(io.StringIO())
        W.check_container(report, ctx, gate1=True)
        problems.check(not lines_at(report, "PASS") and any(
            "could not establish" in f for f in lines_at(report, "FAIL")),
            f"container [unreadable]: must FAIL as unknown, never PASS: {report.lines}")
        print("  unreadable            → FAIL unknown (not PASS)")

    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)  # no container directory at all
        report = W.Report(io.StringIO())
        W.check_container(report, ctx, gate1=True)
        problems.check(lines_at(report, "PASS") and not run.calls,
                       f"container [no directory]: expected PASS without running defaults: "
                       f"{report.lines} {run.calls}")
        print("  no container dir      → PASS, defaults not run")


def test_real_defaults(problems):
    print("REAL /usr/bin/defaults ON A PLANTED TEMP PLIST — the truncation the reader must survive")
    if not Path(W.DEFAULTS).exists():
        problems.append("/usr/bin/defaults is missing — this test cannot run here")
        return
    for label, stored, expect_present in (
            ("with record", {W.ENTITLEMENT_KEY: SWIFT_RECORDS["verified"][0],
                             W.OFFER_KEY: SWIFT_OFFER}, True),
            ("without record", {W.OFFER_KEY: SWIFT_OFFER}, False)):
        with tempfile.TemporaryDirectory() as tmp:
            prefs = Path(tmp) / "Preferences" / "com.jasonye.nihongoride.walktest.plist"
            prefs.parent.mkdir(parents=True)
            with prefs.open("wb") as handle:
                plistlib.dump(stored, handle)
            root = Path(tmp) / "snapshots"

            def run(argv, timeout, cwd=None):
                return W._run_readonly(argv, timeout, cwd, snapshot_root=root)
            readings = W.read_container_keys(prefs, [W.ENTITLEMENT_KEY, W.OFFER_KEY], run)
            ent, offer = readings[W.ENTITLEMENT_KEY], readings[W.OFFER_KEY]
            problems.check(ent.present is expect_present,
                           f"real defaults [{label}]: entitlement present={ent.present}")
            problems.check(offer.present is True and offer.data == SWIFT_OFFER,
                           f"real defaults [{label}]: offer bytes not recovered intact "
                           f"({offer.value_source}): {offer.data!r}")
            if expect_present:
                # On macOS 27 `defaults read` truncates this 131-byte value, so the bytes come from
                # `defaults export`. The requirement is the BYTES; the source is accepted either
                # way so a macOS that prints full hex cannot turn CI red for a working reader.
                problems.check(ent.data == SWIFT_RECORDS["verified"][0] and
                               ent.value_source.startswith(("defaults export",
                                                            "defaults read (complete hex)")),
                               f"real defaults [{label}]: record not recovered intact: "
                               f"{ent.value_source} {ent.data!r}")
            else:
                problems.check(ent.presence_source.startswith("defaults read (cfprefsd): key not "
                                                              "found"),
                               f"real defaults [{label}]: absence source {ent.presence_source}")
            print(f"  {label:<15} present={ent.present} value via {ent.value_source or '-'}")


# =================================================================================================
# 5. devicectl: locked, readable, not installed, wrong build, empty listing
# =================================================================================================

def device(identifier, name, reality="physical", platform="iOS"):
    return {"identifier": identifier,
            "properties": {"hardware": {"reality": reality, "platform": platform,
                                        "marketingName": "iPhone 15 Pro Max",
                                        "productType": "iPhone16,2", "udid": "SECRET-UDID",
                                        "serialNumber": "SECRET-SERIAL"},
                           "state": {"name": name},
                           "connection": {"pairingState": "paired", "state": "disconnected"}},
            "deviceProperties": {"name": name, "osVersionNumber": "27.0"}}


LOCKED = {"info": {"outcome": "failed"}, "error": {
    "code": 12040, "domain": "com.apple.dt.CoreDeviceError",
    "userInfo": {"NSLocalizedDescription": {"string": "The developer disk image could not be "
                                                      "mounted on this device."},
                 "NSUnderlyingError": {"error": {"code": 10003, "userInfo": {
                     "NSLocalizedDescription": {"string": "The operation failed because the "
                                                          "device was still locked."},
                     "NSLocalizedFailureReason": {"string": "The device is currently locked."}}}}}}}


def app(bundle_id, version, build, by_developer=False):
    return {"bundleIdentifier": bundle_id, "version": version, "bundleVersion": build,
            "builtByDeveloper": by_developer, "name": "x", "removable": True}


def listing(apps):
    return {"info": {"outcome": "success"}, "result": {"apps": apps}}


def devicectl_ctx(tmp, apps_by_device):
    ctx, run = context(tmp)
    devices = {"info": {"outcome": "success"}, "result": {"devices": [
        device("DEV-A", "js"), device("DEV-B", "locked phone"),
        device("SIM-1", "iPhone 17 Pro", reality="simulated"),
        device("WATCH", "watch", platform="watchOS")]}}

    def write_json(payload):
        def handler(argv):
            Path(argv[argv.index("--json-output") + 1]).write_text(json.dumps(payload))
            return W.Completed(argv, 0 if payload.get("info", {}).get("outcome") == "success"
                               else 1, "", "")
        return handler
    run.on([W.XCRUN, "devicectl", "list", "devices"], write_json(devices))
    for ident, payload in apps_by_device.items():
        run.on([W.XCRUN, "devicectl", "device", "info", "apps", "--device", ident],
               write_json(payload))
    return ctx, run


def test_devicectl(problems):
    print("DEVICECTL — only the named device is queried; locked is WARN never FAIL; empty is not 'not installed'")
    others = [app("com.1password.1password", "8.12.36", "81236040"),
              app("com.jasonye.wearform", "1.1.4", "15", by_developer=True)]

    def apps_calls(run):
        return [c for c in run.calls if c[:5] == [W.XCRUN, "devicectl", "device", "info", "apps"]]

    # The pair that matters most: without --device NOTHING is queried; with it, only that device.
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = devicectl_ctx(tmp, {"DEV-A": listing([app(W.BUNDLE_ID, "1.32", "57")]),
                                       "DEV-B": LOCKED})
        report = W.Report(io.StringIO())
        listed, readable = W.check_ios(report, ctx, verdicts=True)
        problems.check(apps_calls(run) == [],
                       f"devicectl [no --device]: queried a device's apps anyway: {apps_calls(run)}")
        problems.check((listed, readable) == (2, 0),
                       f"devicectl [no --device]: (listed, readable) = {(listed, readable)}, expected (2, 0)")
        problems.check(any("apps not queried" in ln and "js" in ln for ln in lines_at(report, "INFO"))
                       and any("no device's apps were queried" in ln for ln in lines_at(report, "INFO")),
                       f"devicectl [no --device]: must say plainly that nothing was queried: {report.lines}")
        problems.check(not any("mounts its developer disk image and opens" in ln and "listing an unlocked"
                               in ln for ln in report.lines),
                       "devicectl [no --device]: printed the DDI side-effect notice although nothing ran")
        print(f"  no --device        → listed {listed}, queried {len(apps_calls(run))}")
    for selector, expected_calls in (("DEV-A", ["DEV-A"]), ("js", ["DEV-A"]), ("nope", [])):
        with tempfile.TemporaryDirectory() as tmp:
            ctx, run = devicectl_ctx(tmp, {"DEV-A": listing(others), "DEV-B": LOCKED})
            report = W.Report(io.StringIO())
            W.check_ios(report, ctx, verdicts=True, device_selector=selector)
            queried = [c[c.index("--device") + 1] for c in apps_calls(run)]
            problems.check(queried == expected_calls,
                           f"devicectl [--device {selector}]: queried {queried}, expected {expected_calls}")
            if not expected_calls:
                problems.check(any("matches 0 paired" in ln for ln in lines_at(report, "WARN")),
                               f"devicectl [--device {selector}]: an unmatched name must WARN: {report.lines}")
            print(f"  --device {selector:<9} → queried {queried}")

    scenarios = [
        ("App Store build", [app(W.BUNDLE_ID, "1.32", "57")] + others, "PASS", "installed 1.32 (57)"),
        ("wrong build", [app(W.BUNDLE_ID, "1.31", "56")] + others, "WARN", "not 1.32 (57)"),
        ("not installed", others, "WARN", "is not installed"),
        ("empty listing", [], "WARN", "could not read its apps"),
        ("built by developer", [app(W.BUNDLE_ID, "1.32", "57", by_developer=True)] + others,
         "WARN", "builtByDeveloper=True"),
    ]
    for label, apps, level, needle in scenarios:
        with tempfile.TemporaryDirectory() as tmp:
            ctx, run = devicectl_ctx(tmp, {"DEV-A": listing(apps), "DEV-B": LOCKED})
            report = W.Report(io.StringIO())
            listed, readable = W.check_ios(report, ctx, verdicts=True, device_selector="js")
            hits = [ln for ln in lines_at(report, level) if "js" in ln and needle in ln]
            problems.check(hits, f"devicectl [{label}]: expected a {level} with {needle!r}: "
                                 f"{report.lines}")
            problems.check(not lines_at(report, "FAIL"),
                           f"devicectl [{label}]: iOS checks must never FAIL: {report.lines}")
            problems.check(readable == (0 if label == "empty listing" else 1),
                           f"devicectl [{label}]: readable count {readable}")
            calls = apps_calls(run)
            problems.check(all("--include-all-apps" in c for c in calls) and len(calls) == 1,
                           f"devicectl [{label}]: exactly one apps listing, with --include-all-apps "
                           f"(the default listing hides App Store apps): {calls}")
            problems.check("SECRET" not in "\n".join(report.lines),
                           "devicectl: serial numbers / UDIDs must not be printed")
            problems.check(any("mounts its developer disk image" in i
                               for i in lines_at(report, "INFO")),
                           f"devicectl [{label}]: the measured DDI side effect must be stated on "
                           f"screen before the device is queried: {report.lines}")
            print(f"  {label:<19} → {level} (readable {readable})")

    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = devicectl_ctx(tmp, {"DEV-A": listing(others), "DEV-B": LOCKED})
        report = W.Report(io.StringIO())
        W.check_ios(report, ctx, verdicts=True, device_selector="locked phone")
        problems.check(any(w.startswith("WARN  locked phone ·") and w.endswith(": locked — unlock and re-run")
                           for w in lines_at(report, "WARN"))
                       and not any("is not installed" in ln for ln in report.lines),
                       f"devicectl [locked]: must WARN 'unlock and re-run' and never say 'not installed': "
                       f"{report.lines}")
        print("  locked phone        → WARN unlock and re-run")

    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = devicectl_ctx(tmp, {"DEV-A": listing([]), "DEV-B": LOCKED})
        code = W.cmd_ios_state(ctx, out=io.StringIO(), device="js")
        problems.check(code == 2, f"ios-state --device js with nothing readable: exit {code}, expected 2")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = devicectl_ctx(tmp, {"DEV-A": listing(others), "DEV-B": LOCKED})
        code = W.cmd_ios_state(ctx, out=io.StringIO(), device="js")
        problems.check(code == 0, f"ios-state --device js readable: exit {code}, expected 0")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = devicectl_ctx(tmp, {"DEV-A": listing(others), "DEV-B": LOCKED})
        code = W.cmd_ios_state(ctx, out=io.StringIO())
        problems.check(code == 0 and apps_calls(run) == [],
                       f"ios-state without --device: exit {code}, queried {apps_calls(run)}; expected 0, none")
    print("  ios-state exit: --device unreadable → 2 · readable → 0 · no --device → 0, nothing queried")


# =================================================================================================
# 6. App Store Connect, via a fake GET
# =================================================================================================

def fake_asc(**change):
    versions = {
        "MAC_OS": [("m131", "1.31", "READY_FOR_SALE", "2026-08-31T01:18:00-07:00"),
                   ("m132", "1.32", "READY_FOR_SALE", "2026-09-10T17:22:47-07:00")],
        "IOS": [("i132", "1.32", "READY_FOR_SALE", "2026-09-10T17:20:00-07:00"),
                ("i131", "1.31", "READY_FOR_SALE", "2026-08-31T01:10:00-07:00")],
    }
    versions.update(change.get("versions", {}))
    builds = {"m132": "56", "i132": "57", "m133": "58"}
    builds.update(change.get("builds", {}))
    subs = change.get("subs", [("COMPLETE", "IOS"), ("COMPLETE", "MAC_OS")])
    iap = {"productId": PID, "inAppPurchaseType": "NON_CONSUMABLE", "state": "APPROVED",
           "familySharable": False}
    iap.update(change.get("iap", {}))
    for k in change.get("drop_iap", ()):
        iap.pop(k)
    calls = []

    def get(endpoint):
        calls.append(endpoint)
        if "error" in change:
            raise W.AscError(change["error"])
        if "/appStoreVersions?" in endpoint:
            platform = "MAC_OS" if "filter[platform]=MAC_OS" in endpoint else "IOS"
            return {"data": [{"id": i, "attributes": {"platform": platform, "versionString": v,
                                                      "appStoreState": s, "createdDate": c}}
                             for i, v, s, c in versions[platform]]}
        if endpoint.startswith("/v1/appStoreVersions/"):
            vid = endpoint.split("/")[3]
            return {"data": {"attributes": {"version": builds.get(vid)}}}
        if endpoint.startswith("/v1/reviewSubmissions?"):
            return {"data": [{"id": f"s{n}", "attributes": {"state": s, "platform": p}}
                             for n, (s, p) in enumerate(subs)]}
        if endpoint.startswith("/v2/inAppPurchases/"):
            return {"data": {"attributes": iap}}
        raise W.AscError(f"unexpected endpoint {endpoint}")
    get.calls = calls
    return get


def test_asc(problems):
    print("ASC — each expectation against its one-variable violation")
    scenarios = [
        ("as released", {}, 0, False),
        ("newer version created later", {"versions": {"MAC_OS": [
            ("m132", "1.32", "READY_FOR_SALE", "2026-09-10T17:22:47-07:00"),
            ("m133", "1.33", "PREPARE_FOR_SUBMISSION", "2026-09-20T09:00:00-07:00")]}}, 2, False),
        ("iOS build 56", {"builds": {"i132": "56"}}, 1, False),
        ("open submission", {"subs": [("COMPLETE", "IOS"), ("WAITING_FOR_REVIEW", "MAC_OS")]},
         1, False),
        ("unknown submission state", {"subs": [("SOMETHING_NEW", "IOS")]}, 1, False),
        ("familySharable true", {"iap": {"familySharable": True}}, 1, False),
        ("familySharable missing", {"drop_iap": ["familySharable"]}, 1, False),
        ("IAP not approved", {"iap": {"state": "DEVELOPER_ACTION_NEEDED"}}, 1, False),
        ("no submissions at all", {"subs": []}, 0, True),
        ("API error", {"error": "asc_api.sh exit 2"}, 0, True),
    ]
    for label, change, expected_fails, expect_api in scenarios:
        with tempfile.TemporaryDirectory() as tmp:
            ctx, run = context(tmp, asc_get=fake_asc(**change))
            report = W.Report(io.StringIO())
            W.check_asc(report, ctx)
            fails = lines_at(report, "FAIL")
            problems.check(len(fails) == expected_fails,
                           f"asc [{label}]: expected {expected_fails} FAIL, got {fails}")
            problems.check(bool(report.api_failures) == expect_api,
                           f"asc [{label}]: api failures {report.api_failures}")
            print(f"  {label:<28} FAIL {len(fails)} · API {len(report.api_failures)}")

    # asc_get itself: failure shapes are failures, and the argv is a GET the allowlist accepts.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for label, completed, raises in (
                ("exit 2", W.Completed([], 2, "", "key not found"), True),
                ("empty body", W.Completed([], 0, "  ", ""), True),
                ("non-JSON", W.Completed([], 0, "<html>", ""), True),
                ("errors payload", W.Completed([], 0, '{"errors":[{"status":"401"}]}', ""), True),
                ("good", W.Completed([], 0, '{"data":[]}', ""), False)):
            run = FakeRun(root).on([W.BASH], lambda argv, c=completed: c)
            try:
                W.asc_get("/v1/apps/x", run)
                raised = False
            except W.AscError:
                raised = True
            problems.check(raised == raises, f"asc_get [{label}]: raised={raised}")


# =================================================================================================
# 7. preflight end to end: exit codes and snapshot
# =================================================================================================

def full_preflight_ctx(tmp, receipt=True, asc_change=None):
    ctx, run = container_ctx(tmp, {W.OFFER_KEY: SWIFT_OFFER})
    ctx.asc_get = fake_asc(**(asc_change or {}))
    make_bundle(ctx.app_path, receipt=receipt)
    run.on([W.CODESIGN], done(0, "", "Authority=Apple Mac OS Application Signing\n"))
    run.on([W.MDFIND], done(0, f"{ctx.app_path}\n"))
    run.on([W.PS], done(0, ps_output(4242, (7, f"{ctx.app_path}/Contents/MacOS/Nihongo Ride"))))
    devices = {"info": {"outcome": "success"}, "result": {"devices": [device("DEV-A", "js")]}}

    def write_json(payload):
        def handler(argv):
            Path(argv[argv.index("--json-output") + 1]).write_text(json.dumps(payload))
            return W.Completed(argv, 0, "", "")
        return handler
    run.on([W.XCRUN, "devicectl", "list", "devices"], write_json(devices))
    run.on([W.XCRUN, "devicectl", "device", "info", "apps"],
           write_json(listing([app(W.BUNDLE_ID, "1.32", "57"), app("com.x", "1", "1")])))
    return ctx, run


def test_preflight_exit(problems):
    print("PREFLIGHT — exit 0 / 1 / 3 and the snapshot")
    for label, kwargs, expected in (("all good", {}, 0),
                                    ("receipt absent", {"receipt": False}, 1),
                                    ("receipt absent + ASC down",
                                     {"receipt": False, "asc_change": {"error": "boom"}}, 3)):
        with tempfile.TemporaryDirectory() as tmp:
            ctx, run = full_preflight_ctx(tmp, **kwargs)
            out = io.StringIO()
            code = W.cmd_preflight(ctx, out=out)
            text = out.getvalue()
            problems.check(code == expected, f"preflight [{label}]: exit {code}, expected "
                                             f"{expected}\n{text}")
            snap = ctx.snapshot_root / "20260916T010203Z"
            problems.check((snap / "preflight.txt").is_file() and (snap / "preflight.json").is_file()
                           and f"snapshot: {snap}" in text,
                           f"preflight [{label}]: snapshot not written/printed under {snap}")
            print(f"  {label:<26} exit {code} (expected {expected})")


# =================================================================================================
# 8. manifest and baseline
# =================================================================================================

def test_manifest(problems):
    print("MANIFEST — sha256 against NIST vectors and hashlib")
    with tempfile.TemporaryDirectory() as tmp:
        evidence = Path(tmp) / "stage1-walk-2026-09-17"
        (evidence / "sub").mkdir(parents=True)
        (evidence / "abc.txt").write_bytes(b"abc")
        (evidence / "sub" / "million.bin").write_bytes(b"a" * 1_000_000)
        # Bigger than the 1 MiB read chunk, with a different byte in the last chunk: the million-a
        # vector alone fits in ONE chunk and would pass a reader that never loops (measured).
        big_bytes = b"\x5a" * (3 * (1 << 20)) + b"tail"
        (evidence / "sub" / "chunks.bin").write_bytes(big_bytes)
        (evidence / ".DS_Store").write_bytes(b"finder")
        os.symlink(str(evidence / "abc.txt"), str(evidence / "link.txt"))
        ctx, run = context(tmp)
        out, err = io.StringIO(), io.StringIO()
        code = W.cmd_manifest(ctx, str(evidence), out=out, err=err)
        rows = [json.loads(line) for line in out.getvalue().splitlines()]
        by_file = {r["file"]: r for r in rows}
        problems.check(code == 0, f"manifest exit {code}")
        chunks = by_file.get("stage1-walk-2026-09-17/sub/chunks.bin", {})
        problems.check(chunks.get("sha256") == hashlib.sha256(big_bytes).hexdigest(),
                       f"manifest sha256 of a multi-chunk file: {chunks}")
        problems.check(set(by_file) == {"stage1-walk-2026-09-17/abc.txt",
                                        "stage1-walk-2026-09-17/sub/chunks.bin",
                                        "stage1-walk-2026-09-17/sub/million.bin"},
                       f"manifest files {sorted(by_file)} (.DS_Store and the symlink must be "
                       f"skipped, and reported)")
        abc = by_file.get("stage1-walk-2026-09-17/abc.txt", {})
        big = by_file.get("stage1-walk-2026-09-17/sub/million.bin", {})
        problems.check(abc.get("sha256") == SHA256_ABC == hashlib.sha256(b"abc").hexdigest(),
                       f"manifest sha256(abc) {abc.get('sha256')}")
        problems.check(big.get("sha256") == SHA256_MILLION_A,
                       f"manifest sha256/size of 1M 'a' {big}")
        problems.check(all(set(r) == {"file", "sha256"} for r in rows),
                       f"manifest stdout must be exactly the registry's evidence shape: {rows}")
        # The contract between the two tools, checked with the instrument's OWN validator rather
        # than a copy of its rule: an entry carrying these lines as evidence must validate.
        sys.path.insert(0, str(Path(W.__file__).resolve().parent))
        import sales_report as SR
        entry = {"id": "t", "kind": "purchase", "report_day_pt": "2026-09-16", "platform": "macOS",
                 "country_code": "JP", "units": 1, "status": "awaiting-report",
                 "matched_product_type": None, "local_timestamp": "2026-09-17T10:00:00+09:00",
                 "walk_step": "t", "evidence": rows, "notes": ""}
        registry = {"schema": 1, "day0": "2026-09-09",
                    "decisions": {"exclude_walk_first_downloads_from_N": None,
                                  "exclude_owner_refund_from_refund_ceiling": None},
                    "entries": [entry]}
        ev_problems = [x for x in SR.validate_registry(registry) if "evidence" in x]
        problems.check(rows and not ev_problems,
                       f"manifest lines rejected by sales_report.validate_registry: {ev_problems}")
        snap_rows = [json.loads(line) for line in
                     next(ctx.snapshot_root.glob("*/manifest.jsonl")).read_text().splitlines()]
        problems.check(all(set(r) == {"file", "sha256", "size", "mtime"} and
                           W.parse_iso(r["mtime"]).utcoffset() is not None for r in snap_rows),
                       f"manifest snapshot must keep file/sha256/size/mtime with an offset: {snap_rows}")
        problems.check(".DS_Store" in err.getvalue() and "link.txt" in err.getvalue(),
                       f"manifest must report what it skipped: {err.getvalue()}")
        problems.check(W.cmd_manifest(ctx, str(evidence / "nope"), out=io.StringIO(),
                                      err=io.StringIO()) == 2, "manifest on a missing dir: exit 2")
        print(f"  {len(rows)} files, abc and 1M-a match NIST, skipped reported")


def test_baseline(problems):
    print("BASELINE — injected runner: argv, transcripts, exit mapping")
    table = {(0, 0): 0, (0, 5): 0, (4, 5): 4, (0, 4): 4, (0, 2): 2, (None, 0): 1, (3, 5): 3,
             (0, None): 1}
    for (cal, chk), expected in table.items():
        got = W.baseline_exit(cal, chk)
        problems.check(got == expected, f"baseline_exit({cal}, {chk}) = {got}, expected {expected}")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        snap = ctx.snapshot_root / "20260916T010203Z"
        run.on([sys.executable, str(W.SALES_REPORT), "--calibrate"],
               done(0, "FIRST-TIME DOWNLOADS 155\nCALIBRATION OK\n", ""))
        run.on([sys.executable, str(W.SALES_REPORT), "--checkpoint"],
               done(5, "BOUND WITHHELD: no matched known-positive\n", ""))
        out = io.StringIO()
        code = W.cmd_baseline(ctx, out=out)
        problems.check(code == 0, f"baseline exit {code}, expected 0 (calibrate 0, checkpoint 5)")
        problems.check([c[2:] for c in run.calls] ==
                       [["--calibrate", "--json", str(snap / "sales.json")], ["--checkpoint"]],
                       f"baseline argv: {run.calls}")
        record = json.loads((snap / "baseline.json").read_text())
        problems.check([r["exit"] for r in record["runs"]] == [0, 5] and record["exit"] == 0,
                       f"baseline.json exits: {record}")
        problems.check("CALIBRATION OK" in (snap / "calibrate.stdout.txt").read_text() and
                       "BOUND WITHHELD" in (snap / "checkpoint.stdout.txt").read_text(),
                       "baseline transcripts not saved")
        problems.check(f"snapshot: {snap}" in out.getvalue(), "baseline must print the snapshot")
    with tempfile.TemporaryDirectory() as tmp:
        ctx, run = context(tmp)
        run.on([sys.executable, str(W.SALES_REPORT), "--calibrate"], done(4, "CALIBRATION-FAIL\n"))
        run.on([sys.executable, str(W.SALES_REPORT), "--checkpoint"], done(4, ""))
        code = W.cmd_baseline(ctx, out=io.StringIO())
        problems.check(code == 4, f"baseline with calibration failing: exit {code}, expected 4")
        print("  calibrate 0 + checkpoint 5 → 0 · calibrate 4 → 4 · transcripts saved")


# =================================================================================================
# 9. The read-only allowlist and the snapshot writer, behaviourally
# =================================================================================================

def test_allowlist(problems):
    print("ALLOWLIST — every production argv accepted, every write/store form refused")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "snapshots"
        temp_json = str(Path(tempfile.gettempdir()) / "x" / "out.json")
        dom = "/Users/x/Library/Containers/c/Data/Library/Preferences/c"
        accepted = [
            [W.DEFAULTS, "read", dom, W.ENTITLEMENT_KEY],
            [W.DEFAULTS, "export", dom, "-"],
            [W.CODESIGN, "-dv", "--verbose=2", str(W.MAC_APP)],
            [W.MDFIND, "kMDItemCFBundleIdentifier == 'com.jasonye.nihongoride'"],
            [W.PS, "-axww", "-o", "pid=,comm="],
            [W.XCRUN, "devicectl", "list", "devices", "--timeout", "30", "--json-output", temp_json],
            [W.XCRUN, "devicectl", "device", "info", "apps", "--device", "D", "--include-all-apps",
             "--timeout", "45", "--json-output", temp_json],
            [W.BASH, str(W.ASC_API), "GET", "/v1/apps/6777469778"],
            [sys.executable, str(W.SALES_REPORT), "--checkpoint"],
            [sys.executable, str(W.SALES_REPORT), "--calibrate", "--json", str(root / "t/sales.json")],
        ]
        refused = [
            [W.DEFAULTS, "write", dom, "k", "v"],
            [W.DEFAULTS, "delete", dom, "k"],
            [W.DEFAULTS, "import", dom, "/tmp/x.plist"],
            [W.DEFAULTS, "export", dom, "/tmp/copy.plist"],
            [W.CODESIGN, "-s", "-", str(W.MAC_APP)],
            [W.XCRUN, "devicectl", "device", "install", "app", "--device", "D", "/tmp/x.app"],
            [W.XCRUN, "devicectl", "device", "process", "launch", "--device", "D", W.BUNDLE_ID],
            [W.XCRUN, "devicectl", "device", "info", "apps", "--device", "D", "--json-output",
             str(W.REPO / "docs/x.json")],
            [W.XCRUN, "devicectl", "device", "info", "apps", "--device"],
            [W.BASH, str(W.ASC_API), "POST", "/v1/reviewSubmissions"],
            [W.BASH, str(W.ASC_API), "PATCH", "/v1/appStoreVersions/x"],
            [W.BASH, str(W.ASC_API), "DELETE", "/v1/reviewSubmissions/x"],
            [sys.executable, str(W.SALES_REPORT), "--calibrate", "--json",
             str(W.REPO / "docs/measurements/stage1-known-positives.json")],
            [sys.executable, str(W.SALES_REPORT), "--confirm-known-positive"],
            ["/usr/bin/open", "macappstore://apps.apple.com/app/id6777469778"],
            ["/usr/bin/touch", str(Path(tmp) / "created")],
            [],
        ]
        for argv in accepted:
            try:
                W._assert_readonly_argv(argv, root)
            except W.ReadOnlyViolation as exc:
                problems.append(f"allowlist refused a production form: {exc}")
        for argv in refused:
            try:
                W._assert_readonly_argv(argv, root)
                problems.append(f"allowlist ACCEPTED a forbidden form: {argv}")
            except W.ReadOnlyViolation:
                pass
        try:
            W._run_readonly(["/usr/bin/touch", str(Path(tmp) / "created")], 5, snapshot_root=root)
            problems.append("_run_readonly ran a command outside the allowlist")
        except W.ReadOnlyViolation:
            pass
        problems.check(not (Path(tmp) / "created").exists(),
                       "_run_readonly let a refused command create a file")
        print(f"  {len(accepted)} accepted · {len(refused)} refused · refusal happens before running")

        snap = W._snapshot_dir(root, dt.datetime(2026, 9, 16, tzinfo=dt.timezone.utc))
        first = W._snapshot_write(snap, root, "a.txt", "1")
        second = W._snapshot_write(snap, root, "a.txt", "2")
        problems.check(first.read_text() == "1" and second.name == "a-2.txt",
                       f"snapshot collision must not overwrite: {first} {second}")
        for bad in ("../escape.txt", "../../escape.txt", "sub/x.txt", ".."):
            try:
                W._snapshot_write(snap, root, bad, "x")
                problems.append(f"_snapshot_write wrote outside its snapshot folder: {bad}")
            except W.ReadOnlyViolation:
                pass
            except Exception as exc:  # an OSError is luck, not a refusal
                problems.append(f"_snapshot_write did not refuse {bad!r}; it failed with {exc!r}")
        problems.check(not (root / "escape.txt").exists() and
                       not (Path(tmp) / "escape.txt").exists(),
                       "_snapshot_write created an escaped file before refusing")
        try:
            W._snapshot_dir(W.REPO / "docs", dt.datetime(2026, 9, 16, tzinfo=dt.timezone.utc))
            problems.append("_snapshot_dir accepted a root inside the repo")
        except W.ReadOnlyViolation:
            pass


# =================================================================================================
# 10. The no-side-effects source scan, and the planted violations that prove it fires
# =================================================================================================

FORBIDDEN_IMPORTS = {"urllib", "http", "socket", "ssl", "webbrowser", "requests", "ftplib",
                     "smtplib", "telnetlib", "pty", "ctypes", "objc", "AppKit", "Foundation",
                     "StoreKit", "shutil", "asyncio", "multiprocessing"}
# Whole-string matches: the argv elements of a write verb or a store action.
FORBIDDEN_EXACT = {"write", "delete", "import", "rename", "remove", "POST", "PATCH", "PUT",
                   "DELETE", "install", "uninstall", "launch", "terminate", "process", "copy",
                   "reboot", "erase", "pair", "unpair", "open", "/usr/bin/open", "mas",
                   "purchase", "restore", "signin", "signout", "sync", "-s", "--sign", "--force",
                   "kill", "killall", "/usr/bin/killall", "tccutil", "lsregister"}
# Substrings, case-insensitive: commands written as one string, URLs and store APIs.
FORBIDDEN_SUBSTRINGS = ("defaults write", "defaults delete", "defaults import", "macappstore:",
                        "itms-apps:", "itms:", "apps.apple.com", "product.purchase", "buyproduct",
                        "appstore.sync", "sktestsession", "devicectl device install",
                        "devicectl device uninstall", "devicectl device process",
                        "reportaproblem", "mas purchase", "mas signin")
OS_FORBIDDEN = {"system", "popen", "remove", "unlink", "rmdir", "removedirs", "rename", "renames",
                "replace", "chmod", "chown", "truncate", "symlink", "link", "kill", "killpg",
                "putenv", "write", "open", "fork", "forkpty"}
WRITE_FUNCS = {"_snapshot_dir", "_snapshot_write"}
WRITE_METHODS = {"write", "write_text", "write_bytes", "mkdir", "touch", "unlink", "rmdir",
                 "rename", "symlink_to", "hardlink_to", "chmod", "writelines", "truncate",
                 "makedirs"}
DYNAMIC = {"eval", "exec", "compile", "__import__", "getattr", "setattr"}


def scan_source(source):
    """Problems in the walk tool's source, as `rule: detail` strings."""
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
                # An alias hides the name every other rule looks for (`subprocess`, `os`).
                if alias.name.split(".")[0] in ("os", "subprocess") and alias.asname:
                    problems.append(f"import: {alias.name} as {alias.asname} ({where(node)})")
        elif isinstance(node, ast.ImportFrom):
            # `from subprocess import run` / `from os import system` bind a bare name that no rule
            # below can see, so they are refused wherever they appear — at module level AND inside
            # a function (the first version checked only module level; review 2026-09-16).
            if (node.module or "").split(".")[0] in FORBIDDEN_IMPORTS or \
                    (node.module or "").split(".")[0] in ("os", "subprocess"):
                problems.append(f"import: from {node.module} import … ({where(node)})")
        elif isinstance(node, ast.Name) and node.id == "subprocess" and fn != "_run_readonly":
            problems.append(f"subprocess-outside-runner: ({where(node)})")
        elif isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            owner, attr = node.value.id, node.attr
            if owner == "os" and (attr in OS_FORBIDDEN or attr.startswith(("exec", "spawn",
                                                                           "posix_spawn"))):
                problems.append(f"os-call: os.{attr} ({where(node)})")
            if owner == "os" and attr in ("makedirs", "mkdir") and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-snapshot: os.{attr} ({where(node)})")
            if owner == "plistlib" and attr in ("dump", "dumps"):
                problems.append(f"plistlib-dump: plistlib.{attr} ({where(node)})")
            if owner == "json" and attr == "dump" and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-snapshot: json.dump ({where(node)})")
            if owner == "tempfile" and attr != "gettempdir" and fn != "_devicectl_json":
                problems.append(f"tempfile-outside-devicectl: tempfile.{attr} ({where(node)})")
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in DYNAMIC:
                problems.append(f"dynamic: {func.id}() ({where(node)})")
            if isinstance(func, ast.Attribute) and func.attr in WRITE_METHODS \
                    and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-snapshot: .{func.attr}() ({where(node)})")
            # `.replace` is str.replace almost everywhere, so only a Path(...) receiver counts: that
            # one is a rename on disk.
            if isinstance(func, ast.Attribute) and func.attr == "replace" \
                    and isinstance(func.value, ast.Call) and isinstance(func.value.func, ast.Name) \
                    and func.value.func.id == "Path" and fn not in WRITE_FUNCS:
                problems.append(f"write-outside-snapshot: Path(...).replace() ({where(node)})")
            is_open = (isinstance(func, ast.Name) and func.id == "open") or \
                (isinstance(func, ast.Attribute) and func.attr == "open")
            if is_open:
                index = 1 if isinstance(func, ast.Name) else 0
                mode = node.args[index] if len(node.args) > index else next(
                    (k.value for k in node.keywords if k.arg == "mode"), None)
                if mode is not None:
                    if not (isinstance(mode, ast.Constant) and isinstance(mode.value, str)):
                        problems.append(f"open-mode-unknown: ({where(node)})")
                    elif any(c in mode.value for c in "wax+") and fn not in WRITE_FUNCS:
                        problems.append(f"write-outside-snapshot: open(mode={mode.value!r}) "
                                        f"({where(node)})")
        if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in docstrings:
            if node.value in FORBIDDEN_EXACT:
                problems.append(f"forbidden-string: {node.value!r} ({where(node)})")
            low = node.value.lower()
            for sub in FORBIDDEN_SUBSTRINGS:
                if sub in low:
                    problems.append(f"forbidden-substring: {sub!r} ({where(node)})")

    runners = [n for n in ast.walk(tree)
               if isinstance(n, ast.FunctionDef) and n.name == "_run_readonly"]
    if len(runners) != 1:
        problems.append("runner-unguarded: expected exactly one _run_readonly")
    else:
        guard_lines = [n.lineno for n in ast.walk(runners[0]) if isinstance(n, ast.Call)
                       and isinstance(n.func, ast.Name) and n.func.id == "_assert_readonly_argv"]
        spawn_lines = [n.lineno for n in ast.walk(runners[0])
                       if isinstance(n, ast.Name) and n.id == "subprocess"]
        if not guard_lines or (spawn_lines and min(guard_lines) > min(spawn_lines)):
            problems.append("runner-unguarded: _run_readonly does not call _assert_readonly_argv "
                            "before subprocess")
    writers = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)
               and n.name in WRITE_FUNCS}
    for name in sorted(WRITE_FUNCS):
        node = writers.get(name)
        if node is None or not any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                                   and n.func.id == "_inside" for n in ast.walk(node)):
            problems.append(f"writer-unguarded: {name} does not check _inside")
    return problems


RUNNER_GUARD = ("    _assert_readonly_argv(argv, snapshot_root if snapshot_root is not None "
                "else SNAPSHOT_ROOT)\n")
PLANTED = [
    ("forbidden-string", 'def _p1():\n    _run_readonly(["/usr/bin/defaults", "write", "d", "k", '
                         '"v"], 1)\n'),
    ("forbidden-string", 'def _p2():\n    return [DEFAULTS, "delete", "d", "k"]\n'),
    ("forbidden-string", 'def _p3():\n    return [DEFAULTS, "import", "d", "/tmp/p"]\n'),
    ("forbidden-string", 'def _p4():\n    return [BASH, str(ASC_API), "POST", "/v1/x"]\n'),
    ("forbidden-string", 'def _p5():\n    return [XCRUN, "devicectl", "device", "install", '
                         '"app"]\n'),
    ("subprocess-outside-runner", 'def _p6():\n    subprocess.run(["true"])\n'),
    ("forbidden-substring", 'def _p7():\n    return "macappstore://apps.apple.com/app/id1"\n'),
    ("import", "import urllib.request\n"),
    ("plistlib-dump", "def _p8(p):\n    plistlib.dump({}, p)\n"),
    ("write-outside-snapshot", 'def _p9(p):\n    with open(p, "w") as handle:\n'
                               '        handle.write("x")\n'),
    ("write-outside-snapshot", 'def _p10(p):\n    Path(p).write_text("x")\n'),
    ("os-call", 'def _p11():\n    os.system("true")\n'),
    ("forbidden-substring", 'def _p12():\n    return "defaults write com.jasonye.nihongoride k v"\n'),
    ("forbidden-substring", 'def _p13():\n    return "Product.purchase()"\n'),
    ("dynamic", 'def _p14():\n    return eval("1")\n'),
    ("tempfile-outside-devicectl", "def _p15():\n    return tempfile.mkdtemp()\n"),
    # Found by review 2026-09-16: each of these bypassed the scan before.
    ("import", "def _p16(argv):\n    from subprocess import run\n    return run(argv)\n"),
    ("import", "def _p17(cmd):\n    from os import system\n    return system(cmd)\n"),
    ("import", "def _p18(argv):\n    import subprocess as sp\n    return sp.run(argv)\n"),
    ("write-outside-snapshot", "def _p19(p, q):\n    return Path(p).replace(q)\n"),
]


def test_source_scan(problems):
    print("SOURCE SCAN — the real tool is clean; every planted violation is reported")
    source = SCRIPT.read_text(encoding="utf-8")
    clean = scan_source(source)
    problems.check(clean == [], "stage1_walk.py violates the no-side-effects scan:\n  " +
                   "\n  ".join(clean))
    print(f"  stage1_walk.py: {len(clean)} problem(s)")
    for rule, snippet in PLANTED:
        found = scan_source(source + "\n\n" + snippet)
        fired = [p for p in found if p.startswith(rule + ":")]
        problems.check(fired, f"source scan did NOT fire on a planted {rule} violation:\n{snippet}")
        print(f"  planted {rule:<28} → {'fired' if fired else 'SILENT'}")
    problems.check(source.count(RUNNER_GUARD) == 1,
                   "the runner-guard control is vacuous: the guard line was not found verbatim")
    fired = [p for p in scan_source(source.replace(RUNNER_GUARD, "")) if p.startswith("runner-")]
    problems.check(fired, "source scan did NOT notice _run_readonly losing its allowlist check")
    print(f"  removed runner guard{'':<14} → {'fired' if fired else 'SILENT'}")
    prose = ('def _prose():\n    """Never runs defaults write, never POSTs, never opens '
             'macappstore: links."""\n    return None\n')
    quiet = scan_source(source + "\n\n" + prose)
    problems.check(quiet == [], f"source scan fired on a docstring (it would get weakened): {quiet}")
    print(f"  docstring-only mention{'':<12} → {'quiet' if not quiet else 'FIRED'}")


def main():
    problems = Problems()
    for test in (test_mac_binary, test_other_copies, test_processes, test_entitlement_decode,
                 test_defaults_parse, test_container, test_real_defaults, test_devicectl, test_asc,
                 test_preflight_exit, test_manifest, test_baseline, test_allowlist,
                 test_source_scan):
        try:
            test(problems)
        except Exception as exc:  # a crash is a failure with a name, not the end of the run
            problems.append(f"{test.__name__} CRASHED: {exc!r}\n{traceback.format_exc()}")
        print()
    if problems:
        print(f"{len(problems)} FAILURE(S):")
        for p in problems:
            print(f"\nFAIL  {p}")
        return 1
    print("every walk verdict holds against its pair, every 'absent' refuses a broken instrument, "
          "and the read-only scan fires on each planted violation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
