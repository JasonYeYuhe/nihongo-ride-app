#!/usr/bin/env python3
"""Instrument 1b's release predicate, on the two shapes v1.37's review found it wrong on.

`scripts/check_propagated_exclusions.py` decides whether a withheld sentence goes back into
dictation. Its audio half (rendering, byte identity) is calibrated by its own `--calibrate`; this
file pins the PREDICATE that reads the hashes, which no calibration reaches:

  1. **A katakana match of the corpus reading is agreement** (corpus-2). For n5-b105 (二十センチ)
     and n4-b104 (五十ページ) only the katakana spelling ニジュッセンチ / ゴジュッページ renders
     byte-identical to the sentence. verdict() compared strings, so the committed instrument
     reported KEEP ("says ニジュッセンチ not にじゅっせんち") where the v1.37 re-measure, on a
     scratch-only patch, recorded RELEASE. A katakana match of ANOTHER reading is still KEEP, and
     the decoys now include katakana spellings, so the katakana path has a negative control.
  2. **n2-b034 is never released on a re-run that confirms only 一** (corpus-3). Its complaint
     names 一 alone ("一 いち -> ひと"), and its correction changed the lexeme 一晩中 as a whole
     (中 included). The predicate took the complaint's first word and printed RELEASE on 一 = ひと
     while every spelling of 一晩中 was silent; only a hand-written id list stood in the way. Now a
     disputed token inside a lexicalised compound disputes the compound (disputed_surfaces), so
     n2-b034 is SILENT and n4-b186 (一晩, confirmed as a span) is still RELEASE.
  3. `--spec` lays a re-measure over the mismatch record as it says it does (apply_spec).

The instrument imports check_dictation_readings, which needs numpy and scipy, and this gate runs
on a python3 that may have neither (CI). The predicate needs only `sha`, `clip` and `to_hira` from
it, so a stand-in replaces the module: audio is a dict from text to hash, and `to_hira` is written
here (ァ..ヶ minus 0x60), not taken from the code under test. Every expected verdict is written out
by hand; none is computed by the function under test.

Run: python3 scripts/test_check_propagated_exclusions.py
"""
import json
import sys
import types
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

AUDIO = {}          # text -> the "sha1" of its render; a text absent here has no usable render
SENTENCE = "T"      # the hash every sentence's own render gets


def _to_hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


_stub = types.ModuleType("check_dictation_readings")
_stub.to_hira = _to_hira
_stub.clip = lambda text: text
_stub.sha = lambda text: AUDIO.get(text)
sys.modules["check_dictation_readings"] = _stub
sys.path.insert(0, str(HERE))
import check_propagated_exclusions as P  # noqa: E402


def corpus_row(entry_id):
    level = entry_id.split("-")[0]
    for e in json.loads((REPO / f"Sources/VocabKit/Resources/{level}.json").read_text(encoding="utf-8")):
        if e["id"] == entry_id:
            return {"id": e["id"], "exJP": e["exJP"], "exKana": e["exKana"],
                    "tokens": [list(t) for t in e["exTokens"]]}
    raise LookupError(entry_id)


def recorded_complaint(entry_id):
    rows = json.loads((REPO / "docs/measurements/dictation-reading-mismatches.json")
                      .read_text(encoding="utf-8"))["excluded"]
    return next(r["heardInstead"] for r in rows if r["id"] == entry_id)


def plan_for(row, spans):
    """A plan as analyse() builds it, with audio: `spans` is [(token index, length, {candidate:
    renders byte-identical to the sentence?})]. The sentence itself renders to SENTENCE."""
    AUDIO.clear()
    AUDIO[row["exJP"]] = SENTENCE
    plan = {}
    for i, length, cands in spans:
        toks = row["tokens"][i:i + length]
        key = (i, length, "".join(t[0] for t in toks), "".join(t[1] for t in toks))
        plan[key] = {}
        for kana, same in cands.items():
            text = P.substituted(row["tokens"], i, length, kana)
            AUDIO[text] = SENTENCE if same else f"other:{text}"
            plan[key][kana] = text
    return plan


class KatakanaCandidates(unittest.TestCase):
    """corpus-2: n5-b105 and n4-b104 as the v1.37 re-measure measured them (corrected tokens)."""

    def test_katakana_spelling_of_the_corpus_reading_releases(self):
        row = corpus_row("n5-b105")      # この箱はたてが二十センチあります。 二十 にじゅっ + センチ せんち
        self.assertEqual(row["tokens"][5:7], [["二十", "にじゅっ"], ["センチ", "せんち"]])
        plan = plan_for(row, [(5, 2, {"にじゅっせんち": False, "にじゅうせんち": False,
                                      "ニジュッセンチ": True, "ニジュウセンチ": False})])
        self.assertEqual(P.verdict(row, plan, {"二十センチ"}),
                         ("RELEASE", [("二十センチ", "にじゅっせんち")]))

    def test_katakana_page_releases_too(self):
        row = corpus_row("n4-b104")      # 本の五十ページを開いてください。
        self.assertEqual(row["tokens"][2:4], [["五十", "ごじゅっ"], ["ページ", "ぺーじ"]])
        plan = plan_for(row, [(2, 2, {"ごじゅっぺーじ": False, "ゴジュッページ": True, "ゴジュウページ": False})])
        self.assertEqual(P.verdict(row, plan, {"五十ページ"})[0], "RELEASE")

    def test_katakana_spelling_of_another_reading_is_still_a_disagreement(self):
        row = corpus_row("n5-b105")
        plan = plan_for(row, [(5, 2, {"にじゅっせんち": False, "ニジュッセンチ": False, "ニジュウセンチ": True})])
        self.assertEqual(P.verdict(row, plan, {"二十センチ"}),
                         ("KEEP", [("二十センチ", "にじゅっせんち", ["ニジュウセンチ"])]))

    def test_the_decoys_have_katakana_spellings(self):
        # The negative control must reach the path a katakana candidate takes.
        self.assertLessEqual({"ぷりんてぃん", "ぬめりこ", "プリンティン", "ヌメリコ"}, set(P.DECOYS))


class LexemeSpans(unittest.TestCase):
    """corpus-3: a disputed token inside a lexicalised compound disputes the compound."""

    # n2-b034 as v137-dictation-remeasure.json measured it: 一 ひと and 一晩 ヒトバン byte-identical,
    # every spelling of 一晩中 silent. Tokens 一 ひと / 晩 ばん / 中 じゅう start at index 2.
    N2_B034_AUDIO = [
        (2, 1, {"いち": False, "ひと": True}),
        (2, 2, {"いちばん": False, "ひとばん": False, "イチバン": False, "ヒトバン": True}),
        (2, 3, {"いちばんじゅう": False, "いちばんちゅう": False, "ひとばんじゅう": False,
                "ひとばんちゅう": False, "イチバンジュウ": False, "イチバンチュウ": False,
                "ヒトバンジュウ": False, "ヒトバンチュウ": False}),
    ]

    def test_n2_b034_is_silent_when_only_one_is_confirmed(self):
        row = corpus_row("n2-b034")      # 母親は一晩中、熱を出した妹の看病をした。
        self.assertEqual(row["tokens"][2:5], [["一", "ひと"], ["晩", "ばん"], ["中", "じゅう"]])
        for heard in ("一 いち -> ひと", recorded_complaint("n2-b034")):
            with self.subTest(heard=heard):
                disputed = P.disputed_surfaces(heard, row["exJP"])
                self.assertEqual(P.verdict(row, plan_for(row, self.N2_B034_AUDIO), disputed),
                                 ("SILENT", ["一晩中"]))

    def test_n2_b034_releases_only_once_its_whole_lexeme_is_confirmed(self):
        row = corpus_row("n2-b034")
        spans = self.N2_B034_AUDIO[:2] + [(2, 3, {"いちばんちゅう": False, "ヒトバンジュウ": True})]
        self.assertEqual(P.verdict(row, plan_for(row, spans), P.disputed_surfaces("一 いち -> ひと", row["exJP"]))[0],
                         "RELEASE")

    def test_n4_b186_still_releases_on_its_confirmed_lexeme(self):
        row = corpus_row("n4-b186")      # 京都の古い旅館に一晩泊まりました。 一 ひと / 晩 ばん at index 5
        self.assertEqual(row["tokens"][5:7], [["一", "ひと"], ["晩", "ばん"]])
        spans = [(5, 1, {"いち": False, "ひと": True}),
                 (5, 2, {"いちばん": False, "ひとばん": True, "イチバン": False, "ヒトバン": True})]
        disputed = P.disputed_surfaces(recorded_complaint("n4-b186"), row["exJP"])
        self.assertEqual(P.verdict(row, plan_for(row, spans), disputed),
                         ("RELEASE", [("一", "ひと"), ("一晩", "ひとばん")]))

    def test_widening_adds_only_lexemes_that_contain_a_disputed_surface(self):
        self.assertEqual(P.disputed_surfaces("一 いち -> ひと", "母親は一晩中、熱を出した。"),
                         {"一", "一晩", "一晩中"})
        self.assertEqual(P.disputed_surfaces("人 にん -> り", "家族は四人です。"), {"人", "四人"})
        self.assertEqual(P.disputed_surfaces("紙 かみ -> がみ", "一晩中、紙を折った。"), {"紙"})
        self.assertEqual(P.disputed_surfaces("same word proven misread in another sentence",
                                             "一晩泊まった。", fallback={"一"}), {"一", "一晩"})

    def test_a_disputed_word_never_confirmed_is_silent(self):
        # n2-g210's shape (v1.28): another span agreeing does not release the sentence.
        row = corpus_row("n4-b186")
        self.assertEqual(row["tokens"][2], ["古い", "ふるい"])
        plan = plan_for(row, [(2, 1, {"ふるい": True, "ふりい": False})])
        self.assertEqual(P.verdict(row, plan, {"一", "一晩"}), ("SILENT", ["一", "一晩"]))


class Spec(unittest.TestCase):
    MISM = {"excluded": [{"id": "a", "exJP": "A", "exKana": "a", "heardInstead": "一 いち -> ひと",
                          "evidence": "stale"},
                         {"id": "b", "exJP": "B", "exKana": "b", "heardInstead": "十 じゅう -> じゅっ",
                          "evidence": "undecided"}]}
    CORPUS = [{"id": "p", "exJP": "P", "exKana": "p"}, {"id": "a", "exJP": "A", "exKana": "a"}]

    def test_rows_are_re_pointed_overridden_or_added(self):
        mism, want = P.apply_spec(self.MISM, {"evidence": "cls", "rows": {
            "a": None, "b": "十センチ じゅうせんち -> じゅっせんち", "p": "一日 ついたち -> いちにち"}}, self.CORPUS)
        by = {r["id"]: r for r in mism["excluded"]}
        self.assertEqual(want, {"a", "b", "p"})
        self.assertEqual((by["a"]["evidence"], by["a"]["heardInstead"]), ("cls", "一 いち -> ひと"))
        self.assertEqual((by["b"]["evidence"], by["b"]["heardInstead"]), ("cls", "十センチ じゅうせんち -> じゅっせんち"))
        self.assertEqual(by["p"], {"id": "p", "exJP": "P", "exKana": "p",
                                   "heardInstead": "一日 ついたち -> いちにち", "evidence": "cls"})
        self.assertEqual(self.MISM["excluded"][0]["evidence"], "stale")   # the record itself is untouched

    def test_a_row_the_spec_cannot_ground_is_refused(self):
        with self.assertRaises(ValueError):
            P.apply_spec(self.MISM, {"evidence": "cls", "rows": {"p": None}}, self.CORPUS)
        with self.assertRaises(ValueError):
            P.apply_spec(self.MISM, {"evidence": "cls", "rows": {"zz": "一 いち -> ひと"}}, self.CORPUS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
