#!/usr/bin/env python3
"""Create the 1.37 App Store versions, set What's New and the review notes, attach the builds,
and submit both platforms for review.

Configuration only. The machinery is `scripts/asc_release.py`, held to `submit_1_30.py` by
`scripts/test_asc_release.py`. Every previous `submit_<version>.py` is left exactly as it was — they
are the record of what was actually sent.

WHAT 1.37 IS
------------
`docs/PLAN-V1.37.md` §C P0-2 and P0-12 (the open-surface release; submitted only after 1.36 is live
on both platforms, PLAN-V1.37 §I).

  * Corpus: `correctedThisRelease` example sentences whose number + counter reading was wrong (六十キロ
    ろくじゅっきろ, 一週間 いっしゅうかん, 第一章 だいいっしょう, 一晩 ひとばん, …), each upheld 2-of-2
    by independent refuters and declared in `docs/measurements/v137-reading-manifest.json`. `n5-g010`
    十ページ is NOT among them (1 of 2; recorded, not corrected). Every swap is one kana for one, so no
    sentence rides a different distance. Two of the corrected sentences were in the dictation pool and
    are withheld from it, because calibrated instrument 1b is silent on the corrected span (pool 5,935 →
    5,933, `release_numbers`); three stay in it, 1b proving the voice says the corrected reading.
  * The install-cohort marker (P0-12): `NihongoRide.installCohort.v1`, written once at launch if
    absent, in local `UserDefaults` only. Nothing reads it in 1.37 and a rider sees nothing, so What's
    New does not mention it; the review notes state it, because it is a new on-device record.
  * Tests only, nothing a rider sees: a removed word's Remove button is pinned to never speak its id
    (it already did not, since 1.36), and CI's corpus check diffs against the newest successful run.
    Neither is claimed in What's New.

WHAT IS DELIBERATELY NOT IN IT
------------------------------
**No change to the purchase, its code, its screen or its placements**: `RouteStore`, `RoadView`,
`SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `Theme`, `ScaledFont`, `EntitlementKit` and
`xcode/NihongoRide.storekit` are byte-identical to 1.35's build commit `fdb2b5f` (`git diff fdb2b5f`
over that list is empty on this branch; the headless renders of the Road, the in-app-purchase review
screen and the menu are compared before submission, PLAN-V1.37 §J V2). The offer, its price, its
placement and its presentation are frozen for the pre-registered observation window (`PLAN-WINDOW`
constraint 1).

**No description, keyword, title, subtitle or screenshot change** (`PLAN-WINDOW` constraint 4). The
marker is local and never synced or sent, so `Data Not Collected` is unchanged; the privacy page's
local-storage sentence for it is the owner's push (PLAN-V1.37 P0-6), not this script's.

Three phases:
  python3 scripts/submit_1_37.py --dry-run  --platform=both   # print the copy; GETs only
  python3 scripts/submit_1_37.py --metadata --platform=both   # versions + What's New + notes
  python3 scripts/submit_1_37.py --submit   --platform=both   # attach builds

NOTE: --metadata cannot run while a previous version is WAITING_FOR_REVIEW or IN_REVIEW.
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_release import Release, main          # noqa: E402
from release_numbers import BASELINE_REF, CORPUS_MANIFEST, REPO, RESOURCES, numbers   # noqa: E402

VERSION = "1.37"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "build_num": "62"},
    {"name": "iOS",   "platform": "IOS",    "build_num": "63"},
]

# Measured, never typed.
N = numbers()
FIXED = N["correctedThisRelease"]
WITHHELD = N["withheldThisRelease"]

# The manifest this copy is written against. `release_numbers.CORPUS_MANIFEST` is what FIXED counts;
# if it moves to another release's manifest, this copy is about a different set of corrections.
MANIFEST = "docs/measurements/v137-reading-manifest.json"

# The entries the corpus sentences below are written against: all 12 corrections the v1.37 manifest
# declares (PLAN-V1.37 §C P0-2). `n5-g010` is in the manifest's `recordedNotCorrected`, not its
# entries, and must stay out of this list. When a correction joins or leaves the manifest, this list
# and the sentences change together.
NAMED_IDS = [
    "n1-b1418",
    "n2-b034", "n2-b1180", "n2-b277", "n2-b511", "n2-g285",
    "n3-b310", "n3-k061",
    "n4-b104", "n4-b186", "n4-g189",
    "n5-b105",
]
# The examples the sentences quote, and the kana each entry must now teach for the quote to be true.
EXAMPLES = {
    "n2-b277": ("六十キロ", "ろくじゅっきろ"),
    "n2-b511": ("一週間", "いっしゅうかん"),
    "n1-b1418": ("第一章", "だいいっしょう"),
    "n4-b186": ("一晩", "ひとばん"),
}
# The two corrected sentences that leave the dictation pool in 1.37, and the only change to the pool
# against what is on sale (`release_numbers.BASELINE_REF`, 1.36's build commit). "2 of these
# sentences" in the copy is true only while every newly withheld id is one of NAMED_IDS and nothing
# returned to the pool.
WITHHELD_IDS = ["n1-b1418", "n2-b511"]


def _token_reading(tokens, word):
    """The joined readings of the run of consecutive tokens whose surfaces spell `word`, or None."""
    tokens = tokens or []
    for start in range(len(tokens)):
        surface, reading = "", ""
        for tok_surface, tok_reading in tokens[start:]:
            surface += tok_surface
            reading += tok_reading
            if surface == word:
                return reading
            if not word.startswith(surface):
                break
    return None


def corpus_copy_problems(manifest_ids, entries_by_id, fixed, withheld_ids, released_ids,
                         manifest_counts):
    """Why the corpus sentences below would be false, or [] when they are true.

    The guard checks which entries the manifest declares, not how many (1.36's whole-release review,
    round 1): with the count alone, the manifest naming different entries, or the corpus reverted
    while the manifest still declared them, both passed. 1.37 adds two things 1.36 did not check: a
    quoted word must be spelled by the sentence's own tokens with the quoted kana (a substring of
    exKana alone can be met by the wrong span), and the dictation sentence's count is held to which
    ids left the pool, not only how many.
    """
    problems = []
    if sorted(manifest_ids) != sorted(NAMED_IDS):
        problems.append(f"the v1.37 manifest declares {sorted(manifest_ids)}; What's New is written "
                        f"against {sorted(NAMED_IDS)}")
    if fixed != len(NAMED_IDS):
        problems.append(f"correctedThisRelease is {fixed}; What's New is written against "
                        f"{len(NAMED_IDS)} correction(s)")
    for entry_id, (word, kana) in EXAMPLES.items():
        entry = entries_by_id.get(entry_id) or {}
        if entry_id not in NAMED_IDS:
            problems.append(f"{entry_id} is quoted but is not one of the corrections NAMED_IDS holds")
        if word not in (entry.get("exJP") or ""):
            problems.append(f"{entry_id}'s exJP is {entry.get('exJP')!r}, which does not contain {word}")
        if kana not in (entry.get("exKana") or ""):
            problems.append(f"{entry_id}'s exKana is {entry.get('exKana')!r}, which does not "
                            f"teach {word} as {kana}")
        got = _token_reading(entry.get("exTokens"), word)
        if got != kana:
            problems.append(f"{entry_id}'s tokens read {word} as {got!r}, not {kana}")
    if sorted(withheld_ids) != sorted(WITHHELD_IDS):
        problems.append(f"the ids newly withheld from dictation since {BASELINE_REF} are "
                        f"{sorted(withheld_ids)}; the copy is written against {sorted(WITHHELD_IDS)}")
    if not set(WITHHELD_IDS) <= set(NAMED_IDS):
        problems.append(f"WITHHELD_IDS {WITHHELD_IDS} are not all corrections, but the copy calls them "
                        "'of these sentences'")
    if released_ids:
        problems.append(f"{sorted(released_ids)} returned to the dictation pool since {BASELINE_REF}; "
                        "the copy says only that sentences left it")
    if manifest_counts.get("withheldFromDictation") != len(WITHHELD_IDS):
        problems.append(f"the manifest's withheldFromDictation is "
                        f"{manifest_counts.get('withheldFromDictation')!r}, not {len(WITHHELD_IDS)}")
    return problems


def _manifest():
    if CORPUS_MANIFEST != MANIFEST:
        sys.exit(f"error: release_numbers.CORPUS_MANIFEST is {CORPUS_MANIFEST!r}; this copy is written "
                 f"against {MANIFEST!r}, so FIXED would count a different release's corrections")
    return json.loads((REPO / MANIFEST).read_text(encoding="utf-8"))


def _entries_by_id():
    out = {}
    for level in ("n1", "n2", "n3", "n4", "n5"):
        for entry in json.loads((RESOURCES / f"{level}.json").read_text(encoding="utf-8")):
            out[entry["id"]] = entry
    return out


def _excluded(text):
    return {row["id"] for row in json.loads(text)["excluded"]}


def _pool_moves():
    """(newly withheld ids, newly released ids): this tree's dictation exclusions against BASELINE_REF."""
    now = _excluded((RESOURCES / "dictation-exclusions.json").read_text(encoding="utf-8"))
    before = _excluded(subprocess.run(
        ["git", "show", f"{BASELINE_REF}:Sources/VocabKit/Resources/dictation-exclusions.json"],
        cwd=REPO, capture_output=True, text=True, check=True).stdout)
    return now - before, before - now


_manifest_data = _manifest()
_withheld_ids, _released_ids = _pool_moves()
_problems = corpus_copy_problems([e["id"] for e in _manifest_data["entries"]], _entries_by_id(), FIXED,
                                 _withheld_ids, _released_ids, _manifest_data.get("counts") or {})
if WITHHELD != len(WITHHELD_IDS):
    _problems.append(f"withheldThisRelease is {WITHHELD}; the copy is written against "
                     f"{len(WITHHELD_IDS)} sentence(s) leaving dictation")
if _problems:
    sys.exit("error: the corpus sentences in What's New and the review notes are not true of this "
             "tree:\n  " + "\n  ".join(_problems) + "\nRewrite them (and NAMED_IDS / EXAMPLES / "
             "WITHHELD_IDS) before sending.")

# What's New — no star glyph (preflight enforces it). Same voice as every release since v1.27:
# report what changed, never solicit. Each sentence is checked against the code and the manifest
# before this is sent (PLAN-V1.37 §J V7); the check table is kept with the release work, outside the
# repository. Mode names are the menu's (`GameMode.shortLabel`): "Sentence" / 例句, and the app's own
# word for the listening mode, "Dictation" / 听写 (its start button and the Ride Log).
WHATS_NEW = {
    "en-US": (
        f"• Corrected {FIXED} example sentences where a number and its counter were read wrong: for "
        "example, 六十キロ is now read ろくじゅっきろ, 一週間 いっしゅうかん, 第一章 だいいっしょう, "
        "and 一晩 ひとばん.\n"
        f"• Of these, {WITHHELD} sentences are no longer used in Dictation, because the voice could not "
        "be confirmed to say the corrected reading. You can still type them in Sentence mode."
    ),
    "zh-Hans": (
        f"• 更正了 {FIXED} 条例句中数字与量词的读法,例如「六十キロ」现在读作 ろくじゅっきろ,"
        "「一週間」读作 いっしゅうかん,「第一章」读作 だいいっしょう,「一晩」读作 ひとばん。\n"
        f"• 其中 {WITHHELD} 条例句不再用于听写,因为无法确认语音读出的是更正后的读法;"
        "它们仍可在「例句」模式中练习。"
    ),
    # The app's interface is English or Chinese only, so a Japanese rider sees the English labels;
    # the Japanese copy quotes them in 「」 where it names a mode.
    "ja": (
        f"• 数字と助数詞の読みを誤っていた例文 {FIXED} 件を訂正しました(例:「六十キロ」ろくじゅっきろ、"
        "「一週間」いっしゅうかん、「第一章」だいいっしょう、「一晩」ひとばん)。\n"
        f"• そのうち {WITHHELD} 件は、音声が訂正後の読みで読み上げることを確認できなかったため、"
        "聞き取り(「Dictation」)では出題されなくなりました。「Sentence」モードでは引き続き入力できます。"
    ),
}

# The quotes in the copy are the EXAMPLES the guard holds to the corpus: each example's word and kana
# must appear in every locale's What's New, and the review notes quote the first three.
_unquoted = [f"{loc}: {word} {kana}" for loc, text in WHATS_NEW.items()
             for word, kana in EXAMPLES.values() if word not in text or kana not in text]
if _unquoted:
    sys.exit("error: What's New does not quote what EXAMPLES holds to the corpus:\n  " + "\n  ".join(_unquoted))

# No description edit — see the module docstring.
DESCRIPTION_EDITS = {}

REVIEW_NOTES = (
    "Nihongo Ride is a typing-practice app for learners of Japanese. It requires no account or "
    "login with the developer, and the developer collects no data.\n\n"
    "VERSION 1.37 ADDS NO IN-APP PURCHASE AND DOES NOT CHANGE THE EXISTING ONE: its product, "
    "price, content, screen, placements and purchase code are unchanged from 1.36. The existing "
    "non-consumable com.jasonye.nihongoride.scenery.lifetime is approved and live, in the same two "
    "placements (Settings > \"The Road\", plus the menu's route strip once lifetime distance passes "
    "Kyoto). Restore Purchases is on the same screen and is always present. There is no modal, no "
    "badge, and nothing about the purchase on the post-ride results screen.\n\n"
    "WHAT IS NEW.\n"
    f"1) Content: {FIXED} example sentences were corrected where a number and its counter were read "
    "wrong (for example 六十キロ is now read ろくじゅっきろ, 一週間 いっしゅうかん, 第一章 "
    "だいいっしょう). "
    f"{WITHHELD} of them are no longer offered in dictation practice, because the on-device voice "
    "could not be confirmed to say the corrected reading "
    f"({N['dictationPoolBefore']:,} dictation sentences before, {N['dictationPool']:,} now). They "
    "remain in sentence practice.\n"
    "2) No visible change: the first time this version launches, the app stores on the device the "
    "version and build that launched, the platform, and whether the app's own saved data already "
    "existed. It is written once and never changed, and nothing in this version reads it. It is not "
    "part of iCloud sync and is never sent anywhere.\n\n"
    "Data handling: the developer still collects no data. There is no analytics SDK, no advertising, "
    "and no developer-operated server in this app. Optional iCloud sync uses the user's own private "
    "CloudKit database, which the developer cannot read, and the app is fully usable with it "
    "switched off. Dictation uses the on-device system Japanese text-to-speech voice "
    "(AVSpeechSynthesizer, ja-JP) and reports itself unavailable, with an explanation, when no "
    "Japanese voice is installed.\n\n"
    "No keywords, URLs, description text or screenshots changed in this version."
)

_unquoted_notes = [f"{word} {kana}" for word, kana in list(EXAMPLES.values())[:3]
                   if word not in REVIEW_NOTES or kana not in REVIEW_NOTES]
if _unquoted_notes:
    sys.exit("error: the review notes do not quote what EXAMPLES holds to the corpus: "
             + ", ".join(_unquoted_notes))

# --- Both platforms move together, as 1.36 did ------------------------------------------------
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
    print("==> review notes: one set — 1.37 changes the purchase a customer sees on neither platform")
    main(Release(version=VERSION, targets=_targets, whats_new=WHATS_NEW,
                 description_edits=DESCRIPTION_EDITS, review_notes=REVIEW_NOTES,
                 iap=None,
                 numbers=N),
         doc=__doc__)
