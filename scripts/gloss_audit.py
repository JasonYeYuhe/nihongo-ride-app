#!/usr/bin/env python3
"""Split vocabulary entries into chunks for the gloss-coverage audit (PLAN-V1.17 §A1).

The audit asks, per entry, whether the en and zh gloss lists cover the same senses and whether
a COMMON sense is missing from both. It is a judgment task, so it runs as agents over these
chunks rather than as a rule here — the one thing this script must not do is decide anything.

Measured on a 240-word sample of the 872 pending N3 words (2026-08-04): 83% aligned,
15% missing a sense from BOTH lists, 85% low polysemy risk. The problem is concentrated.

    python3 scripts/gloss_audit.py n3 --pending --sample 240 --chunks 6 --out /tmp/gloss-audit
    python3 scripts/gloss_audit.py n3 --pending --chunks 24 --out /tmp/gloss-audit   # all 872
"""
import argparse
import json
import random
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("level", help="n1..n5")
    ap.add_argument("--pending", action="store_true",
                    help="only entries with no example sentence yet")
    ap.add_argument("--sample", type=int, default=0, help="0 = all")
    ap.add_argument("--chunks", type=int, default=6)
    ap.add_argument("--out", default="/tmp/gloss-audit")
    ap.add_argument("--seed", type=int, default=20260804,
                    help="recorded so a sample is reproducible")
    args = ap.parse_args()

    entries = json.load(open(REPO / f"Sources/VocabKit/Resources/{args.level}.json"))
    if args.pending:
        entries = [e for e in entries if not e.get("exJP")]
    if args.sample:
        random.seed(args.seed)
        entries = random.sample(entries, min(args.sample, len(entries)))

    rows = [{"id": e["id"], "surface": e["surface"], "kana": e["kana"],
             "en": (e.get("meanings") or {}).get("en") or [],
             "zh": (e.get("meanings") or {}).get("zh") or []} for e in entries]

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    size = (len(rows) + args.chunks - 1) // args.chunks
    for i in range(args.chunks):
        chunk = rows[i * size:(i + 1) * size]
        if not chunk:
            continue
        (out / f"chunk-{i}.json").write_text(
            json.dumps(chunk, ensure_ascii=False, indent=1))
        print(f"chunk-{i}: {len(chunk)}")
    print(f"{len(rows)} entries -> {out}")


if __name__ == "__main__":
    main()
