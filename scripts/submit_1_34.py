#!/usr/bin/env python3
"""Create the 1.34 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py`. Every previous `submit_<version>.py` is left exactly as it was — they
are the record of what was actually sent.

WHAT 1.34 IS
------------
**The ride ends by saying what comes next, and five smaller things that were wrong.** Scope and
evidence: `docs/PLAN-V1.34.md` §B and its release record.

  * The results screen at the end of a ride now says the streak (from two days) and how many words and
    forms will be due tomorrow — today's unreviewed cards plus tomorrow's — from the reads the Ride Log
    already makes; only after a ride that was recorded, so not after a cram. Text only: no button, no
    prompt (§B1).
  * At the accessibility text sizes the ride's status bar hides some pills (since 1.33); VoiceOver now
    hears their values on the progress pill, which every row draws (§B3).
  * A long sentence's romaji hint wraps instead of being cut off with "…" (§B5).
  * A paste over 200 sentences or 20,000 characters says what is kept and dropped instead of being cut
    silently; a pasted text can be deleted from its context menu on every platform — on the Mac it could
    not be deleted at all before (§B2).
  * About's small grey text reaches 4.5:1 contrast (§B4).

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No change to the purchase, its code, its screen or its placements** (`RouteStore.swift`,
`RoadView.swift`, the Settings road card and the menu route strip are untouched — `git diff` checked
before submission). The offer, its price, its placement and its presentation are frozen for the
pre-registered observation window (`PLAN-WINDOW` constraint 1).

**No description, keyword, title, subtitle or screenshot change** (`PLAN-WINDOW` constraint 4).
What's New is version text, not listing metadata. No new persisted record, no new network use, so the
privacy paragraph and `Data Not Collected` are unchanged.

Three phases:
  python3 scripts/submit_1_34.py --dry-run  --platform=both   # print the copy, touch nothing
  python3 scripts/submit_1_34.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_34.py --submit   --platform=both   # attach builds

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import numbers            # noqa: E402

VERSION = "1.34"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "58"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "59"},
]

# Measured, never typed. This release's copy quotes no corpus number.
N = numbers()

# What's New — no star glyph (preflight enforces it). Same voice as every release since v1.27:
# report what changed, never solicit. Each sentence is checked against the code it describes
# before this is sent (PLAN-V1.34 §G item 6).
WHATS_NEW = {
    "en-US": (
        "• The screen at the end of a ride now tells you your streak and how many words and verb "
        "forms will be due for review tomorrow.\n"
        "• With VoiceOver at the accessibility text sizes, the ride's progress now also reads out "
        "the numbers the status bar hides at those sizes.\n"
        "• A long sentence's romaji hint now wraps onto a second line instead of being cut off.\n"
        "• My text: pasting more than 200 sentences or 20,000 characters now tells you how much is "
        "kept and how much is left out, and a text can be deleted from its context menu "
        "(right-click on a Mac, where it could not be deleted before; touch and hold on iPhone and "
        "iPad).\n"
        "• The small grey text on the About page is easier to read."
    ),
    "zh-Hans": (
        "• 骑行结束时的结果页,现在会告诉你连续骑行了几天,以及明天有多少个词和变形需要复习。\n"
        "• 在辅助功能的超大字号下使用旁白(VoiceOver)时,骑行进度现在也会读出顶部信息栏在这些字号下隐藏的数字。\n"
        "• 长句子的罗马字提示现在会换到第二行显示,不再被截断。\n"
        "• 我的文本:粘贴超过 200 句或 20,000 个字符时,现在会说明保留了多少、去掉了多少;"
        "也可以从文本的快捷菜单删除它(Mac 上右键点按,此前在 Mac 上无法删除;iPhone 和 iPad 上长按)。\n"
        "• 关于页的灰色小字更易读了。"
    ),
    # The app's interface is English or Chinese only, so a Japanese rider sees the English labels;
    # the Japanese copy quotes them in 「」 where it names a screen.
    "ja": (
        "• ライドの終わりの結果画面に、連続日数と、明日復習する単語と活用の数が表示されるようになりました。\n"
        "• アクセシビリティの大きな文字サイズで VoiceOver を使うとき、ライドの進み具合と一緒に、"
        "そのサイズで上部表示から隠れる数字も読み上げるようになりました。\n"
        "• 長い文のローマ字ヒントが、途中で切れずに 2 行目に折り返して表示されるようになりました。\n"
        "• 「My text」:200 文または 20,000 文字を超えて貼り付けたとき、残る量と外れる量を表示します。"
        "テキストはコンテキストメニューから削除できます(Mac では右クリック。これまで Mac では削除できませんでした。"
        "iPhone と iPad では長押し)。\n"
        "• 「About & Credits」画面の小さな灰色の文字が読みやすくなりました。"
    ),
}

# No description edit — see the module docstring.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.34 ADDS NO IN-APP PURCHASE AND DOES NOT CHANGE THE EXISTING ONE: its product, "
    "price, content, screen, placements and purchase code are unchanged from 1.33. The existing "
    "non-consumable com.jasonye.nihongoride.scenery.lifetime is approved and live, in the same two "
    "placements (Settings > \"The Road\", plus the menu's route strip once lifetime distance passes "
    "Kyoto). Restore Purchases is on the same screen and is always present. There is no modal, no "
    "badge, and nothing about the purchase on the post-ride results screen.\n\n"
    "WHAT IS NEW.\n"
    "1) After a ride that is recorded, the post-ride results screen shows one new line of text: the "
    "user's streak (from two days) and how many review cards will be due tomorrow. It is text only, "
    "with no button, link or prompt.\n"
    "2) ACCESSIBILITY. At the largest Dynamic Type sizes the ride's status bar hides some items to "
    "keep the pause button on screen (since 1.33); VoiceOver now reads their values as part of the "
    "progress item. A long sentence's romaji hint wraps instead of being truncated. The About "
    "page's small grey text has higher contrast.\n"
    "3) The user's own pasted texts: a paste over the length limits now says what was kept and "
    "dropped, and a text can be deleted from its context menu on every platform (on macOS it could "
    "not be deleted before).\n\n"
    "Data handling is unchanged. There is no analytics SDK, no advertising, and no "
    "developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Both platforms move together, as 1.33 did ------------------------------------------------
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
    print("==> review notes: one set — 1.34 changes the purchase a customer sees on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
