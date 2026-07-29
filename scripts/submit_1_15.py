#!/usr/bin/env python3
"""Create the 1.15 App Store versions, set What's New + review notes, then attach
the processed builds and submit for review.

v1.15 headline: the Typing Coach — after a ride the app names the recurring mistake
PATTERN (particle spelling, dropped sokuon, small-ya, Hepburn m), replays the learner's
own keystrokes against a spelling that works, and offers a targeted drill built from the
app's own corpus. Deterministic: no model, no network. Plus 779 new reviewed example
sentences for N5/N4, data corrections, and a batch of recorded-number fixes (ridden-time
WPM, midnight streaks, macOS stray-key typos, store corruption resilience).

Two phases:
  scripts/submit_1_15.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_15.py --submit     # attach VALID builds (mac 26 / iOS 27) + submit

NOTE: build numbers are PER-PLATFORM and collide across platforms; find_build resolves
each candidate's platform via its preReleaseVersion. App and widget carry the SAME build
number per platform: mac app+widget 26, iOS app+widget 27. iOS can only be created and
submitted once iOS 1.14 leaves review (one version in review per platform) — the script
tolerates that: each platform proceeds independently and a blocked one just reports.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.15"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "26"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "27"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 NEW: the Typing Coach. When a mistake keeps happening across different words, "
        "the app now names the pattern -- particles typed the way they sound (konnichiwa for "
        "\u3053\u3093\u306b\u3061\u306f), a dropped small tsu, kya typed as ki+ya, m before b/p -- "
        "shows YOUR keystrokes next to a spelling that works, explains the rule, and offers a "
        "targeted drill built from words you already know. All on your device, no AI guesswork: "
        "the app knows exactly which key was refused and why.\n"
        "\u2022 779 new example sentences for N5 and N4 words -- generated, machine-checked "
        "against the app's own reading and level data, then reviewed before shipping. Nearly "
        "every N5/N4 word now has one.\n"
        "\u2022 Recorded numbers are honest now: paused time no longer counts as riding time in "
        "your WPM, a ride that crosses midnight keeps your streak, and on Mac, stray presses of "
        "Tab or the arrow keys no longer count as typos or reschedule words you typed correctly.\n"
        "\u2022 Data fixes: eleven headwords that displayed one word while grading another "
        "(\u30b8\u30a7\u30c3\u30c8, \u3051\u308c\u3069, \u30ad\u30ed and friends), and your "
        "review history now survives a damaged file -- one bad record costs that record, not "
        "everything.\n"
        "\u2022 Small honesty fixes: passage practice shows the passage's length instead of "
        "calling everything N5, the space bar no longer silently skips your passage, and "
        "clearing a word list asks first."
    ),
    "zh-Hans": (
        "\u2022 \u65b0\u589e\uff1a\u6253\u5b57\u6559\u7ec3\u3002\u5f53\u540c\u4e00\u7c7b\u9519\u8bef\u5728\u4e0d\u540c\u7684\u8bcd\u4e0a\u53cd\u590d\u51fa\u73b0\uff0c\u5e94\u7528\u4f1a\u6307\u51fa\u5177\u4f53\u6a21\u5f0f\u2014\u2014\u52a9\u8bcd\u6309\u8bfb\u97f3\u62fc\u5199\uff08\u3053\u3093\u306b\u3061\u306f \u6253\u6210 konnichiwa\uff09\u3001\u6f0f\u4fc3\u97f3\u3001\u62d7\u97f3\u62c6\u5f00\u6253\u7b49\uff0c\u628a\u4f60\u81ea\u5df1\u7684\u6309\u952e\u548c\u6b63\u786e\u6253\u6cd5\u5e76\u6392\u5c55\u793a\uff0c\u8bb2\u6e05\u89c4\u5219\uff0c\u5e76\u7528\u4f60\u5b66\u8fc7\u7684\u8bcd\u751f\u6210\u9488\u5bf9\u7ec3\u4e60\u3002\u5168\u90e8\u5728\u8bbe\u5907\u672c\u5730\u5b8c\u6210\uff0c\u4e0d\u9760 AI \u731c\u6d4b\u3002\n"
        "\u2022 \u65b0\u589e 779 \u6761 N5/N4 \u4f8b\u53e5\u2014\u2014\u751f\u6210\u540e\u7ecf\u8bfb\u97f3\u4e0e\u7b49\u7ea7\u6821\u9a8c\uff0c\u518d\u7ecf\u4eba\u5de5\u590d\u6838\u624d\u53d1\u5e03\u3002N5/N4 \u8bcd\u6c47\u51e0\u4e4e\u5168\u90e8\u914d\u4e0a\u4e86\u4f8b\u53e5\u3002\n"
        "\u2022 \u8bb0\u5f55\u7684\u6570\u5b57\u66f4\u8bda\u5b9e\uff1a\u6682\u505c\u65f6\u95f4\u4e0d\u518d\u8ba1\u5165 WPM\uff0c\u8de8\u5348\u591c\u7684\u9a91\u884c\u4e0d\u518d\u65ad\u8fde\u7eed\u5929\u6570\uff0cMac \u4e0a\u8bef\u6309 Tab/\u65b9\u5411\u952e\u4e0d\u518d\u8ba1\u4e3a\u6253\u9519\u3002\n"
        "\u2022 \u6570\u636e\u4fee\u6b63\uff1a\u5341\u4e00\u4e2a\u300c\u663e\u793a\u4e00\u4e2a\u8bcd\u3001\u8003\u53e6\u4e00\u4e2a\u8bcd\u300d\u7684\u8bcd\u6761\uff1b\u590d\u4e60\u8fdb\u5ea6\u6587\u4ef6\u5c40\u90e8\u635f\u574f\u65f6\u53ea\u4e22\u635f\u574f\u7684\u90a3\u4e00\u6761\uff0c\u4e0d\u518d\u6e05\u7a7a\u5168\u90e8\u3002\n"
        "\u2022 \u7ec6\u8282\uff1a\u6bb5\u843d\u7ec3\u4e60\u6309\u957f\u5ea6\u6807\u6ce8\u800c\u4e0d\u662f\u4e00\u5f8b N5\uff0c\u7a7a\u683c\u4e0d\u518d\u9759\u9ed8\u8df3\u8fc7\u6bb5\u843d\uff0c\u6e05\u7a7a\u8bcd\u5355\u4f1a\u5148\u786e\u8ba4\u3002"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.15 adds a Typing Coach: a deterministic, on-device analyzer that classifies the user's OWN "
    "refused keystrokes into named romaji-input patterns and offers a practice drill built from the app's "
    "bundled vocabulary. No machine learning at runtime, no network calls, no data collection -- the "
    "keystroke trace lives in memory for the current session only and is never persisted or synced. The "
    "release also adds 779 bundled example sentences (generated offline, validated against the app's own "
    "reading data, human-reviewed before inclusion) and fixes several recording bugs. Everything remains "
    "local and offline; iCloud sync is the user's own private database and the app is fully usable "
    "without it."
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
