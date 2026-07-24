#!/usr/bin/env python3
"""Create the 1.13 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.13:
  - Lock-screen widgets (accessory rectangular / inline / circular) -- the widget's
    data pipeline was already family-agnostic, so these are new layouts, not new data.
  - Sync correctness, round 2: clearing the app's iCloud data (Settings > Apple ID >
    iCloud > Manage Storage) deleted the zone server-side, and the app ignored it --
    it recreated an empty zone and reported "Synced" while the cloud held nothing. Now
    it rebuilds the zone and re-uploads everything, and never says Synced until it has.
  - The small widget no longer says "all caught up" while conjugation drills are due.
  - Two iPhone polish fixes carried from the branch: a landmark no longer punches
    through the word card, and scrolling content no longer slides under the clock.

Two phases:
  scripts/submit_1_13.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_13.py --submit     # attach VALID builds (mac 20 / iOS 21) + submit

NOTE: build numbers are PER-PLATFORM and collide across platforms, so find_build
resolves each candidate's platform via its preReleaseVersion -- never match by build
number alone. The embedded widget extension carries the SAME build number as its host
app (App Store rejects a mismatch): mac app+widget 20, iOS app+widget 21.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.13"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "20"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "21"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 NEW: lock-screen widgets. Add Nihongo Ride to your Lock Screen to see how many "
        "words and conjugations are due at a glance -- inline, rectangular, or circular.\n"
        "\u2022 Fixed: if you cleared the app's iCloud data, this device stopped uploading and still "
        "said \"Synced\". It now rebuilds your iCloud copy and re-uploads everything.\n"
        "\u2022 Fixed: the small widget could say \"all caught up\" while verb-conjugation drills were "
        "still due. It now shows those too.\n"
        "\u2022 iPhone polish: a horizon landmark no longer overlaps the word you're typing, and lists "
        "no longer slide under the status bar clock while scrolling."
    ),
    "zh-Hans": (
        "\u2022 \u65b0\u589e\uff1a\u9501\u5c4f\u5c0f\u7ec4\u4ef6\u3002\u628a Nihongo Ride \u52a0\u5230\u9501\u5c4f\uff0c\u4e00\u773c\u770b\u5230\u591a\u5c11\u8bcd\u548c\u53d8\u5f62\u5230\u671f\u2014\u2014\u884c\u5185\u3001\u77e9\u5f62\u6216\u5706\u5f62\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u82e5\u4f60\u6e05\u9664\u4e86\u5e94\u7528\u7684 iCloud \u6570\u636e\uff0c\u6b64\u8bbe\u5907\u4f1a\u505c\u6b62\u4e0a\u4f20\u5374\u4ecd\u663e\u793a\u300c\u5df2\u540c\u6b65\u300d\u3002\u73b0\u5728\u4f1a\u91cd\u5efa iCloud \u526f\u672c\u5e76\u91cd\u65b0\u4e0a\u4f20\u5168\u90e8\u6570\u636e\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u5c0f\u7ec4\u4ef6\u53ef\u80fd\u5728\u8fd8\u6709\u52a8\u8bcd\u53d8\u5f62\u5230\u671f\u65f6\u8bf4\u300c\u5168\u90e8\u590d\u4e60\u5b8c\u5566\u300d\u3002\u73b0\u5728\u4e5f\u4f1a\u663e\u793a\u53d8\u5f62\u6570\u3002\n"
        "\u2022 iPhone \u7ec6\u8282\uff1a\u5730\u5e73\u7ebf\u5730\u6807\u4e0d\u518d\u906e\u4f4f\u4f60\u6b63\u5728\u8f93\u5165\u7684\u8bcd\uff1b\u5217\u8868\u6eda\u52a8\u65f6\u4e0d\u518d\u94bb\u5230\u72b6\u6001\u680f\u65f6\u949f\u4e0b\u9762\u3002"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.13 adds lock-screen (accessory) widgets showing the user's own review-due counts -- no new "
    "data, no network calls, reusing the same App Group snapshot as the existing home-screen widget. It also "
    "fixes a correctness issue in the app's private iCloud sync: if the user clears the app's iCloud data "
    "(Settings > Apple ID > iCloud > Manage Storage), the CloudKit zone is deleted server-side; the app now "
    "detects that, rebuilds the zone, and re-uploads the user's local data, instead of leaving an empty zone "
    "while reporting synced. Everything is local + offline; iCloud is the user's own private database and the "
    "app is fully usable without it."
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
