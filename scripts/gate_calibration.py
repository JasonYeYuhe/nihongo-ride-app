#!/usr/bin/env python3
"""Calibrate a proposed tightening of `pilot_gate` against sentences already known good.

A gate written from intuition measures itself. The first level gate rejected 23 of 28 pilot
sentences because た and で collide with N2 vocabulary entries — it was finding its own
tokenizer, not bad Japanese. The fix then, and the method here, is to run any proposed rule
against a corpus whose verdict is already settled before trusting it on new material.

The corpus: the 779 sentences that shipped in v1.15 (`exMeta.batch` present). Every one
passed the current gate AND two-lens agent review AND adjudication. So a proposed rule that
rejects a lot of them is not stricter, it is wrong — and the ones it does reject are exactly
the sample worth reading by hand.

Usage:  python3 scripts/gate_calibration.py            # report all proposed rules
        python3 scripts/gate_calibration.py --show 20  # + print that many rejected sentences
"""
import argparse
import collections
import glob
import json
import re
import sys
from pathlib import Path

from sudachipy import Dictionary
from sudachipy.tokenizer import Tokenizer

sys.path.insert(0, str(Path(__file__).parent))
import pilot_gate as G

SplitMode = Tokenizer.SplitMode
REPO = Path(__file__).resolve().parent.parent


def shipped_corpus():
    """The 779 reviewed sentences, as gate items paired with their vocabulary entry."""
    out = []
    for path in sorted(glob.glob(str(REPO / "Sources/VocabKit/Resources/n[1-5].json"))):
        for e in json.load(open(path)):
            if (e.get("exMeta") or {}).get("batch") and e.get("exJP"):
                out.append(({"id": e["id"], "jp": e["exJP"],
                             "en": e.get("exEN", ""), "zh": e.get("exZH", "")}, e))
    return out


# ── the three proposed rules, each a function item,entry,tokenizer → reason or None ──

def rule_morphology_only(item, entry, tok):
    """Drop the substring fallback: the target must be found MORPHOLOGICALLY.

    Today `target_tokens(...) or gen.contains_target(...)` passes a sentence that merely
    contains the characters. That is how a sentence about 学ぶ can be filed under 学校.
    """
    if not G.target_tokens(tok, item["jp"], entry):
        return "target not found morphologically"
    return None


def unknown_content_words(item, entry, tok):
    """Content tokens carrying no JLPT level at all."""
    levels = LEVELS
    target = {t.surface() for t in G.target_tokens(tok, item["jp"], entry)}
    target |= {entry["surface"], entry["kana"]}
    unknown = []
    for t in tok.tokenize(item["jp"], SplitMode.C):
        if t.part_of_speech()[0] not in G.CONTENT_POS:
            continue
        # 非自立 = the token cannot stand alone: the いる of ～ています, the ある of ～てある,
        # the くる of ～てくる. Counting them made 「庭で可愛い小鳥が鳴いています。」 look like it
        # had three unknown content words, one of which was the grammar. Same mistake the
        # first level gate made with た and で — a counter that finds its own tokenizer.
        if "非自立" in "".join(t.part_of_speech()):
            continue
        if t.surface() in target or t.dictionary_form() in target:
            continue
        if levels.get(t.dictionary_form()) is None and levels.get(t.surface()) is None:
            unknown.append(t.surface())
    return unknown


def rule_unknown_cap(item, entry, tok, cap):
    """Cap content words the vocabulary has never heard of.

    The level gate only checks tokens it can find a level FOR (`lvl is not None`), so a
    sentence built entirely from words outside every JLPT list sails through with nothing
    flagged. That is the blind spot this closes; the cap itself has to be measured.
    """
    u = unknown_content_words(item, entry, tok)
    if len(u) > cap:
        return f"{len(u)} unknown content words: {' '.join(u)}"
    return None


# Transitive/intransitive pairs: teaching 開ける with a sentence that uses 開く teaches the
# wrong verb, and the two are one character apart. Detection is by particle: a transitive
# verb governs を, an intransitive one cannot.
def rule_transitivity(item, entry, tok):
    pos = entry.get("pos") or []
    if not any(p.startswith("v") for p in pos):
        return None
    kind = TRANSITIVITY.get(entry["surface"])
    if kind is None:
        return None
    toks = list(tok.tokenize(item["jp"], SplitMode.C))
    hits = [i for i, t in enumerate(toks)
            if t.surface() == entry["surface"] or t.dictionary_form() == entry["surface"]]
    if not hits:
        return None
    # Does an を appear anywhere before the verb in the same clause? Crude but checkable:
    # scan back to the previous 。、or clause-final verb.
    for i in hits:
        window = toks[max(0, i - 8):i]
        has_wo = any(t.surface() == "を" for t in window)
        if kind == "vt" and not has_wo:
            return f"transitive {entry['surface']} with no を object"
        if kind == "vi" and has_wo:
            return f"intransitive {entry['surface']} governing を"
    return None


def load_transitivity():
    """Pairs are marked in the vocabulary's own part-of-speech tags where JMdict had them."""
    out = {}
    for path in sorted(glob.glob(str(REPO / "Sources/VocabKit/Resources/n[1-5].json"))):
        for e in json.load(open(path)):
            pos = e.get("pos") or []
            if any(p == "vt" for p in pos):
                out[e["surface"]] = "vt"
            elif any(p == "vi" for p in pos):
                out[e["surface"]] = "vi"
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", type=int, default=0)
    args = ap.parse_args()

    tok = Dictionary().create()
    corpus = shipped_corpus()
    print(f"corpus: {len(corpus)} reviewed sentences that already shipped\n")

    rules = [
        ("morphology only (drop substring fallback)", rule_morphology_only),
        ("unknown content words > 3", lambda i, e, t: rule_unknown_cap(i, e, t, 3)),
        ("unknown content words > 2", lambda i, e, t: rule_unknown_cap(i, e, t, 2)),
        ("unknown content words > 1", lambda i, e, t: rule_unknown_cap(i, e, t, 1)),
        ("unknown content words > 0", lambda i, e, t: rule_unknown_cap(i, e, t, 0)),
        ("transitivity particle", rule_transitivity),
    ]
    for name, rule in rules:
        hits = []
        for item, entry in corpus:
            why = rule(item, entry, tok)
            if why:
                hits.append((entry["id"], item["jp"], why))
        pct = 100 * len(hits) / len(corpus)
        print(f"{name:44}  rejects {len(hits):4}  ({pct:5.1f}% of known-good)")
        for id_, jp, why in hits[:args.show]:
            print(f"      {id_:10} {jp}\n                 → {why}")
    print()

    dist = collections.Counter(len(unknown_content_words(i, e, tok)) for i, e in corpus)
    print("unknown-content-word count distribution across the known-good corpus:")
    for k in sorted(dist):
        print(f"  {k}: {dist[k]:4}  {'#' * (dist[k] // 8)}")


LEVELS = G.vocab_by_surface()
TRANSITIVITY = load_transitivity()

if __name__ == "__main__":
    main()
