#!/usr/bin/env python3
"""Split a gated batch into review chunks, rendered as the learner's card sees them.

Two rules the v1.17 pilot arrived at the hard way, both encoded here so a rerun cannot lose
them:

**Interleave survivors and gap items.** Concatenating them puts every gap in the last chunk,
and a reviewer who notices their chunk is all one kind calibrates to it. Alternating keeps each
chunk mixed.

**Withhold the gate's routing verdict.** The reviewers' job is to judge the sentence
independently; handing them `vocabularyGap` first makes the gate's opinion their prior, and
then any agreement between gate and review is circular. The pilot's strongest evidence — two
independent methods picking the same four items out of thirty-six — is only worth anything
because neither could see the other's answer.

    python3 scripts/make_review_chunks.py <survivors.json> <gaps.json> <outdir> [--chunks N]
"""
import argparse
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LEVELS = REPO / "Sources/VocabKit/Resources"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("survivors")
    ap.add_argument("gaps")
    ap.add_argument("outdir")
    ap.add_argument("--chunks", type=int, default=8)
    args = ap.parse_args()

    entries = {}
    for path in LEVELS.glob("n[1-5].json"):
        for e in json.load(open(path)):
            entries[e["id"]] = e

    surv = json.load(open(args.survivors))
    gaps = json.load(open(args.gaps))

    def row(x):
        e = entries[x["id"]]
        glosses = (e.get("meanings") or {}).get("en") or []
        return {"id": x["id"], "surface": e["surface"], "reading": e["kana"],
                # the comma-joined line is literally what gloss(for:) renders
                "glosses": ", ".join(glosses),
                "appGlosses": glosses,
                "jp": x["jp"], "en": x.get("en", ""), "zh": x.get("zh", ""),
                "declaredSense": x.get("sense", ""),
                "flag": x.get("reviewFlag", "")}

    rows = []
    for i in range(max(len(surv), len(gaps))):
        if i < len(surv):
            rows.append(row(surv[i]))
        if i < len(gaps):
            rows.append(row(gaps[i]))

    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    size = (len(rows) + args.chunks - 1) // args.chunks
    for i in range(args.chunks):
        chunk = rows[i * size:(i + 1) * size]
        if not chunk:
            continue
        json.dump(chunk, open(out / f"chunk-{i}.json", "w"), ensure_ascii=False, indent=1)
        print(f"chunk-{i}: {len(chunk)}")
    print(f"\n{len(rows)} items across {args.chunks} chunks in {out}")
    print("routing verdict withheld; survivors and gap items interleaved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
