#!/usr/bin/env python3
"""Create the 1.32 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py` across eleven scenarios. Every previous `submit_<version>.py` is
left exactly as it was — they are the record of what was actually sent.

WHAT 1.32 IS, and it is an unusually honest answer
--------------------------------------------------
**One new thing a learner sees, three fixes they will notice, and a lot they will not.** Most of
this release is test infrastructure, release gates and measurement work, which does not belong in
What's New and is not there.

  * **"What you keep missing."** The app has recorded which kana a learner is refused on since
    v1.18 and has thrown the record away at the end of every ride. It now keeps a local, bounded
    tally and shows the ones that recur across separate sittings, on the Stats screen, with the
    rule behind the worst of them. Never transmitted; not synced.
  * **The first-launch intro said "Three modes". Six ship.** Verbs, Sentence and Listen have been
    advertised nowhere a new user would look since v1.6, v1.18 and v1.21 respectively.
  * **The Ride Log was unreadable at the accessibility text sizes.** Not "ran off the edge" — at
    AX5 each column squeezed to about one glyph and every value wrapped vertically: "MINE" as four
    stacked letters, "100%" as 1/0/0/% with the % off the edge. The title and the Back button were
    clipped off both screen edges. Both fixed and verified on a device.
  * **A conjugation card the drill could never build a prompt for** counted toward the menu
    button, the badge, the reminder, the widget and the Stats forecast — six readouts promising
    work no review could clear.

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No purchase change of any kind.** The non-consumable is APPROVED and live and this release does
not touch it: same product, same price, same content, same two placements. Verified against the
live API rather than assumed — both platforms were READY_FOR_SALE at 1.31 with the purchase
APPROVED when this was written.

**No description edit.** `STATE`'s habit is to re-read the privacy paragraph whenever a capability
touching the network or an account ships. v1.32 adds a new PERSISTED record (the stumble tally),
so the paragraph was re-read against it: the tally is a local file in the app's own container, is
not synced to iCloud, is not exported, and reaches no server. Every sentence in the paragraph
stays true, and `Data Not Collected` is unchanged.

**No keyword, title, subtitle or screenshot change**, which is the measurement window's clause
about which devices arrive.

**The store description still says "THREE WAYS TO RIDE"**, which has the same defect the intro
had. It is not corrected here: `PLAN-WINDOW` constraint 4 freezes en-US / zh-Hans / ja store
metadata for the window, and the in-app copy is the half the window permits. Recorded rather than
overlooked.

Three phases:
  python3 scripts/submit_1_32.py --dry-run  --platform=both   # print the copy, touch nothing
  python3 scripts/submit_1_32.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_32.py --submit   --platform=both   # attach builds (mac 56 / iOS 57)

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
Uploading builds is fine at any time; this is the step that blocks.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import numbers            # noqa: E402

VERSION = "1.32"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "56"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "57"},
]

# Measured, never typed. v1.25's What's New said "fifty more sentences" against a measured 42.
N = numbers()

# What's New — no star glyph (preflight enforces it).
#
# Same voice as every release since v1.27: report what changed, never solicit. v1.32 sells
# nothing, so there is no price here and nothing to act on.
#
# Four bullets for four things a learner can actually notice. The release's other ~4,000 lines are
# tests, gates and measurement, and a What's New that listed them would be describing work rather
# than reporting a change.
WHATS_NEW = {
    "en-US": (
        "• A new Stats card: what you keep missing. The app has always known which kana refused "
        "your keystrokes during a ride, and always forgot at the end of it. It now keeps a "
        "running tally and shows the ones that come back across different days, with the rule "
        "behind the worst of them. It stays on your device.\n"
        "• The first-launch intro now names all six modes. Verbs, Sentence and Listen were in the "
        "app and mentioned nowhere a new rider would look.\n"
        "• The Ride Log is readable at the large accessibility text sizes. Every column used to "
        "squeeze until the values wrapped one letter per line, and the title and Back button ran "
        "off the edges of the screen.\n"
        "• A conjugation card the drill could not actually build a prompt for no longer counts "
        "toward the review button, the badge, the reminder, the widget or the forecast. It made "
        "all six promise work that no review could clear."
    ),
    "zh-Hans": (
        "• 统计页新增一张卡片:你反复卡住的假名。app 一直知道骑行中哪个假名拒绝了你的按键,"
        "也一直在骑行结束时把它忘掉。现在它会累计记录,并显示那些跨天反复出现的,"
        "以及其中最顽固那个背后的规则。这些只留在你的设备上。\n"
        "• 首次启动的介绍现在会说全六种模式。变形、例句、听写一直在 app 里,"
        "却没有出现在任何新用户会看的地方。\n"
        "• 骑行日志在超大字号下可读了。此前每一列都会被挤压到数值逐字换行,"
        "标题和返回按钮也会跑出屏幕两边。\n"
        "• 一张练习无法为其生成题目的变形卡片,不再计入复习按钮、角标、提醒、小组件和预报。"
        "此前这六处都在承诺一份任何复习都清不掉的任务。"
    ),
    # The app's interface is English or Chinese only, so the Japanese copy names what a Japanese
    # rider actually sees on screen.
    "ja": (
        "• 統計画面に新しいカードが加わりました。「よくつまずく仮名」です。"
        "どの仮名で入力が弾かれたかは以前から記録していましたが、ライドが終わるたびに"
        "捨てていました。これからは積み重ねて、日をまたいで繰り返し出てくるものと、"
        "その中でいちばん多いものの理由を表示します。記録は端末内にとどまります。\n"
        "• 初回起動時の説明が、6 つのモードすべてを挙げるようになりました。活用・例文・聞き取りは"
        "アプリの中にありながら、新しい方の目に触れる場所には書かれていませんでした。\n"
        "• 大きな文字サイズでもライドログが読めるようになりました。これまでは各列が潰れて"
        "数値が 1 文字ずつ折り返し、タイトルと戻るボタンも画面の外にはみ出していました。\n"
        "• ドリルが問題を作れない活用カードが、復習ボタン・バッジ・リマインダー・ウィジェット・"
        "予報のいずれにも数えられなくなりました。どの復習でも消せない課題を、"
        "6 か所すべてが示していました。"
    ),
}

# No description edit this release — see the module docstring, including the privacy paragraph
# having been re-read against the new persisted record rather than assumed unchanged.
DESCRIPTION_EDITS = {}

# --- One set of notes, because for the first time since 1.30 the two platforms are the same ----
#
# 1.31 needed two: iOS was live and carried no purchase while macOS carried the app's first one.
# That is over — both platforms are READY_FOR_SALE at 1.31 and the purchase is APPROVED, verified
# against the live API rather than remembered. 1.32 changes nothing about it on either platform,
# so there is one truth and one set of notes.
REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.32 ADDS NO IN-APP PURCHASE AND CHANGES NONE. The existing non-consumable "
    "com.jasonye.nihongoride.scenery.lifetime is approved and live and is untouched by this "
    "version: same product identifier, same price, same content, and the same two placements "
    "(Settings > \"The Road\", plus the menu's route strip once lifetime distance passes Kyoto). "
    "Restore Purchases is on the same screen and is always present, including for an account "
    "that already owns the item. There is no modal, no badge, and nothing on the post-ride "
    "results screen.\n\n"
    "WHAT IS NEW.\n"
    "1) A NEW STATS CARD, \"WHAT YOU KEEP MISSING\". The app already recorded, during a ride, "
    "which kana a keystroke was refused on; that record was discarded when the ride ended. This "
    "version keeps a small running tally of it and shows the kana that recur across separate "
    "sessions. The tally is a local file in the app's own container. It is NOT transmitted, NOT "
    "synced to iCloud, NOT exported, and reaches no server of any kind. It contains kana and "
    "counts, no text the user wrote and no identifiers. The App Privacy declaration is unchanged "
    "(Data Not Collected).\n"
    "2) The first-launch introduction now names all six practice modes instead of three. This is "
    "in-app copy only; no store metadata changed.\n"
    "3) ACCESSIBILITY FIX. At the larger Dynamic Type sizes the Ride Log's rows became "
    "unreadable - each column squeezed until its value wrapped one character per line - and the "
    "screen title and Back button were clipped at both edges. The rows now stack at those sizes "
    "and the header does too, so the Back control is reachable. This was verified on an iPhone "
    "at the largest accessibility text size.\n"
    "4) A conjugation review card that the drill could not build a prompt for was still counted "
    "by the review button, the app icon badge, the daily reminder, the home-screen widget and "
    "the Stats forecast. All six promised work that no review could clear. They now share one "
    "predicate with the drill itself.\n\n"
    "Data handling is unchanged. There is no analytics SDK, no advertising, and no "
    "developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Both platforms move together this release --------------------------------
#
# 1.31 had to ship them apart: macOS 1.30 was IN_REVIEW and ASC refuses --metadata on a platform
# with a version in review. Neither platform has a version in review now — checked against the
# live API, not remembered — so `--platform=both` is available and is the right call, because the
# two are shipping identical code with identical review notes.
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
    print("==> review notes: one set — 1.32 changes the purchase on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
