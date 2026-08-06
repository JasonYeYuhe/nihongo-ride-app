#!/usr/bin/env python3
"""Where does a content batch stand? One command, no hand-assembled greps.

The v1.17 pilot ran as a dozen ad-hoc shell one-liners, which was fine for 245 words and is
not fine for 690. This reports the disposition of a generated batch against the live corpus so
the next stage is chosen from data rather than from memory of what was run.

    python3 scripts/pipeline_status.py /tmp/n3_rest_words.json /tmp/n3_rest_out
"""
import json
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    words, outdir = sys.argv[1], pathlib.Path(sys.argv[2])

    total = len(json.load(open(words)))
    files = sorted(outdir.glob("*.json")) if outdir.exists() else []
    items = []
    for f in files:
        txt = f.read_text()
        m = re.search(r"\[.*\]", txt, re.S)
        if m:
            try:
                items += json.loads(m.group(0))
            except json.JSONDecodeError:
                print(f"  !! {f.name} is not parseable JSON — the batch is incomplete")
    generated = len(items)

    print(f"words in this batch : {total}")
    print(f"batch files written : {len(files)}")
    print(f"sentences generated : {generated}")
    if generated < total:
        print(f"  still generating  : {total - generated} to go")
        return 0

    merged = outdir.parent / (outdir.name + "_merged.json")
    json.dump(items, open(merged, "w"), ensure_ascii=False)
    print(f"merged -> {merged}")

    print("\nrunning the gate...")
    r = subprocess.run([sys.executable, str(REPO / "scripts/pilot_gate.py"), words, str(merged)],
                       capture_output=True, text=True)
    print(r.stdout or r.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
