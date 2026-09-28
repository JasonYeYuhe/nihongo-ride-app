#!/usr/bin/env python3
"""
Practice-passage pipeline (the "para" pipeline, scripted).

Generates literary hiragana paragraphs for Practice mode's hard tier via the
Gemini CLI. The model writes a PUNCTUATED hiragana paragraph (display); the
typing target (kana) is derived by stripping punctuation, so the two can
never drift apart. Engine typeability is enforced later by `swift test`
("practice passages load and every kana is typeable by the engine").

Usage:
  python3 scripts/gen_passages.py gen --count 50
  python3 scripts/gen_passages.py gen --count 50 --dry
  python3 scripts/gen_passages.py audit
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from corpus_io import escape_residue   # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PASSAGES = ROOT / "Sources/VocabKit/Resources/passages.json"
MODEL = "gemini-3.1-pro-preview"

HIRAGANA = re.compile(r"^[ぁ-ゖー]+$")
PUNCT = "、。!?「」 　"


def strip_punct(text: str) -> str:
    return "".join(ch for ch in text if ch not in PUNCT)


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
        if isinstance(obj, dict):
            items.append(obj)
    return items


GEN_PROMPT = """You write short literary Japanese paragraphs for a typing-practice app. Learners type them in hiragana, so the entire paragraph must be written in HIRAGANA ONLY (no kanji, no katakana, no latin, no digits).

Write {count} distinct paragraphs. Each:
- 2-3 sentences, 60-110 hiragana characters total (excluding punctuation)
- Quiet, literary, sensory tone — a moment observed: seasons, light, weather, a street at dusk, tea steam, distant trains, memory, small epiphanies. (Like polished diary prose, 随筆風.)
- Standard punctuation: 、 and 。 only. Every paragraph ends with 。
- Natural modern Japanese; avoid archaic grammar. The ONLY script is hiragana (ー allowed for long vowels).
- Vary subjects and imagery strongly across the batch; no repeated openings.
- topic: one short lowercase English word for the theme.
- Translations: natural English (en) and Simplified Chinese (zh) of the whole paragraph.

Output STRICT JSONL, one line each, exactly:
{{"display": "<punctuated hiragana paragraph>", "topic": "...", "en": "...", "zh": "..."}}
No markdown fences, no commentary."""


def validate(item, seen_kana):
    display = item.get("display", "")
    kana = strip_punct(display)
    if not display.endswith("。"):
        return None, "missing final 。"
    if not HIRAGANA.match(kana or "x"):
        bad = "".join(sorted({c for c in kana if not HIRAGANA.match(c)}))[:10]
        return None, f"non-hiragana chars: {bad}"
    if not (55 <= len(kana) <= 120):
        return None, f"kana length {len(kana)}"
    if kana in seen_kana:
        return None, "duplicate"
    sentences = [s for s in display.split("。") if s]
    if not (2 <= len(sentences) <= 3):
        return None, f"{len(sentences)} sentences"
    if len(item.get("en", "")) < 20 or len(item.get("zh", "")) < 10:
        return None, "translation too short"
    for lang in ("en", "zh"):
        residue = escape_residue(item[lang])
        if residue:
            return None, f"{lang} carries {residue}"
    return kana, None


def next_para_number(data) -> int:
    best = 100
    for p in data:
        match = re.fullmatch(r"para(\d+)", p["id"])
        if match:
            best = max(best, int(match.group(1)))
    return best + 1


def cmd_gen(args):
    data = json.loads(PASSAGES.read_text(encoding="utf-8"))
    seen_kana = {p["kana"] for p in data}
    accepted = []
    rounds = 0

    while len(accepted) < args.count and rounds < args.max_rounds:
        rounds += 1
        want = min(args.chunk, args.count - len(accepted))
        print(f"-- round {rounds}: asking for {want} (have {len(accepted)}/{args.count})")
        try:
            blob = call_gemini(GEN_PROMPT.format(count=want))
        except (RuntimeError, subprocess.TimeoutExpired) as err:
            print(f"   round failed: {err}")
            continue
        got = 0
        for item in parse_jsonl(blob):
            if len(accepted) >= args.count:
                break
            kana, problem = validate(item, seen_kana)
            if problem:
                if args.verbose:
                    print(f"   reject: {problem} | {item.get('display', '')[:30]}")
                continue
            seen_kana.add(kana)
            accepted.append({
                "kana": kana,
                "display": item["display"],
                "topic": re.sub(r"[^a-z]", "", item.get("topic", "moment").lower()) or "moment",
                "en": item["en"].strip(),
                "zh": item["zh"].strip(),
            })
            got += 1
        print(f"   +{got} accepted")
        time.sleep(1)

    print(f"accepted {len(accepted)}/{args.count} after {rounds} rounds")
    if args.dry:
        for a in accepted[:5]:
            print("  ", a["display"][:60])
        print("(dry run — not merging)")
        return

    number = next_para_number(data)
    new_ids = []
    for item in accepted:
        pid = f"para{number}"
        number += 1
        new_ids.append(pid)
        data.append({
            "id": pid,
            "kana": item["kana"],
            "topic": item["topic"],
            "level": "hard",
            "meanings": {"en": item["en"], "zh": item["zh"]},
            "display": item["display"],
        })
    PASSAGES.write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    manifest = ROOT / f"review-sheets/passages-batch-{time.strftime('%Y%m%d-%H%M')}.json"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(json.dumps(new_ids, indent=1), encoding="utf-8")
    print(f"merged {len(accepted)} hard passages into passages.json "
          f"({new_ids[0]}..{new_ids[-1]}); manifest {manifest.name}")
    print("NOW RUN: swift test  (engine-typeability gate)")


AUDIT_PROMPT = """You audit hiragana paragraphs in a Japanese typing app. Flag ONLY real errors:
- ungrammatical or unnatural Japanese a native would catch
- a hiragana spelling that's wrong for the intended word (e.g. づ/ず misuse)
- EN or ZH translation that mismatches the Japanese

Do NOT flag style or alternative phrasings. Most items are fine.
Output STRICT JSONL for FLAGGED items only: {{"id": "...", "problem": "...", "suggestion": "..."}}
If none: CLEAN

Items ({count}):
{items}"""


def cmd_audit(args):
    data = json.loads(PASSAGES.read_text(encoding="utf-8"))
    manifests = sorted((ROOT / "review-sheets").glob("passages-batch-*.json"))
    if not manifests:
        sys.exit("no passage batch manifest — run gen first")
    ids = set(json.loads(manifests[-1].read_text()))
    entries = [p for p in data if p["id"] in ids]
    print(f"auditing {len(entries)} passages from {manifests[-1].name}")

    flags = []
    for start in range(0, len(entries), args.chunk):
        chunk = entries[start : start + args.chunk]
        items = "\n".join(
            f'{p["id"]} | {p["display"]} | {p["meanings"]["en"]} | {p["meanings"]["zh"]}'
            for p in chunk
        )
        try:
            blob = call_gemini(AUDIT_PROMPT.format(count=len(chunk), items=items))
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
    print("ADJUDICATE BY HAND before changing any data.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("gen")
    gen.add_argument("--count", type=int, default=50)
    gen.add_argument("--chunk", type=int, default=25)
    gen.add_argument("--max-rounds", type=int, default=8)
    gen.add_argument("--dry", action="store_true")
    gen.add_argument("--verbose", action="store_true")
    gen.set_defaults(func=cmd_gen)

    audit = sub.add_parser("audit")
    audit.add_argument("--chunk", type=int, default=25)
    audit.set_defaults(func=cmd_audit)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
