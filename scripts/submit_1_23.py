#!/usr/bin/env python3
"""Create the 1.22 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.22 is mostly repair. Its reason to exist is a counting bug: the filter that stops a
withdrawn vocabulary entry counting toward review work had been wired into one of the
five places that count due cards, so the badge, the widget, the reminders and the Ride
Log had been over-counting for anyone who had studied one of the two entries withdrawn
in v1.18 — permanently, since a card whose word is gone can never be reviewed away.

It also gives 64 cards a line saying which reading of their spelling is the everyday
one, and lets dictation follow a saved list or the due stack the way Sentence mode
learned to in v1.21.

Two phases:
  python3 scripts/submit_1_22.py --metadata   # create versions + What's New + review detail
  python3 scripts/submit_1_22.py --submit     # attach VALID builds (mac 42 / iOS 43) + submit

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW. ASC refuses
to create 1.23 until 1.22 reaches READY_FOR_SALE. Uploading builds is fine at any time;
this is the step that fails.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.23"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "44"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "45"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 After a sentence or dictation ride, the results screen now names the words "
        "you were stopped on, with their readings. It could already tell you how many "
        "mistakes you made, and when a mistake followed a typing rule it explained the rule "
        "-- but when you simply did not know a word, or did not catch it, it never said "
        "which word that was. In dictation, which word is the whole answer.\n"
        "\u2022 Fixed a riding streak that disagreed with the dots beside it. A ride that "
        "crossed midnight counted for both days in the number but lit only one dot, so a "
        "chain you had not broken showed a gap in the middle.\n"
        "\u2022 Weak-words practice and the due verb-form review were handing back short "
        "sessions. Words withdrawn from the dictionary took up places in the run and were "
        "then dropped, so a session that offered fifteen could give you twelve.\n"
        "\u2022 Passage practice no longer counts time while the app is in the background. "
        "Putting the app down mid-passage used to be written into the Ride Log as riding, "
        "which stretched how long the ride looked and slowed down its speed."
    ),
    "zh-Hans": (
        "\u2022 句子和听写骑行结束后,结算页现在会点名你被卡住的那几个词,并标出读音。"
        "此前它能告诉你错了几次,也能在错误符合某条打字规则时讲清那条规则 \u2014\u2014 "
        "但当你只是不认识、或者没听出来时,它从不说是哪个词。而在听写里,是哪个词就是全部答案。\n"
        "\u2022 修正了连续骑行天数与旁边圆点对不上的问题。跨过午夜的一程在数字里算两天,"
        "却只点亮一颗圆点,于是你并没有中断的连续记录,中间却显示出一个缺口。\n"
        "\u2022 弱项词练习和到期动词变形复习此前会少给几题。已从词库撤下的词会占掉名额、"
        "随后又被剔除,于是一场标着十五题的练习实际只有十二题。\n"
        "\u2022 长句练习不再把 App 退到后台的时间算进骑行。此前练到一半放下 App,"
        "那段时间会被记进骑行日志,让这一程显得更长、速度更慢。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.22 is a maintenance release. It fixes a spaced-repetition counting bug (a card whose "
    "dictionary entry had been withdrawn kept counting toward the app badge, the widget and the local "
    "reminder, and could never be cleared), adds an explanatory line to 87 vocabulary cards, and extends "
    "the Dictation mode added in 1.21 so it can draw its sentences from a saved word list or from the "
    "words due for review.\n\n"
    "Dictation is unchanged in how it works: the app speaks an example sentence with the system Japanese "
    "text-to-speech voice (AVSpeechSynthesizer, on-device ja-JP) and the learner types what they heard. No "
    "network calls, no microphone, no speech recognition, no data collection. If no Japanese voice is "
    "installed the mode is shown as unavailable with an explanation pointing at Settings > Accessibility > "
    "Spoken Content. Everything remains local and offline; iCloud sync is the user's own private database "
    "and the app is fully usable without it."
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
    print(f"  {name}: version state is {state} — nothing to submit, skipping")
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
        print("  create version ERR:", r["errors"][0].get("detail")); sys.exit(1)
    vid = r["data"]["id"]
    print(f"  created version {VERSION}: {vid}")
    return vid


def set_whats_new(vid):
    locs = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"
                      f"?fields[appStoreVersionLocalizations]=locale&limit=50").get("data", [])
    by_locale = {l["attributes"]["locale"]: l["id"] for l in locs}
    for locale, text in WHATS_NEW.items():
        lid = by_locale.get(locale)
        if not lid:
            print(f"    !! no localization for {locale} (have {list(by_locale)}) — skipping"); continue
        r = asc("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
            "type": "appStoreVersionLocalizations", "id": lid, "attributes": {"whatsNew": text}}})
        print(f"    whatsNew {locale}:", "OK" if not r.get("errors") else r["errors"][0].get("detail"))


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
    print("  review detail:", "OK" if not r.get("errors") else r["errors"][0].get("detail"))


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
                print("  create submission ERR:", sub["errors"][0].get("detail")); continue
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
                print("  create submission ERR:", sub["errors"][0].get("detail")); continue
            sid = sub["data"]["id"]
            it = add_item(sid, vid)
        print("  add item:", "OK" if not it.get("errors") else it["errors"][0].get("detail"))
        if it.get("errors"):
            print("  no item attached — not marking submitted"); continue
        fin = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions",
                  "id": sid, "attributes": {"submitted": True}}})
        print("  SUBMIT:", "OK" if not fin.get("errors") else fin["errors"][0].get("detail"))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--metadata":
        do_metadata()
    elif mode == "--submit":
        do_submit()
    else:
        print(__doc__); sys.exit(2)
