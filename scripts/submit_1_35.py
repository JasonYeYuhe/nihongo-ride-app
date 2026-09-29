#!/usr/bin/env python3
"""Create the 1.35 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py`. Every previous `submit_<version>.py` is left exactly as it was — they
are the record of what was actually sent.

WHAT 1.35 IS
------------
**Corrective first, then one feature** (the owner's v1.35 decision of 2026-09-29, `docs/PLAN-V1.34.md`
§F, after Codex and Gemini 3.8 Flash were consulted). Scope and evidence: that addendum and each
step's dated record.

  * Word Lists: a list's screen searches the whole dictionary (writing, reading, romaji, gloss) and
    adds a result with one tap (§B6).
  * Pasted texts: over a cap, the notice leads with the counts and Add asks before storing the cut
    text; VoiceOver announces the notice (step 2).
  * Corpus: `correctedThisRelease` entries corrected by evidence (the v1.35 residue manifest), and 18
    Practice translations that showed a tripled apostrophe (step 1, passages.json — not in the
    manifest).
  * Accessibility: the iPad ride HUD no longer splits a value across lines in narrow windows (step
    4b); the Verbs drill speaks the score it hides at the accessibility sizes (step 3); the results
    screen's small panel text meets 4.5:1 and the tomorrow line keeps four-digit counts whole (step 4).

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No change to the purchase, its code, its screen or its placements** (`RouteStore.swift`,
`RoadView.swift`, the Settings road card and the menu route strip are untouched — `git diff` checked
before submission). The offer, its price, its placement and its presentation are frozen for the
pre-registered observation window (`PLAN-WINDOW` constraint 1).

**No description, keyword, title, subtitle or screenshot change** (`PLAN-WINDOW` constraint 4).
What's New is version text, not listing metadata. No new persisted record beyond the words a rider
adds to a list (the existing list store and its sync), no new network use, so the privacy paragraph
and `Data Not Collected` are unchanged.

Three phases:
  python3 scripts/submit_1_35.py --dry-run  --platform=both   # print the copy, touch nothing
  python3 scripts/submit_1_35.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_35.py --submit   --platform=both   # attach builds

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import numbers            # noqa: E402

VERSION = "1.35"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "60"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "61"},
]

# Measured, never typed.
N = numbers()
FIXED = N["correctedThisRelease"]

# What's New — no star glyph (preflight enforces it). Same voice as every release since v1.27:
# report what changed, never solicit. Each sentence is checked against the code it describes
# before this is sent (PLAN-V1.34 §G item 6).
WHATS_NEW = {
    "en-US": (
        "• Word Lists: search the whole dictionary from a list — by kanji, kana, romaji or meaning — "
        "and add a word with one tap.\n"
        "• My text: when a paste is over the limit (200 sentences or 20,000 characters), the notice "
        "now leads with the counts, and Add asks before saving the shortened text. VoiceOver reads "
        "the notice.\n"
        f"• Corrected {FIXED} dictionary entries, mostly readings you type in example sentences "
        "(何を is now read なにを), and fixed stray apostrophes in 18 English translations of Practice "
        "passages.\n"
        "• iPad: when the status bar at the top of a ride runs out of room, it no longer splits a "
        "number across two lines. It tightens first, then leaves out the least-needed items, which "
        "VoiceOver still reads.\n"
        "• With VoiceOver at the accessibility text sizes, the Verbs drill now reads out the score its "
        "status bar hides. Small text on the results screen has a little more contrast."
    ),
    "zh-Hans": (
        "• 词单:现在可以在词单里搜索整个词库(汉字、假名、罗马字或释义都可以),点一下就能加入。\n"
        "• 我的文本:粘贴超过上限(200 句或 20,000 个字符)时,提示会先给出数量;点「添加」时会先确认,"
        "再保存截短后的文本。旁白(VoiceOver)会读出这条提示。\n"
        f"• 更正了 {FIXED} 个词条,主要是例句里需要输入的读音(例如「何を」现在读作 なにを);"
        "并修正了 18 条练习段落英文译文里多余的撇号。\n"
        "• iPad:骑行顶部的信息栏空间不够时,不再把数字拆成两行——会先收紧间距,再省略次要的项目,"
        "旁白仍会读出它们。\n"
        "• 在辅助功能的超大字号下使用旁白时,「变形」练习现在也会读出信息栏隐藏的分数。"
        "结果页小字的对比度略有提高。"
    ),
    # The app's interface is English or Chinese only, so a Japanese rider sees the English labels;
    # the Japanese copy quotes them in 「」 where it names a screen.
    "ja": (
        "• 「Word Lists」:リストの画面から辞書全体を検索できるようになりました(漢字・かな・ローマ字・意味)。"
        "ワンタップで追加できます。\n"
        "• 「My text」:貼り付けが上限(200 文または 20,000 文字)を超えたとき、残る数と外れる数を先に表示し、"
        "「Add」は短くしたテキストを保存する前に確認するようになりました。このメッセージは VoiceOver でも"
        "読み上げます。\n"
        f"• {FIXED} 件の単語データを訂正しました。主に例文で入力する読み(「何を」は なにを)です。"
        "「Practice」の文章の英訳 18 件にあった余分なアポストロフィも直しました。\n"
        "• iPad:ライドの上部表示に入りきらないとき、数字を 2 行に分けなくなりました。"
        "まず間隔を詰め、それでも入らないときは優先度の低い項目を省きます(VoiceOver では読み上げます)。\n"
        "• アクセシビリティの大きな文字サイズで VoiceOver を使うとき、「Verbs」ドリルでも上部表示から"
        "隠れるスコアを読み上げるようになりました。結果画面の小さな文字のコントラストも少し上げました。"
    ),
}

# No description edit — see the module docstring.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.35 ADDS NO IN-APP PURCHASE AND DOES NOT CHANGE THE EXISTING ONE: its product, "
    "price, content, screen, placements and purchase code are unchanged from 1.34. The existing "
    "non-consumable com.jasonye.nihongoride.scenery.lifetime is approved and live, in the same two "
    "placements (Settings > \"The Road\", plus the menu's route strip once lifetime distance passes "
    "Kyoto). Restore Purchases is on the same screen and is always present. There is no modal, no "
    "badge, and nothing about the purchase on the post-ride results screen.\n\n"
    "WHAT IS NEW.\n"
    "1) Word Lists: a list's screen has a \"Search the dictionary\" button. It searches the app's "
    "bundled word list on the device (no network) and adds a result to that list.\n"
    "2) The user's own pasted texts: over the length limits, Add now asks for confirmation before "
    "saving the shortened text (Cancel saves nothing), and VoiceOver announces the notice.\n"
    f"3) Content: {FIXED} dictionary entries were corrected (mostly the readings of example "
    "sentences), and stray apostrophes were removed from 18 English translations of practice "
    "passages.\n"
    "4) Accessibility and layout: on iPad, when space is short, the ride's status bar stays on one line "
    "(VoiceOver reads any item it leaves out); in the conjugation drill VoiceOver reads the score "
    "hidden at the largest text sizes; small text on the results screen has higher contrast.\n\n"
    "Data handling is unchanged. There is no analytics SDK, no advertising, and no "
    "developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Both platforms move together, as 1.34 did ------------------------------------------------
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
    print("==> review notes: one set — 1.35 changes the purchase a customer sees on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
