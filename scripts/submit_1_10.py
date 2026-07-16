#!/usr/bin/env python3
"""Create the 1.10 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.10 = the version that stops lying. Headline: removing a word from a list now
actually converges across devices (it never did -- the merge unioned ids add-wins,
so the next fetch from any peer put the word straight back). Supporting: the sync
layer no longer reports success for work it didn't do, and a share card on results.

Two phases:
  scripts/submit_1_10.py --metadata   # create versions + What's New + review detail
  scripts/submit_1_10.py --submit     # attach VALID builds (mac 14 / iOS 15) + submit

NOTE: build numbers are PER-PLATFORM and collide across platforms (mac 14 here vs
the iOS 1.9 build 14 already uploaded), so find_build resolves each candidate's
platform via its preReleaseVersion -- never match by build number alone.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.10"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "14"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "15"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
#
# The removal copy is deliberately forward-looking ("from now on"), NOT "your past
# removals will sync". Two reasons, both honest:
#   1. Whether CKSyncEngine retains or drops a pending change after a non-transient
#      per-record error was never verified on-device, and that decides whether
#      already-attempted removals ever flush.
#   2. A removal made by a v1.9 device leaves no tombstone at all -- there is nothing
#      to propagate later. Only removals made by v1.10+ carry one.
# Claiming retroactive repair would be exactly the kind of lie this release is about.
WHATS_NEW = {
    "en-US": (
        "• Fixed: removing a word from a list now syncs to your other devices. Until now a removal "
        "quietly came back the next time another device synced. Removals you make from this version "
        "onward stick.\n"
        "• Fixed: deleting a whole list now syncs too — it never did.\n"
        "• Share your ride: a results-screen card with your score, distance, combo and accuracy.\n"
        "• Sync reliability: turning iCloud sync off now stops it immediately, and sync problems are "
        "reported instead of silently showing 'Synced'.\n"
        "• The menu now shows the word count for the level you actually picked."
    ),
    "zh-Hans": (
        "• 修复:从词单中移除单词,现在会同步到你的其他设备。此前移除会在别的设备同步后悄悄复原;"
        "从本版起做的移除会真正生效。\n"
        "• 修复:删除整个词单现在也会同步了——此前一直不会。\n"
        "• 分享成绩:结算页可生成成绩卡(得分、距离、连击、正确率)。\n"
        "• 同步可靠性:关闭 iCloud 同步会立即停止;同步出问题时会如实提示,而不再一律显示「已同步」。\n"
        "• 菜单词数现在按你实际选择的等级显示。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.10 is a correctness release for the app's private iCloud sync of the user's own word lists. "
    "Removing a word from a list, and deleting a list, now converge across the user's devices (both "
    "previously did not). It also adds a Share button on the results screen that exports an image of the "
    "user's own ride stats via the standard share sheet — this is why the iOS build now declares "
    "NSPhotoLibraryAddUsageDescription: the app itself never reads or writes the photo library, but the "
    "system share sheet offers 'Save Image' for any image, and the key is required for that action to work "
    "rather than terminate the app. No new data is collected. Everything is local + offline; iCloud is "
    "optional (the user's own private database) and the app is fully usable without it."
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
