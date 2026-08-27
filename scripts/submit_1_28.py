#!/usr/bin/env python3
"""Create the 1.27 App Store versions, set What's New + review notes, then attach the
processed builds and submit both platforms for review.

v1.27 is the first product-stage release: it ships one feature, the App Store rating request,
and touches no vocabulary file. The paragraphs below are kept from the v1.26 template because the
defects they record are properties of the TEMPLATE, not of that release.

The v1.26 notes, retained for the two template fixes they explain: it turned v1.25's closing
sentence — a gate validated by what it CATCHES has not been
validated — on v1.25's own gate. The reading gate answered its question for 5,864 of 6,738
sentences and could not see the other 874, because a verb in a sentence is conjugated and its
dictionary form never appears. Two stem-aware walks now reach them, five sentences were reading
their headword as a different word, and — the part that matters — the population NO reading gate
inspects is computed, printed and ratcheted at 112 rather than assumed to be empty.

TWO DEFECTS OF THE 1.25 TEMPLATE ARE FIXED HERE, both of the same family:

  * `submittable()` turned an unrecognised version state into a friendly skip, and main exited
    0 regardless. A run that submitted NOTHING looked exactly like a clean run. Every skip and
    every error now records a failure and the process exits non-zero.
  * Nothing read the submissions back. Both platforms are re-queried after submitting, and a
    state that is not WAITING_FOR_REVIEW is a failure.

Every number in the copy below is derived from the corpus by `release_numbers.py` at runtime.
v1.25's What's New told users "Fifty more sentences are available in Dictation"; the measured
figure was 42, because eight sentences went back into exclusion after the copy was written.

Two phases:
  python3 scripts/submit_1_28.py --metadata   # create versions + What's New + review detail
  python3 scripts/submit_1_28.py --submit     # attach VALID builds (mac 51 / iOS 52) + submit

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW. Uploading builds is
fine at any time; this is the step that blocks.
"""
import json, subprocess, sys, os
from pathlib import Path

APP = "6777469778"
VERSION = "1.28"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "51"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "52"},
]

# Measured, never typed. See release_numbers.py for why this is a module rather than a habit.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_numbers import numbers as _release_numbers   # noqa: E402

# v1.27 quotes NO corpus figure, because it changes no corpus — see release_numbers.CORPUS_MANIFEST.
# The call is kept anyway: it raises if a constant the copy has ever quoted was renamed away, and a
# free integrity check at submit time is worth more than a tidy import list.
N = _release_numbers()

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 After a ride that went well, Nihongo Ride may now ask whether you would like to "
        "rate it on the App Store. It waits until you have come back on a second day and finished "
        "a few rides, it does not ask after a rough ride, and it will not ask again for months.\n"
        "\u2022 That is still nothing to do with the network. The app keeps its own count of when "
        "it asked and when it decided not to, on your device, and that count never leaves it."
    ),
    "zh-Hans": (
        "\u2022 骑行结束且成绩不错时,Nihongo Ride 现在可能会问你是否愿意在 App Store 上评分。"
        "它会等到你第二天再回来、并且已经完成过几次骑行才问;成绩不理想时不问;问过之后几个月内"
        "不会再问。\n"
        "\u2022 这依然和联网无关。App 会在你的设备上自己记录何时问过、何时决定不问,"
        "这些记录永远不会离开设备。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.27 adds a single user-facing change: the app may request an App Store rating using SwiftUI's "
    "requestReview environment action, shown only after a completed practice ride, and only for someone who "
    "has returned on a second day and finished several rides. It is not shown after a poor result, not on "
    "launch, and not more than once in several months.\n\n"
    "Nothing about data handling has changed and the App Privacy declaration is unchanged. The app records, "
    "in local storage on the device, the dates on which it made a rating request and a tally of the reasons "
    "it decided not to make one. That record is never transmitted, is not associated with any identifier, and "
    "is used only so the app can space its own requests correctly. There is no analytics SDK, no network call, "
    "no account and no advertising in this app.\n\n"
    "Everything else runs on-device as before: no microphone, no speech recognition. Dictation uses the system "
    "Japanese text-to-speech voice (AVSpeechSynthesizer, on-device ja-JP) and is shown as unavailable, with an "
    "explanation, when no Japanese voice is installed. iCloud sync is the user's own private database and the "
    "app is fully usable without it."
)
CONTACT = {"contactFirstName": "Yuhe", "contactLastName": "Ye",
           "contactPhone": "+81 80-3526-7088", "contactEmail": "yyyyy.yeyuhe@gmail.com"}


def asc(method, ep, body=None, allow_empty=False):
    """One ASC call. An empty or non-JSON response is a FAILURE, not an empty success.

    Every submit script from 1.10 to 1.21 returned `{}` here when the helper exited
    non-zero — a missing key, a locked keychain, a network blip. `{}` has no "errors"
    key, and every call site reads a missing "errors" key as OK, so a run in which
    nothing at all reached Apple printed OK at every step. That is the same failure this
    project has a memory file about: a clean number from an instrument that was not
    working. Raising here means a broken run stops at the first call instead of
    congratulating itself through twelve.
    """
    env = dict(os.environ)
    if body is not None:
        json.dump(body, open("/tmp/asc_body.json", "w"), ensure_ascii=False)
        env["ASC_BODY_FILE"] = "/tmp/asc_body.json"
    proc = subprocess.run(["scripts/asc_api.sh", method, ep],
                          capture_output=True, text=True, env=env)
    out = proc.stdout
    if proc.returncode != 0:
        raise SystemExit(
            f"ASC call FAILED: {method} {ep}\n"
            f"  exit={proc.returncode}\n"
            f"  stdout={out.strip()[:400]!r}\n"
            f"  stderr={proc.stderr.strip()[:400]!r}\n"
            "Nothing was assumed to have succeeded. Fix the call and re-run; the script "
            "is idempotent up to this point.")
    if not out.strip():
        # Exactly ONE call in either phase answers with no body: PATCH on the version's
        # build relationship, which is 204 No Content on success. Every other endpoint here
        # returns 200 or 201 with a payload, so an empty body from any of them is a failure
        # that must not be read as an empty success — which is the bug this helper was
        # rewritten to stop. So emptiness is permitted per call site, never globally.
        #
        # (The first attempt at this rewrite raised on every empty body. It would have
        # aborted the attach — the one moment something HAD reached Apple — while printing
        # "nothing was assumed to have succeeded".)
        if allow_empty:
            return {}
        raise SystemExit(
            f"ASC returned an EMPTY body for {method} {ep}, which this call does not "
            "expect. Treating that as success is how a failed run reports OK twelve times.")
    try:
        return json.loads(out)
    except Exception:
        raise SystemExit(f"ASC returned non-JSON for {method} {ep}:\n{out[:400]}")


# Every skip and every error lands here, and a non-empty ledger is a non-zero exit.
#
# The 1.25 template's `submittable()` turned an unrecognised version state into a friendly
# message and returned False; the caller `continue`d and main returned None, so the process
# exited 0. A run that submitted NOTHING was indistinguishable from a clean run — which is this
# project's signature defect (a null result from an instrument nobody checked was working)
# sitting on the last step before Apple.
FAILURES = []


def fail(message):
    print(f"  FAIL: {message}")
    FAILURES.append(message)


SUBMITTABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
               "METADATA_REJECTED", "INVALID_BINARY"}


def submittable(vid, name):
    """True only if this version can still accept a build and a submission.

    Fix (1) for the orphan: a version that is READY_FOR_SALE, IN_REVIEW or WAITING_FOR_REVIEW
    must not be touched. The v1.15 run learned this by creating an uncancellable, undeletable
    empty submission against an already-live macOS version.
    """
    d = asc("GET", f"/v1/appStoreVersions/{vid}")
    state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
    if state in SUBMITTABLE:
        return True
    # READY_FOR_SALE / IN_REVIEW / WAITING_FOR_REVIEW are the states where doing nothing is
    # CORRECT — v1.15 created an uncancellable empty submission against a live version by not
    # checking. Those are reported and not counted as failures. Anything else is a state this
    # script does not understand, and continuing past it silently is how a run submits nothing
    # and exits 0.
    if state in {"READY_FOR_SALE", "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE"}:
        print(f"  {name}: version state is {state} — already submitted or live, nothing to do")
        return False
    fail(f"{name}: unrecognised version state {state!r} — refusing to guess")
    return False


def open_submission(platform):
    """An existing un-submitted reviewSubmission for this platform, if any.

    Fix (2): reuse a container rather than POSTing a second one. Orphans accumulate precisely
    because every failed run leaves one behind that no API call can remove.
    """
    d = asc("GET", f"/v1/apps/{APP}/reviewSubmissions?filter[platform]={platform}"
                   f"&filter[state]=READY_FOR_REVIEW&limit=10")
    for s in (d.get("data") or []):
        return s["id"]
    return None


def add_item(sid, vid):
    return asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
               "relationships": {
                   "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                   "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})


def find_version(platform):
    d = asc("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]={platform}"
                   f"&filter[versionString]={VERSION}&limit=1")
    data = d.get("data") or []
    return data[0]["id"] if data else None


def ensure_version(platform):
    vid = find_version(platform)
    if vid:
        print(f"  version {VERSION} exists: {vid}")
        return vid
    r = asc("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": platform, "versionString": VERSION},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    if r.get("errors"):
        # Recorded, not exited: aborting mid-loop skips the OTHER platform and, in --submit,
        # skips the read-back entirely — so a platform that HAD submitted would go unverified.
        fail(f"create version {VERSION}: {r['errors'][0].get('detail')}")
        return None
    vid = r["data"]["id"]
    print(f"  created version {VERSION}: {vid}")
    return vid


def set_whats_new(vid):
    locs = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"
                      f"?fields[appStoreVersionLocalizations]=locale&limit=50").get("data", [])
    by_locale = {l["attributes"]["locale"]: l["id"] for l in locs}
    # The loop below asks "does every locale I WROTE have a destination". The pre-submission
    # review caught that it cannot see the other direction: a locale configured on the App
    # Store that this script has no copy for is never visited, so it silently ships the
    # PREVIOUS version's What's New — claiming the last release's changes as this one's.
    # Latent today (en-US and zh-Hans are the only two) and reachable the moment v1.28 adds
    # ja / zh-Hant, which is exactly when nobody would be looking for it.
    unwritten = sorted(set(by_locale) - set(WHATS_NEW))
    if unwritten:
        fail(f"App Store has locales this script writes no What's New for: {unwritten} "
             f"— they would keep the previous version's copy")
    for locale, text in WHATS_NEW.items():
        lid = by_locale.get(locale)
        if not lid:
            # NOT a skip. A locale that is configured on the App Store and missing here means
            # the release ships that language with the PREVIOUS version's What's New, and the
            # previous template printed "skipping" and exited 0.
            fail(f"no localization for {locale} (have {list(by_locale)}) — What's New unset"); continue
        r = asc("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
            "type": "appStoreVersionLocalizations", "id": lid, "attributes": {"whatsNew": text}}})
        if r.get("errors"):
            fail(f"whatsNew {locale}: {r['errors'][0].get('detail')}"); continue
        # Read it BACK. The response to a PATCH is not evidence that the text is what we sent —
        # ASC silently truncates and normalises, and the star-glyph rejection lands here.
        check = asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                           f"?fields[appStoreVersionLocalizations]=whatsNew")
        stored = (check.get("data") or {}).get("attributes", {}).get("whatsNew")
        if stored != text:
            fail(f"whatsNew {locale}: stored text differs from what was sent "
                 f"({len(stored or '')} chars vs {len(text)})")
        else:
            print(f"    whatsNew {locale}: OK ({len(text)} chars, read back identical)")


def set_review_detail(vid):
    cur = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    attrs = dict(CONTACT); attrs["notes"] = REVIEW_NOTES; attrs["demoAccountRequired"] = False
    existing = cur.get("data")
    if existing:
        rid = existing["id"]
        r = asc("PATCH", f"/v1/appStoreReviewDetails/{rid}",
                {"data": {"type": "appStoreReviewDetails", "id": rid, "attributes": attrs}})
    else:
        r = asc("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if r.get("errors"):
        fail(f"review detail: {r['errors'][0].get('detail')}")
        return
    # Read back, for the same reason: App Review reads these notes, and a version that reaches
    # them with the PREVIOUS release's notes describes work that is not in this build.
    back = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    stored = ((back.get("data") or {}).get("attributes") or {}).get("notes")
    if stored != REVIEW_NOTES:
        fail(f"review detail: stored notes differ from what was sent "
             f"({len(stored or '')} chars vs {len(REVIEW_NOTES)})")
    else:
        print(f"  review detail: OK ({len(REVIEW_NOTES)} chars, read back identical)")


def find_build(platform, num):
    """Match by build number AND platform — build numbers are per-platform, so mac 14
    and iOS 14 can coexist; resolve each candidate's platform via its preReleaseVersion."""
    d = asc("GET", f"/v1/builds?filter[app]={APP}&limit=50&sort=-uploadedDate"
                   f"&fields[builds]=version,processingState,usesNonExemptEncryption")
    for b in d.get("data", []):
        if b["attributes"]["version"] != num:
            continue
        bid = b["id"]
        pv = asc("GET", f"/v1/builds/{bid}/preReleaseVersion?fields[preReleaseVersions]=platform")
        plat = (pv.get("data") or {}).get("attributes", {}).get("platform")
        if plat == platform:
            return bid, b["attributes"]
    return None, None


def do_metadata():
    for t in TARGETS:
        print(f"\n===== {t['name']} metadata =====")
        vid = ensure_version(t["platform"])
        set_whats_new(vid)
        set_review_detail(vid)


def do_submit():
    submitted = []
    for t in TARGETS:
        print(f"\n===== {t['name']} submit (build {t['build_num']}) =====")
        vid = find_version(t["platform"])
        if not vid:
            print(f"  !! no {VERSION} version — run --metadata first"); sys.exit(1)
        if not submittable(vid, t["name"]):
            continue
        bid, battr = find_build(t["platform"], t["build_num"])
        if not bid:
            print(f"  !! {t['name']} build {t['build_num']} not found"); sys.exit(1)
        if battr.get("processingState") != "VALID":
            print(f"  !! build {t['build_num']} state={battr.get('processingState')} (not VALID)"); sys.exit(1)
        print(f"  build {bid} VALID")
        if battr.get("usesNonExemptEncryption") is None:
            asc("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                "attributes": {"usesNonExemptEncryption": False}}})
        # The only 204-answering call in the script — see asc()'s allow_empty.
        r = asc("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": bid}}, allow_empty=True)
        print("  attach build:", "OK" if not r.get("errors") else r["errors"])
        if r.get("errors"):
            # The attach is the real gate. If it failed, do NOT create a submission container —
            # that is exactly how the v1.15 orphan came to exist.
            print("  attach failed, not creating a submission"); continue
        sid = open_submission(t["platform"])
        reused = sid is not None
        if sid:
            print(f"  reusing open submission {sid}")
        else:
            sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                      "attributes": {"platform": t["platform"]},
                      "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
            if sub.get("errors"):
                fail(f"{t['name']}: create submission — {sub['errors'][0].get('detail')}"); continue
            sid = sub["data"]["id"]
        it = add_item(sid, vid)
        if it.get("errors") and reused:
            # The reused container turned out not to accept items after all — do not lose the
            # release over an orphan from the last one. Fall back to a fresh submission.
            print("  reuse rejected:", it["errors"][0].get("detail"), "— creating a new one")
            sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                      "attributes": {"platform": t["platform"]},
                      "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
            if sub.get("errors"):
                fail(f"{t['name']}: create submission — {sub['errors'][0].get('detail')}"); continue
            sid = sub["data"]["id"]
            it = add_item(sid, vid)
        print("  add item:", "OK" if not it.get("errors") else it["errors"][0].get("detail"))
        if it.get("errors"):
            fail(f"{t['name']}: no item attached — {it['errors'][0].get('detail')}"); continue
        fin = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions",
                  "id": sid, "attributes": {"submitted": True}}})
        if fin.get("errors"):
            fail(f"{t['name']}: submit — {fin['errors'][0].get('detail')}"); continue
        print("  SUBMIT: OK")
        submitted.append(t)


    # --- read the submissions BACK -----------------------------------------------------
    #
    # Nothing in the 1.25 template verified that anything had actually landed. Every step above
    # reports on the response to its own call; this asks Apple, afterwards, what state the
    # version is in. A submission that was accepted and then rejected asynchronously, or one
    # that silently did nothing, is only visible here.
    print("\n===== reading back =====")
    for t in TARGETS:
        vid = find_version(t["platform"])
        if not vid:
            fail(f"{t['name']}: version {VERSION} is gone after submitting"); continue
        d = asc("GET", f"/v1/appStoreVersions/{vid}")
        state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
        expected = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE"}
        mark = "OK" if state in expected else "NOT SUBMITTED"
        print(f"  {t['name']}: {state} [{mark}]")
        if state not in expected:
            fail(f"{t['name']}: after submitting, state is {state!r}, not a submitted state")

    if not submitted and not FAILURES:
        # Both platforms were already submitted or live. That is a legitimate no-op, but it must
        # be SAID, because "submitted nothing" and "submitted everything" printed the same thing
        # in the previous template.
        print("\n  nothing needed submitting — both platforms were already in review or live")


def report():
    """Non-zero if anything at all went wrong. The whole point of the ledger."""
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILURE(S):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nclean.")
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--metadata":
        do_metadata()
    elif mode == "--submit":
        do_submit()
    elif mode == "--dry-run":
        # Prints the derived copy and the configuration WITHOUT touching Apple, so the numbers
        # and the build targets can be reviewed before anything is created.
        print(f"VERSION {VERSION}")
        for t in TARGETS:
            print(f"  {t['name']:6s} platform={t['platform']:6s} build={t['build_num']}")
        print("\nderived numbers:")
        for k, v in N.items():
            print(f"  {k:24s} {v}")
        for locale, text in WHATS_NEW.items():
            print(f"\n--- What's New [{locale}] ({len(text)} chars) ---\n{text}")
        print(f"\n--- Review notes ({len(REVIEW_NOTES)} chars) ---\n{REVIEW_NOTES}")
        sys.exit(0)
    else:
        print(__doc__); sys.exit(2)
    sys.exit(report())
