#!/usr/bin/env python3
"""Create the 1.33 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py`. Every previous `submit_<version>.py` is left exactly as it was — they
are the record of what was actually sent.

WHAT 1.33 IS
------------
**The app readable at the largest text sizes — everywhere except the purchase screen — and one
wrong screen fixed at every size.** Scope and evidence: `docs/PLAN-V1.33.md`.

  * At the accessibility text sizes the results screen, the ride and drill HUDs, the coach, Word
    Lists, the Ride Log, Stats, Practice, Settings and About broke words mid-letter ("Word / s",
    "Setting / s", "Saved" as "Save / d"), wrapped the progress pill ("0/1" over "2"), and clipped
    words off both screen edges. Measured with CoreText and seen on an iPhone simulator (402pt) at
    AX5, 2026-09-17. On iPad at those sizes the ride HUD now shows the phone's pill set (review
    round 2); iPad was measured with hosted layouts, not seen on an iPad simulator at AX5.
  * A ride or drill ended before anything was typed showed "You've arrived!" or "Drill complete!"
    with a grade and 100% accuracy. It now says the ride ended before its first word (or sentence, in
    the sentence and dictation modes), or the drill before its first answer, using the same rule the Ride Log already applied when it refused to
    record such a run.
  * Practice's labels are in Chinese in the Chinese interface. Settings' three small captions and
    About's on-device counter lines reach 4.5:1 contrast; About's footer, contact line and credit
    URLs and Settings' sync status do not yet (PLAN-V1.33 §G). A one-ride accuracy chart shows its
    point instead of nothing.

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**The purchase screen ("The Road") is NOT fixed, although it breaks the same way at AX5.** Its two
entrances are left exactly as they are: the Settings row already fits at AX5, and the menu's route strip
is already replaced by a sentence at the accessibility sizes. The offer, its price, its placement and its
presentation are frozen for the pre-registered observation window (`PLAN-WINDOW` constraint 1).
Deferred by name in `PLAN-V1.33.md` §C, to the first release after `PLAN-STAGE1` §K's decision fires.

**No change to what a customer is offered.** Same product, price, content, placements. The purchase
CODE was restructured (751a37a — `PLAN-V1.33.md` §D): each StoreKit answer is mapped by one pure,
tested function, with one behaviour change — a re-purchase after a refund this device recorded is
stamped after that refund even if the clock moved backwards. Said plainly in the review notes rather
than left for review to discover.

**No description, keyword, title, subtitle or screenshot change** (`PLAN-WINDOW` constraint 4).
What's New is version text, not listing metadata. No new persisted record, no new network use, so the
privacy paragraph and `Data Not Collected` are unchanged.

Three phases:
  python3 scripts/submit_1_33.py --dry-run  --platform=both   # print the copy, touch nothing
  python3 scripts/submit_1_33.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_33.py --submit   --platform=both   # attach builds

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import numbers            # noqa: E402

VERSION = "1.33"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "57"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "58"},
]

# Measured, never typed. This release's copy quotes no corpus number.
N = numbers()

# What's New — no star glyph (preflight enforces it).
#
# Same voice as every release since v1.27: report what changed, never solicit. The screens are
# NAMED rather than "everywhere", because the purchase screen was deliberately left out and
# "everywhere" would be false for a large-text customer who opens it.
WHATS_NEW = {
    "en-US": (
        "• Readable at the largest text sizes. With the accessibility text sizes on, the results "
        "screen, the ride and drill displays, the typing coach, Word Lists, the Ride Log, Stats, "
        "Practice, Settings and About used to break words mid-letter, wrap numbers onto a second "
        "line and push words off the edges of the screen. They now rearrange to fit.\n"
        "• A ride or drill that ends before you type anything no longer congratulates you with a "
        "grade and 100% accuracy. It says the ride ended before its first word or sentence, or the "
        "drill before its first answer.\n"
        "• Practice's labels now appear in Chinese when the app is in Chinese.\n"
        "• The small grey captions in Settings and the on-device counters in About are easier to "
        "read, and the accuracy chart shows your first ride instead of an empty chart."
    ),
    "zh-Hans": (
        "• 最大字号下也能读了。开启辅助功能的超大字号后,结果页、骑行和变形练习的顶部信息栏、"
        "打字教练、词单、骑行日志、统计、练习、设置和关于页,此前会把单词从字母中间断开、"
        "把数字挤到第二行、把文字推出屏幕边缘。现在它们会重新排布以适应屏幕。\n"
        "• 一个字都还没打就结束的骑行或变形练习,不再显示“到站”“完成”、评级和 100% 准确率,"
        "而是如实说明在第一个词、第一句或第一题之前就结束了。\n"
        "• 中文界面下,练习模式的标签现在显示为中文。\n"
        "• 设置页的灰色说明小字和关于页的本机计数更易读了;只骑过一次时,准确率图表会显示这一次,"
        "而不是一片空白。"
    ),
    # The app's interface is English or Chinese only, so the Japanese copy names what a Japanese
    # rider actually sees on screen.
    "ja": (
        "• 最大の文字サイズでも読めるようになりました。アクセシビリティの大きな文字サイズでは、"
        "結果画面、ライドとドリルの上部表示、タイピングコーチ、単語リスト、ライドログ、統計、"
        "練習、設定、情報の各画面で、単語が文字の途中で折り返されたり、数字が 2 行目に"
        "はみ出したり、文字が画面の端から押し出されたりしていました。"
        "今は画面に収まるように並び替えられます。\n"
        "• 何も入力しないうちに終えたライドやドリルで、「到着」「完了」の表示や評価、正確さ 100% が"
        "出なくなりました。最初の単語や文(ドリルでは最初の解答)の前に終わったことをそのまま表示します。\n"
        "• 中国語表示のとき、練習モードのラベルも中国語で表示されるようになりました。\n"
        "• 設定画面の小さな灰色の説明文と情報画面の端末内カウンターが読みやすくなり、1 回だけの"
        "ライドでも正確さのグラフにその 1 回が表示されるようになりました。"
    ),
}

# No description edit — see the module docstring.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.33 ADDS NO IN-APP PURCHASE AND DOES NOT CHANGE THE EXISTING ONE'S PRODUCT, PRICE, "
    "CONTENT, SCREEN OR PLACEMENTS. The existing "
    "non-consumable com.jasonye.nihongoride.scenery.lifetime is approved and live: same product "
    "identifier, same price, same content, and the same two placements (Settings > \"The Road\", "
    "plus the menu's route strip once lifetime distance passes Kyoto). Restore Purchases is on the "
    "same screen and is always present. There is no modal, no badge, and nothing on the post-ride "
    "results screen.\n\n"
    "One internal change to the purchase code, stated so it is not a surprise: the code that reads "
    "StoreKit's purchase result was restructured so that the meaning of each result (success, "
    "unverified, pending, cancelled, failed, unknown, product not loaded) is decided in one tested "
    "function. Every result produces the same message and the same outcome as in 1.32, with one "
    "exception: if this device had recorded a refund and its clock was later set backwards, buying "
    "again now unlocks immediately instead of waiting for the store's own entitlement list to "
    "confirm it.\n\n"
    "WHAT IS NEW.\n"
    "1) ACCESSIBILITY. At the larger Dynamic Type accessibility sizes, many screens broke words "
    "mid-letter, wrapped numbers onto a second line or pushed text off the screen edges: the "
    "results screen, the ride and drill status bars, the typing coach, Word Lists, the Ride Log, "
    "Stats, Practice, Settings and About. These screens now rearrange at those sizes; on iPad the "
    "ride status bar shows the same items as on iPhone at those sizes. At the default text size "
    "these screens are unchanged except where content did not fit its container: a long "
    "conjugation answer or typing-coach word now wraps inside its card instead of running past "
    "its edges. Checked on an iPhone simulator at the largest accessibility size in English and "
    "Chinese.\n"
    "2) A ride or conjugation drill ended before anything was typed used to show a success "
    "headline, a grade and 100% accuracy. It now says the run ended before its first word, "
    "sentence or answer, and offers no Share card for it.\n"
    "3) Practice mode's labels are translated in the Chinese interface; the small captions in "
    "Settings and the on-device counter lines in About have higher contrast; a one-ride accuracy "
    "chart draws its single point.\n\n"
    "Data handling is unchanged. There is no analytics SDK, no advertising, and no "
    "developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Both platforms move together, as 1.32 did ------------------------------------------------
#
# `--platform` stays REQUIRED. The failure it prevents is silent-looking: run it with a target
# that cannot move and that half dies partway through, after the other half has been written.
PLATFORM_ARG = {"ios": ("IOS",), "macos": ("MAC_OS",), "both": ("IOS", "MAC_OS")}


def _targets_for(argv):
    flags = [a for a in argv[1:] if a.startswith("--platform=")]
    if not flags:
        sys.exit("error: --platform=ios|macos|both is required. The two platforms have shipped "
                 "apart before and a default here is how the wrong one moves.")
    if len(flags) > 1:
        sys.exit(f"error: --platform given {len(flags)} times: {flags}")
    want = flags[0].split("=", 1)[1]
    if want not in PLATFORM_ARG:
        sys.exit(f"error: --platform={want} — expected one of {sorted(PLATFORM_ARG)}")
    keep = PLATFORM_ARG[want]
    return [t for t in TARGETS if t["platform"] in keep]


if __name__ == "__main__":
    _targets = _targets_for(sys.argv)
    print("==> review notes: one set — 1.33 changes the purchase a customer sees on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
