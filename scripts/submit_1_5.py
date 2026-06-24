#!/usr/bin/env python3
"""Create the 1.5 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

Two phases (idempotent-ish):
  scripts/submit_1_5.py --metadata   # create versions + What's New + review detail (build NOT needed yet)
  scripts/submit_1_5.py --submit     # attach VALID builds (mac 8 / iOS 9) + submit

Run --metadata any time; run --submit only once both builds show processingState VALID.
Metadata/screenshots/description auto-inherit from the prior version on create.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.5"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "8"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "9"},
]

# What's New — MUST NOT contain the literal ★ glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "• NEW: Custom Word Lists — make as many named lists as you like. Tap the star to save a word "
        "to your favourites, or long-press it to file the word into any list. Practice any list on its own, "
        "right from the menu. Your lists sync privately across your devices via iCloud.\n"
        "• NEW: A short, skippable intro on first launch — romaji spelling, the three modes, and saving words.\n"
        "• Accessibility: VoiceOver now reads every screen — the HUD, score cards, ride log, settings, and your word lists.\n"
        "• Polish and fixes throughout."
    ),
    "zh-Hans": (
        "• 新增「自定义词单」：想建几个就建几个。点星标把词加入收藏，长按可把它归入任意词单；在菜单里单独练习任何一个词单。你的词单通过 iCloud 在设备间私密同步。\n"
        "• 新增首次启动的简短引导（可跳过）：罗马音拼写、三种模式、收藏词。\n"
        "• 无障碍：VoiceOver 现已朗读每一个界面——HUD、成绩卡、骑行日志、设置，以及你的词单。\n"
        "• 多处细节打磨与修复。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. "
    "No account or login is required; the developer collects no data.\n\n"
    "Version 1.5 adds Custom Word Lists. Lists (and the favourites/saved deck) are the user's OWN content, "
    "stored locally and, when iCloud sync is on, in the user's PRIVATE iCloud (CloudKit private database) — "
    "not accessible to the developer. The app is fully usable without signing in to iCloud. The first-launch "
    "intro does not request any permissions and can be skipped."
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


def find_build(num):
    d = asc("GET", f"/v1/builds?filter[app]={APP}&limit=30&sort=-uploadedDate"
                   f"&fields[builds]=version,processingState,usesNonExemptEncryption")
    for b in d.get("data", []):
        if b["attributes"]["version"] == num:
            return b["id"], b["attributes"]
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
            print("  !! no 1.5 version — run --metadata first"); sys.exit(1)
        bid, battr = find_build(t["build_num"])
        if not bid:
            print(f"  !! build {t['build_num']} not found"); sys.exit(1)
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
