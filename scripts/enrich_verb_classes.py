#!/usr/bin/env python3
"""B0 verb-class data spike (PLAN-V1.5 §B0) — MEASURE ONLY, no data is written.

Reports, per JLPT level and by SOURCE, how much of the verb set can be assigned a
conjugation class `verbClass ∈ {ichidan, godan_{k,g,s,t,n,b,m,r,u}, suru, kuru}`:

  1. exact      — explicit POS label (v1 / v5x / vs). Only ~107 entries carry these.
  2. heuristic  — kana-ending + okurigana gate, with the double exclusion that drops
                  the ~480 suru-nouns ([n,v] / pure-kanji-no-okurigana). る-ending is
                  left AMBIGUOUS (ichidan vs godan_r) — it is NOT resolved heuristically.
  3. jmdict     — (optional) exact v1/v5x pulled from a local JMdict_e file, used to
                  break the る ambiguity and cover bare-`v` core verbs.
  4. unresolved — excluded from conjugation practice (we do not guess).

Run:  python3 scripts/enrich_verb_classes.py [--jmdict PATH_TO_JMdict_e[.gz]]

The gate for promoting Workstream B into v1.5 is NOT this coverage % — it is the
ConjugationKit golden set running 100% correct (see PLAN-V1.5 §B0 决策闸). This
script quantifies how load-bearing JMdict is, to inform the JMdict go/no-go.
"""
from __future__ import annotations
import argparse
import glob
import gzip
import json
import os
import sys
from collections import defaultdict, Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VOCAB_GLOB = os.path.join(REPO, "Sources/VocabKit/Resources/n[1-5].json")

# Dictionary-form final kana → godan row (る is intentionally absent: ambiguous).
GODAN_ENDING = {
    "う": "godan_u", "く": "godan_k", "ぐ": "godan_g", "す": "godan_s",
    "つ": "godan_t", "ぬ": "godan_n", "ぶ": "godan_b", "む": "godan_m",
}
EXACT_LABEL = {
    "v1": "ichidan",
    "v5u": "godan_u", "v5k": "godan_k", "v5g": "godan_g", "v5s": "godan_s",
    "v5t": "godan_t", "v5n": "godan_n", "v5b": "godan_b", "v5m": "godan_m",
    "v5r": "godan_r",
    "vs": "suru",
}
VERBISH = {"v", "verb", "vi", "vt"}          # generic verb tags (no class info)
NOUN_TAGS = {"n", "noun"}


def is_hiragana(ch: str) -> bool:
    return "぀" <= ch <= "ゟ"


def has_okurigana(surface: str, kana: str) -> bool:
    """A genuine inflecting verb shows kana okurigana in its surface form
    (食べる ends る, 帰る ends る); a suru-noun is pure kanji (暗殺)."""
    return bool(surface) and is_hiragana(surface[-1])


def load_vocab():
    rows = []
    for f in sorted(glob.glob(VOCAB_GLOB)):
        rows.extend(json.load(open(f, encoding="utf-8")))
    return rows


def load_jmdict(path: str):
    """Returns {(surface, reading): set(verb_class)} from JMdict_e XML. Best-effort;
    only verb POS entries are kept. Accepts .gz or plain XML."""
    import xml.etree.ElementTree as ET
    opener = gzip.open if path.endswith(".gz") else open
    classes: dict[tuple[str, str], set[str]] = defaultdict(set)
    # JMdict POS entities look like "Godan verb with `ru' ending" etc.; map the
    # canonical entity codes (v1, v5r, v5k, ...) which appear as &v5r; expanded text.
    # We parse <sense><pos> text and match known substrings.
    POS_TEXT = [
        ("Ichidan verb", "ichidan"),
        ("Godan verb with `u'", "godan_u"),
        ("Godan verb with `ku'", "godan_k"),
        ("Godan verb with `gu'", "godan_g"),
        ("Godan verb with `su'", "godan_s"),
        ("Godan verb with `tsu'", "godan_t"),
        ("Godan verb with `nu'", "godan_n"),
        ("Godan verb with `bu'", "godan_b"),
        ("Godan verb with `mu'", "godan_m"),
        ("Godan verb with `ru'", "godan_r"),
        ("suru verb", "suru"),
        ("Kuru verb", "kuru"),
    ]
    ctx = ET.iterparse(opener(path, "rb"), events=("end",))
    for _, elem in ctx:
        if elem.tag != "entry":
            continue
        kebs = [k.text for k in elem.findall("./k_ele/keb") if k.text]
        rebs = [r.text for r in elem.findall("./r_ele/reb") if r.text]
        cls = set()
        for pos in elem.findall("./sense/pos"):
            txt = pos.text or ""
            for needle, c in POS_TEXT:
                if needle in txt:
                    cls.add(c)
        if cls:
            surfaces = kebs or rebs
            for s in surfaces:
                for r in rebs:
                    classes[(s, r)].update(cls)
                classes[(s, s)].update(cls)   # key by surface alone too
            for r in rebs:
                classes[(r, r)].update(cls)   # kana-only verbs keyed by reading
        elem.clear()
    return classes


def classify(entry, jmdict):
    """Returns (verb_class_or_None, source). source ∈
    {exact, heuristic, heuristic-suru, jmdict, ambiguous-ru, unresolved, not-verb}."""
    pos = [p.lower() for p in entry.get("pos", [])]
    pset = set(pos)
    surface = entry.get("surface", "")
    kana = entry.get("kana", "")

    # 1. exact labels (handle v1/v5x case-insensitively; vs)
    for p in pos:
        if p in EXACT_LABEL:
            return EXACT_LABEL[p], "exact"

    verbish = bool(pset & VERBISH)
    if not verbish:
        return None, "not-verb"

    has_noun = bool(pset & NOUN_TAGS)
    okuri = has_okurigana(surface, kana)

    # 2. suru-noun double-exclusion gate: [n,v] or pure-kanji-no-okurigana → suru
    #    composition (noun+する), NEVER godan-by-kana-ending.
    if has_noun or not okuri:
        # JMdict may still confirm a real class for these; try it before suru-default.
        jc = jmdict_lookup(jmdict, surface, kana)
        if jc:
            return jc, "jmdict"
        return "suru", "heuristic-suru"

    # standalone irregulars
    if kana.endswith("する"):
        return "suru", "heuristic"
    if kana in ("くる", "来る") or kana.endswith("くる"):
        return "kuru", "heuristic"

    end = kana[-1] if kana else ""
    if end in GODAN_ENDING:
        return GODAN_ENDING[end], "heuristic"

    if end == "る":
        # ambiguous ichidan vs godan_r — only JMdict / exact label resolves it.
        jc = jmdict_lookup(jmdict, surface, kana)
        if jc:
            return jc, "jmdict"
        return None, "ambiguous-ru"

    # verbish but not a recognizable dictionary-form ending
    jc = jmdict_lookup(jmdict, surface, kana)
    if jc:
        return jc, "jmdict"
    return None, "unresolved"


def jmdict_lookup(jmdict, surface, kana):
    if not jmdict:
        return None
    for key in ((surface, kana), (kana, kana), (surface, surface)):
        cls = jmdict.get(key)
        if cls and len(cls) == 1:
            return next(iter(cls))
        if cls:
            # multiple senses (e.g. v1 & v5r homographs) → ambiguous, skip
            return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jmdict", help="path to JMdict_e (xml or .gz)")
    ap.add_argument("--samples", type=int, default=12, help="how many spot-check samples to print")
    args = ap.parse_args()

    jmdict = None
    if args.jmdict:
        if not os.path.exists(args.jmdict):
            sys.exit(f"JMdict not found: {args.jmdict}")
        print(f"loading JMdict from {args.jmdict} …", file=sys.stderr)
        jmdict = load_jmdict(args.jmdict)
        print(f"  {len(jmdict)} verb (surface,reading) keys", file=sys.stderr)

    rows = load_vocab()

    # per-level, per-source counts over the VERB set (verbish or exact-labeled)
    levels = [5, 4, 3, 2, 1]
    by_level = {lv: Counter() for lv in levels}
    verb_total = {lv: 0 for lv in levels}
    samples = defaultdict(list)
    class_hist = Counter()

    for e in rows:
        lv = e.get("jlpt")
        cls, src = classify(e, jmdict)
        if src == "not-verb":
            continue
        verb_total[lv] += 1
        by_level[lv][src] += 1
        if cls:
            class_hist[cls] += 1
        if len(samples[src]) < args.samples:
            samples[src].append(f"{e.get('surface')}/{e.get('kana')} pos={e.get('pos')} -> {cls}")

    # report
    SRC_ORDER = ["exact", "heuristic", "heuristic-suru", "jmdict", "ambiguous-ru", "unresolved"]
    def resolved(src): return src in ("exact", "heuristic", "heuristic-suru", "jmdict")

    print("\n=== B0 verb-class coverage by JLPT and source (MEASURE ONLY) ===")
    hdr = f"{'lvl':>4} {'verbs':>6} " + " ".join(f"{s:>14}" for s in SRC_ORDER) + f" {'resolved%':>9}"
    print(hdr)
    grand = Counter(); gtot = 0; gres = 0
    for lv in levels:
        c = by_level[lv]; tot = verb_total[lv]
        res = sum(c[s] for s in SRC_ORDER if resolved(s))
        grand.update(c); gtot += tot; gres += res
        cells = " ".join(f"{c[s]:>14}" for s in SRC_ORDER)
        pct = (100.0 * res / tot) if tot else 0.0
        print(f"N{lv:>3} {tot:>6} {cells} {pct:>8.1f}%")
    cells = " ".join(f"{grand[s]:>14}" for s in SRC_ORDER)
    print(f"{'ALL':>4} {gtot:>6} {cells} {(100.0*gres/gtot if gtot else 0):>8.1f}%")

    # N5-N3 subset (the plan's ~23% pure-heuristic claim)
    n53_tot = sum(verb_total[lv] for lv in (5, 4, 3))
    n53_heur = sum(by_level[lv][s] for lv in (5, 4, 3) for s in ("exact", "heuristic", "heuristic-suru"))
    n53_jm = sum(by_level[lv]["jmdict"] for lv in (5, 4, 3))
    print(f"\nN5–N3 verbs={n53_tot}  exact+heuristic(no JMdict)={n53_heur} ({100.0*n53_heur/n53_tot:.1f}%)"
          f"  +jmdict={n53_jm} ({100.0*(n53_heur+n53_jm)/n53_tot:.1f}%)")
    amb = sum(by_level[lv]['ambiguous-ru'] for lv in (5,4,3))
    print(f"N5–N3 still-ambiguous る (needs JMdict)={amb}")

    print("\n=== resolved class histogram ===")
    for cls, n in class_hist.most_common():
        print(f"  {n:>5}  {cls}")

    print("\n=== spot-check samples per source ===")
    for src in SRC_ORDER:
        if samples.get(src):
            print(f"[{src}]")
            for s in samples[src]:
                print(f"    {s}")


if __name__ == "__main__":
    main()
