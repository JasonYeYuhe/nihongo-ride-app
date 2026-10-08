#!/usr/bin/env python3
"""Create the 1.36 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py`. Every previous `submit_<version>.py` is left exactly as it was — they
are the record of what was actually sent.

WHAT 1.36 IS
------------
`docs/PLAN-V1.36.md` (scope fixed 2026-10-07, before the N = 100 reading; its §H is the record).

  * Word Lists: a list's own words show their reading under the word — the rule the dictionary
    search results on that screen have used since 1.35 — and a long meaning wraps instead of being
    cut to one line; at the accessibility text sizes the Remove button sits under the text, as the
    search results' button does; VoiceOver reads a word, its reading and its meaning as one item
    (item 1).
  * Word Lists: the Saved list's row shows its star once — its gold icon — instead of the icon plus a
    ★ in the name. The stored name is unchanged (item 2).
  * Corpus: `correctedThisRelease` entries, declared in `docs/measurements/v136-reading-manifest.json`
    — n5-kazoku's 四人 is taught as よにん (item 3).

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No change to the purchase, its code, its screen or its placements**: `RouteStore`, `RoadView`,
`SettingsView`, `MenuView`, `AboutView`, `OnboardingView` and `EntitlementKit` are byte-identical to
1.35's build commit `fdb2b5f` (checked before submission; the headless renders of the Road, the
in-app-purchase review screen and the menu are pixel-identical to 1.35's). The offer, its price, its
placement and its presentation are frozen for the pre-registered observation window (`PLAN-WINDOW`
constraint 1).

**No description, keyword, title, subtitle or screenshot change** (`PLAN-WINDOW` constraint 4).
No new persisted record and no new network use, so the privacy paragraph and `Data Not Collected`
are unchanged.

Three phases:
  python3 scripts/submit_1_36.py --dry-run  --platform=both   # print the copy, touch nothing
  python3 scripts/submit_1_36.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_36.py --submit   --platform=both   # attach builds

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import CORPUS_MANIFEST, REPO, RESOURCES, numbers   # noqa: E402

VERSION = "1.36"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "61"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "62"},
]

# Measured, never typed.
N = numbers()
FIXED = N["correctedThisRelease"]

# The entries the corpus sentences below are written against: all 22 corrections the v1.36 manifest
# declares (PLAN-V1.36 §C items 3–4 and §I's two addenda). When a correction joins or leaves the
# manifest, this list and the sentences change together.
NAMED_IDS = [
    "n1-b1147", "n1-b1630", "n1-b1841", "n1-b327", "n1-b439", "n1-b615", "n1-b957",
    "n2-b072", "n2-b311", "n2-b449", "n2-b479", "n2-b942",
    "n3-b020", "n3-b678", "n3-b750", "n3-b781",
    "n4-b127", "n4-g180",
    "n5-b018", "n5-b071", "n5-b303", "n5-kazoku",
]
# The examples the sentences quote, and the kana each entry must now teach for the quote to be true.
EXAMPLES = {
    "n5-b303": ("四月", "しがつ"),
    "n5-b071": ("九時", "くじ"),
    "n1-b439": ("三千円", "さんぜんえん"),
    "n4-b127": ("十分", "じゅっぷん"),
    "n5-kazoku": ("四人", "よにん"),
}


def corpus_copy_problems(manifest_ids, exkana_by_id, fixed):
    """Why the corpus sentences below would be false, or [] when they are true.

    The guard checks which entries the manifest declares, not how many (whole-release review,
    round 1): with the count alone, the manifest naming different entries, or the corpus reverted
    while the manifest still declared them, both passed, and the copy would have told riders and App
    Review about readings the build does not teach.
    """
    problems = []
    if sorted(manifest_ids) != sorted(NAMED_IDS):
        problems.append(f"the v1.36 manifest declares {sorted(manifest_ids)}; What's New is written "
                        f"against {sorted(NAMED_IDS)}")
    if fixed != len(NAMED_IDS):
        problems.append(f"correctedThisRelease is {fixed}; What's New is written against "
                        f"{len(NAMED_IDS)} correction(s)")
    for entry_id, (word, kana) in EXAMPLES.items():
        if kana not in (exkana_by_id.get(entry_id) or ""):
            problems.append(f"{entry_id}'s exKana is {exkana_by_id.get(entry_id)!r}, which does not "
                            f"teach {word} as {kana}")
    return problems


def _manifest_ids():
    if CORPUS_MANIFEST is None:
        return []
    manifest = json.loads((REPO / CORPUS_MANIFEST).read_text(encoding="utf-8"))
    return [e["id"] for e in manifest["entries"]]


def _exkana_by_id():
    out = {}
    for level in ("n1", "n2", "n3", "n4", "n5"):
        for entry in json.loads((RESOURCES / f"{level}.json").read_text(encoding="utf-8")):
            out[entry["id"]] = entry.get("exKana")
    return out


_problems = corpus_copy_problems(_manifest_ids(), _exkana_by_id(), FIXED)
if _problems:
    sys.exit("error: the corpus sentences in What's New and the review notes are not true of this "
             "tree:\n  " + "\n  ".join(_problems) + "\nRewrite them (and NAMED_IDS) before sending.")

# What's New — no star glyph (preflight enforces it). Same voice as every release since v1.27:
# report what changed, never solicit. Each sentence is checked against the merged code before this
# is sent (PLAN-V1.36 §C item 6).
WHATS_NEW = {
    "en-US": (
        "• Word Lists: on a list's page, words written with kanji now show their reading underneath, "
        "as the dictionary search results there already do, and a long meaning wraps instead of being "
        "cut off.\n"
        "• Word Lists: the Saved list's row shows its star once instead of twice.\n"
        f"• Corrected {FIXED} example sentences where a number and its counter were read wrong: for "
        "example, 四月 is now read しがつ, 九時 くじ, 三千円 さんぜんえん, 十分 (ten minutes) じゅっぷん, "
        "and 四人 よにん."
    ),
    "zh-Hans": (
        "• 词单:在词单页面里,用汉字书写的词下方现在会显示读音,与该页面词库搜索结果的显示方式相同;"
        "较长的释义会换行显示,不再被截断。\n"
        "• 词单:「收藏」词单那一行的星标现在只显示一次。\n"
        f"• 更正了 {FIXED} 条例句中数字与量词的读法,例如「四月」现在读作 しがつ,「九時」读作 くじ,"
        "「三千円」读作 さんぜんえん,「十分」(十分钟)读作 じゅっぷん,「四人」读作 よにん。"
    ),
    # The app's interface is English or Chinese only, so a Japanese rider sees the English labels;
    # the Japanese copy quotes them in 「」 where it names a screen.
    "ja": (
        "• 「Word Lists」:リストのページで、漢字で書く単語の下に読みが表示されるようになりました"
        "(辞書検索の結果と同じ表示です)。長い意味は省略されず、折り返して表示されます。\n"
        "• 「Word Lists」:「Saved」リストの行の星が 1 つだけになりました。\n"
        f"• 数字と助数詞の読みを誤っていた例文 {FIXED} 件を訂正しました(例:「四月」しがつ、「九時」くじ、"
        "「三千円」さんぜんえん、「十分」(10 分間)じゅっぷん、「四人」よにん)。"
    ),
}

# No description edit — see the module docstring.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.36 ADDS NO IN-APP PURCHASE AND DOES NOT CHANGE THE EXISTING ONE: its product, "
    "price, content, screen, placements and purchase code are unchanged from 1.35. The existing "
    "non-consumable com.jasonye.nihongoride.scenery.lifetime is approved and live, in the same two "
    "placements (Settings > \"The Road\", plus the menu's route strip once lifetime distance passes "
    "Kyoto). Restore Purchases is on the same screen and is always present. There is no modal, no "
    "badge, and nothing about the purchase on the post-ride results screen.\n\n"
    "WHAT IS NEW.\n"
    "1) Word Lists: on a list's screen, each word written with kanji now shows its kana reading under "
    "it, and a long meaning wraps instead of being cut off. VoiceOver reads a word, its reading and "
    "its meaning together.\n"
    "2) Word Lists: the default \"Saved\" list's row now shows one star, its star icon. It showed "
    "two: the second was a star character at the start of the list's name, which the row no longer "
    "shows.\n"
    f"3) Content: {FIXED} example sentences were corrected where a number and its counter were read "
    "wrong (for example 四月 is now read しがつ, 九時 くじ, 三千円 さんぜんえん).\n\n"
    "Data handling is unchanged. There is no analytics SDK, no advertising, and no "
    "developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

# --- Both platforms move together, as 1.35 did ------------------------------------------------
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
    print("==> review notes: one set — 1.36 changes the purchase a customer sees on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
