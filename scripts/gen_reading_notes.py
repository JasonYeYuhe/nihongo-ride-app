#!/usr/bin/env python3
"""Builds the shipped reading notes for the entries no example sentence can teach.

PLAN-V1.21 §C offered two ways out for the 225: keep them and mark them, or retire
them. Both external reviewers said retire, and both argued from the same premise —
that a card asks "given this spelling, what reading?" and these cards leave that
underdetermined. That premise is false for this app, which is why the answer here is
neither of theirs. Every mode PRINTS the reading beside the spelling: the word card
renders `kanaReading` unconditionally (assistance gates the romaji, not the kana), the
conjugation drill shows the dictionary reading, and dictation never draws these
entries because it needs an example sentence they do not have. The learner is asked to
TYPE a reading they can see, never to choose one.

So the harm the reviewers described — drilling a minority reading in a vacuum until
you over-apply it — needs a recall task this app does not have. Retiring 222 entries
and every learner's progress on them to fix a problem the interface already prevents
is the more expensive mistake.

What their critique DOES earn is the shape of the note. Codex: "'a sentence could not
be generated' is implementation history, not information useful to the learner." Right
— so these notes say nothing about sentences or pipelines. They say the one thing the
card is missing, which measurement made concrete: 29 of the 98 sibling pairs ship
BYTE-IDENTICAL English glosses. 鼠/ねず and 鼠/ねずみ are two cards with the same kanji
and the same definition, and nothing on either says which one an ordinary sentence
would use. That is worth telling a learner whether or not an example exists.

ONE note kind ships, and the other was cut after it was checked rather than trusted.

    commonIs   — this spelling's everyday reading is X, and it has its own card

The cut half was `lessCommon`, built from the measurement file's `defaultReading`. The
field name promises "the everyday reading of this spelling"; what it actually holds is
whatever the pipeline's tokenizer produced while judging a generated sentence, and on
the first six N5 cards it was backwards three times. It would have printed "言う is
usually read ゆう" on the very card v1.18 created by RETIRING 言う/ゆう as the colloquial
form, and "箱 is usually read ばこ" when ばこ only occurs in compounds.

Checking those claims against the corpus's own 6,737 reviewed sentences contradicted
only one outright — and had no evidence at all for 99 of 118, which is why "only one
contradiction" is not a pass. An instrument blind to 84% of its cases reporting one
problem says nothing about the other 99.

`commonIs` survives because it has a second source: the everyday reading it names is
not asserted, it is a sibling ENTRY that exists in the corpus with that spelling and
that reading.

WHICH sibling, though, is where the first version of this got it WRONG and shipped three
false statements into review. It named whichever sibling carried a reviewed sentence, and
checked that against how often the corpus reads that spelling each way. That check is
CIRCULAR: the corpus's token readings only count sentences that exist, and sentences only
exist for the entry that got one. 日本 read にっぽん 52 times in the corpus says nothing
about Japanese and everything about which of the two 日本 entries the pipeline served — so
the にほん card was told its reading was the unusual one, which is backwards. 辛い/からい at
N5 was told the usual reading is つらい. 下/げ was pointed at しも while した ships at N5.

The signal that is NOT circular is the JLPT level. The corpus's levels come from the JLPT
lists, which are built from what learners meet first, and nothing about them depends on
which entry this pipeline happened to give a sentence to. So a note ships only when the
sibling it names is STRICTLY EASIER than the card, and is the easiest reading of that
spelling in the corpus. Same level means no signal, and no signal means no note — 日本 is
exactly that case and now gets nothing instead of getting it backwards.

The token-frequency check is kept, but demoted to a VETO: it can contradict a note (the
corpus reads this spelling the card's way more often), never support one.

    python3 scripts/gen_reading_notes.py            # report
    python3 scripts/gen_reading_notes.py --write
"""
import argparse
import collections
import glob
import json
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"
SOURCE = REPO / "docs/measurements/entries-no-sentence-can-teach.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    blocked = json.loads(SOURCE.read_text(encoding="utf-8"))
    entries = []
    for f in sorted(RESOURCES.glob("n[1-5].json")):
        entries += json.loads(f.read_text(encoding="utf-8"))
    by_id = {e["id"]: e for e in entries}
    by_surface = collections.defaultdict(list)
    for e in entries:
        by_surface[e["surface"]].append(e)
    # How each spelling is ACTUALLY read across every reviewed example sentence — the
    # second source a note has to survive.
    corpus_readings = collections.defaultdict(collections.Counter)
    for e in entries:
        for surface, reading in (e.get("exTokens") or []):
            corpus_readings[surface][reading] += 1

    notes, skipped = [], []
    for x in blocked["entries"]:
        if x["id"] not in by_id:
            skipped.append((x["id"], "retired since the list was written"))
            continue
        if by_id[x["id"]].get("exJP"):
            skipped.append((x["id"], "has an example now"))
            continue
        if not x["kind"].startswith("minority"):
            # The `lessCommon` half, cut. See the module docstring: `defaultReading` does
            # not hold what its name says, and nothing corroborates it.
            skipped.append((x["id"], "no second source for the claimed everyday reading"))
            continue
        # The EASIEST recorded sibling, not the first one listed. 下 records both しも and
        # した; taking the first meant naming しも as the everyday reading of a spelling whose
        # everyday reading ships at N5.
        candidates = [s for s in x["siblings"] if s.get("kana") and s["id"] in by_id]
        sibling = max(candidates, key=lambda s: by_id[s["id"]]["jlpt"], default=None)
        if not sibling:
            skipped.append((x["id"], "no sibling reading recorded"))
            continue
        other = by_id.get(sibling["id"])
        if other is None:
            skipped.append((x["id"], f"sibling {sibling['id']} is not in the corpus"))
            continue
        if not other.get("exJP"):
            # No reviewed sentence in which that spelling is read that way, so the claim
            # rests on the measurement file alone — which is what was cut above.
            skipped.append((x["id"], f"sibling {sibling['id']} has no reviewed sentence"))
            continue

        me = by_id[x["id"]]
        # A bigger `jlpt` number is an EASIER level (N5 = 5). The named sibling has to be
        # strictly easier than this card, and the easiest reading of the spelling there is —
        # otherwise the note points at a reading that is not the everyday one, which is
        # worse than saying nothing.
        family = by_surface.get(me["surface"], [])
        easiest = max((f["jlpt"] for f in family), default=me["jlpt"])
        if other["jlpt"] <= me["jlpt"]:
            skipped.append((x["id"], f"sibling {sibling['id']} is not at an easier level "
                                     f"(N{other['jlpt']} vs N{me['jlpt']}) — no evidence "
                                     f"which reading is the everyday one"))
            continue
        if other["jlpt"] < easiest:
            other_easiest = [f for f in family if f["jlpt"] == easiest]
            skipped.append((x["id"], f"sibling {sibling['id']} is not the easiest reading of "
                                     f"{me['surface']} — {other_easiest[0]['id']} "
                                     f"({other_easiest[0]['kana']}) is at N{easiest}"))
            continue

        seen = corpus_readings.get(me["surface"], {})
        if seen.get(me["kana"], 0) > seen.get(sibling["kana"], 0):
            # A veto, never support: these counts only cover sentences that exist.
            skipped.append((x["id"], "the corpus's own sentences read this spelling the "
                                     "card's way more often than the sibling's"))
            continue
        notes.append({"id": x["id"], "kind": "commonIs", "common": sibling["kana"],
                      "siblingID": sibling["id"]})

    # The nine blocked by repeated failure are NOT annotated. Their defect is not "this
    # spelling has another reading" — it is that no sentence could force the taught one, or
    # that the headword itself was wrong. Three of those were resolved as data in this same
    # release; the remaining six need authored Japanese, not a label.
    payload = {
        "measurement": "scripts/gen_reading_notes.py",
        "source": "docs/measurements/entries-no-sentence-can-teach.json",
        "date": "2026-08-11",
        "what": "the reading each of these cards teaches is not the everyday reading of its "
                "spelling — the note says which one is, so two cards with the same kanji "
                "and the same gloss are no longer indistinguishable",
        "notes": sorted(notes, key=lambda n: n["id"]),
    }

    print(f"notes: {len(payload['notes'])}  "
          f"({collections.Counter(n['kind'] for n in payload['notes'])})")
    if skipped:
        print(f"skipped {len(skipped)}:")
        for eid, why in skipped:
            print(f"    {eid}: {why}")
    if args.write:
        out = RESOURCES / "reading-notes.json"
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size // 1024} KB)")
    else:
        print("(report only — pass --write)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
