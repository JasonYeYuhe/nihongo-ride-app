#!/usr/bin/env python3
"""Generate example sentences for a word list, one batch at a time, via `agy` (Gemini).

Separate from `gen_examples.py`, which still targets the dead `gemini` CLI and a different
prompt. This one exists to be resumable: 939 words is sixteen calls, any of which can time
out, and re-running must not regenerate what already landed.

Every batch is written to its own file under the output directory, so a crash costs one batch.

    scripts/gen_batch.py /tmp/batch_words.json /tmp/batch_out --size 60
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

PROMPT_HEAD = """You write example sentences for a Japanese typing-practice app used by JLPT learners.
You have NO repository access and no files to open — everything is inline. Do not try to read
or write anything; just produce the answer.

For each word below, write ONE example sentence.

HARD REQUIREMENTS — a sentence that breaks any of these is discarded automatically:
- It must USE the word with the READING given. Not a homograph, not a different word that
  merely shares a kanji. If the word has another common reading, make the context force the
  one given.
- One sentence. 5 to 40 characters. Ends with 。
- No latin letters or digits anywhere in the Japanese.
- Natural, everyday Japanese at or below the stated JLPT level. Do not surround an N5 word
  with N2 or harder vocabulary.
- Consistent register. In particular: honorific prefixes and humble/respectful verbs describe
  OTHER people, never the speaker's own family or actions. 「ご両親」 is someone else's
  parents; for your own, write 両親.
- Choose the kanji the meaning calls for: warmth of feeling is 温かい, temperature is 暖かい.
- Nothing violent, sexual, medical-advisory, or reliant on a stereotype.
- Do not merely MENTION the word (「「薬」という字」); use it in its meaning.
- Transitivity must be right. Use the verb you were given, not its partner: 開ける and 開く
  are different words. An intransitive verb does not take a direct object — but を also marks
  a path that is traversed, so 「橋を渡る」, 「階段を上がる」 and 「この道を通る」 are all correct.

Also give an English translation and a Simplified Chinese translation of your sentence.

Return ONLY a JSON array, no prose, no code fence, one object per input line:
[{"id": "...", "jp": "...", "en": "...", "zh": "..."}]

Input — id, surface, reading, level, English gloss, tab-separated:
"""


def batch_prompt(words) -> str:
    lines = []
    for e in words:
        gloss = ", ".join((e.get("meanings") or {}).get("en") or [])
        lines.append(f'{e["id"]}\t{e["surface"]}\t{e["kana"]}\tN{e.get("jlpt")}\t{gloss}')
    return PROMPT_HEAD + "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("words")
    ap.add_argument("outdir")
    ap.add_argument("--size", type=int, default=60)
    ap.add_argument("--model", default="gemini-3.6-flash")
    ap.add_argument("--effort", default="high")
    args = ap.parse_args()

    words = json.load(open(args.words))
    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    batches = [words[i:i + args.size] for i in range(0, len(words), args.size)]
    for n, batch in enumerate(batches):
        dest = outdir / f"batch-{n:02}.json"
        if dest.exists() and dest.stat().st_size > 0:
            print(f"[{n:02}] already done, skipping", flush=True)
            continue
        prompt = batch_prompt(batch)
        started = time.time()
        try:
            result = subprocess.run(
                ["agy", "--model", args.model, "--effort", args.effort,
                 "--print-timeout", "20m", "-p", prompt],
                capture_output=True, text=True, timeout=1500)
            dest.write_text(result.stdout)
            print(f"[{n:02}] {len(batch)} words, {time.time() - started:.0f}s, "
                  f"{len(result.stdout)} chars", flush=True)
        except subprocess.TimeoutExpired:
            print(f"[{n:02}] TIMED OUT — re-run to retry this batch", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
