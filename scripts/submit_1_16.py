#!/usr/bin/env python3
"""Create the 1.16 App Store versions, set What's New + review notes, then attach the
processed builds and submit for review.

v1.16 headline: ONE assistance policy. The app had two hint systems that did not know about
each other — an always-on romaji display, and a reveal that charges the honest price
(usedHint, minimal score, SRS lapse) which no view had ever called. Now: Always / When stuck
/ Off. "When stuck" OFFERS the answer after repeated DISTINCT attempts at the same matcher
state (a held key can only ever produce 2, and the threshold is 3, so leaning on a key never
triggers it), and taking the offer costs exactly what the reveal always cost. Plus word-list
data-loss fixes, the Practice screen no longer hiding the characters you are typing, and an
accessibility batch: fixed frames that clipped at large text sizes, and three things
VoiceOver said that were not true.

NOT in this release: N3 example sentences. The pilot's pre-committed stop rule fired twice —
see docs/PLAN-V1.16.md §B. The Japanese the pipeline writes is fine; the blocker is that N3
vocabulary is polysemous and the app shows one narrow gloss per entry, so a sentence using
any other real sense reads as a wrong definition. That is a data-model fix, not a prompt.

Two phases:
  scripts/submit_1_16.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_16.py --submit     # attach VALID builds (mac 30 / iOS 31) + submit

Build numbers are PER-PLATFORM and collide across platforms; find_build resolves each
candidate's platform via its preReleaseVersion. App and widget carry the SAME build number
per platform: mac app+widget 30, iOS app+widget 31.
"""
# Both fixes the v1.15 script asked for are implemented below (`submittable` and
# `open_submission`). The bug they prevent: running --submit for a platform whose version is
# ALREADY LIVE creates an EMPTY reviewSubmission — the attach fails on the live version, but
# the submission container is POSTed first. ASC then refuses to cancel it ("not in cancellable
# state") AND refuses to DELETE it (403), so it sits in READY_FOR_REVIEW forever. One such
# orphan was stuck on MAC_OS: 14d60575-fdec-4a50-a3a0-801e3e62cc63 (created 2026-07-31).
#
# RESULT (2026-08-04): the reuse path CONSUMED it. The v1.16 macOS submit printed "reusing
# open submission 14d60575-…", added its item and submitted — so the container that could not
# be cancelled or deleted became this release's real submission. The orphan is gone, and the
# guard that would have created a second one never fired.
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.16"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "30"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "31"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 One setting for hints, instead of two that did not know about each other. "
        "Choose Always (full romaji on screen, as before), When stuck, or Off. \"When stuck\" "
        "shows nothing until you are genuinely stuck -- repeated different attempts at the same "
        "character -- and then OFFERS the answer rather than handing it over. Leaning on a key "
        "is not being stuck, so the app does not count a held key as trying again. Taking the "
        "offer costs what it should: the word scores minimally and comes back for review. "
        "Time Attack never offers -- the clock runs either way. Off means off.\n"
        "\u2022 Your word lists are safer. A list of more than 500 saved words is no longer "
        "silently trimmed, and if the app cannot read your lists at startup it now says so and "
        "refuses to overwrite them instead of quietly replacing them with an empty set.\n"
        "\u2022 Practice no longer hides the characters you are supposed to be typing on short "
        "screens, and its text scrolls at every text size.\n"
        "\u2022 Accessibility: at the large text sizes the Time Attack countdown no longer "
        "truncates 35 seconds into something that reads as 3, list buttons and journal dates stop "
        "clipping, and charts grow with their labels. VoiceOver fixes too -- the Best WPM tile "
        "said \"em dash\" where it meant \"no rides yet\", the BEST badge in Speed trend was on "
        "screen but unreachable, and your best speed is now the same number in the journal and "
        "the stats."
    ),
    "zh-Hans": (
        "\u2022 \u63d0\u793a\u5408\u5e76\u4e3a\u4e00\u4e2a\u8bbe\u7f6e\uff1a\u603b\u662f\u3001\u5361\u4f4f\u65f6\u3001\u5173\u95ed\u3002"
        "\u9009\u201c\u5361\u4f4f\u65f6\u201d\u65f6\u5c4f\u5e55\u4e0a\u4e0d\u663e\u793a\u4efb\u4f55\u7f57\u9a6c\u5b57\uff0c"
        "\u53ea\u6709\u5f53\u4f60\u5728\u540c\u4e00\u4e2a\u5b57\u4e0a\u53cd\u590d\u5c1d\u8bd5\u4e0d\u540c\u6309\u952e\u65f6\uff0c"
        "\u624d\u4f1a\u51fa\u73b0\u4e00\u4e2a\u201c\u770b\u7b54\u6848\u201d\u6309\u94ae\u2014\u2014\u662f\u63d0\u4f9b\uff0c\u4e0d\u662f\u76f4\u63a5\u7ed9\u4f60\u3002"
        "\u6309\u7740\u4e00\u4e2a\u952e\u4e0d\u7b97\u5361\u4f4f\uff0c\u6240\u4ee5\u957f\u6309\u6c38\u8fdc\u4e0d\u4f1a\u89e6\u53d1\u5b83\u3002"
        "\u7528\u4e86\u5c31\u8981\u4ed8\u4ee3\u4ef7\uff1a\u8be5\u8bcd\u53ea\u8ba1\u6700\u4f4e\u5206\uff0c\u5e76\u4f1a\u91cd\u65b0\u5b89\u6392\u590d\u4e60\u3002\n"
        "\u2022 \u8bcd\u5355\u66f4\u5b89\u5168\uff1a\u8d85\u8fc7 500 \u8bcd\u7684\u6536\u85cf\u5355\u4e0d\u518d\u88ab\u9759\u9ed8\u622a\u65ad\uff1b"
        "\u82e5\u542f\u52a8\u65f6\u8bfb\u4e0d\u51fa\u4f60\u7684\u8bcd\u5355\uff0c\u5e94\u7528\u4f1a\u660e\u786e\u544a\u77e5\u5e76\u62d2\u7edd\u8986\u5199\uff0c"
        "\u800c\u4e0d\u662f\u9759\u9ed8\u5730\u7528\u7a7a\u5217\u8868\u66ff\u6389\u5b83\u4eec\u3002\n"
        "\u2022 \u7ec3\u4e60\u6a21\u5f0f\u5728\u77ee\u5c4f\u5e55\u4e0a\u4e0d\u518d\u906e\u4f4f\u4f60\u8981\u6253\u7684\u5b57\uff0c\u4efb\u4f55\u5b57\u53f7\u4e0b\u90fd\u53ef\u6eda\u52a8\u3002\n"
        "\u2022 \u65e0\u969c\u788d\uff1a\u5927\u5b57\u53f7\u4e0b\u9650\u65f6\u5012\u8ba1\u65f6\u4e0d\u518d\u628a 35 \u79d2\u622a\u6210\u770b\u4f3c 3 \u79d2\uff0c"
        "\u5217\u8868\u6309\u94ae\u3001\u9a91\u884c\u65e5\u5fd7\u65e5\u671f\u4e0d\u518d\u88ab\u88c1\u5207\uff0c\u56fe\u8868\u968f\u6807\u7b7e\u589e\u9ad8\u3002"
        "\u65c1\u767d\u4e5f\u4fee\u4e86\uff1a\u6700\u4f73 WPM \u5361\u7247\u5728\u65e0\u8bb0\u5f55\u65f6\u4f1a\u62a5\u201c\u7834\u6298\u53f7\u201d\uff0c"
        "\u901f\u5ea6\u8d8b\u52bf\u91cc\u7684\u6700\u4f73\u5f92\u6807\u5728\u5c4f\u5e55\u4e0a\u5374\u8bfb\u4e0d\u5230\uff0c"
        "\u4e14\u540c\u4e00\u4e2a\u6700\u4f73\u901f\u5ea6\u5728\u65e5\u5fd7\u548c\u7edf\u8ba1\u91cc\u5dee\u4e00\u3002"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.16 replaces the app's two separate romaji-hint mechanisms with one setting: Always / When "
    "stuck / Off. \"When stuck\" shows nothing while typing, and after repeated distinct attempts at the "
    "same character it offers a control that reveals the answer; taking it scores that word minimally and "
    "schedules it for review. All of this is deterministic and on-device -- no machine learning at runtime, "
    "no network calls, no data collection. The release also hardens the saved-word-list storage against "
    "data loss, fixes the Practice screen hiding its own text on short screens, and includes an "
    "accessibility batch (layouts that clipped at large Dynamic Type sizes, and three VoiceOver values that "
    "did not match what was on screen). Everything remains local and offline; iCloud sync is the user's own "
    "private database and the app is fully usable without it."
)
CONTACT = {"contactFirstName": "Yuhe", "contactLastName": "Ye",
           "contactPhone": "+81 80-3526-7088", "contactEmail": "yyyyy.yeyuhe@gmail.com"}


def asc(method, ep, body=None):
    env = dict(os.environ)
    if body is not None:
        json.dump(body, open("/tmp/asc_body.json", "w"), ensure_ascii=False)
        env["ASC_BODY_FILE"] = "/tmp/asc_body.json"
    out = subprocess.run(["scripts/asc_api.sh", method, ep], capture_output=True, text=True, env=env).stdout
    try:
        return json.loads(out) if out.strip() else {}
    except Exception:
        return {"_raw": out}


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
        r = asc("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": bid}})
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
