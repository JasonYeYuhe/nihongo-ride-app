#!/usr/bin/env python3
"""Create the 1.7 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

Two phases:
  scripts/submit_1_7.py --metadata   # create versions + What's New + review detail (build NOT needed yet)
  scripts/submit_1_7.py --submit     # attach VALID builds (mac 10 / iOS 11) + submit

Run --metadata any time; run --submit only once both builds show processingState VALID.
Metadata/screenshots/description auto-inherit from the prior version on create.

NOTE: macOS build 10 COLLIDES with the existing iOS 1.6 build 10 (build numbers are
per-platform), so find_build resolves each candidate's platform via its
preReleaseVersion — never match by build number alone.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.7"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "10"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "11"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "• Bigger text support: Nihongo Ride now follows your system \"Larger Text\" (Dynamic Type) "
        "setting across the whole app, so the menus, word cards, and stats scale up for easier reading.\n"
        "• NEW: Weak Words — a focused cram of the words you struggle with most, drawn from your review "
        "history. It's pure practice: it never changes your spaced-repetition schedule.\n"
        "• Verb Conjugation: choose exactly which forms to drill (te-form, past, negative, potential, "
        "volitional, and more) from the menu, instead of always getting every form.\n"
        "• Polish and fixes throughout."
    ),
    "zh-Hans": (
        "• 更大字体支持：にほんご ライド 现在全 app 跟随系统「更大字体」（动态字体）设置，"
        "菜单、单词卡与统计都会随之放大，更易阅读。\n"
        "• 新增「弱词练习」：从你的复习记录里挑出你最薄弱的词，集中强化。纯练习，绝不改动你的间隔复习计划。\n"
        "• 动词变形：现在可在菜单里精选要练哪些变形（て形、过去、否定、可能、意志等），不必每次全练。\n"
        "• 多处细节打磨与修复。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. "
    "No account or login is required; the developer collects no data.\n\n"
    "Version 1.7 adds: (1) Dynamic Type / \"Larger Text\" support across the app — an accessibility "
    "improvement; rendering is unchanged at the default text size. (2) A \"Weak Words\" practice mode "
    "that drills the user's hardest reviewed words; it is pure practice and writes nothing to the "
    "spaced-repetition schedule. (3) The ability to choose which verb-conjugation forms to drill (a "
    "local menu preference). All three are local and offline — no new data is collected and iCloud is "
    "not required. The app is fully usable without iCloud."
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
    """Match by build number AND platform — build numbers are per-platform, so mac 10
    and iOS 10 can coexist; resolve each candidate's platform via its preReleaseVersion."""
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
            print("  !! no 1.7 version — run --metadata first"); sys.exit(1)
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
