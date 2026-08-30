#!/usr/bin/env python3
"""Instrument 1b — proof by byte identity under a whole-WORD kana substitution.

Run with ./.venv-jp/bin/python (build_rows needs SudachiPy).

WHY
---
964 sentences are withheld from Dictation. 15 of them were never measured: they were
withheld because a word in them was proven misread IN A DIFFERENT SENTENCE, under the
comment *"a voice does not change its mind between sentences"*. Nothing enforced that,
and Kyoko's front-end is context-sensitive by construction.

Instrument 1 renders the whole reading as kana and compares bytes. That changes prosody,
so it decides only 3 of the 15 — the plan's claim that it "can decide each directly" is
measured false.

THE INSTRUMENT
--------------
Keep the sentence in kanji; replace exactly one CONTIGUOUS SPAN of tokens with kana.
Word boundaries and accent context elsewhere are unchanged, so a byte-identical render is
proof about that span in that sentence. A non-match stays silent.

**Spans, not single tokens, and that distinction is the whole correctness of this file.**
An earlier version substituted one token at a time. `四人` is tokenised 四 + 人 but
lexicalises as よにん, so single-token substitution produced `家族は四ひとです` — a text
whose morphology Kyoko never sees in the original — and then reported the sentence
"proven misread" while never testing よにん, the only correct reading. Testing below the
lexeme manufactures a syntactic context and measures that instead.

CALIBRATION
-----------
Three ways, and `--calibrate` runs all of them:

  * **Negative control.** Substitute readings that are definitely wrong (a decoy kana
    string, and a real-but-wrong alternative). If any of them ever renders byte-identical
    to the original, byte identity is not proof and every verdict here is void.
  * **Positive control at scale.** Run against sentences instrument 1 already proved say
    their corpus reading. 1b must agree; a disagreement means the two instruments are
    measuring different things.
  * **Rebuild identity.** Concatenating a sentence's tokens must reproduce its audio
    exactly. This one proves only that the string handling is faithful — it carries no
    linguistic weight, and is not counted as calibration on its own.
"""
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_dictation_readings as C

REPO = Path(__file__).resolve().parent.parent
MAX_SPAN = 3
DECOYS = ["ぷりんてぃん", "ぬめりこ"]      # not readings of anything

# Readings a lexeme takes that SudachiPy's per-token lookup does not offer for the span.
EXTRA = {
    "四人": ["よにん", "よんにん", "よったり"],
    "四": ["よん", "よ", "し"],
    "何": ["なん", "なに"],
    "畑": ["はたけ", "ばたけ"],
    "数分": ["すうふん", "すうぶん"],
    "何だ": ["なんだ", "なにだ"],
    "四ページ": ["よんぺーじ", "よぺーじ", "しぺーじ"],
}


def has_kanji(s):
    return any("一" <= c <= "鿿" for c in s)


def span_candidates(surface, dic_readings):
    cands = set(dic_readings) | set(EXTRA.get(surface, []))
    return sorted(c for c in cands if c)


def substituted(tokens, i, length, kana):
    pieces = [t[0] for t in tokens]
    return "".join(pieces[:i] + [kana] + pieces[i + length:])


def analyse(rows, readings_of, decoys=True, complaint=None):
    """For each row: {span -> {kana: matched?}}, plus the decoy results.

    `complaint` maps row id -> {surface: {readings}}: the hypothesis the PREVIOUS instrument
    named for that sentence. It is added to the candidate list unconditionally, because an
    instrument that declines to test the hypothesis it was pointed at cannot report on it.
    Measured 2026-08-28: Sudachi already proposed it for 518 of 523 silent sentences, so this
    buys five — which is also the finding. The silence is a prosody limit, not a coverage gap,
    and no amount of extra candidates will move it.
    """
    complaint = complaint or {}
    plans, decoy_texts = {}, {}
    for r in rows:
        toks, plan = r["tokens"], {}
        for i in range(len(toks)):
            for L in range(1, MAX_SPAN + 1):
                if i + L > len(toks):
                    break
                surf = "".join(t[0] for t in toks[i:i + L])
                if not has_kanji(surf):
                    continue
                corpus = "".join(t[1] for t in toks[i:i + L])
                extra = complaint.get(r["id"], {}).get(surf, set())
                cands = span_candidates(surf, readings_of(surf) | {corpus} | extra)
                if len(cands) < 2 and corpus in cands:
                    continue                      # nothing to distinguish
                plan[(i, L, surf, corpus)] = {c: substituted(toks, i, L, c) for c in cands}
        plans[r["id"]] = plan
        if decoys and plan:
            i, L, surf, corpus = next(iter(plan))
            decoy_texts[r["id"]] = [substituted(toks, i, L, d) for d in DECOYS]
    texts = [r["exJP"] for r in rows]
    for p in plans.values():
        for m in p.values():
            texts += list(m.values())
    for v in decoy_texts.values():
        texts += v
    C.render(texts)
    return plans, decoy_texts


def verdict(row, plan, disputed):
    """Decide one sentence. `disputed` is the set of surfaces that got it withheld.

    **A release must confirm the DISPUTED word, not merely some word.** The first version
    returned RELEASE as soon as any span agreed with its corpus reading, and the
    pre-submission review found that this released `n2-g210` (彼が殺人を犯した動機は何だ)
    on 彼 = かれ while 何 -- the entire reason it was withheld -- was never confirmed. That
    is this project's oldest defect in a new place: the evidence that released the sentence
    and the reason it was withheld were different predicates, agreeing only by inspection.
    """
    target = C.sha(C.clip(row["exJP"]))
    # `sha` returns None for a clip that is missing or torn. Comparing two of those gives
    # None == None -> True, which is a byte-identical MATCH manufactured out of two absent
    # recordings -- proof of a pronunciation from audio that does not exist. It did not bite
    # (0 of 910 rows had a None target when this ran) but it is one failed render away from a
    # confidently wrong verdict, which is the shape this whole file exists to avoid.
    if target is None:
        return "SILENT", ["no usable render of the sentence itself"]
    agrees, disagrees, covered = [], [], set()
    for (i, L, surf, corpus), cands in plan.items():
        matched = [k for k, txt in cands.items()
                   if (h := C.sha(C.clip(txt))) is not None and h == target]
        if not matched:
            continue
        if corpus in matched:
            agrees.append((surf, corpus))
            covered |= {w for w in disputed if w in surf}
        else:
            disagrees.append((surf, corpus, matched))
    if disagrees:
        return "KEEP", disagrees
    here = {w for w in disputed if w in row["exJP"]}
    if here and not here <= covered:
        return "SILENT", sorted(here - covered)      # the disputed word was never confirmed
    if agrees:
        return "RELEASE", agrees
    return "SILENT", []


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--evidence", default="propagated",
                    help="which evidence class to inspect. The default class was retired by "
                         "v1.28 §A, so a bare run now reports FINISHED; re-point it to "
                         "re-measure, or to attack the 910 'nearest' exclusions.")
    ap.add_argument("--json")
    args = ap.parse_args()

    from sudachipy import Dictionary
    dic, lex = Dictionary(), {}

    def readings_of(surface):
        if surface not in lex:
            try:
                lex[surface] = {C.to_hira(m.reading_form()) for m in dic.lookup(surface)} - {""}
            except Exception:
                lex[surface] = set()
        return lex[surface]

    mism = json.loads((REPO / "docs/measurements/dictation-reading-mismatches.json")
                      .read_text(encoding="utf-8"))
    want = {r["id"] for r in mism["excluded"] if r["evidence"] == args.evidence}
    # The surface that got EACH sentence withheld, per sentence.
    #
    # **Per row, not one global set, and that distinction is worth more than it looks.** The
    # first version built one set from the rows whose evidence begins "proven", which is right
    # for the `propagated` class -- those inherited a verdict about one of THOSE words. Pointed
    # at `nearest`, where every row carries its own complaint ("紙 かみ -> がみ"), the global set
    # matched nothing in 382 of 388 releases, `here` came out empty, and the coverage check was
    # skipped entirely: exactly the defect the pre-submission review caught, reintroduced by
    # aiming a correct predicate at a different population. A predicate that is right for one
    # population and silently vacuous on another is this project's oldest shape wearing a
    # population instead of a call site.
    global_proven = set()
    for r in mism["excluded"]:
        if not r["evidence"].startswith("proven"):
            continue
        parts = r["heardInstead"].split()
        if len(parts) >= 3 and parts[1] != "->":
            global_proven.add(parts[0])

    def disputed_for(row_id):
        """Surfaces that must be CONFIRMED before this sentence may be released."""
        rec = by_id.get(row_id, {})
        parts = (rec.get("heardInstead") or "").split()
        if len(parts) >= 3 and parts[1] != "->" and "->" in parts:
            return {parts[0]}                    # this row's own complaint
        # No per-row complaint (the `propagated` class says only "same word proven misread in
        # another sentence"), so fall back to every word proven misread anywhere.
        return set(global_proven)

    by_id = {r["id"]: r for r in mism["excluded"]}
    every = C.build_rows()
    rows = [r for r in every if r["id"] in want]
    # A withheld id with no buildable row is a REAL condition, not a glitch: build_rows only
    # yields sentences with exJP + exKana + exTokens, and a withheld sentence may have lost one.
    # Naming them and continuing is right; silently comparing lengths and stopping would make
    # the whole run hostage to one stale id, and silently ignoring them would let the report
    # claim a population it never inspected. So: say which, count them, carry on.
    missing = sorted(want - {r["id"] for r in rows})
    if missing:
        print(f"NOT INSPECTED: {len(missing)} of {len(want)} '{args.evidence}' ids have no "
              f"buildable row (no exJP/exKana/exTokens): {missing[:8]}"
              + (" …" if len(missing) > 8 else ""))
        print("  They stay withheld — this instrument has said nothing about them.\n")
    # A run with nothing to inspect must not report OK, and this one could: `len(rows) !=
    # len(want)` passes when BOTH are zero, and every calibration below then succeeds vacuously
    # on an empty population. It printed "OK — decoys never match" over zero rows and exited 0.
    if not rows:
        print(f"NOTHING TO INSPECT: no exclusion carries evidence {args.evidence!r}.")
        print("  This instrument has no population and CANNOT report a result.")
        print("  It is FINISHED, not clean. Re-point --evidence at another class to reuse it.")
        print(f"  Classes present: "
              + ", ".join(f"{k}={v}" for k, v in sorted(
                  __import__("collections").Counter(
                      r["evidence"] for r in mism["excluded"]).items())))
        return 5

    rc = 0
    calibration = None
    if args.calibrate:
        print("CALIBRATION")
        # 1. rebuild identity (string handling only — no linguistic weight)
        C.render([r["exJP"] for r in rows] + ["".join(t[0] for t in r["tokens"]) for r in rows])
        bad = [r["id"] for r in rows
               if C.sha(C.clip(r["exJP"])) != C.sha(C.clip("".join(t[0] for t in r["tokens"])))]
        rebuild_ok = len(rows) - len(bad)
        print(f"  rebuild identity: {len(rows) - len(bad)}/{len(rows)} "
              + (f"FAIL {bad}" if bad else "(string handling only)"))
        if bad:
            rc = 4

        # 2. positive control at scale, against instrument 1's own verdicts.
        # Sampled and rendered deliberately: all_texts(every) is the whole 6,724-sentence
        # corpus times its variants, which does not finish. A stratified sample by level
        # keeps the control honest without rendering the world.
        by_level = {}
        for r in every:
            by_level.setdefault(r["jlpt"], []).append(r)
        sample_rows = [r for lvl in sorted(by_level) for r in by_level[lvl][:40]]
        C.render(C.all_texts(sample_rows))
        ok, _, _ = C.prove(sample_rows)
        sample = ok[:80]
        plans, _ = analyse(sample, readings_of, decoys=False)
        disagreed = [r["id"] for r in sample
                     if verdict(r, plans[r["id"]], disputed_for(r["id"]))[0] == "KEEP"]
        print(f"  positive control: instrument 1 proved {len(sample)} sentences say their corpus "
              f"reading; 1b contradicts {len(disagreed)}")
        if disagreed:
            print(f"    CALIBRATION-FAIL: {disagreed[:8]}")
            rc = 4

        # 3. negative control — decoys must NEVER match
        _, decoys = analyse(rows, readings_of, decoys=True)
        spurious = []
        for cid, txts in decoys.items():
            tgt = C.sha(C.clip(next(r for r in rows if r["id"] == cid)["exJP"]))
            if tgt is None:
                continue                       # never let None == None read as a match
            spurious += [(cid, t) for t in txts if C.sha(C.clip(t)) == tgt]
        decoy_count = sum(len(v) for v in decoys.values())
        print(f"  negative control: {decoy_count} decoy substitutions, "
              f"{len(spurious)} spurious byte matches")
        if spurious:
            print(f"    CALIBRATION-FAIL: byte identity is not proof — {spurious[:4]}")
            rc = 4
        if rc:
            print("\nInstrument not trustworthy. No verdict below may be used.")
            return rc
        print("  OK — decoys never match, and 1b agrees with instrument 1 at scale.\n")
        calibration = {
            "rebuildIdentity": f"{rebuild_ok}/{len(rows)} — string handling only, no linguistic weight",
            "positiveControl": (f"instrument 1 proved {len(sample)} sentences say their corpus "
                                f"reading; 1b contradicts {len(disagreed)}"),
            "negativeControl": (f"{decoy_count} decoy substitutions, {len(spurious)} spurious "
                                f"byte matches"),
        }

    complaint = {}
    for r in rows:
        parts = (by_id.get(r["id"], {}).get("heardInstead") or "").split()
        # `parts[1] != "->"` matters: on a three-part complaint ("かみ -> がみ") parts[1] IS the
        # arrow, and injecting it would put the literal string "->" into the candidate readings.
        # No row has that shape today; the guard is here so none ever silently does.
        if len(parts) >= 4 and "->" in parts and parts[1] != "->":
            complaint[r["id"]] = {parts[0]: {parts[1], parts[-1]}}
    plans, _ = analyse(rows, readings_of, decoys=False, complaint=complaint)
    out = {"release": [], "keep": [], "silent": []}
    print("VERDICTS")
    for r in rows:
        v, detail = verdict(r, plans[r["id"]], disputed_for(r["id"]))
        if v == "RELEASE":
            out["release"].append(r["id"])
            note = "says the corpus reading"
        elif v == "KEEP":
            out["keep"].append({"id": r["id"],
                                "surface": detail[0][0], "corpus": detail[0][1],
                                "kyoko": detail[0][2]})
            note = f"says {detail[0][0]} = {detail[0][2]} not {detail[0][1]}"
        else:
            out["silent"].append(r["id"])
            note = "silent"
        print(f"  {v:8} {r['id']:12} {r['exJP'][:26]:28} {note}")
    print(f"\nRELEASE {len(out['release'])} · KEEP {len(out['keep'])} · SILENT {len(out['silent'])}")
    print(f"  SILENT means this instrument said NOTHING. Those {len(out['silent'])} stay withheld;")
    print( "  silence is not evidence in either direction.")
    no_basis = [r["id"] for r in rows if not disputed_for(r["id"])]
    if no_basis:
        print(f"  ⚠️  {len(no_basis)} row(s) name no disputed surface at all, so nothing "
              f"constrained their release: {no_basis[:6]}")

    if args.json:
        # The record carries its own provenance and its own calibration, and REFUSES to be
        # written by an uncalibrated run. The first version of this file emitted verdicts only,
        # with the reasoning kept in a hand-written companion — and that companion went stale
        # thirteen minutes later when the instrument was fixed, still naming n2-g210 undecided
        # after the span fix had decided it. A measurement whose prose and whose numbers are
        # maintained separately will disagree; this project has now shipped that defect twice.
        if calibration is None:
            print("REFUSING to write a record from an uncalibrated run — pass --calibrate")
            return 4
        record = {
            "measurement": "scripts/check_propagated_exclusions.py",
            # Measured from the renderer's own stderr when this run rendered anything; a run
            # served entirely from cache cannot observe it and says so rather than guessing.
            "voice": C.RESOLVED_VOICE or "not observed — every clip served from cache this run",
            "question": ("The 15 exclusions whose evidence was 'propagated' were never measured. "
                         "They were excluded because a word in them was proven misread IN A "
                         "DIFFERENT SENTENCE, under the comment 'a voice does not change its mind "
                         "between sentences'. This measures each of them directly."),
            "instrument": ("1b: the sentence stays in kanji and exactly one CONTIGUOUS SPAN of "
                           "tokens is replaced by kana, so word boundaries and accent context are "
                           "unchanged. A byte-identical render is proof about that span in that "
                           "sentence; a non-match stays silent."),
            "calibration": calibration,
            "instrument1Recall": ("3 of 15 — the carried-forward plan's claim that 'instrument 1 "
                                  "can decide each directly' is measured FALSE. Rendering the "
                                  "whole reading as kana changes prosody, so byte identity goes "
                                  "silent even where the reading is right."),
            "theCommentIsFalse": ("畑 is read はたけ in n1-b432 and ばたけ in n1-b1000 — same word, "
                                  "same voice, two sentences, two readings, both proven by byte "
                                  "identity. The assumption that justified propagating 15 verdicts "
                                  "is disproven by the data those verdicts were derived from."),
            **out,
        }
        Path(args.json).write_text(json.dumps(record, ensure_ascii=False, indent=1) + "\n",
                                   encoding="utf-8")
        print(f"wrote {args.json}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
