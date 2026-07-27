#!/usr/bin/env python3
"""Does each example sentence use its target word with the READING the app teaches?

This is the gate that catches the dangerous class. The app grades a learner on a word's
reading, so an example whose target token is read some other way teaches a false reading —
the exact failure v1.14 shipped an apology for. A substring check cannot see it: 「牛の角が
大きい。」 contains 角 whether that 角 is かど (corner) or つの (horn).

WHAT THIS IS NOT
    A morphological analyser is a REJECTION SIGNAL, not a proof. Sudachi reads the 角 of
    「牛の角が大きい。」 as カド, which is wrong — a cow's 角 is つの. So a sentence that passes
    has not been shown correct; it has only failed to be shown wrong. Nothing here removes
    the need for a human to read what ships. What it does remove is the class of error that
    is invisible to a human skim: the target token quietly carrying another reading.

    It also says nothing about grammar. 「彼がドアを開く。」 passes — 開く really is read ひらく
    there — and is still ungrammatical, because 開く is intransitive and cannot take を.

Usage:
    .venv-jp/bin/python scripts/check_example_readings.py            # audit shipped data
    .venv-jp/bin/python scripts/check_example_readings.py --json     # machine-readable
"""
import argparse
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources" / "VocabKit" / "Resources"

try:
    from sudachipy import Dictionary, SplitMode
except ImportError:
    sys.exit("needs sudachipy — .venv-jp/bin/pip install sudachipy sudachidict_core")


KATA_TO_HIRA = str.maketrans({chr(c): chr(c - 0x60) for c in range(0x30A1, 0x30F7)})


def hira(text: str) -> str:
    """Katakana → hiragana, so a Sudachi reading can be compared with the app's kana."""
    return (text or "").translate(KATA_TO_HIRA)


def entries():
    for path in sorted(RESOURCES.glob("n[1-5].json")):
        for entry in json.load(path.open()):
            yield entry


def check(tokenizer, entry) -> str | None:
    """None if the example is consistent with the entry's reading, else why not."""
    sentence = (entry.get("exJP") or "").strip()
    if not sentence:
        return None
    surface, kana = entry["surface"], entry["kana"]

    tokens = tokenizer.tokenize(sentence, SplitMode.C)
    # The target may appear as itself (nouns) or via its dictionary form (inflected verbs).
    matches = [t for t in tokens
               if t.surface() == surface or t.dictionary_form() == surface]
    if not matches:
        # Not a reading problem — the target is absent or split differently. The substring
        # gate in ExampleSentenceTests owns that question; staying silent here keeps the two
        # checks from blaming each other for the same sentence.
        return None

    for token in matches:
        reading = hira(token.reading_form())
        # A noun's contextual reading is directly comparable. An inflected verb's is not
        # (読み vs よむ), so compare the part that does not inflect: the reading of the
        # dictionary form, obtained by tokenizing the headword on its own.
        if token.dictionary_form() == surface and token.surface() != surface:
            alone = tokenizer.tokenize(surface, SplitMode.C)
            reading = hira("".join(t.reading_form() for t in alone))
        if reading == kana or reading == hira(kana):
            return None
    got = ", ".join(sorted({hira(t.reading_form()) for t in matches}))
    return f"reads {got}, app teaches {kana}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    tokenizer = Dictionary().create()
    checked = 0
    problems = []
    for entry in entries():
        if not (entry.get("exJP") or "").strip():
            continue
        checked += 1
        if why := check(tokenizer, entry):
            problems.append({"id": entry["id"], "surface": entry["surface"],
                             "kana": entry["kana"], "sentence": entry["exJP"], "why": why})

    if args.json:
        json.dump({"checked": checked, "problems": problems}, sys.stdout,
                  ensure_ascii=False, indent=2)
        print()
    else:
        print(f"checked {checked} example sentences; {len(problems)} disagree on the reading")
        for p in problems[:40]:
            print(f"  {p['id']:10} {p['surface']:8} 「{p['sentence']}」 — {p['why']}")
        if len(problems) > 40:
            print(f"  … and {len(problems) - 40} more")
    return 0


if __name__ == "__main__":
    sys.exit(main())
