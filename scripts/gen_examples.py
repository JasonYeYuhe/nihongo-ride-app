#!/usr/bin/env python3
"""
Example-sentence pipeline for Nihongo Ride vocab (the "H" pipeline, scripted).

Generates JLPT-appropriate example sentences for the next words of a level
that don't have one yet, via the Gemini CLI, with machine validation and a
merge step that preserves the JSON file layout.

Usage:
  python3 scripts/gen_examples.py gen n3 --count 120         # one batch
  python3 scripts/gen_examples.py audit n3                   # audit newest batch (writes flags file)
  python3 scripts/gen_examples.py gen n3 --count 120 --dry   # generate + validate, no merge

Machine gates (per sentence):
  - target word appears in exJP (surface, surface stem, kana, or kana stem)
  - exJP 6..42 chars, ends with 。/?/!, single sentence (no internal 。)
  - exEN / exZH present, non-trivial
  - exJP globally unique (across every level file + within the batch)

The audit step asks Gemini to flag unnatural usage / wrong translations.
Flags are written to a file for HUMAN adjudication — never auto-applied
(the auditor over-flags; see design/known-bad-readings.txt history).
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Sources/VocabKit/Resources"
MODEL = "gemini-3.1-pro-preview"
LEVELS = {"n5", "n4", "n3", "n2", "n1"}

JP_END = ("。", "?", "!", "?", "!")


def load_level(level: str):
    path = RES / f"{level}.json"
    return json.loads(path.read_text(encoding="utf-8")), path


def all_existing_sentences():
    seen = set()
    for level in LEVELS:
        data, _ = load_level(level)
        for entry in data:
            if entry.get("exJP"):
                seen.add(entry["exJP"])
    return seen


def gloss_of(entry):
    en = entry.get("meanings", {}).get("en", [])
    return en[0] if en else ""


# Verb classes whose written form changes in a sentence, so the dictionary form does not
# appear literally: 食べる shows up as 食べて / 食べた / 食べます.
INFLECTING_VC = {"godan_u", "godan_k", "godan_g", "godan_s", "godan_t",
                 "godan_n", "godan_b", "godan_m", "godan_r", "ichidan", "zuru"}
SURU_VC = {"suru", "kuru"}
# One spelling, since v1.21 §D collapsed the tag vocabulary and a Swift data test now fails
# on any other. This used to enumerate "i-adjective" and "I-adjective" too, which worked
# only for as long as somebody remembered to add the next spelling a reviewer invented.
INFLECTING_POS = {"adj-i"}
# A stem shorter than this is not evidence. 行く's stem is 行, which appears in 銀行, 旅行,
# 行事 … — matching on it would call almost anything an example of 行く.
MIN_STEM = 2


def _stems(entry):
    """Forms of this entry that a sentence may legitimately contain, besides the headword.

    Class-aware rather than "drop the last character", which was applied to every entry and
    turned the noun 学校 into 学 — so 「数学を勉強します。」 validated as an example of 学校.
    This is the only check that a generated sentence is about the right word, so it has to
    mean something.

    Deliberately biased toward FALSE NEGATIVES. A rejected good sentence costs one more
    generation; an accepted wrong one ships to a learner. Words whose stem is a single
    character (行く → 行) therefore get no stem at all and must appear in full.
    """
    surface, kana = entry["surface"], entry["kana"]
    vc, pos = entry.get("vc"), entry.get("pos", [])
    out = []
    if vc in SURU_VC:
        # 勉強する → 勉強, which is a literal prefix of 勉強して / 勉強します.
        for form, suffix in ((surface, "する"), (kana, "する"),
                             (surface, "くる"), (kana, "くる")):
            if form.endswith(suffix):
                out.append(form[: -len(suffix)])
    elif vc in INFLECTING_VC or any(p in INFLECTING_POS for p in pos):
        out.append(surface[:-1])
        out.append(kana[:-1])
    return [x for x in out if len(x) >= MIN_STEM]


def contains_target(sentence: str, entry) -> bool:
    """Does the sentence actually use this entry's word?"""
    candidates = [entry["surface"], entry["kana"], *_stems(entry)]
    return any(c and c in sentence for c in candidates)


def validate(item, entry, seen_jp):
    jp, en, zh = item.get("exJP", ""), item.get("exEN", ""), item.get("exZH", "")
    if not (6 <= len(jp) <= 42):
        return f"length {len(jp)}"
    if not jp.endswith(JP_END):
        return "no sentence-final punctuation"
    if any(p in jp[:-1] for p in ("。", "!", "?")):
        return "multiple sentences"
    if not contains_target(jp, entry):
        return "target word not in sentence"
    if len(en) < 4 or len(zh) < 2:
        return "translation too short"
    if jp in seen_jp:
        return "duplicate sentence"
    if re.search(r"[a-zA-Z0-9]", jp):
        return "latin chars in exJP"
    return None


def call_gemini(prompt: str) -> str:
    result = subprocess.run(
        ["gemini", "--skip-trust", "-m", MODEL, "-p", prompt, "-o", "text"],
        capture_output=True, text=True, timeout=900,
    )
    if result.returncode != 0:
        raise RuntimeError(f"gemini CLI failed: {result.stderr[:400]}")
    return result.stdout


def parse_jsonl(blob: str):
    items = []
    for line in blob.splitlines():
        line = line.strip().strip("`")
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and obj.get("id"):
            items.append(obj)
    return items


GEN_PROMPT = """You write example sentences for a Japanese-learning typing app. The learners study JLPT {level_label}.

For EACH word below, write ONE short, natural, everyday Japanese example sentence plus faithful English and Simplified Chinese translations.

Hard rules:
- The sentence MUST contain the word (surface form; normal conjugation of verbs/adjectives is fine).
- One sentence only, 8-32 Japanese characters, ending with 。
- Use the word in the everyday sense given by the gloss.
- Surrounding vocabulary should stay at {level_label} difficulty or easier.
- Vary topics and sentence patterns across the batch (daily life, work, travel, weather, feelings, school...). Do not reuse a template.
- Translations must be natural and faithful; Chinese in 简体.
- Output STRICT JSONL: one line per word, exactly {{"id": "...", "exJP": "...", "exEN": "...", "exZH": "..."}}. No markdown, no commentary, no extra keys.

Words ({count}):
{words}"""


def cmd_gen(args):
    level = args.level
    data, path = load_level(level)
    pending = [e for e in data if not e.get("exJP")]
    targets = pending[: args.count]
    if not targets:
        print(f"{level}: nothing without an example — done.")
        return
    print(f"{level}: generating for {len(targets)} words "
          f"({len(pending)} still without examples)")

    seen_jp = all_existing_sentences()
    accepted: dict[str, dict] = {}
    rejected: dict[str, str] = {}
    todo = list(targets)

    for attempt in range(1, args.retries + 2):
        if not todo:
            break
        print(f"-- attempt {attempt}: {len(todo)} words")
        for start in range(0, len(todo), args.chunk):
            chunk = todo[start : start + args.chunk]
            words = "\n".join(
                f'{e["id"]} | {e["surface"]} | {e["kana"]} | {gloss_of(e)}'
                for e in chunk
            )
            prompt = GEN_PROMPT.format(
                level_label=level.upper(), count=len(chunk), words=words
            )
            try:
                blob = call_gemini(prompt)
            except (RuntimeError, subprocess.TimeoutExpired) as err:
                print(f"   chunk failed: {err}")
                continue
            by_id = {e["id"]: e for e in chunk}
            got = 0
            for item in parse_jsonl(blob):
                entry = by_id.get(item["id"])
                if not entry or item["id"] in accepted:
                    continue
                problem = validate(item, entry, seen_jp)
                if problem:
                    rejected[item["id"]] = problem
                    continue
                accepted[item["id"]] = item
                seen_jp.add(item["exJP"])
                got += 1
            print(f"   chunk {start // args.chunk + 1}: +{got}/{len(chunk)}")
            time.sleep(1)
        todo = [e for e in targets if e["id"] not in accepted]

    print(f"accepted {len(accepted)}/{len(targets)}; rejected last-reasons: {len(rejected)}")
    if rejected and args.verbose:
        for wid, why in list(rejected.items())[:20]:
            print(f"   {wid}: {why}")

    if args.dry:
        print("(dry run — not merging)")
        return

    by_id = {item["id"]: item for item in accepted.values()}
    merged = 0
    for entry in data:
        item = by_id.get(entry["id"])
        if item:
            entry["exJP"] = item["exJP"]
            entry["exEN"] = item["exEN"]
            entry["exZH"] = item["exZH"]
            merged += 1
    # No trailing newline — matches how these files were originally written.
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    # Batch manifest so `audit` knows what's new.
    manifest = ROOT / f"review-sheets/examples-batch-{level}-{time.strftime('%Y%m%d-%H%M')}.json"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(
        json.dumps(sorted(by_id.keys()), indent=1), encoding="utf-8"
    )
    print(f"merged {merged} examples into {path.name}; manifest {manifest.name}")


AUDIT_PROMPT = """You are auditing example sentences in a Japanese-learning app (JLPT {level_label} learners). For each item: the target word, its reading, its gloss, the example sentence, and EN/ZH translations.

Flag an item ONLY if it has a REAL error:
- the sentence does not actually use the target word (or uses a different sense than the gloss)
- a grammar error a native speaker would catch
- an English or Chinese translation that mismatches the Japanese

Do NOT flag stylistic preferences, formality choices, or acceptable alternative phrasings. Be conservative: most items are correct.

Output STRICT JSONL, one line per FLAGGED item only:
{{"id": "...", "problem": "<one short sentence>", "suggestion": "<corrected exJP or translation>"}}
If nothing is wrong, output the single word: CLEAN

Items ({count}):
{items}"""


def cmd_audit(args):
    level = args.level
    data, _ = load_level(level)
    manifests = sorted((ROOT / "review-sheets").glob(f"examples-batch-{level}-*.json"))
    if not manifests:
        sys.exit(f"no batch manifest for {level} — run gen first")
    ids = set(json.loads(manifests[-1].read_text()))
    entries = [e for e in data if e["id"] in ids]
    print(f"auditing {len(entries)} sentences from {manifests[-1].name}")

    flags = []
    for start in range(0, len(entries), args.chunk):
        chunk = entries[start : start + args.chunk]
        items = "\n".join(
            f'{e["id"]} | {e["surface"]}({e["kana"]}) | {gloss_of(e)} | {e["exJP"]} | {e["exEN"]} | {e["exZH"]}'
            for e in chunk
        )
        prompt = AUDIT_PROMPT.format(level_label=level.upper(), count=len(chunk), items=items)
        try:
            blob = call_gemini(prompt)
        except (RuntimeError, subprocess.TimeoutExpired) as err:
            print(f"   audit chunk failed: {err}")
            continue
        chunk_flags = [f for f in parse_jsonl(blob) if f.get("id") in ids]
        flags.extend(chunk_flags)
        print(f"   chunk {start // args.chunk + 1}: {len(chunk_flags)} flags")
        time.sleep(1)

    out = manifests[-1].with_name(manifests[-1].stem + "-flags.json")
    out.write_text(json.dumps(flags, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(flags)} flags → {out.name}")
    print("ADJUDICATE BY HAND before changing any data (auditor over-flags).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("gen")
    gen.add_argument("level", choices=sorted(LEVELS))
    gen.add_argument("--count", type=int, default=120)
    gen.add_argument("--chunk", type=int, default=40)
    gen.add_argument("--retries", type=int, default=2)
    gen.add_argument("--dry", action="store_true")
    gen.add_argument("--verbose", action="store_true")
    gen.set_defaults(func=cmd_gen)

    audit = sub.add_parser("audit")
    audit.add_argument("level", choices=sorted(LEVELS))
    audit.add_argument("--chunk", type=int, default=60)
    audit.set_defaults(func=cmd_audit)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
