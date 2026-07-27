#!/usr/bin/env python3
"""Run generated example sentences through every deterministic gate, and report WHY each one
was rejected.

The point of a pilot is the numbers: what fraction survives, and what the survivors' real
defect rate is once a human reads them. Both are needed before deciding whether generating
4,953 sentences is a good idea or an expensive way to damage a teaching app.

Usage:
    .venv-jp/bin/python scripts/pilot_gate.py /tmp/pilot_words.json /tmp/gen_out.txt
"""
import importlib.util
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))

spec = importlib.util.spec_from_file_location("gen", REPO / "scripts" / "gen_examples.py")
gen = importlib.util.module_from_spec(spec)
_argv, sys.argv = sys.argv, ["gen_examples"]
try:
    spec.loader.exec_module(gen)
except SystemExit:
    pass
sys.argv = _argv

reading_spec = importlib.util.spec_from_file_location(
    "readings", REPO / "scripts" / "check_example_readings.py")
readings = importlib.util.module_from_spec(reading_spec)
_argv, sys.argv = sys.argv, ["check_example_readings"]
try:
    reading_spec.loader.exec_module(readings)
except SystemExit:
    pass
sys.argv = _argv

from sudachipy import Dictionary, SplitMode   # noqa: E402

JP_END = ("。", "!", "?", "！", "？")


def shipped_sentences() -> set[str]:
    out = set()
    for path in (REPO / "Sources/VocabKit/Resources").glob("n[1-5].json"):
        for e in json.load(path.open()):
            if (e.get("exJP") or "").strip():
                out.add(e["exJP"].strip())
    return out


def level_of(entry) -> int:
    return int(entry.get("jlpt") or 5)


def vocab_by_surface() -> dict:
    """surface → easiest JLPT level it appears at (5 = easiest, 1 = hardest)."""
    out = {}
    for path in (REPO / "Sources/VocabKit/Resources").glob("n[1-5].json"):
        for e in json.load(path.open()):
            lvl = int(e.get("jlpt") or 5)
            out[e["surface"]] = max(out.get(e["surface"], 0), lvl)
    return out


# Only CONTENT words carry a level. The first version of this gate compared every token
# against the vocabulary, so it rejected 「りんごを三つ買いました。」 because the past-tense
# auxiliary た collides with an N2 entry, and 「父は毎日仕事で忙しいです。」 because the
# particle で does. Twenty-three of twenty-eight rejections in the first pilot run were this,
# i.e. the gate was measuring itself rather than the sentences.
CONTENT_POS = {"名詞", "動詞", "形容詞", "副詞", "連体詞"}


def target_tokens(tokenizer, sentence, entry):
    """Tokens in `sentence` that ARE the target word, decided morphologically.

    Better than a substring test in both directions: 「私は大きな鞄を持っています。」 really does
    use 持つ (the substring gate missed it, because 持つ's stem is the single character 持 and
    single-character stems are refused as too permissive), while a sentence merely containing
    学 is not thereby about 学校.
    """
    surface, kana = entry["surface"], entry["kana"]
    out = []
    for token in tokenizer.tokenize(sentence, SplitMode.C):
        if token.surface() == surface or token.dictionary_form() == surface:
            out.append(token)
        elif token.surface() == kana or token.dictionary_form() == kana:
            out.append(token)
    return out


def gates(item, entry, tokenizer, seen, levels):
    """→ list of reasons this sentence must not ship. Empty means it survived."""
    jp, en, zh = item.get("jp", ""), item.get("en", ""), item.get("zh", "")
    bad = []
    if not jp:
        return ["empty"]
    if not (5 <= len(jp) <= 40):
        bad.append(f"length {len(jp)}")
    if not jp.endswith(JP_END):
        bad.append("no final punctuation")
    if any(p in jp[:-1] for p in ("。", "!", "?")):
        bad.append("more than one sentence")
    if re.search(r"[a-zA-Z0-9]", jp):
        bad.append("latin characters")
    present = target_tokens(tokenizer, jp, entry)
    if not present and not gen.contains_target(jp, entry):
        bad.append("target word absent")
    if len(en) < 4:
        bad.append("english too short")
    if len(zh) < 2:
        bad.append("chinese too short")
    if jp in seen:
        bad.append("duplicate of a shipped sentence")

    # Reading alignment — the gate a substring check cannot do.
    probe = dict(entry)
    probe["exJP"] = jp
    if why := readings.check(tokenizer, probe):
        bad.append(f"reading: {why}")

    # Level: no token may be harder than the target's own level. A correct sentence that
    # wraps an N5 word in N1 vocabulary is useless to the learner who needs it.
    target_level = level_of(entry)
    target_surfaces = {t.surface() for t in present} | {entry["surface"], entry["kana"]}
    for token in tokenizer.tokenize(jp, SplitMode.C):
        if token.part_of_speech()[0] not in CONTENT_POS:
            continue
        if token.surface() in target_surfaces or token.dictionary_form() in target_surfaces:
            continue   # the word being taught is allowed to be as hard as it is
        lvl = levels.get(token.dictionary_form()) or levels.get(token.surface())
        if lvl is not None and lvl < target_level - 1:
            bad.append(f"vocabulary above level: {token.surface()} is N{lvl}, "
                       f"target is N{target_level}")
            break
    return bad


def main() -> int:
    words = {e["id"]: e for e in json.load(open(sys.argv[1]))}
    raw = open(sys.argv[2]).read()
    match = re.search(r"\[.*\]", raw, re.S)
    if not match:
        sys.exit("no JSON array in the generator output")
    items = json.loads(match.group(0))

    tokenizer = Dictionary().create()
    seen = shipped_sentences()
    levels = vocab_by_surface()

    survivors, rejected = [], []
    counts = {}
    for item in items:
        entry = words.get(item.get("id"))
        if entry is None:
            rejected.append((item.get("id"), ["unknown id"], item.get("jp", "")))
            continue
        reasons = gates(item, entry, tokenizer, seen, levels)
        if reasons:
            rejected.append((entry["id"], reasons, item.get("jp", "")))
            for r in reasons:
                counts[r.split(":")[0]] = counts.get(r.split(":")[0], 0) + 1
        else:
            survivors.append({**item, "surface": entry["surface"], "kana": entry["kana"]})
        seen.add(item.get("jp", ""))

    print(f"generated {len(items)} for {len(words)} words")
    print(f"survived every gate: {len(survivors)}  ({100 * len(survivors) / max(1, len(items)):.0f}%)")
    print(f"rejected: {len(rejected)}\n")
    print("rejections by cause:")
    for cause, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:3}  {cause}")
    print("\nrejected sentences:")
    for eid, reasons, jp in rejected:
        print(f"  {eid:10} 「{jp}」")
        for r in reasons:
            print(f"             ↳ {r}")
    json.dump(survivors, open("/tmp/pilot_survivors.json", "w"), ensure_ascii=False, indent=2)
    print(f"\nsurvivors written to /tmp/pilot_survivors.json — they still need a human to read them")
    return 0


if __name__ == "__main__":
    sys.exit(main())
