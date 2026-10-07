#!/usr/bin/env python3
"""Collapse the part-of-speech tag spellings to one vocabulary (PLAN-V1.21 §D).

The `pos` field accumulated 42 distinct tags for what is really about 20 classes,
because every generation batch and every reviewer round-trip wrote its own spelling.
`import_review_sheets.py` writes back whatever a human typed in the sheet, with no
normalisation, which is the pipe new spellings arrive through.

PLAN-V1.21 §D names the i-adjective tag as the untidy one. It is not — it is the
SMALLEST of six families with the same problem: 9 entries carry `i-adjective` or
`I-adjective` against 212 canonical `adj-i`, while `noun`/`Noun` account for 620
occurrences against `n`. Fixing only the one the plan happened to notice would leave
the next reader hitting the same wall in a bigger room. (The plan also says there are
"nine variants" of the i-adjective tag; there are three spellings across nine entries.
Corrected there and in the state snapshot alongside this change.)

Only spellings are merged. Nothing that carries extra information is touched: `vt`,
`vi`, `vs`, `v1`, `v5*` stay as they are, and `adj-no`/`adj-t`/`adj-f`/`adv-to` are
distinct classes, not misspellings of their neighbours.

This edit is invisible to `check_vocab_diff.py` — `pos` is not in FROZEN and is not
compared at all — so the guard's silence here is not evidence of anything. What
enforces it going forward is a data test over the canonical vocabulary
(`ConjugationDataTests`), which fails on any tag outside the set below.

    python3 scripts/normalize_pos_tags.py            # report only
    python3 scripts/normalize_pos_tags.py --write
"""
import argparse
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from corpus_io import CorpusFile   # noqa: E402

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"

# spelling -> canonical. Every key is a different way of writing its value, never a
# different meaning from it.
ALIASES = {
    "noun": "n", "Noun": "n",
    "verb": "v", "Verb": "v",
    "adverb": "adv", "Adverb": "adv",
    "na-adjective": "adj-na", "Na-adjective": "adj-na",
    "i-adjective": "adj-i", "I-adjective": "adj-i",
    "conjunction": "conj", "Conjunction": "conj",
    "pronoun": "pron",
    "Suffix": "suf",
    "expression": "exp", "Phrase": "exp",
}

# The complete set a shipped entry may use after normalisation. Kept here as the single
# written-down answer; the Swift data test asserts the data against the same list.
CANONICAL = {
    "n", "v", "adj-i", "adj-na", "adj-no", "adj-t", "adj-f",
    "adv", "adv-to", "conj", "pron", "suf", "pref", "num", "exp", "int",
    "vs", "vt", "vi", "v1", "v5r", "v5s", "v5m", "v5g", "v5u", "v5t",
}


def normalise(tags):
    """Aliases applied, order preserved, duplicates the merge creates removed.

    A merge can duplicate: an entry tagged ['n', 'Noun'] becomes ['n', 'n'], which is
    one tag written twice, not two senses. Order is preserved because nothing reads
    `pos` positionally today and a stable order keeps the diff readable.
    """
    out, seen = [], set()
    for tag in tags:
        canon = ALIASES.get(tag, tag)
        if canon not in seen:
            seen.add(canon)
            out.append(canon)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="apply the change")
    args = ap.parse_args(argv)

    changed_entries = 0
    moves = collections.Counter()
    leftovers = collections.Counter()
    to_write = []

    for path in sorted(RESOURCES.glob("n[1-5].json")):
        corpus = CorpusFile(path)
        entries = corpus.data
        touched = 0
        for e in entries:
            before = e.get("pos") or []
            after = normalise(before)
            if after != before:
                touched += 1
                for tag in before:
                    if ALIASES.get(tag, tag) != tag:
                        moves[f"{tag} -> {ALIASES[tag]}"] += 1
                e["pos"] = after
            for tag in after:
                if tag not in CANONICAL:
                    leftovers[tag] += 1
        changed_entries += touched
        print(f"{path.name}: {touched} entries normalised")
        if touched:
            to_write.append(corpus)

    # This said "indent=2 + trailing newline: byte-for-byte the shipped layout". It was, when it
    # was written (d2bec44, 2026-08-10); since abac89d (2026-08-21) the files are indent=1, and a
    # --write would have re-indented every line of each file it touched. Now each file goes back
    # through corpus_io in the layout it was read in, so the diff is the tags that moved and
    # nothing else — and a touched file that cannot be written back byte for byte (another
    # layout, CRLF line endings) stops the run before ANY file is written. The report says so too.
    refused = [corpus for corpus in to_write if not corpus.round_trips()]
    for corpus in refused:
        print(f"REFUSED: {corpus.refusal()}")
    if args.write:
        if refused:
            raise SystemExit("nothing written")
        for corpus in to_write:
            corpus.write()
            print(f"wrote {corpus.path.name}")

    print(f"\n{changed_entries} entries touched")
    for move, n in moves.most_common():
        print(f"  {move:28s} {n}")
    if leftovers:
        print("\nTAGS OUTSIDE THE CANONICAL SET (neither aliased nor allowed):")
        for tag, n in leftovers.most_common():
            print(f"  {tag!r}: {n}")
        print("Decide whether each is a new class or a new misspelling before shipping.")
    if not args.write:
        print("\n(report only — pass --write to apply)")
    return 1 if leftovers else 0


if __name__ == "__main__":
    raise SystemExit(main())
