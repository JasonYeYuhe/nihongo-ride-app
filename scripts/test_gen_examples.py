#!/usr/bin/env python3
"""Unit tests for gen_examples.py's target gate — the only check that a generated sentence is
about the right word.

It shipped as "drop the last character is a stem" applied to EVERY entry, so the noun 学校
became 学 and 「数学を勉強します。」 validated as an example of it. Any sentence containing a
common kanji passed for a large fraction of the corpus, and nothing downstream would notice.

Run: python3 scripts/test_gen_examples.py
"""
import importlib.util, sys, pathlib

spec = importlib.util.spec_from_file_location("g", pathlib.Path(__file__).with_name("gen_examples.py"))
g = importlib.util.module_from_spec(spec)
sys.argv = ["gen_examples"]
try:
    spec.loader.exec_module(g)
except SystemExit:
    pass

CASES = [
    # (sentence, entry, expected, why)
    ("数学を勉強します。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, False,
     "a noun gets no stem: 学校 and 数学 share one kanji and nothing else"),
    ("学校へ行きます。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, True,
     "the word itself"),
    ("がっこうへいきます。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, True,
     "kana form counts too"),
    ("パンを食べています。", {"surface": "食べる", "kana": "たべる", "pos": ["v"], "vc": "ichidan"}, True,
     "an inflecting verb appears as its stem"),
    ("毎日勉強しています。", {"surface": "勉強する", "kana": "べんきょうする", "pos": ["v"], "vc": "suru"}, True,
     "suru-verbs strip する, not one character"),
    ("車が高いです。", {"surface": "高い", "kana": "たかい", "pos": ["adj-i"]}, True,
     "i-adjectives inflect"),
    ("水を飲みます。", {"surface": "飲み物", "kana": "のみもの", "pos": ["n"]}, False,
     "a noun that merely shares a kanji with the verb in the sentence"),
    ("銀行へ行きます。", {"surface": "行く", "kana": "いく", "pos": ["v"], "vc": "godan_k"}, False,
     "single-character stems are refused: 行 is in 銀行, 旅行, 行事 …"),
    ("学校へ行くつもりだ。", {"surface": "行く", "kana": "いく", "pos": ["v"], "vc": "godan_k"}, True,
     "…so such a word must appear in full"),
]


def main() -> int:
    failures = 0
    for sentence, entry, expected, why in CASES:
        got = g.contains_target(sentence, entry)
        if got != expected:
            failures += 1
            print(f"FAIL  {entry['surface']} in 「{sentence}」 → {got}, expected {expected}\n      ({why})")
    if failures:
        print(f"\n{failures} of {len(CASES)} failed")
        return 1
    print(f"{len(CASES)} cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
