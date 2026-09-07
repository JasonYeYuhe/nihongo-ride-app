#!/usr/bin/env python3
"""`asc_release.py` must do exactly what `submit_1_30.py` did, and its new guards must fire.

WHY A DIFFERENTIAL AND NOT A UNIT TEST. `asc_release.py` is a port of the 791-line script that
shipped v1.30. The failure mode of any such port is that it is *plausible* — it reads correctly,
its own tests pass, and it sends Apple something slightly different from what the release that
worked sent. Reading it carefully is not a control. So this file drives BOTH implementations
against the same stateful fake App Store Connect, with v1.30's own configuration read out of
`submit_1_30.py`, and requires the same API calls, with the same bodies, in the same order, the
same failure ledger, and the same end state.

ELEVEN SCENARIOS, NOT ONE, AND THAT IS THE POINT. A differential over the happy path is a
differential over the branch that was never in doubt. *For any scan, compute the population it
SKIPS* — so the matrix below deliberately includes the branches that have actually cost this
project something: the purchase that cannot be staged (two cancelled submissions, 2026-08-31), a
description whose sentence is no longer there (a listing keeping a claim that stopped being
true), a locale on the App Store the script has no copy for (shipping the previous release's
notes), one platform already in review, and a submission container left behind by a failed run.

AND THE DIFFERENTIAL IS ITSELF CONTROLLED, ONCE PER DIMENSION IT COMPARES. A comparison that
always passes and a comparison of two identical things look the same.
  * `control_calls` drops the byte-exact read-back after a PATCH and requires the call-log
    comparison to go RED.
  * `control_ledger` makes `fail()` swallow its argument and requires the ledger comparison to go
    RED on a scenario where v1.30 records a failure.
  The end-state comparison is NOT independently controlled: it is a redundant check that mostly
  restates the call log, and it is kept because it is nearly free, not because it is evidence.

WHAT ELSE IS HERE, each a mutation with a paired control that must fire:

  * **The submit gate**, ported from `test_submit_gate.py`: with a purchase declared and
    unstageable, nothing is submitted and the ledger records why; with the identical fake and one
    variable changed, exactly two submissions go out.
  * **The gate is not vacuous when no purchase is declared.** `iap=None` submits both platforms
    AND touches no in-app-purchase endpoint at all — the second half matters, because a gate that
    silently reads "no purchase" as "purchase accounted for" is this repo's oldest defect
    arriving in the release path.
  * **Preflight**, rule by rule: every contract that has lived in a comment since v1.5 gets a
    config that violates it and must be rejected, against the real v1.30 config which must pass.

    python3 scripts/test_asc_release.py
"""
import contextlib
import copy
import importlib.util
import io
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import asc_release                                             # noqa: E402
from asc_release import Release                                # noqa: E402


def load_v130():
    """The shipped v1.30 script, imported as a module so its config can be read off it."""
    spec = importlib.util.spec_from_file_location("submit_1_30_under_test",
                                                  SCRIPTS / "submit_1_30.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def release_from(module, **overrides):
    """A `Release` carrying v1.30's own configuration, so the differential compares behaviour
    rather than comparing two sets of test fixtures."""
    kwargs = dict(
        version=module.VERSION,
        targets=copy.deepcopy(module.TARGETS),
        whats_new=copy.deepcopy(module.WHATS_NEW),
        description_edits=copy.deepcopy(module.DESCRIPTION_EDITS),
        review_notes=module.REVIEW_NOTES,
        iap={"id": module.IAP_ID, "product_id": module.IAP_PRODUCT_ID},
        app=module.APP,
        contact=copy.deepcopy(module.CONTACT),
    )
    kwargs.update(overrides)
    return Release(**kwargs)


# --- the fake App Store Connect ----------------------------------------------------------------
#
# Stateful on purpose. A PATCH stores what it was sent, so the byte-exact read-back after it is
# exercised rather than stubbed into agreeing; submitting a container advances the states of the
# items inside it, so the read-back at the end of `do_submit` reports what actually happened.

BASE_LOCALES = ("en-US", "zh-Hans", "ja")


def fresh_state(module, sc):
    """A store shaped by one scenario. `sc` is the scenario dict; every knob has a default."""
    locales = BASE_LOCALES + tuple(sc.get("extra_locales", ()))
    descriptions = {}
    for locale in locales:
        pair = module.DESCRIPTION_EDITS.get(locale)
        if pair is None:
            descriptions[locale] = "Nihongo Ride.\nアカウント登録は不要。\nMore description text."
        elif sc.get("descriptions") == "corrected":
            descriptions[locale] = f"Nihongo Ride.\n{pair[1]}\nMore description text."
        elif sc.get("descriptions") == "rewritten":
            descriptions[locale] = "Nihongo Ride.\nSomebody rewrote this paragraph.\nMore text."
        else:
            descriptions[locale] = f"Nihongo Ride.\n{pair[0]}\nMore description text."

    versions = {}
    if sc.get("versions_exist"):
        for t in module.TARGETS:
            versions[t["platform"]] = {
                "id": f"ver-{t['platform']}",
                "state": sc.get("version_states", {}).get(t["platform"],
                                                          "PREPARE_FOR_SUBMISSION")}
    submissions = {}
    if sc.get("open_submissions"):
        for t in module.TARGETS:
            submissions[f"open-{t['platform']}"] = []
    # A purchase that is "already in review" is IN something. Seeding only the state string
    # produced a world Apple cannot be in — the purchase in review, held by no submission — which
    # is exactly the post-cancel window the containment probe exists to refuse. The scenario was
    # asserting that the old code sailed through an impossible state; making the world coherent is
    # what lets it assert the real property instead.
    if sc.get("iap_state") in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL",
                               "APPROVED", "APPROVED_PENDING_RELEASE"):
        submissions.setdefault("open-carrying-iap", []).append(("iap", None))
    return {
        "locales": list(locales),
        "versions": versions,
        "loc": {locale: dict(whatsNew="previous release notes",
                             description=descriptions[locale]) for locale in locales},
        "review_detail": ({"notes": "the previous release's notes"}
                          if sc.get("review_detail") else None),
        "iap": sc.get("iap_state", "READY_TO_SUBMIT"),
        "submissions": submissions,
        "preexisting_submissions": dict.fromkeys(submissions, True),
    }


def make_fake(state, module, sc, log):
    """One fake, driven by both implementations. `log` records (method, endpoint, body)."""
    iap_stageable = sc.get("iap_stageable", True)

    def platform_of_version(vid):
        for platform, v in state["versions"].items():
            if v["id"] == vid:
                return platform
        raise AssertionError(f"unknown version id {vid}")

    def fake(method, ep, body=None, allow_empty=False):
        log.append((method, ep, copy.deepcopy(body)))

        # --- versions -----------------------------------------------------------------------
        if method == "GET" and "/appStoreVersions?filter[platform]=" in ep:
            platform = ep.split("filter[platform]=")[1].split("&")[0]
            v = state["versions"].get(platform)
            if "filter[versionString]" in ep:
                return {"data": [{"id": v["id"]}] if v else []}
            # the dry run's "what will this version inherit from" query
            return {"data": ([{"id": v["id"], "attributes": {"versionString": "1.29"}}]
                             if v else [])}
        if method == "POST" and ep == "/v1/appStoreVersions":
            platform = body["data"]["attributes"]["platform"]
            state["versions"][platform] = {"id": f"ver-{platform}",
                                           "state": "PREPARE_FOR_SUBMISSION"}
            return {"data": {"id": f"ver-{platform}"}}
        if method == "GET" and ep.startswith("/v1/appStoreVersions/ver-") and "?" not in ep \
                and ep.count("/") == 3:
            vid = ep.rsplit("/", 1)[1]
            return {"data": {"attributes":
                             {"appStoreState": state["versions"][platform_of_version(vid)]["state"]}}}

        # --- localizations ------------------------------------------------------------------
        if method == "GET" and "/appStoreVersionLocalizations?" in ep:
            return {"data": [{"id": f"loc-{locale}", "attributes": {"locale": locale}}
                             for locale in state["locales"]]}
        if method == "PATCH" and ep.startswith("/v1/appStoreVersionLocalizations/"):
            lid = ep.rsplit("/", 1)[1]
            locale = lid[len("loc-"):]
            for field, value in body["data"]["attributes"].items():
                state["loc"][locale][field] = value
            return {"data": {"id": lid}}
        if method == "GET" and ep.startswith("/v1/appStoreVersionLocalizations/"):
            lid, _, query = ep.partition("?")
            locale = lid.rsplit("/", 1)[1][len("loc-"):]
            field = query.split("=")[-1]
            return {"data": {"id": f"loc-{locale}",
                             "attributes": {field: state["loc"][locale].get(field)}}}

        # --- review detail ------------------------------------------------------------------
        if method == "GET" and ep.endswith("/appStoreReviewDetail"):
            if state["review_detail"] is None:
                return {"data": None}
            return {"data": {"id": "rd-1", "attributes": dict(state["review_detail"])}}
        if method == "POST" and ep == "/v1/appStoreReviewDetails":
            state["review_detail"] = dict(body["data"]["attributes"])
            return {"data": {"id": "rd-1"}}
        if method == "PATCH" and ep.startswith("/v1/appStoreReviewDetails/"):
            state["review_detail"] = dict(body["data"]["attributes"])
            return {"data": {"id": "rd-1"}}

        # --- builds -------------------------------------------------------------------------
        if method == "GET" and ep.startswith("/v1/builds?"):
            return {"data": [
                {"id": f"b{t['build_num']}",
                 "attributes": {"version": t["build_num"], "processingState": "VALID",
                                "usesNonExemptEncryption": False}}
                for t in module.TARGETS]}
        if method == "GET" and "/preReleaseVersion" in ep:
            bid = ep.split("/v1/builds/")[1].split("/")[0]
            platform = next(t["platform"] for t in module.TARGETS
                            if f"b{t['build_num']}" == bid)
            return {"data": {"attributes": {"platform": platform}}}
        if method == "PATCH" and ep.endswith("/relationships/build"):
            return {}

        # --- in-app purchase ----------------------------------------------------------------
        if method == "GET" and "inAppPurchases" in ep and "/versions" in ep:
            return {"data": [{"id": "iapv-1"}]}
        if method == "GET" and ep.startswith("/v2/inAppPurchases/"):
            return {"data": {"attributes": {"state": state["iap"],
                                            "productId": module.IAP_PRODUCT_ID}}}

        # --- review submissions -------------------------------------------------------------
        if method == "GET" and "reviewSubmissions?" in ep and "filter[platform]=" in ep:
            platform = ep.split("filter[platform]=")[1].split("&")[0]
            sid = f"open-{platform}"
            return {"data": [{"id": sid}] if sid in state["preexisting_submissions"] else []}
        if method == "GET" and "reviewSubmissions?" in ep:
            # No platform filter: the containment probe asks about EVERY platform at once. The
            # real API allows this; the fake refused to model it and raised IndexError, which is
            # the fake being incomplete rather than the module being wrong.
            live = [{"id": sid, "attributes": {"state": "READY_FOR_REVIEW", "platform": "?"}}
                    for sid in list(state["preexisting_submissions"]) + list(state["submissions"])]
            return {"data": live}
        if method == "GET" and "/items?" in ep and "reviewSubmissions/" in ep:
            sid = ep.split("reviewSubmissions/")[1].split("/")[0]
            held = state["submissions"].get(sid, [])
            included = [{"type": "inAppPurchaseVersions", "id": "iapv-1"}
                        for kind, _ in held if kind == "iap"]
            return {"data": [{"id": f"item-{i}"} for i, _ in enumerate(held)],
                    "included": included}
        if method == "POST" and ep == "/v1/reviewSubmissions":
            sid = "sub-" + body["data"]["attributes"]["platform"]
            state["submissions"][sid] = []
            return {"data": {"id": sid}}
        if method == "POST" and ep == "/v1/reviewSubmissionItems":
            rels = body["data"]["relationships"]
            sid = rels["reviewSubmission"]["data"]["id"]
            if "inAppPurchaseVersion" in rels:
                if not iap_stageable:
                    return {"errors": [{"detail": "This in-app purchase cannot be reviewed."}]}
                state["submissions"][sid].append(("iap", None))
                return {"data": {"id": "item-iap"}}
            state["submissions"][sid].append(("version", rels["appStoreVersion"]["data"]["id"]))
            return {"data": {"id": "item-ver"}}
        if method == "PATCH" and ep.startswith("/v1/reviewSubmissions/"):
            # Submitting a container is what advances everything inside it — so a version only
            # reads back as submitted if it was actually an item in something that was sent.
            for kind, ident in state["submissions"].get(ep.rsplit("/", 1)[1], []):
                if kind == "iap":
                    state["iap"] = "WAITING_FOR_REVIEW"
                else:
                    state["versions"][platform_of_version(ident)]["state"] = "WAITING_FOR_REVIEW"
            return {"data": {"attributes": {"state": "WAITING_FOR_REVIEW"}}}

        raise AssertionError(f"the fake was asked something it does not stub: {method} {ep}")

    return fake


def drive_old(module, sc):
    """Run the shipped v1.30 script's phase against a fresh fake."""
    state, log = fresh_state(module, sc), []
    module.FAILURES.clear()
    module.asc = make_fake(state, module, sc, log)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        getattr(module, sc["phase"])()
    return log, list(module.FAILURES), state, buf.getvalue()


def drive_new(module, sc, release=None):
    """Run the extracted module's phase against a fresh fake, identically configured."""
    state, log = fresh_state(module, sc), []
    release = release or release_from(module)
    release.asc = make_fake(state, module, sc, log)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        getattr(release, sc["phase"])()
    return log, list(release.failures), state, buf.getvalue()


# The port deliberately makes calls v1.30's script did not, and they are enumerated here for the
# same reason `LEDGER_EQUIVALENTS` is: a rule like "ignore extra GETs" would also swallow the next
# divergence, which nobody has read.
#
# What they are: the containment probe added 2026-09-07. v1.30 decided "is the purchase already
# carried?" by reading the purchase's own state string, and `IAP_ALREADY_IN` contains `IN_REVIEW`.
# Apple's cancel is asynchronous, so immediately after a submission is withdrawn the purchase
# still reads `IN_REVIEW` while belonging to nothing — and the old expression concluded "carried",
# skipped staging, satisfied the phase-3 gate, and submitted a version advertising a purchase that
# was in no review. Printing OK. Exiting 0.
#
# So the module now asks WHERE the purchase is instead of WHAT it says. That is strictly more
# reads and no more writes, which is the only shape of divergence allowed here: the assertion
# below is that every extra call is a GET. A port that started sending extra PATCHes would fail.
def is_iap_location_read(call):
    """A read whose only purpose is answering "where is the purchase?".

    The two implementations answer it differently ON PURPOSE, so this question is lifted out of
    the strict call-log diff on BOTH sides — v1.30's state read and the module's containment
    reads alike — and asserted instead by `test_containment_probe`, which checks the behaviour
    rather than the byte sequence. Everything else, including every WRITE and the staging POST
    that actually puts the purchase in a submission, is still compared byte for byte.

    Narrow by construction: `open_submission()` also GETs `reviewSubmissions?`, and both
    implementations make that call, so it must NOT be swallowed here. It is distinguished by
    carrying `filter[platform]=`, which the containment sweep deliberately omits.
    """
    method, endpoint = call[0], call[1]
    if method != "GET":
        return False
    if endpoint.startswith("/v2/inAppPurchases/") and "fields[inAppPurchases]=state" in endpoint:
        return True
    if "reviewSubmissions?" in endpoint and "filter[platform]=" not in endpoint:
        return True
    if "/items?" in endpoint and "include=inAppPurchaseVersion" in endpoint:
        return True
    return False


def diff_logs(old, new):
    """The first place two call logs disagree, rendered so it can be read."""
    if old == new:
        return None
    for i, (a, b) in enumerate(zip(old, new)):
        if a != b:
            return (f"call #{i} differs\n"
                    f"      v1.30 : {a[0]} {a[1]}\n              body={a[2]}\n"
                    f"      module: {b[0]} {b[1]}\n              body={b[2]}")
    shorter, longer = ("v1.30", "module") if len(old) < len(new) else ("module", "v1.30")
    extra = (new if len(new) > len(old) else old)[min(len(old), len(new)):]
    return (f"{shorter} stopped after {min(len(old), len(new))} calls; {longer} made "
            f"{len(extra)} more, starting with {extra[0][0]} {extra[0][1]}")


# The branches this comparison is required to walk. `expect_failures` says whether v1.30 itself
# records a problem in that scenario — a scenario where both sides are silently broken would
# otherwise compare clean.
SCENARIOS = [
    ("metadata, versions created fresh",
     dict(phase="do_metadata"), False),
    ("metadata, versions exist / already corrected / review detail present",
     dict(phase="do_metadata", versions_exist=True, descriptions="corrected",
          review_detail=True), False),
    ("metadata, the description sentence is no longer there",
     dict(phase="do_metadata", versions_exist=True, descriptions="rewritten"), True),
    ("metadata, a locale on the App Store this release writes no copy for",
     dict(phase="do_metadata", versions_exist=True, extra_locales=("fr-FR",)), True),
    ("submit, clean",
     dict(phase="do_submit", versions_exist=True), False),
    ("submit, the purchase cannot be staged",
     dict(phase="do_submit", versions_exist=True, iap_stageable=False), True),
    ("submit, macOS already WAITING_FOR_REVIEW",
     dict(phase="do_submit", versions_exist=True,
          version_states={"MAC_OS": "WAITING_FOR_REVIEW"}), False),
    ("submit, an open submission left by a failed run",
     dict(phase="do_submit", versions_exist=True, open_submissions=True), False),
    ("submit, the purchase is already in review",
     dict(phase="do_submit", versions_exist=True, iap_state="WAITING_FOR_REVIEW"), False),
    ("dry run, against this version",
     dict(phase="do_dry_run", versions_exist=True), False),
    ("dry run, before the version exists",
     dict(phase="do_dry_run"), False),
]


# The ONE ledger message that differs between the two, and it differs on purpose: v1.30's
# script names v1.30 in its own text, and a module shared by every release cannot. It is
# enumerated here rather than normalised away with a regex, because a regex that tolerates "any
# version-shaped difference" would also tolerate the next difference, which nobody has read.
LEDGER_EQUIVALENTS = {
    "the in-app purchase is in no review submission, so NOTHING was submitted — v1.30's "
    "release notes describe a purchase that would not exist":
    "the in-app purchase is in no review submission, so NOTHING was submitted — the "
    "release notes describe a purchase that would not exist",
}


def same_ledger(old, new):
    """True when the two ledgers agree, up to the one enumerated wording difference above."""
    return [LEDGER_EQUIVALENTS.get(m, m) for m in old] == new


def test_differential(module, problems):
    """Both implementations, same fake, same config: the same calls, ledger and end state."""
    for name, sc, expect_failures in SCENARIOS:
        old_log, old_fail, old_state, _ = drive_old(module, sc)
        new_log, new_fail, new_state, _ = drive_new(module, sc)
        trimmed_old = [c for c in old_log if not is_iap_location_read(c)]
        trimmed_new = [c for c in new_log if not is_iap_location_read(c)]
        if [c for c in new_log if is_iap_location_read(c) and c[0] != "GET"]:
            problems.append(f"{name}: an IAP-location call is not a read — the exemption above "
                            "only covers reads, and a write hid inside it")
        difference = diff_logs(trimmed_old, trimmed_new)
        verdict = "IDENTICAL" if difference is None else "DIFFERENT"
        print(f"  {name:60s} {len(old_log):3d} calls  {len(old_fail)} fail  {verdict}")
        if not old_log:
            problems.append(f"{name}: the differential compared EMPTY call logs — the harness "
                            "never reached the API, so 'identical' means nothing")
        if difference:
            problems.append(f"{name}: the port does not send what v1.30 sent —\n    {difference}")
        if not same_ledger(old_fail, new_fail):
            problems.append(f"{name}: ledgers differ —\n    v1.30 : {old_fail}\n"
                            f"    module: {new_fail}")
        if old_state != new_state:
            problems.append(f"{name}: the App Store ends in a different state —\n"
                            f"    v1.30 : {old_state}\n    module: {new_state}")
        if bool(old_fail) != expect_failures:
            problems.append(f"{name}: expected v1.30 to record "
                            f"{'a failure' if expect_failures else 'no failure'} here and it "
                            f"recorded {old_fail!r} — the scenario is not exercising the branch "
                            "it was written for")


def test_control_calls(module, problems):
    """Control for the CALL-LOG comparison: perturb the port, require it to go red.

    The perturbation is the byte-exact read-back after a PATCH — the habit that caught the
    star-glyph rejection before review — so this doubles as proof that the read-back is in the
    call sequence rather than merely in the source.
    """
    original = Release.patch_localization

    def without_readback(self, lid, locale, field, text):
        self.asc("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
            "type": "appStoreVersionLocalizations", "id": lid, "attributes": {field: text}}})

    sc = dict(phase="do_metadata")
    Release.patch_localization = without_readback
    try:
        old_log, _, _, _ = drive_old(module, sc)
        new_log, _, _, _ = drive_new(module, sc)
    finally:
        Release.patch_localization = original
    fired = diff_logs(old_log, new_log) is not None
    print(f"  call-log control  : port with the read-back removed -> "
          f"{'DIFFERENT (good)' if fired else 'IDENTICAL (bad)'}")
    if not fired:
        problems.append("the call-log comparison did not notice a port with the byte-exact "
                        "read-back removed, so 'identical' above is a fact about the harness")


def test_control_ledger(module, problems):
    """Control for the LEDGER comparison, on a scenario where v1.30 records a failure."""
    original = Release.fail
    Release.fail = lambda self, message: None
    sc = dict(phase="do_submit", versions_exist=True, iap_stageable=False)
    try:
        _, old_fail, _, _ = drive_old(module, sc)
        _, new_fail, _, _ = drive_new(module, sc)
    finally:
        Release.fail = original
    fired = not same_ledger(old_fail, new_fail)
    print(f"  ledger control    : port that swallows failures -> "
          f"{'DIFFERENT (good)' if fired else 'IDENTICAL (bad)'}")
    if not old_fail:
        problems.append("the ledger control ran on a scenario where v1.30 records nothing, so "
                        "it could not have detected a swallowed failure")
    if not fired:
        problems.append("the ledger comparison did not notice a port that swallows every "
                        "failure")


def submits_in(log):
    return [c for c in log
            if c[0] == "PATCH" and c[1].startswith("/v1/reviewSubmissions/")
            and (c[2] or {}).get("data", {}).get("attributes", {}).get("submitted")]


def test_submit_gate(module, problems):
    """A declared purchase that cannot be staged stops every submission — and the control fires."""
    log, failures, state, out = drive_new(module, dict(phase="do_submit", versions_exist=True))
    n = len(submits_in(log))
    print(f"  gate control  : submitted={n} iap={state['iap']}")
    if n != 2:
        problems.append(f"gate control submitted {n} times, not 2 — the harness never reaches "
                        f"the submit, so the mutation below would prove nothing\n{out}")
    if failures:
        problems.append(f"gate control recorded failures on a clean run: {failures}")

    log, failures, state, out = drive_new(
        module, dict(phase="do_submit", versions_exist=True, iap_stageable=False))
    n = len(submits_in(log))
    print(f"  gate mutation : submitted={n} iap={state['iap']}")
    if n != 0:
        problems.append(f"THE GATE DID NOT HOLD: {n} review submissions were sent with the "
                        f"in-app purchase in none of them\n{out}")
    if any(v["state"] != "PREPARE_FOR_SUBMISSION" for v in state["versions"].values()):
        problems.append(f"a version advanced anyway: {state['versions']}")
    if not failures:
        problems.append("the gate stopped the submit but recorded no failure — a run that did "
                        "nothing would exit 0, which is the defect the ledger exists for")


def test_no_iap_release(module, problems):
    """`iap=None` submits both platforms and touches no purchase endpoint.

    The second clause is the one worth having. A gate that treats "no purchase declared" and
    "the purchase is accounted for" as the same state would pass the first clause and be exactly
    the defect this repo has shipped twenty-three times.
    """
    release = release_from(module, iap=None)
    log, failures, state, out = drive_new(
        module, dict(phase="do_submit", versions_exist=True, iap_stageable=False),
        release=release)
    n = len(submits_in(log))
    touched = [c for c in log if "inAppPurchase" in c[1] or "inAppPurchase" in str(c[2])]
    print(f"  no-iap release: submitted={n} iap-endpoints-touched={len(touched)}")
    if n != 2:
        problems.append(f"a release with no purchase submitted {n} platforms, not 2\n{out}")
    if failures:
        problems.append(f"a release with no purchase recorded failures: {failures}")
    if touched:
        problems.append(f"a release with iap=None still called the purchase API: "
                        f"{[c[1] for c in touched]}")
    if state["iap"] != "READY_TO_SUBMIT":
        problems.append("a release with no purchase moved the purchase's state")


def test_preflight(module, problems):
    """Every contract that used to live in a comment, one violating config each.

    The control is the real v1.30 configuration, which must pass — without it, a preflight that
    rejected everything would look like a working one.
    """
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            release_from(module).preflight()
        print("  control: the real v1.30 config passes")
    except SystemExit as exc:
        problems.append(f"preflight REJECTS the configuration that actually shipped: {exc}")

    cases = [
        ("the star glyph", dict(whats_new={**module.WHATS_NEW, "en-US": "★ a starred line"}),
         "★"),
        ("What's New over 4000", dict(whats_new={**module.WHATS_NEW, "en-US": "x" * 4001}),
         "over the 4000"),
        ("empty What's New", dict(whats_new={**module.WHATS_NEW, "en-US": "   "}), "is empty"),
        ("review notes over 4000", dict(review_notes="x" * 4001), "over the 4000"),
        ("empty review notes", dict(review_notes="  "), "review notes are empty"),
        ("an edit whose OLD is inside its NEW",
         dict(description_edits={"en-US": ("• Works offline.", "• Works offline. And more.")}),
         "substring"),
        ("an edit that replaces a sentence with itself",
         dict(description_edits={"en-US": ("same", "same")}), "with itself"),
        ("an edit for a locale with no What's New",
         dict(description_edits={"fr-FR": ("a", "b")}), "no What's New"),
        ("two targets on one platform",
         dict(targets=[{"name": "macOS", "platform": "MAC_OS", "build_num": "54"},
                       {"name": "iOS", "platform": "MAC_OS", "build_num": "55"}]),
         "share platform"),
        ("a build number that is not an integer",
         dict(targets=[{"name": "macOS", "platform": "MAC_OS", "build_num": "54a"}]),
         "not a plain integer"),
        ("a purchase declared without a product id",
         dict(iap={"id": "6806755720", "product_id": ""}), "product_id"),
    ]
    for name, override, expected in cases:
        release = release_from(module, **override)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                release.preflight()
        except SystemExit as exc:
            if expected not in str(exc):
                problems.append(f"preflight rejected {name!r} for the wrong reason: {exc}")
            else:
                print(f"  rejects: {name}")
            continue
        problems.append(f"preflight ACCEPTED {name!r} — the contract is still only a comment")


def test_containment_probe(module, problems):
    """The property the differential deliberately stopped comparing, asserted directly.

    v1.30 answered "is the purchase already carried?" by reading its state string, and
    `IAP_ALREADY_IN` contains `IN_REVIEW`. Apple's cancel is asynchronous, so between a
    withdrawal and the state settling there is a window where the purchase reads `IN_REVIEW`
    while belonging to nothing. The old expression called that "carried", skipped staging,
    satisfied the phase-3 gate, and submitted a version whose notes advertise a purchase in no
    review — printing OK and exiting 0.

    Both directions are asserted, because a probe that always refuses would pass the first half
    and break every legitimate resubmission.
    """
    # 1. IN_REVIEW but held by nothing — the post-cancel window. Must REFUSE.
    sc = dict(phase="do_submit", versions_exist=True, iap_state="IN_REVIEW")
    state = fresh_state(module, sc)
    state["submissions"] = {}            # the state string lies; nothing actually holds it
    state["preexisting_submissions"] = {}
    log = []
    release = release_from(module)
    release.asc = make_fake(state, module, sc, log)
    with contextlib.redirect_stdout(io.StringIO()):
        release.do_submit()
    refused = any("NO live review submission" in m for m in release.failures)
    print(f"  post-cancel window (IN_REVIEW, held by nothing) -> "
          f"{'REFUSED' if refused else 'SUBMITTED ANYWAY'}")
    if not refused:
        problems.append("containment: a purchase reading IN_REVIEW while held by NO submission "
                        "was treated as carried — this is the defect the probe exists to stop, "
                        "and it would ship a version advertising a purchase nobody is reviewing")
    if state["versions"]["MAC_OS"]["state"] == "WAITING_FOR_REVIEW":
        problems.append("containment: the version was submitted despite the refusal")

    # 2. IN_REVIEW and genuinely held. Must PROCEED, or every real resubmission breaks.
    sc2 = dict(phase="do_submit", versions_exist=True, iap_state="IN_REVIEW")
    state2 = fresh_state(module, sc2)    # fresh_state seeds the carrying submission
    log2 = []
    release2 = release_from(module)
    release2.asc = make_fake(state2, module, sc2, log2)
    with contextlib.redirect_stdout(io.StringIO()):
        release2.do_submit()
    blocked = any("NO live review submission" in m for m in release2.failures)
    print(f"  genuinely carried (IN_REVIEW, held) -> "
          f"{'WRONGLY REFUSED' if blocked else 'proceeded'}")
    if blocked:
        problems.append("containment: a purchase that IS in a live submission was refused — the "
                        "probe cannot tell the two worlds apart, so it is not measuring "
                        "containment, only pessimism")


def main():
    problems = []
    module = load_v130()
    print(f"loaded submit_1_30.py: version {module.VERSION}, {len(module.WHATS_NEW)} locales, "
          f"iap {module.IAP_PRODUCT_ID}\n")
    print("DIFFERENTIAL — v1.30's script and the extracted module, same fake, same config")
    test_differential(module, problems)
    print("\nCONTROLS — the comparison must be able to fail")
    test_control_calls(module, problems)
    test_control_ledger(module, problems)
    print("\nTHE CONTAINMENT PROBE — the question the differential stops comparing")
    test_containment_probe(module, problems)
    print("\nTHE SUBMIT GATE")
    test_submit_gate(module, problems)
    test_no_iap_release(module, problems)
    print("\nPREFLIGHT — contracts that used to be comments")
    test_preflight(module, problems)

    if problems:
        print(f"\n{len(problems)} FAILURE(S):")
        for p in problems:
            print(f"\nFAIL  {p}")
        return 1
    print("\nthe port sends what v1.30 sent across 11 scenarios, both comparisons can fail, the "
          "gate holds both ways, and every preflight contract fires.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
