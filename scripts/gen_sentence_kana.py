#!/usr/bin/env python3
"""Give every example sentence its reading, so it can be typed and furigana'd.

KanaInputMatcher types against a kana target. Words carry `kana`; sentences carried nothing,
which is why 3,714 example sentences shipped in v1.17 as display-only text.

This writes two fields per sentence:

  exKana    the whole reading, the typing target
  exTokens  [[surface, reading], ...] — what furigana needs to put the right reading over the
            right characters

Sudachi is the right tool for this and was the wrong tool in v1.17 §F. A whole sentence in
context is where a statistical tokenizer is strong; where it is weak is an isolated word whose
taught reading is the minority one, and those entries have no sentence at all.

The output is NOT trusted because it parsed. Two mechanical gates run here and a sentence
failing either gets no exKana, which makes it invisible to sentence mode:

  round-trip     every character of exKana must be kana or sentence punctuation. A stray
                 kanji means the tokenizer gave up, and a half-read sentence typed as a
                 target would tell the learner they are wrong when they are right.
  alignment      the token surfaces must concatenate back to exJP exactly, and the token
                 readings back to exKana exactly. Furigana that drifts puts the reading over
                 the wrong character, which is worse than no furigana.

    python3 scripts/gen_sentence_kana.py            # report only
    python3 scripts/gen_sentence_kana.py --write
"""
import argparse
import json
import pathlib
import sys

from sudachipy import Dictionary, SplitMode

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"

KANA = set("ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとど"
           "なにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー")
PUNCT = set("、。！？「」")


def to_hiragana(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def is_kana_only(s):
    return all(c in KANA or c in PUNCT for c in s)


def read_sentence(tokenizer, jp):
    """→ (kana, tokens) or (None, reason)."""
    # Latin letters and digits read aloud as kana — and both come out untypeable while
    # remaining kana-only, so they sail straight past the round-trip check.
    #
    # ABC becomes えーびーしー: the learner sees ABC and cannot guess the target. Digits are
    # worse because they look harmless — Sudachi reads them DIGIT BY DIGIT, so 「荷物は10キロ
    # あります」 becomes にもつはいちれいきろあります ("one-zero kilos") and 200グラム becomes
    # にれいれいぐらむ. A learner typing じゅっキロ, which is what the sentence says, is told
    # they are wrong.
    #
    # Twelve shipped sentences have digits; they predate the corpus gate that now refuses
    # them. They keep their display text and simply do not become typing targets. A data
    # script should not depend on an assumption made by a gate elsewhere.
    if any(c.isascii() and c.isalnum() for c in jp):
        return None, "sentence contains latin letters or digits"
    tokens = []
    for t in tokenizer.tokenize(jp, SplitMode.C):
        surface = t.surface()
        # A token already written in kana or punctuation reads as itself — taking Sudachi's
        # reading here would normalise ー and small kana away and break alignment.
        if is_kana_only(surface):
            reading = surface
        else:
            reading = to_hiragana(t.reading_form())
        tokens.append([surface, reading])

    kana = "".join(r for _, r in tokens)
    if not is_kana_only(kana):
        stray = sorted({c for c in kana if c not in KANA and c not in PUNCT})
        return None, f"reading still contains {''.join(stray)}"
    if "".join(s for s, _ in tokens) != jp:
        return None, "token surfaces do not reconstruct the sentence"
    return (kana, tokens), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    tokenizer = Dictionary().create()
    total = ok = 0
    failures = []

    for path in sorted(RESOURCES.glob("n[1-5].json")):
        data = json.load(path.open())
        changed = False
        for entry in data:
            jp = (entry.get("exJP") or "").strip()
            if not jp:
                continue
            total += 1
            result, reason = read_sentence(tokenizer, jp)
            if result is None:
                failures.append((entry["id"], entry["surface"], jp, reason))
                continue
            ok += 1
            kana, tokens = result
            if args.write:
                entry["exKana"] = kana
                entry["exTokens"] = tokens
                changed = True
        if args.write and changed:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

    print(f"sentences        : {total}")
    print(f"readable         : {ok} ({100 * ok / max(1, total):.1f}%)")
    print(f"withheld         : {len(failures)}")
    for fid, surface, jp, reason in failures[:15]:
        print(f"   {surface:6} {reason}")
        print(f"          {jp}")
    if args.write:
        print("\nwritten. A withheld sentence has no exKana and is invisible to sentence mode.")
    else:
        print("\n(report only — pass --write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
