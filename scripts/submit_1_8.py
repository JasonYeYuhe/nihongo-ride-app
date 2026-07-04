#!/usr/bin/env python3
"""Create the 1.8 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

Two phases:
  scripts/submit_1_8.py --metadata   # create versions + What's New + review detail (build NOT needed yet)
  scripts/submit_1_8.py --submit     # attach VALID builds (mac 11 / iOS 12) + submit

Run --metadata any time; run --submit only once both builds show processingState VALID.
Metadata/screenshots/description auto-inherit from the prior version on create.

NOTE: macOS build 11 COLLIDES with the existing iOS 1.7 build 11 (build numbers are
per-platform), so find_build resolves each candidate's platform via its
preReleaseVersion — never match by build number alone.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.8"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "11"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "12"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
# Conjugation iCloud sync is present but GATED OFF this release — do NOT mention cloud sync.
WHATS_NEW = {
    "en-US": (
        "• NEW: Conjugation Review — verb-conjugation practice now remembers the forms you get wrong "
        "and brings them back with spaced repetition, weighted toward your weakest forms. A \"Review N due\" "
        "button appears in the menu when forms are ready.\n"
        "• More verbs to drill: the ずる verbs (演ずる, 感ずる, 信ずる, and more) are now conjugable, "
        "adding N1/N2 verbs to the pool.\n"
        "• NEW: Read Aloud — turn on the speaker button (in Settings) to hear the kana spoken with an "
        "offline Japanese voice, on the word and conjugation cards.\n"
        "• Polish and fixes throughout."
    ),
    "zh-Hans": (
        "• 新增「变形复习」：动词变形练习现在会记住你答错的变形，用间隔复习把它们按时带回来，"
        "并向你最薄弱的变形加权。有到期变形时，菜单会出现「复习 N 个」按钮。\n"
        "• 更多可练动词：ずる 动词（演ずる、感ずる、信ずる 等）现已可变形，为词池加入 N1/N2 动词。\n"
        "• 新增「假名朗读」：在设置里打开朗读按钮，即可在单词卡与变形卡上用离线日语语音听假名发音。\n"
        "• 多处细节打磨与修复。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. "
    "No account or login is required; the developer collects no data.\n\n"
    "Version 1.8 adds: (1) Conjugation Review — the verb-conjugation drill now uses local spaced "
    "repetition to bring back the forms the user misses, weighted toward their weakest forms. It uses "
    "its own separate on-device store and never affects the vocabulary review schedule. (2) More "
    "conjugable verbs (the ずる verbs); conjugation-class labels are derived at build time from EDRDG's "
    "JMdict (CC BY-SA 4.0, credited on the in-app About screen). (3) Optional kana Text-to-Speech — a "
    "speaker button (off by default) reads the kana aloud with the system's offline Japanese voice. "
    "All local and offline — no new data is collected and iCloud is not required."
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
    """Match by build number AND platform — build numbers are per-platform, so mac 11
    and iOS 11 can coexist; resolve each candidate's platform via its preReleaseVersion."""
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
            print("  !! no 1.8 version — run --metadata first"); sys.exit(1)
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
