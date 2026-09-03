#!/usr/bin/env python3
"""Does any shipped sentence read a LEXICALISED counter as if it were two morphemes?

WHY A SCAN CAN SEE THIS AND NO TOKENIZER CAN. A handful of Japanese counters are single lexical
items — 二人 is ふたり, not に+にん — and **every tokenizer this project has tried splits them and
reads each half in isolation**. Measured 2026-09-04 on 四人:

    Sudachi            四[ヨン] + 人[ニン]
    CFStringTokenizer  四[よん] + 人[にん]
    the corpus         四[よん] + 人[にん]

Two independent implementations agreeing is normally strong evidence. **Here it is one
architectural blind spot seen twice** — STATE's "a gate and the thing it gates can share a blind
spot", and the reason this family needs an enumerated list rather than a parser. The same two
tools also give よんつ for 四つ, ふたか for 二日 and よんにち for 四日, all wrong.

WHAT THIS SCAN COSTS, MEASURED BEFORE IT WAS TRUSTED. The first version enumerated 24 compounds
and matched them as plain substrings. It produced **9 hits of which 7 were false positives — a
78% false-positive rate** — from three distinct causes, each fixed below:

  * **absorbed** (4): the counter sits inside a LONGER lexical item with its own correct
    reading — 真っ二つ まっぷたつ, 三日月 みかづき, 四つ角 よつかど, 一日中 いちにちじゅう.
  * **substring** (2): 二十日 contains 十日, and both readings were already correct.
  * **wrong expectation** (1): 一日 is ついたち as a DATE and いちにち as a DURATION. Surface
    alone cannot decide it, so 一日 is deliberately NOT enumerated — a rule that cannot be right
    from the surface does not belong in a surface scan.

WHAT IT STILL CANNOT SEE, stated because this repo pays for unstated scopes: a counter written
in a form this list does not contain, a compound absorbed by a word not in ABSORBERS, and any
reading error outside this family. It is a sweep of one closed set, not a reading gate.

    python3 scripts/check_counter_readings.py [--json out.json]
"""
import argparse, glob, json, sys

# surface -> the standard lexicalised reading. Regular compounds (三人 さんにん, 五人 ごにん) are
# deliberately absent: they are not lexicalised and the split reading is correct.
LEXICALISED = {
    "一人": "ひとり", "二人": "ふたり", "四人": "よにん",
    "一つ": "ひとつ", "二つ": "ふたつ", "三つ": "みっつ", "四つ": "よっつ", "五つ": "いつつ",
    "六つ": "むっつ", "七つ": "ななつ", "八つ": "やっつ", "九つ": "ここのつ",
    "二日": "ふつか", "三日": "みっか", "四日": "よっか", "五日": "いつか",
    "六日": "むいか", "七日": "なのか", "八日": "ようか", "九日": "ここのか", "十日": "とおか",
    "二十日": "はつか", "二十歳": "はたち",
}

# Longer lexical items that CONTAIN a counter and have their own reading. A sentence is not
# flagged for a counter whose every occurrence is inside one of these.
ABSORBERS = ("真っ二つ", "三日月", "四つ角", "一日中", "二十日", "十日町", "二人三脚", "一人前")


def occurrences_outside_absorbers(sentence, compound):
    """Does `compound` appear anywhere that is not inside a longer lexical item?"""
    masked = sentence
    for absorber in ABSORBERS:
        if compound in absorber and absorber != compound:
            masked = masked.replace(absorber, "　" * len(absorber))
    return compound in masked


def scan(resources="Sources/VocabKit/Resources"):
    hits, checked = [], 0
    for path in sorted(glob.glob(f"{resources}/n[1-5].json")):
        for entry in json.load(open(path, encoding="utf-8")):
            jp, kana = entry.get("exJP"), entry.get("exKana")
            if not jp or not kana:
                continue
            checked += 1
            for compound, standard in LEXICALISED.items():
                if not occurrences_outside_absorbers(jp, compound):
                    continue
                if standard in kana:
                    continue
                hits.append({"id": entry["id"], "compound": compound, "standard": standard,
                             "exJP": jp, "exKana": kana})
    return checked, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="write the hits here")
    args = ap.parse_args()
    checked, hits = scan()
    print(f"population   : {checked} sentences carrying an exKana")
    print(f"enumerated   : {len(LEXICALISED)} lexicalised counters, {len(ABSORBERS)} absorbers")
    print(f"flagged      : {len(hits)}")
    for h in hits:
        print(f"\n  {h['id']}  {h['compound']} -> expected …{h['standard']}…")
        print(f"      {h['exJP']}")
        print(f"      {h['exKana']}")
    if args.json:
        json.dump({"population": checked, "enumerated": len(LEXICALISED),
                   "absorbers": list(ABSORBERS), "hits": hits},
                  open(args.json, "w"), ensure_ascii=False, indent=1)
        print(f"\nwrote {args.json}")
    # A scan that inspected nothing must not report clean.
    if checked < 6000:
        print(f"\n!! only {checked} sentences inspected — this scan is reading almost nothing")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
