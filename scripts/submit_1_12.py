#!/usr/bin/env python3
"""Create the 1.12 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.12 is mostly a correctness release, with the scenery work on top:

  A  A second device could seed its odometer from the FLEET's ride history (the
     journal is rebuilt from merged cloud records), permanently doubling lifetime
     totals -- grow-only counter, so nothing could bring it back down.
  B  "Due" meant two different things: the widget/Ride Log/notification bucketed by
     calendar day while the menu and the actual ride compared instants. Practise in
     the evening and the next morning the widget said 8 due while a ride pulled none.
  C  Turning iCloud sync off still uploaded and still displayed "Synced"; the widget
     streak went stale on a ride-only sync; a run where nothing was typed was graded
     "Steady -- solid pace, clean accuracy".
  D  The ride scene now changes with the road: eight stretches from Edo to Kyoto,
     chosen by lifetime distance, and the results screen keeps the sky you finished
     under. Plus Reduce Motion support and a 4x drop in scene repaint rate.

Two phases:
  scripts/submit_1_12.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_12.py --submit     # attach VALID builds (mac 18 / iOS 19) + submit

NOTE: build numbers are PER-PLATFORM and collide across platforms, so find_build
resolves each candidate's platform via its preReleaseVersion -- never match by build
number alone. The embedded widget extension carries the SAME build number as its host
app (App Store rejects a mismatch): mac app+widget 18, iOS app+widget 19.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.12"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "18"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "19"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 Fixed: on a second device, your lifetime distance and word count could end up "
        "roughly doubled. New installs no longer count another device's rides as their own.\n"
        "\u2022 Fixed: the widget, Ride Log and daily reminder could say words were due while the "
        "app offered none. Both now agree, and a card is due for the whole day it falls on.\n"
        "\u2022 Fixed: turning iCloud Sync off now stops it immediately, instead of finishing an "
        "upload and still showing \"Synced\".\n"
        "\u2022 Fixed: a ride where nothing was typed is no longer graded as a clean run.\n"
        "\u2022 The road now goes somewhere: as your lifetime distance grows you ride eight "
        "stretches from Edo to Kyoto, each with its own sky, light and road surface. The results "
        "screen keeps the sky you arrived under.\n"
        "\u2022 The ride scene now respects Reduce Motion, and repaints far less often."
    ),
    "zh-Hans": (
        "\u2022 \u4fee\u590d\uff1a\u5728\u7b2c\u4e8c\u53f0\u8bbe\u5907\u4e0a\uff0c\u7ec8\u8eab\u91cc\u7a0b\u548c\u8bcd\u6570\u53ef\u80fd\u4f1a\u53d8\u6210\u7ea6\u4e24\u500d\u3002\u65b0\u5b89\u88c5\u4e0d\u4f1a\u518d\u628a\u53e6\u4e00\u53f0\u8bbe\u5907\u7684\u9a91\u884c\u7b97\u6210\u81ea\u5df1\u7684\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u5c0f\u7ec4\u4ef6\u3001\u9a91\u884c\u65e5\u5fd7\u548c\u6bcf\u65e5\u63d0\u9192\u4f1a\u8bf4\u6709\u8bcd\u5230\u671f\uff0c\u800c\u5e94\u7528\u91cc\u5374\u4e00\u4e2a\u4e5f\u4e0d\u7ed9\u3002\u73b0\u5728\u4e24\u8fb9\u4e00\u81f4\uff0c\u5230\u671f\u5f53\u5929\u5168\u5929\u6709\u6548\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u5173\u95ed iCloud \u540c\u6b65\u4f1a\u7acb\u5373\u505c\u6b62\uff0c\u4e0d\u518d\u4f20\u5b8c\u4e00\u8f6e\u8fd8\u663e\u793a\u300c\u5df2\u540c\u6b65\u300d\u3002\n"
        "\u2022 \u4fee\u590d\uff1a\u4e00\u4e2a\u5b57\u90fd\u6ca1\u6253\u7684\u9a91\u884c\uff0c\u4e0d\u4f1a\u518d\u88ab\u8bc4\u4e3a\u8868\u73b0\u7a33\u5065\u3002\n"
        "\u2022 \u8def\u771f\u7684\u901a\u5411\u8fdc\u65b9\uff1a\u968f\u7740\u7ec8\u8eab\u91cc\u7a0b\u589e\u957f\uff0c\u4f60\u4f1a\u9a91\u8fc7\u4ece\u6c5f\u6237\u5230\u4eac\u90fd\u7684\u516b\u6bb5\u8def\uff0c\u5404\u6709\u5929\u8272\u3001\u5149\u7ebf\u4e0e\u8def\u9762\u3002\u7ed3\u7b97\u5c4f\u4f1a\u7559\u4f4f\u4f60\u5230\u7ad9\u65f6\u7684\u90a3\u7247\u5929\u3002\n"
        "\u2022 \u9a91\u884c\u573a\u666f\u73b0\u5728\u9075\u5faa\u300c\u51cf\u5f31\u52a8\u6001\u6548\u679c\u300d\uff0c\u91cd\u7ed8\u9891\u7387\u4e5f\u5927\u5e45\u964d\u4f4e\u3002"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.12 is primarily a correctness release for data the user already owns: a second device could "
    "seed its lifetime odometer from another device's synced ride history (doubling the displayed lifetime "
    "totals); the widget, Ride Log and local notification counted review cards by calendar day while the app "
    "itself counted by exact instant, so they disagreed; switching iCloud sync off did not stop an in-flight "
    "pass and could still display 'Synced'. It also adds a visual progression to the existing in-app ride "
    "scene (eight code-drawn palettes selected by the user's own lifetime distance -- no new data collected, "
    "no network calls, no assets), Reduce Motion support for that scene, and carries it onto the results "
    "screen. Everything is local + offline; iCloud is the user's own private database and the app is fully "
    "usable without it."
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
