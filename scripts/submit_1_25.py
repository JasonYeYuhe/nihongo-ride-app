#!/usr/bin/env python3
"""Create the 1.25 App Store versions, set What's New + review notes, then attach
the processed builds and submit both platforms for review.

v1.25 is about one sentence doing its job. A card teaches a spelling and a reading; its example
sentence carries exKana, which is the literal string the learner is graded against and the
furigana printed over the sentence. Forty-seven sentences read their own word a way their own
card does not teach — 何を keyed as なんを, which is not a reading of anything; 四つ keyed as
よんつ; 二日 as ふたか; 額, glossed "forehead", as がく. Counters and dates, the first irregular
readings a beginner meets, were taught and graded wrong.

The half that lasts is the gate: a reading-level counterpart to the substring test that has
guarded these sentences since v1.19 and never once compared a reading. Its first version matched
a single token and so could not see the 240 entries whose headword the tokenizer splits; the
pre-submission review found that, and it is now span-aware.

Correcting the corpus also repaired the reason 50 sentences were being withheld from dictation,
so the dictation pool grows from 5,720 to 5,770 without any decision being reversed.

Two phases:
  python3 scripts/submit_1_25.py --metadata   # create versions + What's New + review detail
  python3 scripts/submit_1_25.py --submit     # attach VALID builds (mac 47 / iOS 48) + submit

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW. Uploading builds is
fine at any time; this is the step that fails.
"""
import json, subprocess, sys, os

APP = "6777469778"
VERSION = "1.25"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "47"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "48"},
]

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
WHATS_NEW = {
    "en-US": (
        "\u2022 Forty-seven example sentences were spelling out their own word the wrong way. "
        "Every sentence carries the reading you type and the small kana printed above the "
        "characters, and in these the two did not match the word the card teaches -- 何を was "
        "written as \"nan wo\" instead of \"nani wo\", 四つ as \"yontsu\" instead of "
        "\"yottsu\", 二日 as \"futaka\" instead of \"futsuka\". Counters and dates were the "
        "worst affected, which are the first irregular readings anyone meets.\n"
        "\u2022 Fifty more sentences are available in Dictation. They had been held back "
        "because the voice did not say what the answer key said -- and it turned out the voice "
        "was right, so fixing the sentences released them.\n"
        "\u2022 The results screen after a sentence or dictation ride now says what each number "
        "counts. It was reporting sentences under a heading that said words, and listing whole "
        "sentences in boxes meant for single words."
    ),
    "zh-Hans": (
        "\u2022 47 个例句把自己要教的那个词标错了读音。每个句子都带着你要输入的假名,也带着"
        "汉字上方的小字注音,而在这些句子里,它们和卡片教的读音对不上 \u2014\u2014 何を 写成了"
        "「なんを」而不是「なにを」,四つ 写成「よんつ」而不是「よっつ」,二日 写成「ふたか」"
        "而不是「ふつか」。受影响最重的是量词和日期,而它们正是最早遇到的不规则读音。\n"
        "\u2022 听写模式多了 50 个句子。它们原本被保留,是因为语音读的和答案对不上 "
        "\u2014\u2014 后来发现是语音对的,句子改正后它们就回来了。\n"
        "\u2022 句子和听写结束后的结算页,现在每个数字都写明自己在数什么。此前它把句子数"
        "记在写着「词」的标题下,还把整句话塞进只放得下一个词的格子里。"
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a fully offline-capable typing-practice app for Japanese learners. No account or login "
    "is required; the developer collects no data.\n\n"
    "Version 1.25 is a content-correction release. Each vocabulary card carries an example sentence with a "
    "kana transcription, which the app uses both as the text the learner types and as the furigana shown "
    "above the characters. In 47 sentences that transcription did not match the reading the card teaches, so "
    "a learner typing correctly was marked wrong. Those are corrected, and an automated check now fails the "
    "build if a sentence reads its own headword a way its card does not teach.\n\n"
    "As a consequence, 50 sentences previously withheld from the Dictation exercise became available again: "
    "they had been withheld because the system speech voice did not say what the answer key said, and the "
    "answer key was what was wrong.\n\n"
    "Nothing about data handling has changed. Everything runs on-device: no network calls, no microphone, no "
    "speech recognition, no analytics, no accounts. Dictation uses the system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, on-device ja-JP) and is shown as unavailable, with an explanation, when no Japanese "
    "voice is installed. iCloud sync is the user's own private database and the app is fully usable without it."
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
