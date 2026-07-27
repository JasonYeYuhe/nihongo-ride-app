#!/usr/bin/env python3
"""Gate a whole run of generated batches, then (with --write) merge the approved ones into
the vocabulary files with provenance.

Two things this does that the old pipeline did not:

**Provenance.** Each example that lands records the model, the prompt version, the batch it
came from and whether a human has signed off. The shipped data has none of that, so there is
currently no way to roll back "everything the 3.6-flash run added" or to tell a reviewed
sentence from an unreviewed one. Ids identify the VOCABULARY row's source, never the example's.

**Nothing ships unreviewed.** `--write` refuses to merge an example whose id is not in the
approval file. The pilot measured a 3.6% defect rate among sentences that pass every
deterministic gate — including a register error (「ご両親」 used for the speaker's own parents)
that no mechanical check can see — so "it passed the gates" is not a licence to ship.

    scripts/apply_batch.py /tmp/batch_words.json /tmp/batch_out                 # gate + report
    scripts/apply_batch.py /tmp/batch_words.json /tmp/batch_out --approved a.json --write
"""
import argparse
import importlib.util
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources" / "VocabKit" / "Resources"

_spec = importlib.util.spec_from_file_location("pilot", REPO / "scripts" / "pilot_gate.py")
pilot = importlib.util.module_from_spec(_spec)
_argv, sys.argv = sys.argv, ["pilot_gate"]
try:
    _spec.loader.exec_module(pilot)
except SystemExit:
    pass
sys.argv = _argv

from sudachipy import Dictionary   # noqa: E402

PROMPT_VERSION = "gen_batch/2026-07-27"


def load_batches(outdir: pathlib.Path):
    """→ [(batch_name, [item, ...])]"""
    out = []
    for path in sorted(outdir.glob("batch-*.json")):
        raw = path.read_text()
        match = re.search(r"\[.*\]", raw, re.S)
        if not match:
            print(f"  !! {path.name}: no JSON array — regenerate this batch", file=sys.stderr)
            continue
        try:
            out.append((path.stem, json.loads(match.group(0))))
        except json.JSONDecodeError as exc:
            print(f"  !! {path.name}: {exc}", file=sys.stderr)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("words")
    ap.add_argument("outdir")
    ap.add_argument("--approved", help="JSON list of ids a human has signed off")
    ap.add_argument("--reviewer", default="")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--json-out", default="/tmp/batch_survivors.json")
    args = ap.parse_args()

    words = {e["id"]: e for e in json.load(open(args.words))}
    tokenizer = Dictionary().create()
    seen = pilot.shipped_sentences()
    levels = pilot.vocab_by_surface()

    survivors, rejected, causes = [], [], {}
    for batch_name, items in load_batches(pathlib.Path(args.outdir)):
        for item in items:
            entry = words.get(item.get("id"))
            if entry is None:
                continue
            reasons = pilot.gates(item, entry, tokenizer, seen, levels)
            jp = (item.get("jp") or "").strip()
            if reasons:
                rejected.append((entry["id"], reasons, jp))
                for r in reasons:
                    causes[r.split(":")[0]] = causes.get(r.split(":")[0], 0) + 1
            else:
                survivors.append({**item, "surface": entry["surface"], "kana": entry["kana"],
                                  "jlpt": entry.get("jlpt"), "batch": batch_name})
            if jp:
                seen.add(jp)

    total = len(survivors) + len(rejected)
    print(f"gated {total} generated sentences for {len(words)} words")
    print(f"  survived: {len(survivors)} ({100 * len(survivors) / max(1, total):.0f}%)")
    print(f"  rejected: {len(rejected)}")
    for cause, n in sorted(causes.items(), key=lambda kv: -kv[1]):
        print(f"     {n:4}  {cause}")
    json.dump(survivors, open(args.json_out, "w"), ensure_ascii=False, indent=2)
    print(f"\nsurvivors → {args.json_out}")

    if not args.write:
        print("(gate only — pass --approved with --write to merge)")
        return 0

    if not args.approved:
        sys.exit("--write needs --approved: nothing ships without a human having read it")
    approved = set(json.load(open(args.approved)))
    by_id = {s["id"]: s for s in survivors if s["id"] in approved}
    missing = approved - set(by_id)
    if missing:
        print(f"  !! {len(missing)} approved ids are not among the survivors, ignoring them")

    written = 0
    for path in sorted(RESOURCES.glob("n[1-5].json")):
        data = json.load(path.open())
        changed = False
        for entry in data:
            item = by_id.get(entry["id"])
            if not item or (entry.get("exJP") or "").strip():
                continue
            entry["exJP"], entry["exEN"], entry["exZH"] = item["jp"], item["en"], item["zh"]
            entry["exMeta"] = {"model": "gemini-3.6-flash", "prompt": PROMPT_VERSION,
                               "batch": item["batch"], "reviewer": args.reviewer}
            changed = True
            written += 1
        if changed:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {written} examples with provenance")
    return 0


if __name__ == "__main__":
    sys.exit(main())
