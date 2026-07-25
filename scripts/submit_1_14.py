#!/usr/bin/env python3
"""Create the 1.14 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.14 is a correctness release -- no new features:
  - A: the app was TEACHING WRONG ANSWERS. Suru-nouns whose reading ends in -iku
    (hoiku, hatsuiku, seiiku, shiiku, saiku) were run through iku's euphonic exception
    and drilled as "hoitte"; three homophone suru-nouns (hirou, yosou, kisou) were
    tagged as godan verbs and conjugated from the wrong paradigm entirely; one headword
    shipped truncated, and one N5 entry showed yori while teaching the reading hou.
  - B: due reminders and the app-icon badge counted vocabulary only, so a learner
    working on verb conjugations was never reminded and saw a zero badge.
  - C: at the accessibility text sizes the results tiles overlapped each other and lost
    digits, the primary buttons truncated, and the menu's route strip collapsed.

Two phases:
  scripts/submit_1_14.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_14.py --submit     # attach VALID builds (mac 22 / iOS 23) + submit

NOTE: build numbers are PER-PLATFORM and collide across platforms, so find_build
resolves each candidate's platform via its preReleaseVersion -- never match by build
number alone. The embedded widget extension carries the SAME build number as its host
app (App Store rejects a mismatch): mac app+widget 22, iOS app+widget 23.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.14"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "22"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "23"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 Fixed: some verbs were taught with the WRONG conjugation. Nouns read -iku (hoiku, "
        "hatsuiku, shiiku and friends) were drilled with the irregular ending that belongs to iku, "
        "and three words that merely sound like verbs (hirou, yosou, kisou) were conjugated from "
        "the wrong pattern entirely. If you practised those, the answer you were graded against "
        "was not real Japanese -- sorry. They are correct now.\n"
        "\u2022 Fixed: two entries showed the wrong word. One headword was missing its last "
        "character, and one N5 card showed the wrong word for the reading it taught.\n"
        "\u2022 Fixed: review reminders and the app icon badge ignored verb-conjugation drills, so "
        "if you were practising only conjugations you were never reminded and the badge stayed at "
        "zero. Both now count words and conjugations together.\n"
        "\u2022 Accessibility: at the larger text sizes the results tiles overlapped each other and "
        "cut digits off the numbers, the main buttons truncated their labels, and the route strip "
        "on the home screen collapsed. Everything now grows with the text."
    ),
    "zh-Hans": (
        "\u2022 \u4fee\u590d\uff1a\u90e8\u5206\u52a8\u8bcd\u7684\u53d8\u5f62\u6559\u9519\u4e86\u3002\u8bfb\u4f5c -iku \u7684\u540d\u8bcd\uff08\u4fdd\u80b2\u3001\u53d1\u80b2\u3001\u9972\u80b2\u7b49\uff09\u88ab\u5957\u7528\u4e86\u300c\u884c\u304f\u300d\u7684\u4e0d\u89c4\u5219\u53d8\u5f62\uff1b\u53e6\u6709\u4e09\u4e2a\u8bfb\u97f3\u50cf\u52a8\u8bcd\u7684\u540d\u8bcd\uff08\u62ab\u9732\u3001\u9884\u60f3\u3001\u5bc4\u8d60\uff09\u6309\u9519\u8bef\u7684\u8bcd\u578b\u53d8\u5f62\u3002\u5982\u679c\u4f60\u7ec3\u8fc7\u8fd9\u4e9b\u8bcd\uff0c\u5f53\u65f6\u7684\u6807\u51c6\u7b54\u6848\u5e76\u4e0d\u662f\u771f\u6b63\u7684\u65e5\u8bed\u2014\u2014\u62b1\u6b49\u3002\u73b0\u5df2\u4fee\u6b63\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u4e24\u4e2a\u8bcd\u6761\u663e\u793a\u9519\u8bef\u2014\u2014\u4e00\u4e2a\u8bcd\u5934\u6f0f\u4e86\u6700\u540e\u4e00\u4e2a\u5047\u540d\uff0c\u4e00\u5f20 N5 \u5361\u7247\u7684\u8bcd\u5934\u4e0e\u5b83\u6559\u7684\u8bfb\u97f3\u5bf9\u4e0d\u4e0a\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u590d\u4e60\u63d0\u9192\u548c\u5e94\u7528\u56fe\u6807\u89d2\u6807\u4e0d\u7edf\u8ba1\u52a8\u8bcd\u53d8\u5f62\uff0c\u53ea\u7ec3\u53d8\u5f62\u7684\u8bdd\u4ece\u6765\u6536\u4e0d\u5230\u63d0\u9192\uff0c\u89d2\u6807\u4e5f\u4e00\u76f4\u662f\u96f6\u3002\u73b0\u5728\u4e24\u8005\u5408\u8ba1\u3002\n"
        "\u2022 \u65e0\u969c\u788d\uff1a\u5927\u5b57\u53f7\u4e0b\uff0c\u7ed3\u679c\u9875\u7684\u6570\u636e\u683c\u5b50\u4e92\u76f8\u91cd\u53e0\u5e76\u622a\u65ad\u6570\u5b57\uff0c\u4e3b\u6309\u94ae\u6587\u5b57\u88ab\u622a\uff0c\u4e3b\u9875\u8def\u7ebf\u6761\u6324\u6210\u4e00\u56e2\u3002\u73b0\u5728\u90fd\u4f1a\u968f\u5b57\u53f7\u4e00\u8d77\u53d8\u5927\u3002"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.14 is a correctness release: no new features, no new permissions, no data collection, no new "
    "network calls. It corrects errors in the bundled study data -- the app was presenting a few incorrect "
    "Japanese conjugations and two wrong dictionary entries as the answer the learner had to type. It also "
    "makes the local review reminder and the app icon badge count verb-conjugation practice as well as "
    "vocabulary, and fixes layout problems at the larger Dynamic Type sizes (result tiles overlapping, "
    "buttons truncating their labels). Everything remains local and offline; iCloud sync is the user's own "
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
        sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                  "attributes": {"platform": t["platform"]},
                  "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        if sub.get("errors"):
            print("  create submission ERR:", sub["errors"][0].get("detail")); continue
        sid = sub["data"]["id"]
        it = asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("  add item:", "OK" if not it.get("errors") else it["errors"][0].get("detail"))
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
