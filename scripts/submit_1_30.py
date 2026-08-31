#!/usr/bin/env python3
"""Create the 1.30 App Store versions, set What's New, correct one description line, set the
review notes, then attach the processed builds, submit the first in-app purchase, and submit
both platforms for review.

v1.30 is Stage 1: the road west (`com.jasonye.nihongoride.scenery.lifetime`, a NON_CONSUMABLE)
goes on sale, and the free Tōkaidō is unchanged. It is the first in-app purchase this app has
ever had, which is why this script does two things no previous submit script did — see the two
sections below. Every paragraph kept from the v1.29 template records a defect that is a property
of the TEMPLATE rather than of any one release, which is why they travel forward.

WHAT IS NEW IN THIS TEMPLATE, ONE
--------------------------------
**The description is edited SURGICALLY, not replaced.** Shipping the whole 1,773-character
description as a constant in this file would silently revert anything changed in App Store
Connect since the last release — and this listing is not maintained only from here: a separate
session owns product/ASO, and the `ja` locale was written and natively reviewed outside any
submit script. So `DESCRIPTION_EDITS` names, per locale, the exact sentence it expects to find
and the exact sentence it leaves behind. A locale where the old sentence is not present EXACTLY
ONCE is a FAILURE and not a skip: "already corrected" and "somebody rewrote the paragraph" must
not print the same thing, which is this project's oldest rule wearing store metadata.

WHAT IS NEW IN THIS TEMPLATE, TWO
---------------------------------
**The in-app purchase rides the version's own review submission, as an `inAppPurchaseVersion`
item.** This cost a wrong turn on 2026-08-31 and the wrong turn is written down because the
mistake was in the *reasoning*, not the API:

  * `POST /v1/inAppPurchaseSubmissions` exists (it answers `GET_COLLECTION` with "Allowed
    operation is: CREATE", against a control path that 404s) and is the RIGHT endpoint for a
    LATER purchase. For an app's FIRST non-consumable it returns 409
    `STATE_ERROR.FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` — *"must be submitted for
    review at the same time that you submit an app version"* — and it returns that whether the
    version is already in review, or sitting in an open submission that has not been sent.
    **Both readings of "at the same time" were tried and both were wrong.**
  * The relationship is **`inAppPurchaseVersion`**, pointing at an `inAppPurchaseVersions`
    object (`GET /v2/inAppPurchases/{id}/versions`), NOT at the purchase itself. The first probe
    asked for `inAppPurchase` and `inAppPurchaseV2`, got `RELATIONSHIP.UNKNOWN` for both, and
    concluded the resource does not take purchases at all. **The instrument was fine and the
    candidate list was short** — a positive control (`appStoreVersion`, which answers with a
    STATE error rather than an UNKNOWN one) proves the probe distinguishes the two cases, so the
    conclusion was reached from an absence that had not been searched.
  * One purchase cannot be an item in two submissions. Adding it to the second platform returns
    `STATE_ERROR.ENTITY_STATE_INVALID`. That is correct rather than a limitation: the purchase is
    app-level under Universal Purchase, so it is reviewed once and is then live on both.

The ORDER is the safety property, and it is enforced in code rather than described in a comment:
every build is attached first; the purchase item is staged into one submission; and **nothing is
submitted at all unless the purchase is staged or already in review.** The first run of this
script had that rule in its prose and not in its control flow, so when the purchase failed both
platforms went to Apple anyway, carrying release notes for a purchase nobody could make. Both
submissions had to be cancelled and rebuilt.

TEMPLATE DEFECTS THIS FILE STILL CARRIES THE FIXES FOR (do not remove them):

  * `submittable()` turned an unrecognised version state into a friendly skip and main exited 0,
    so a run that submitted NOTHING looked exactly like a clean run. Every skip and every error
    records a failure and the process exits non-zero.
  * Nothing read the submissions back. Everything here is re-queried from Apple afterwards.
  * `asc()` treats an empty or non-JSON response as a FAILURE. Every submit script from 1.10 to
    1.21 returned `{}` on a broken call, and `{}` has no "errors" key, so a run in which nothing
    reached Apple printed OK at every step.
  * Every number in the copy is derived by `release_numbers.py` at runtime. v1.25's What's New
    told users "Fifty more sentences", and the measured figure was 42.

Three phases:
  python3 scripts/submit_1_30.py --dry-run    # print the derived copy and the diffs, touch nothing
  python3 scripts/submit_1_30.py --metadata   # versions + What's New + description + review detail
  python3 scripts/submit_1_30.py --submit     # attach builds (mac 54 / iOS 55) + IAP + submit

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW. Uploading builds is
fine at any time; this is the step that blocks.
"""
import json, subprocess, sys, os
from pathlib import Path

APP = "6777469778"
VERSION = "1.30"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "54"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "55"},
]

# Stage 1's SKU. Both are checked before anything is submitted: the numeric id is what the API
# takes, and the product id is what a human can recognise — asserting they belong together is
# what stops this script submitting some other product because an id was mistyped.
IAP_ID = "6806755720"
IAP_PRODUCT_ID = "com.jasonye.nihongoride.scenery.lifetime"

# Measured, never typed. See release_numbers.py for why this is a module rather than a habit.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_numbers import numbers as _release_numbers   # noqa: E402

# v1.30 changes no vocabulary file, so `release_numbers.BASELINE_REF` was advanced to the v1.29
# release commit and every corpus delta below reads 0. That is the point: leaving the baseline
# behind is how "this release" silently becomes "these two releases". The route figures the copy
# actually quotes are parsed out of the shipped `RideRoute.swift`.
N = _release_numbers()

# What's New — MUST NOT contain the literal star glyph (ASC rejects it).
#
# Written in the same voice as the in-app placement: it reports what changed and never solicits.
# **And the dimension is named, because this project has now paid twice for a prose rule whose
# dimension nobody wrote down.** The five-clause placement discipline (no modal, no badge, no
# post-ride solicitation, no recurring reminder, far from the rating prompt) constrains IN-APP
# SURFACES. Release notes are shown by the App Store, once per update, outside the app; no clause
# reaches them. What does reach them is the standard the menu strip was held to — state the fact,
# do not sell it — so there is no price here, no urgency, and no call to act.
WHATS_NEW = {
    "en-US": (
        f"• The road continues past Kyōto. The Tōkaidō ends there and always "
        f"did; now there is a second journey beyond it — {N['paidRouteStretches']} stretches "
        f"west along the inland sea, {N['paidRouteFirst']} to {N['paidRouteLast']}, each with its "
        "own sky, light and road surface. It is opened by one optional, one-time purchase, from a "
        "single row in Settings.\n"
        f"• The Tōkaidō stays free and complete, all {N['freeRouteStretches']} "
        "stretches of it, and nothing you already had has moved behind anything. This version "
        "takes nothing away from anyone.\n"
        "• The menu's route strip now marks where you actually are on the road, and says so "
        "once you have ridden the Tōkaidō to its end.\n"
        "• On a Mac, a short window no longer cuts the menu off at both ends — it "
        "scrolls.\n"
        "• About now carries an address to write to, and the app's on-device counters. Those "
        "counters stay on your device and are never sent anywhere."
    ),
    "zh-Hans": (
        f"• 京都之后,路继续往西。东海道在京都结束,一直如此;现在它之后有了第二段旅程 —— "
        f"沿濑户内海向西的 {N['paidRouteStretches']} 段路,从大阪到长崎,每一段有自己的天色、光线和路面。"
        "它由一次性购买开启,入口只有设置里的一行。\n"
        f"• 东海道依然免费、完整,{N['freeRouteStretches']} 段一段不少,你原本已有的一切都没有被移到"
        "收费后面。这个版本没有从任何人手里拿走任何东西。\n"
        "• 菜单上的路线条现在会标出你实际走到哪里;东海道走完时,它也会说出来。\n"
        "• Mac 上窗口较矮时,菜单不再上下都被切掉 —— 现在可以滚动。\n"
        "• 「关于」页面新增了可以写信的邮箱地址,以及本机计数。计数只留在你的设备上,从不上传。"
    ),
    # The app's interface is English or Chinese only — the `ja` listing says so itself — so the
    # Japanese copy names the English labels a Japanese rider actually sees on screen.
    "ja": (
        f"• 京都のさらに西へ。東海道は京都で終わります。その先に 2 つめの旅が加わりました。"
        f"瀬戸内をたどって西へ、大阪から長崎までの {N['paidRouteStretches']} 区間。"
        "区間ごとに空の色、光、路面が変わります。買い切りの App 内課金 1 つで開き、"
        "入口は設定内の 1 行だけです。\n"
        f"• 東海道はこれまでどおり無料で、{N['freeRouteStretches']} 区間すべてそのまま残ります。"
        "これまでお使いだったものが課金の内側に移ることはありません。"
        "このバージョンで失われるものは何もありません。\n"
        "• メニューのルート表示が、実際に走ってきた現在地を示すようになりました。"
        "東海道を走りきったときは、そのこともお知らせします。\n"
        "• Mac でウインドウが低いとき、メニューが上下で切れてしまう問題を修正しました。"
        "スクロールできます。\n"
        "• 「About」画面に、連絡用のメールアドレスと端末内カウンターを追加しました。"
        "カウンターは端末内にとどまり、送信されることはありません。"
    ),
}

# ---------------------------------------------------------------------------------------------
# The one description line that stops being true in this version.
#
# WHY IT IS PER-LOCALE AND NOT A TRANSLATION OF ONE NEW SENTENCE. The three locales do not make
# the same claim, and treating them as one sentence in three languages would make the listing
# WORSE. Checked against the live text on 2026-08-31, one locale at a time:
#
#   en-US   "No account"           unqualified — reads as "nothing here needs an account",
#                                  which an in-app purchase makes false.        CORRECTED
#   zh-Hans "无账号"                unqualified, same reading.                   CORRECTED
#   ja      "アカウント登録は不要"    says REGISTRATION is not required, which stays
#                                  true: a buyer uses an Apple Account they already
#                                  have and registers nothing with the developer.
#                                                                              LEFT ALONE
#
# Editing `ja` for symmetry would replace a sentence that is already unambiguous with one that
# needed a qualifier — loosening it while looking like tidying — and it would put un-reviewed
# Japanese into the one listing on this app that had a native review. A Japanese reader is not
# left short: the App Store renders the purchase's own Japanese name and description on the same
# product page.
#
# AND THE HISTORY, because this exact line has gone stale once before. Until v1.28 it read
# "No account, no network, no tracking, no ads" — and `iCloudSyncEnabled` defaults to TRUE, so
# the app reached the network by default while the listing said it did not. The sentence was
# true when written and was falsified by a capability added later, and nobody re-read it.
# **The rule that follows is worth more than this edit: every capability that touches the
# network or an account requires this paragraph to be re-read before it ships.** It is the most
# stale-prone and least re-read paragraph on the product page.
DESCRIPTION_EDITS = {
    "en-US": (
        "• Works fully offline. No account, no ads, no tracking, and no analytics of any kind.",
        "• Works fully offline. No sign-up and no account with the developer, no ads, no "
        "tracking, and no analytics of any kind. The one optional in-app purchase is handled by "
        "the App Store, through your own Apple Account.",
    ),
    "zh-Hans": (
        "• 完全离线可用。无账号、无广告、无追踪,也没有任何统计分析。",
        "• 完全离线可用。无需注册,开发者这边也没有你的账号,无广告、无追踪,也没有任何统计分析。"
        "唯一的一项可选内购由 App Store 通过你自己的 Apple 账户完成。",
    ),
}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.30 ADDS THIS APP'S FIRST IN-APP PURCHASE, submitted with this version:\n"
    f"  {IAP_PRODUCT_ID}\n"
    "  \"Nihongo Ride Scenery - the road west\", non-consumable, CNY 10.00 one time,\n"
    "  Family Sharing off.\n\n"
    "WHAT IT UNLOCKS. The app's background is a stylised bicycle journey whose scenery advances "
    "with the learner's lifetime typing distance. The free route - the Tokaido, "
    f"{N['freeRouteStretches']} stretches, Nihonbashi to Kyoto - ends at {N['freeRouteEndKm']} km "
    "and is unchanged in this version: still free, still complete, no stretch removed and no "
    f"threshold moved. The purchase appends a second route of {N['paidRouteStretches']} stretches "
    f"running west from Kyoto ({N['paidRouteStops']}), and the scenery of that route.\n\n"
    "WHAT IT DOES NOT GATE. No vocabulary, no practice mode, no review queue, no reading "
    "passages, no export. Nothing that was available in version 1.29 sits behind the purchase. "
    "It affects only the background artwork, its colour palette and the results-screen "
    "backdrop.\n\n"
    "WHERE TO FIND IT. Settings > \"The Road\" is one row and opens a screen listing both routes, "
    "with the purchase on it. That screen also states how far the tester still is from Kyoto. "
    "Restore Purchases is on the same screen and is always present, including for an account "
    "that already owns the item. Once lifetime distance passes Kyoto the menu's route strip also "
    "opens that screen. There is no modal, no badge, and nothing on the post-ride results "
    "screen.\n\n"
    "METADATA CHANGE IN THIS VERSION. One line of the description was corrected, in en-US and "
    "zh-Hans only. It read \"No account\"; with an in-app purchase that could be read as claiming "
    "a purchase needs no account, so it now says there is no sign-up and no account with the "
    "developer, and that the optional purchase is handled by the App Store through the customer's "
    "own Apple Account. The Japanese description already said registration is not required and "
    "was left unchanged. No keywords, URLs or other description text changed.\n\n"
    "Data handling is unchanged and the App Privacy declaration is unchanged (Data Not "
    "Collected). There is no analytics SDK, no advertising, and no developer-operated server in "
    "this app. The purchase is verified on device through StoreKit; the developer runs no receipt "
    "server and receives no identifiers. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed."
)
CONTACT = {"contactFirstName": "Yuhe", "contactLastName": "Ye",
           "contactPhone": "+81 80-3526-7088", "contactEmail": "yyyyy.yeyuhe@gmail.com"}


def asc(method, ep, body=None, allow_empty=False):
    """One ASC call. An empty or non-JSON response is a FAILURE, not an empty success.

    Every submit script from 1.10 to 1.21 returned `{}` here when the helper exited non-zero — a
    missing key, a locked keychain, a network blip. `{}` has no "errors" key, and every call site
    reads a missing "errors" key as OK, so a run in which nothing at all reached Apple printed OK
    at every step. Raising here means a broken run stops at the first call instead of
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
        # Exactly TWO calls here answer with no body on success: the PATCH on a version's build
        # relationship, and the POST that submits the in-app purchase. Every other endpoint
        # returns a payload, so an empty body from any of them is a failure that must not be read
        # as an empty success. Emptiness is permitted per call site, never globally.
        if allow_empty:
            return {}
        raise SystemExit(
            f"ASC returned an EMPTY body for {method} {ep}, which this call does not "
            "expect. Treating that as success is how a failed run reports OK twelve times.")
    try:
        return json.loads(out)
    except Exception:
        raise SystemExit(f"ASC returned non-JSON for {method} {ep}:\n{out[:400]}")


def detail(response):
    """The whole of what ASC said went wrong, not just the headline.

    ASC's `detail` is a summary and its `meta.associatedErrors` is the evidence, and they can say
    very different things. On 2026-08-31 the headline was *"This in-app purchase cannot be
    reviewed, please check associated errors."* — which names no error and reads like a dead end
    — while the SAME response body carried
    `STATE_ERROR.FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` and Apple's own sentence
    explaining the rule. Every submit script in this repo up to 1.29 prints `errors[0]['detail']`
    and discards the rest, so the fix belongs in one place rather than at each call site.
    """
    errors = response.get("errors") or []
    if not errors:
        return ""
    first = errors[0]
    parts = [str(first.get("detail") or first.get("title") or first.get("code"))]
    for _, associated in (first.get("meta", {}).get("associatedErrors") or {}).items():
        for a in associated:
            parts.append(f"[{a.get('code')}] {a.get('title') or a.get('detail')}")
    return " // ".join(parts)


# Every skip and every error lands here, and a non-empty ledger is a non-zero exit.
FAILURES = []


def fail(message):
    print(f"  FAIL: {message}")
    FAILURES.append(message)


SUBMITTABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
               "METADATA_REJECTED", "INVALID_BINARY"}


def submittable(vid, name):
    """True only if this version can still accept a build and a submission.

    A version that is READY_FOR_SALE, IN_REVIEW or WAITING_FOR_REVIEW must not be touched. The
    v1.15 run learned this by creating an uncancellable, undeletable empty submission against an
    already-live macOS version.
    """
    d = asc("GET", f"/v1/appStoreVersions/{vid}")
    state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
    if state in SUBMITTABLE:
        return True
    if state in {"READY_FOR_SALE", "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE"}:
        print(f"  {name}: version state is {state} — already submitted or live, nothing to do")
        return False
    fail(f"{name}: unrecognised version state {state!r} — refusing to guess")
    return False


def open_submission(platform):
    """An existing un-submitted reviewSubmission for this platform, if any.

    Reuse a container rather than POSTing a second one. Orphans accumulate precisely because
    every failed run leaves one behind that no API call can remove.
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
        # Recorded, not exited: aborting mid-loop skips the OTHER platform and, in --submit,
        # skips the read-back entirely — so a platform that HAD submitted would go unverified.
        fail(f"create version {VERSION}: {detail(r)}")
        return None
    vid = r["data"]["id"]
    print(f"  created version {VERSION}: {vid}")
    return vid


def localizations(vid):
    """{locale: id} for this version."""
    locs = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"
                      f"?fields[appStoreVersionLocalizations]=locale&limit=50").get("data", [])
    return {l["attributes"]["locale"]: l["id"] for l in locs}


def patch_localization(lid, locale, field, text):
    """PATCH one field and prove it landed, byte for byte.

    The response to a PATCH is not evidence that the text is what was sent — ASC silently
    truncates and normalises, and the star-glyph rejection lands here.
    """
    r = asc("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
        "type": "appStoreVersionLocalizations", "id": lid, "attributes": {field: text}}})
    if r.get("errors"):
        fail(f"{field} {locale}: {detail(r)}")
        return
    check = asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                       f"?fields[appStoreVersionLocalizations]={field}")
    stored = (check.get("data") or {}).get("attributes", {}).get(field)
    if stored != text:
        fail(f"{field} {locale}: stored text differs from what was sent "
             f"({len(stored or '')} chars vs {len(text)})")
    else:
        print(f"    {field} {locale}: OK ({len(text)} chars, read back identical)")


def set_whats_new(vid):
    by_locale = localizations(vid)
    # This loop asks "does every locale I WROTE have a destination". The other direction matters
    # more: a locale configured on the App Store that this script has no copy for is never
    # visited, so it silently ships the PREVIOUS version's What's New — claiming the last
    # release's changes as this one's.
    unwritten = sorted(set(by_locale) - set(WHATS_NEW))
    if unwritten:
        fail(f"App Store has locales this script writes no What's New for: {unwritten} "
             f"— they would keep the previous version's copy")
    for locale, text in WHATS_NEW.items():
        lid = by_locale.get(locale)
        if not lid:
            fail(f"no localization for {locale} (have {list(by_locale)}) — What's New unset")
            continue
        patch_localization(lid, locale, "whatsNew", text)


def edited_description(current, locale):
    """Apply this locale's one-sentence edit, or explain why it cannot be applied.

    Returns (new_text, note). `new_text` is None when nothing should be written, and `note` says
    which of the three cases that is — the distinction the whole design turns on:

      * the old sentence is present exactly once            -> edit
      * the NEW sentence is already there and the old is not -> already done, write nothing
      * anything else                                        -> FAILURE, refuse to guess

    A count of 0 with the new sentence absent means the paragraph was rewritten somewhere else,
    and quietly doing nothing there is how a listing keeps a claim that stopped being true.
    """
    old, new = DESCRIPTION_EDITS[locale]
    if current.count(new) == 1 and old not in current:
        return None, "already corrected in a previous run — read back and left alone"
    hits = current.count(old)
    if hits == 1:
        return current.replace(old, new), None
    if hits == 0:
        return None, ("FAIL: the sentence this edit expects is not in the live description, and "
                      "the corrected one is not there either. The paragraph was changed "
                      "elsewhere; re-read it and update DESCRIPTION_EDITS deliberately.")
    return None, (f"FAIL: the sentence this edit expects appears {hits} times; a replace would "
                  "touch more than the one line it was written for.")


def set_descriptions(vid):
    """Correct one line per locale, surgically, and read the whole description back."""
    by_locale = localizations(vid)
    for locale in DESCRIPTION_EDITS:
        lid = by_locale.get(locale)
        if not lid:
            fail(f"no localization for {locale} — description not corrected")
            continue
        cur = asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                         f"?fields[appStoreVersionLocalizations]=description")
        current = ((cur.get("data") or {}).get("attributes") or {}).get("description") or ""
        new_text, note = edited_description(current, locale)
        if new_text is None:
            if note and note.startswith("FAIL"):
                fail(f"description {locale}: {note[6:]}")
            else:
                print(f"    description {locale}: {note}")
            continue
        if len(new_text) > 4000:
            fail(f"description {locale}: {len(new_text)} chars, over the 4000 limit")
            continue
        patch_localization(lid, locale, "description", new_text)
    untouched = sorted(set(by_locale) - set(DESCRIPTION_EDITS))
    if untouched:
        # Not a failure. Said out loud because "we corrected the description" must never be
        # heard as "in every locale" — ja is deliberately not edited; see DESCRIPTION_EDITS.
        print(f"    description: {untouched} deliberately not edited (see DESCRIPTION_EDITS)")


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
    if r.get("errors"):
        fail(f"review detail: {detail(r)}")
        return
    # Read back, for the same reason: App Review reads these notes, and a version that reaches
    # them with the PREVIOUS release's notes describes work that is not in this build.
    back = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    stored = ((back.get("data") or {}).get("attributes") or {}).get("notes")
    if stored != REVIEW_NOTES:
        fail(f"review detail: stored notes differ from what was sent "
             f"({len(stored or '')} chars vs {len(REVIEW_NOTES)})")
    else:
        print(f"  review detail: OK ({len(REVIEW_NOTES)} chars, read back identical)")


def find_build(platform, num):
    """Match by build number AND platform — build numbers are per-platform, so mac 54 and iOS 54
    can coexist; resolve each candidate's platform via its preReleaseVersion."""
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


# --- the in-app purchase --------------------------------------------------------------------
#
# States an IAP can be in, split by what this script must do about each. Anything outside both
# sets is a state this script does not understand, and continuing past it is how a run submits
# nothing and exits 0.
IAP_READY = {"READY_TO_SUBMIT"}
IAP_ALREADY_IN = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL", "APPROVED",
                  "READY_FOR_SALE"}


def iap_state():
    d = asc("GET", f"/v2/inAppPurchases/{IAP_ID}"
                   f"?fields[inAppPurchases]=state,productId,inAppPurchaseType,familySharable")
    return (d.get("data") or {}).get("attributes", {})


def iap_version_id():
    """The reviewable unit of an in-app purchase, which is NOT the purchase itself.

    `reviewSubmissionItems` takes an `inAppPurchaseVersion` relationship pointing here. Asking it
    for an `inAppPurchase` or an `inAppPurchaseV2` gets `RELATIONSHIP.UNKNOWN`, which is what led
    the first version of this script to the wrong endpoint entirely.
    """
    d = asc("GET", f"/v2/inAppPurchases/{IAP_ID}/versions?limit=10")
    versions = d.get("data") or []
    if len(versions) != 1:
        fail(f"expected exactly one inAppPurchaseVersion, found {len(versions)} — refusing to "
             "guess which one App Review should see")
        return None
    return versions[0]["id"]


def stage_iap(sid, name):
    """Put the purchase into an OPEN review submission. Returns True if it is in one.

    Apple requires an app's first non-consumable to be reviewed with a version, and this is the
    only way to express that: `POST /v1/inAppPurchaseSubmissions` refuses it with
    `FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` regardless of when it is called.
    """
    attrs = iap_state()
    if attrs.get("productId") != IAP_PRODUCT_ID:
        fail(f"IAP {IAP_ID} has productId {attrs.get('productId')!r}, expected "
             f"{IAP_PRODUCT_ID!r} — refusing to stage a product this script cannot identify")
        return False
    state = attrs.get("state")
    if state in IAP_ALREADY_IN:
        print(f"  IAP is already {state} — not staged again")
        return True
    if state not in IAP_READY:
        fail(f"IAP state is {state!r}, which is neither submittable nor already submitted "
             "— refusing to guess (MISSING_METADATA means a required field or the review "
             "screenshot is absent)")
        return False
    vid = iap_version_id()
    if not vid:
        return False
    r = asc("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "inAppPurchaseVersion": {"data": {"type": "inAppPurchaseVersions", "id": vid}}}}})
    if r.get("errors"):
        # Not a failure by itself: one purchase can only be an item in ONE submission, so the
        # second platform is EXPECTED to be refused. The caller decides, because only it knows
        # whether the purchase is already carried somewhere.
        print(f"  IAP not staged on {name}: {detail(r)}")
        return False
    print(f"  IAP staged on {name} (item {r['data']['id'][:12]}…)")
    return True


def do_metadata():
    for t in TARGETS:
        print(f"\n===== {t['name']} metadata =====")
        vid = ensure_version(t["platform"])
        if not vid:
            continue
        set_whats_new(vid)
        set_descriptions(vid)
        set_review_detail(vid)


def do_submit():
    """Attach, stage, then submit — and submit NOTHING unless the purchase is accounted for.

    The ordering is the safety property and it lives here rather than in a comment. The first run
    of this script had it in prose only: the purchase failed, the guard was not in the control
    flow, and both platforms went to Apple carrying release notes for a purchase nobody could
    make. Both submissions had to be cancelled and rebuilt.
    """
    # PHASE 1 — attach every build. The attach is the real gate; a submission container created
    # after a failed attach is exactly how the v1.15 orphan came to exist.
    attached = {}
    for t in TARGETS:
        print(f"\n===== {t['name']} attach (build {t['build_num']}) =====")
        vid = find_version(t["platform"])
        if not vid:
            print(f"  !! no {VERSION} version — run --metadata first"); sys.exit(1)
        if not submittable(vid, t["name"]):
            continue
        bid, battr = find_build(t["platform"], t["build_num"])
        if not bid:
            print(f"  !! {t['name']} build {t['build_num']} not found"); sys.exit(1)
        if battr.get("processingState") != "VALID":
            print(f"  !! build {t['build_num']} state={battr.get('processingState')} (not VALID)")
            sys.exit(1)
        print(f"  build {bid} VALID")
        if battr.get("usesNonExemptEncryption") is None:
            asc("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                "attributes": {"usesNonExemptEncryption": False}}})
        r = asc("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": bid}}, allow_empty=True)
        if r.get("errors"):
            fail(f"{t['name']}: attach build — {detail(r)}")
            continue
        print("  attach build: OK")
        attached[t["name"]] = vid

    # PHASE 2 — build the containers and their items, and submit NONE of them yet.
    #
    # The purchase goes into whichever container will take it: it is app-level under Universal
    # Purchase, so exactly one submission carries it and the other is refused. `carried` is what
    # phase 3 checks, and it is a fact read back from Apple rather than an intention.
    staged = {}
    carried = iap_state().get("state") in IAP_ALREADY_IN
    for t in TARGETS:
        vid = attached.get(t["name"])
        if not vid:
            continue
        print(f"\n===== {t['name']} stage =====")
        sid = open_submission(t["platform"])
        if sid:
            print(f"  reusing open submission {sid}")
        else:
            sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                      "attributes": {"platform": t["platform"]},
                      "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
            if sub.get("errors"):
                fail(f"{t['name']}: create submission — {detail(sub)}"); continue
            sid = sub["data"]["id"]
            print(f"  created submission {sid}")
        it = add_item(sid, vid)
        if it.get("errors"):
            fail(f"{t['name']}: no version item attached — {detail(it)}")
            continue
        print("  version item: OK")
        if not carried:
            carried = stage_iap(sid, t["name"])
        staged[t["name"]] = sid

    # PHASE 3 — the gate, in code. A version may go to Apple only once the purchase it advertises
    # is accounted for.
    if not carried:
        fail("the in-app purchase is in no review submission, so NOTHING was submitted — "
             "v1.30's release notes describe a purchase that would not exist")
        return
    if len(staged) != len(attached):
        fail(f"only {sorted(staged)} could be staged out of {sorted(attached)} — submitting a "
             "subset would split the release across two reviews")
        return

    for t in TARGETS:
        sid = staged.get(t["name"])
        if not sid:
            continue
        print(f"\n===== {t['name']} submit =====")
        fin = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions",
                  "id": sid, "attributes": {"submitted": True}}})
        if fin.get("errors"):
            fail(f"{t['name']}: submit — {detail(fin)}")
            continue
        print(f"  SUBMIT: OK ({fin['data']['attributes']['state']})")

    # --- read everything BACK ------------------------------------------------------------
    #
    # Every step above reports on the response to its own call. This asks Apple, afterwards,
    # what state things are in.
    print("\n===== reading back =====")
    for t in TARGETS:
        vid = find_version(t["platform"])
        if not vid:
            fail(f"{t['name']}: version {VERSION} is gone after submitting"); continue
        d = asc("GET", f"/v1/appStoreVersions/{vid}")
        state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
        expected = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE"}
        mark = "OK" if state in expected else "NOT SUBMITTED"
        print(f"  {t['name']}: {state} [{mark}]")
        if state not in expected:
            fail(f"{t['name']}: after submitting, state is {state!r}, not a submitted state")
    final_iap = iap_state().get("state")
    iap_ok = final_iap in IAP_ALREADY_IN
    print(f"  IAP {IAP_PRODUCT_ID}: {final_iap} [{'OK' if iap_ok else 'NOT SUBMITTED'}]")
    if not iap_ok:
        fail(f"the in-app purchase is {final_iap!r} after this run — the version would ship "
             "release notes describing a purchase nobody can make")


def report():
    """Non-zero if anything at all went wrong. The whole point of the ledger."""
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILURE(S):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nclean.")
    return 0


def do_dry_run():
    """Print the derived copy and the exact description diff WITHOUT touching Apple.

    The description half reads the LIVE text, because the whole point of a surgical edit is that
    the result depends on what is actually there — a dry run that showed a diff against a
    hardcoded "before" would be checking this file against itself.
    """
    print(f"VERSION {VERSION}")
    for t in TARGETS:
        print(f"  {t['name']:6s} platform={t['platform']:6s} build={t['build_num']}")
    print("\nderived numbers:")
    for k, v in N.items():
        print(f"  {k:24s} {v}")
    for locale, text in WHATS_NEW.items():
        print(f"\n--- What's New [{locale}] ({len(text)} chars) ---\n{text}")
    print(f"\n--- Review notes ({len(REVIEW_NOTES)} chars) ---\n{REVIEW_NOTES}")

    print("\n--- description edits, against the LIVE en-US/zh-Hans/ja text ---")
    for t in TARGETS:
        vid = find_version(t["platform"])
        if not vid:
            # Expected before --metadata: the 1.30 versions do not exist yet, so compare against
            # what is live now, which is what 1.30 will inherit.
            d = asc("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]={t['platform']}"
                           f"&limit=1&fields[appStoreVersions]=versionString")
            data = d.get("data") or []
            if not data:
                print(f"  {t['name']}: no version to read"); continue
            vid = data[0]["id"]
            print(f"  {t['name']}: 1.30 does not exist yet; reading "
                  f"{data[0]['attributes']['versionString']}, which it will inherit from")
        by_locale = localizations(vid)
        for locale in sorted(by_locale):
            lid = by_locale[locale]
            cur = asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                             f"?fields[appStoreVersionLocalizations]=description")
            current = ((cur.get("data") or {}).get("attributes") or {}).get("description") or ""
            if locale not in DESCRIPTION_EDITS:
                print(f"  {t['name']} {locale}: NOT EDITED by design ({len(current)} chars)")
                continue
            new_text, note = edited_description(current, locale)
            if new_text is None:
                print(f"  {t['name']} {locale}: {note}")
                continue
            old, new = DESCRIPTION_EDITS[locale]
            print(f"  {t['name']} {locale}: {len(current)} -> {len(new_text)} chars")
            print(f"      - {old}")
            print(f"      + {new}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--metadata":
        do_metadata()
    elif mode == "--submit":
        do_submit()
    elif mode == "--dry-run":
        do_dry_run()
        sys.exit(0)
    else:
        print(__doc__); sys.exit(2)
    sys.exit(report())
