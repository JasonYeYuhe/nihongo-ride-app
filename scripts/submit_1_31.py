#!/usr/bin/env python3
"""Create the 1.31 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

**THE FIRST RELEASE WHOSE MACHINERY IS NOT IN THIS FILE.** Everything below is v1.31's
configuration; the 630 lines that used to be copied into each of these scripts now live in
`scripts/asc_release.py`, which was ported from `submit_1_30.py` and is held to it by
`scripts/test_asc_release.py` — both driven against one stateful fake App Store Connect across
eleven scenarios, required to make the same calls with the same bodies in the same order, plus a
live GET-only diff of both `--dry-run`s that came back identical over 73 lines.

Every previous `submit_<version>.py` is left exactly as it was. They are the record of what was
actually sent for each release, and `submit_1_30.py` is additionally the fixture the port is
tested against, so editing it would delete the evidence.

WHAT 1.31 IS
------------
Three things, all free, none of which touches the offer, the price or the placement:

  * **Practice over the learner's own Japanese.** Paste text in, check the readings the app
    worked out, correct any of them, then type it. On-device, never uploaded, and deliberately
    outside the SRS — a pasted word gets no review card, so nothing reaches CloudKit.
  * **The conjugation drill gets a clock.** Every clean answer used to be graded 5 because the
    session supplied no timing at all; a laboured form now grades 4 and stays in the rotation.
  * **A pause stops the word clock**, on the ride as well as the drill — it stopped the run's
    clock and not the word's, so a rider who paused mid-word was graded on the pause. And the
    ride HUD gains a live speed readout, reading the same `RunClock` the Ride Log records.

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No description edit.** The habit `STATE` records is to re-read the privacy paragraph whenever a
capability touching the network or an account ships — so it was re-read, against the LIVE text
rather than the repo's copy, and nothing in it became false: the learner's own text never leaves
the device, there is still no account with the developer, and the in-app purchase is unchanged.
A *marketing* mention of the new feature would be a different act with a conversion effect, and
the product/ASO session owns that surface.

**No keyword, title, subtitle or screenshot change**, which is the window's clause about which
devices arrive.

Three phases:
  python3 scripts/submit_1_31.py --dry-run    # print the derived copy, touch nothing
  python3 scripts/submit_1_31.py --metadata   # versions + What's New + review detail
  python3 scripts/submit_1_31.py --submit     # attach builds (mac 55 / iOS 56) + submit

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
Uploading builds is fine at any time; this is the step that blocks.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import numbers            # noqa: E402

VERSION = "1.31"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "55"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "56"},
]

# Measured, never typed. v1.25's What's New said "fifty more sentences" against a measured 42.
N = numbers()

# What's New — no star glyph (preflight enforces it now, for the first time since v1.5).
#
# Same voice as every release since v1.27: report what changed, never solicit. v1.31 sells
# nothing, so there is no price here and nothing to act on.
WHATS_NEW = {
    "en-US": (
        "• Practice your own Japanese. Paste in a song, a news item, a page of your textbook — "
        "the app works out the readings, shows them above the kanji, and you can correct any it "
        "gets wrong. Your text stays on your device and is never uploaded.\n"
        "• The conjugation drill now notices how long a form took you. Until now every clean "
        "answer scored the same, so the forms you laboured over left the review rotation as "
        "fast as the ones you knew cold. They now come back when they should.\n"
        "• Pausing stops the clock on the word you are typing, not just on the ride. A word "
        "interrupted by a pause, a sheet, or the app going to the background is no longer "
        "graded on the time you were away.\n"
        "• On a Mac or iPad the ride now shows your speed as you go, over ridden time — the "
        "same number the Ride Log records afterwards.\n"
        "• The menu's route strip now responds wherever you tap it. Only its text did before."
    ),
    "zh-Hans": (
        "• 练习你自己的日语。把歌词、新闻、课本的一页粘贴进来 —— app 会算出读音、标在汉字上方,"
        "读错的地方你可以自己改。你的文本只留在设备上,从不上传。\n"
        "• 活用练习现在会注意你用了多久。此前每个正确答案都是同一个分数,所以你费力想出来的形式"
        "和脱口而出的一样快地离开复习队列。现在它们会在该回来的时候回来。\n"
        "• 暂停时,正在打的这个词的计时也会停,而不只是整段骑行。被暂停、弹窗或切到后台打断的词,"
        "不再按你离开的时间计分。\n"
        "• Mac 和 iPad 上,骑行时会显示当前速度,按实际骑行时间计算 —— 和之后写进骑行记录的是"
        "同一个数。\n"
        "• 菜单上的路线条现在整块都可以点。此前只有上面的文字能点到。"
    ),
    # The app's interface is English or Chinese only, so the Japanese copy names what a Japanese
    # rider actually sees on screen.
    "ja": (
        "• 自分の日本語で練習できます。歌詞でも、ニュースでも、教科書の 1 ページでも、貼り付けると"
        "読みを推定して漢字の上に表示します。間違っているところは自分で直せます。"
        "貼り付けた文章は端末内にとどまり、送信されることはありません。\n"
        "• 活用ドリルが、答えるまでの時間を見るようになりました。これまでは正解であれば同じ評価"
        "だったため、苦労して思い出した形も、すぐ出てきた形と同じ速さで復習から外れていました。"
        "これからは戻ってくるべきときに戻ってきます。\n"
        "• 一時停止すると、いま入力中の単語の計測も止まります。一時停止・シート・バックグラウンド"
        "で中断された単語が、離れていた時間で評価されることはなくなりました。\n"
        "• Mac と iPad では、走行中の速度を表示するようになりました。実際に走った時間で計算する、"
        "あとでライドログに記録されるものと同じ数値です。\n"
        "• メニューのルート表示が、どこをタップしても反応するようになりました。"
        "これまでは文字の部分だけでした。"
    ),
}

# No description edit this release — see the module docstring for why, including the privacy
# paragraph having been re-read against the live text rather than the repo's copy.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.31 ADDS NO IN-APP PURCHASE AND CHANGES NONE. The existing non-consumable "
    "com.jasonye.nihongoride.scenery.lifetime is unchanged: same price, same content, same "
    "placement (Settings > \"The Road\", plus the menu's route strip once lifetime distance "
    "passes Kyoto). Restore Purchases is on the same screen and is always present.\n\n"
    "ONE BUG FIX TOUCHES THAT SECOND ENTRANCE, and it is named here rather than left for review "
    "to notice. In 1.30 the menu's route strip was a button whose middle did not respond to "
    "taps - only its text did - so a user tapping the strip itself often got no reaction. It now "
    "responds across its whole area. Nothing about where it is, what it says, or what it opens "
    "has changed.\n\n"
    "NOTE ON THE IN-APP PURCHASE'S CURRENT STATE, so that nothing here is a surprise. The "
    "non-consumable was submitted on 31 August 2026 as part of the macOS 1.30 submission, "
    "which is still in review, so the purchase itself is not yet approved. Version 1.31 for "
    "iOS does not resubmit it and does not change it. If the purchase does not display a "
    "price during testing, that is the pending approval rather than a defect in this build; "
    "the Restore Purchases control is present and functional either way.\n\n"
    "WHAT IS NEW.\n"
    "1) PRACTICE OVER THE USER'S OWN TEXT. The user can paste Japanese text into the app. The "
    "app splits it into sentences and derives a kana reading for each using Apple's own "
    "CFStringTokenizer with a Japanese locale, entirely on device. The readings are shown and "
    "the user can correct any of them. The text is stored in the app's own container on the "
    "device, is never transmitted, is not synced to iCloud, and is not shared with the "
    "developer or anyone else. No network request is made at any point in this feature.\n"
    "2) The conjugation drill now measures how long each prompt took and grades accordingly. "
    "This is a local scheduling change with no data-handling implications.\n"
    "3) A pause now also stops the per-word timer, and the ride screen shows a live typing "
    "speed on Mac and iPad.\n\n"
    "Data handling is unchanged and the App Privacy declaration is unchanged (Data Not "
    "Collected). There is no analytics SDK, no advertising, and no developer-operated server in "
    "this app. Optional iCloud sync uses the user's own private CloudKit database, which the "
    "developer cannot read, and the app is fully usable with it switched off; the user's pasted "
    "text is NOT part of that sync. Dictation uses the on-device system Japanese "
    "text-to-speech voice (AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an "
    "explanation, when no Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Shipping the two platforms apart -----------------------------------------
# 1.31 is the first release where the platforms separate. macOS 1.30 has been
# IN_REVIEW since 2026-08-31 and ASC refuses --metadata on a platform that has a
# version in review, so macOS 1.31 cannot be created yet; iOS 1.30 is
# READY_FOR_SALE and iOS is free to move. The two live defects 1.31 fixes -- the
# route strip's dead middle and Sentence mode's truncated typing target -- are
# live on iOS *now*, so iOS goes alone and macOS follows when 1.30 clears.
#
# The filter is a required argument rather than a default because the failure it
# prevents is silent-looking: run this with both targets today and the macOS half
# dies partway through, after the iOS half has already been written.
PLATFORM_ARG = {"ios": ("IOS",), "macos": ("MAC_OS",), "both": ("IOS", "MAC_OS")}


def _targets_for(argv):
    flags = [a for a in argv[1:] if a.startswith("--platform=")]
    if not flags:
        sys.exit("error: pass --platform=ios | --platform=macos | --platform=both\n"
                 "       (1.31 ships iOS first; macOS 1.30 is still IN_REVIEW)")
    key = flags[-1].split("=", 1)[1].lower()
    if key not in PLATFORM_ARG:
        sys.exit(f"error: unknown --platform={key}")
    wanted = PLATFORM_ARG[key]
    chosen = [t for t in TARGETS if t["platform"] in wanted]
    assert chosen, f"--platform={key} selected no target"
    print(f"==> platform filter: {key} -> {[t['name'] for t in chosen]}")
    return chosen


if __name__ == "__main__":
    main(Release(version=VERSION, targets=_targets_for(sys.argv), whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,                       # v1.31 sells nothing new; a statement, not a default
                 numbers=N),
         doc=__doc__)
