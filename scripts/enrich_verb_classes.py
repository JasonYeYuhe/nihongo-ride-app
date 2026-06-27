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

WRITE mode (--write, PLAN-V1.6 §B1): stamps the DERIVED verb class (`vc`, a
VerbClass.rawValue string) into the vocab JSON. Only the derived class LABEL is
written — no JMdict text is copied. Verb-class facts come from EDRDG's JMdict_e
(© EDRDG, used under CC-BY-SA 4.0; the in-app About screen carries the attribution).
Bare suru-verbs (vs-s) and entries JMdict can't disambiguate get NO `vc` (withheld),
so they never enter the conjugation pool.
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


def has_kanji(s: str) -> bool:
    return any("一" <= ch <= "鿿" for ch in s)


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
    # JMdict POS entities expand to text like "Godan verb with 'ru' ending". Different
    # dumps quote the row letter with either a backtick+apostrophe (`ru') OR straight
    # apostrophes ('ru') — we strip BOTH from the text before matching, so the needles
    # below carry no quote chars. (Matching the quoted form is the bug that made every
    # godan class silently fail to resolve; see PLAN-V1.6 §Gate-0.) The "with X ending"
    # prefix keeps su/tsu and u/ku/ru from cross-matching.
    POS_TEXT = [
        ("Ichidan verb", "ichidan"),
        ("Godan verb with u ending", "godan_u"),
        ("Godan verb with ku ending", "godan_k"),
        ("Godan verb with gu ending", "godan_g"),
        ("Godan verb with su ending", "godan_s"),
        ("Godan verb with tsu ending", "godan_t"),
        ("Godan verb with nu ending", "godan_n"),
        ("Godan verb with bu ending", "godan_b"),
        ("Godan verb with mu ending", "godan_m"),
        ("Godan verb with ru ending", "godan_r"),
        ("Godan verb - -aru special class", "godan_r"),       # ござる/くださる: engine handles via lemma exc.
        ("Godan verb - Iku/Yuku special class", "godan_k"),   # 行く: engine handles via lemma exc.
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
            txt = (pos.text or "").replace("`", "").replace("'", "")
            # vz "Ichidan verb - zuru verb" (演ずる/応ずる…): the る is part of ずる and the
            # stem shifts ず→じ, so it is NOT a plain ichidan — the engine can't conjugate
            # it. Mark it "zuru" (a withhold sentinel) and do NOT also tag it ichidan
            # (the "Ichidan verb" substring would otherwise match). Genuine godan_r verbs
            # that happen to end ずる (削る/譲る/引きずる) are tagged v5r, not vz, so unaffected.
            if "zuru verb" in txt:
                cls.add("zuru")
                continue
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
        # Three shapes reach here (suru-nouns with pure-kanji surface are caught above):
        #   標準  さっする/察する → bare suru-VERB (vs-s): potential is せる, NOT できる.
        #   罠    こする/擦る     → actually godan_r (kana coincidentally ends する).
        #   仮名  コピーする      → katakana suru-noun, conjugates fine.
        jc = jmdict_lookup(jmdict, surface, kana)
        if jc and jc != "suru":
            return jc, "jmdict"                       # 擦る/こする → godan_r etc.
        if kana == "する":
            return "suru", "heuristic"                # standalone する
        if surface.endswith("する") and not has_noun and has_kanji(surface[:-2]):
            return None, "suru-verb-withheld"          # bare suru-verb: WITHHOLD (§3)
        return "suru", "heuristic"                     # katakana suru-noun (コピーする)
    # Kuru is ONLY the irregular verb 来る (reading …くる). Require BOTH the 来る surface
    # AND a くる reading: excludes 作る/送る (surface not 来る) and 来る/きたる (the godan_r
    # reading 来たる, kana ends る not くる → resolved as godan_r below by JMdict).
    if kana == "くる" or (kana.endswith("くる") and surface.endswith("来る")):
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
        if not cls:
            continue
        if cls == {"zuru"}:
            return None                      # vz verb → withhold (engine can't conjugate)
        usable = cls - {"zuru"}
        if len(usable) == 1:
            return next(iter(usable))
        # multiple senses (e.g. v1 & v5r homographs) → ambiguous, skip
        return None
    return None


def write_mode(jmdict):
    """Stamp the derived `vc` (VerbClass.rawValue) into each vocab JSON, in place.
    Inserts `vc` right after `pos`; never touches other fields; idempotent (re-derives,
    dropping any stale `vc`). Only a definite class is written — withheld/ambiguous/
    unresolved/non-verb entries get no `vc`. Output matches the files' exact 2-space,
    non-ASCII, no-trailing-newline format so diffs show only the added `vc` lines."""
    total = Counter()
    for f in sorted(glob.glob(VOCAB_GLOB)):
        rows = json.load(open(f, encoding="utf-8"))
        n = 0
        new_rows = []
        for e in rows:
            cls, _src = classify(e, jmdict)
            new_e = {}
            for k, v in e.items():
                if k == "vc":
                    continue                       # drop stale vc; re-derive
                new_e[k] = v
                if k == "pos" and cls is not None:
                    new_e["vc"] = cls
            if cls is not None and "vc" not in new_e:
                new_e["vc"] = cls                  # defensive: entry without pos
            if cls is not None:
                n += 1
                total[cls] += 1
            new_rows.append(new_e)
        open(f, "w", encoding="utf-8").write(json.dumps(new_rows, ensure_ascii=False, indent=2))
        print(f"  {os.path.basename(f)}: vc on {n}/{len(rows)} entries", file=sys.stderr)
    print("=== vc written by class ===", file=sys.stderr)
    for c, k in total.most_common():
        print(f"  {k:>5}  {c}", file=sys.stderr)
    print(f"  TOTAL  {sum(total.values())}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jmdict", help="path to JMdict_e (xml or .gz)")
    ap.add_argument("--write", action="store_true",
                    help="stamp derived vc into the vocab JSON in place (PLAN-V1.6 §B1)")
    ap.add_argument("--samples", type=int, default=12, help="how many spot-check samples to print")
    args = ap.parse_args()

    jmdict = None
    if args.jmdict:
        if not os.path.exists(args.jmdict):
            sys.exit(f"JMdict not found: {args.jmdict}")
        print(f"loading JMdict from {args.jmdict} …", file=sys.stderr)
        jmdict = load_jmdict(args.jmdict)
        print(f"  {len(jmdict)} verb (surface,reading) keys", file=sys.stderr)

    if args.write:
        if not jmdict:
            print("WARNING: --write without --jmdict leaves most る/godan_r unresolved; "
                  "pass --jmdict for full coverage.", file=sys.stderr)
        print("writing derived vc into vocab JSON …", file=sys.stderr)
        write_mode(jmdict)
        print("(re-reading written files for the coverage report below)", file=sys.stderr)

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
    SRC_ORDER = ["exact", "heuristic", "heuristic-suru", "jmdict", "ambiguous-ru", "suru-verb-withheld", "unresolved"]
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
