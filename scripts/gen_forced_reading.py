#!/usr/bin/env python3
"""Generate example sentences for entries whose taught reading is the MINORITY one.

The ordinary generator writes the most natural sentence for a word, which for these entries
produces the COMMON reading: asked for 魚 it writes 海の魚を見る (さかな) while the card teaches
うお, and asked for 梅雨 it writes つゆ where the card teaches ばいう. The reading gate then
rejects the sentence, correctly, and the entry stays empty — that is how 25 N3 entries ended
up with no example after three full passes.

The example sentence is DISPLAY-ONLY in the app (GameView renders it under the romaji; the
learner types the word, not the sentence), so the harm is pedagogical rather than a grading
failure: a sentence showing the word under its OTHER reading teaches the wrong association,
which is worse than showing nothing. But it also means the fix is available — a collocation
that forces the minority reading is a perfectly good example, even when the target sits inside
a compound like 魚市場, because nobody has to type it.

So each word here carries a hand-written hint naming the collocations that force its reading,
and the model is told the reading is the requirement and the sentence is negotiable.

    python3 scripts/gen_forced_reading.py /tmp/n3_forced_targets.json /tmp/out
"""
import json
import pathlib
import subprocess
import sys
import time

PROMPT = """You are writing example sentences for a Japanese typing-practice app.
You have NO repository access and no files to open — everything is inline. Do not try to read
or write anything; just produce the answer.

Every word below is a kanji spelling with TWO OR MORE readings, and the app teaches the one
that is NOT the most common. Your single hard requirement:

  **A Japanese reader looking at your sentence must read the target with the reading given,
  not the common one.**

That normally means leaning on a fixed collocation or compound where the minority reading is
the only possibility. Using the target inside a compound is FINE here — the sentence is only
displayed to the learner, never typed — so 「魚市場は朝が早い。」 is a good sentence for 魚/うお
even though 魚 is not standing alone.

Each entry gives you a hint naming the collocations that work. Use one of them unless you know
a better one.

Rules for the sentence itself:
- one sentence, 8 to 40 characters, ending in 。
- plain modern Japanese, vocabulary at or below JLPT N3 apart from the target
- no romaji, no latin letters, no digits, no furigana, no parentheses
- natural — a sentence a native speaker would actually write

Return ONLY a JSON array, one object per word:
  {"id": "...", "jp": "...", "en": "...", "zh": "...", "sense": "...", "forcedBy": "..."}

`sense` is the sense of the word your sentence teaches, in your own words.
`forcedBy` names the collocation or context that makes the given reading the only one
possible, e.g. "魚市場 is read うおいちば". If you cannot make the reading unambiguous, return
an empty jp for that entry rather than a sentence that would be read the common way. An honest
blank is worth more than a wrong example.

Words:
"""


def main():
    words = json.load(open(sys.argv[1]))
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    lines = []
    for w in words:
        lines.append(f"- id={w['id']} 表記={w['surface']} 読み={w['taughtReading']} "
                     f"意味={w.get('glosses')}\n    hint: {w['hint']}")
    prompt = PROMPT + "\n".join(lines)

    t0 = time.time()
    result = subprocess.run(
        ["agy", "--model", "gemini-3.6-flash", "--effort", "high",
         "--print-timeout", "20m", "-p", prompt],
        capture_output=True, text=True, timeout=1500)
    (out / "batch-00.json").write_text(result.stdout)
    print(f"[00] {len(words)} words, {time.time()-t0:.0f}s, {len(result.stdout)} chars")
    return 0


if __name__ == "__main__":
    sys.exit(main())
