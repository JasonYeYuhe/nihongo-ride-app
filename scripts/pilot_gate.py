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

# The cap on content words carrying no JLPT level at all. Derived from the reviewed corpus,
# not chosen: see the comment at its use site and scripts/gate_calibration.py.
UNKNOWN_CONTENT_CAP = 2


def paired_verbs():
    """Verbs sharing a kanji stem with another verb — FLAGGED for review, not gated.

    Teaching 沈む with a sentence that uses 沈める teaches the wrong verb, and the two are one
    character apart. The strengthened `target_tokens` already blocks that particular swap: it
    matches exact surfaces and dictionary forms, so 沈める does not satisfy 沈む. What no gate
    here can check is whether the sentence uses the RIGHT verb with the right particles —
    「船を沈みました」 is ungrammatical in a way only transitivity data would catch.

    That data does not exist: of 2126 verbs in the vocabulary only 38 carry a vt/vi tag, and
    of the 184 verbs still awaiting an N3 example, **zero** do. A transitivity gate written
    against those tags would report a clean sweep while checking nothing.

    Two rules were drafted here and both were killed by measurement, which is why this is a
    flag and not a gate:

    - **Quarantine the pair verbs.** It would have blocked 73 of the 779 reviewed sentences.
      Reading all 73: every one uses the right verb with the right particle. A quarantine
      would cost 51 of the 872 pending N3 words to prevent a defect class with zero observed
      occurrences in 73 reviewed samples.
    - **Require を for transitive, forbid it for intransitive.** Wrong Japanese. 「橋を渡る」,
      「階段を上がる」 and 「この道を通る」 are all in the shipped corpus and all correct: を marks
      the path traversed, not an object. The rule would have failed at least three good
      sentences out of the handful it could even reach.

    What survives is: mark these items so the review stage is told to check particles on a
    verb whose partner is one character away. The check belongs where the capability is.

    Shared-kanji-stem overgenerates a little — 命じる/命ずる and 信じる/信ずる are one verb in
    two conjugation classes, not a transitivity pair. For a review flag that is harmless.
    """
    import collections
    stems = collections.defaultdict(set)
    for path in (REPO / "Sources/VocabKit/Resources").glob("n[1-5].json"):
        for e in json.load(path.open()):
            if not any(p.startswith("v") or p.lower() == "verb" for p in (e.get("pos") or [])):
                continue
            stem = re.sub(r"[ぁ-ん]+$", "", e["surface"])
            if stem and stem != e["surface"]:
                stems[stem].add(e["surface"])
    return {v for group in stems.values() if len(group) > 1 for v in group}


PAIRED_VERBS = paired_verbs()


def target_tokens(tokenizer, sentence, entry):
    """Tokens in `sentence` that ARE the target word, decided morphologically.

    Better than a substring test in both directions: 「私は大きな鞄を持っています。」 really does
    use 持つ (the substring gate missed it, because 持つ's stem is the single character 持 and
    single-character stems are refused as too permissive), while a sentence merely containing
    学 is not thereby about 学校.

    Two false-negative classes had to be closed before the substring fallback could go
    (measured on the 779 reviewed sentences that already shipped — 63 of them, 8.1%, failed
    a naive one-token mode-C match, and every one was a good sentence):

    - **The target is finer than mode C.** 時代 lives inside 学生時代, 世界 inside 世界中,
      都 inside 東京都, 億 inside 一億. Mode A splits those; mode C does not.
    - **The target spans several tokens.** ご主人 → ご|主人, けれども → けれど|も,
      ごらんになる → ごらん|に|なり. A run of adjacent tokens is checked by concatenating
      their surfaces, and — so inflected multi-token targets like 知らせる (知ら|せ) match —
      by concatenating all but the last surface with the last token's dictionary form.

    A run must concatenate to EXACTLY the target, which is what keeps this stricter than the
    substring test it replaces: 学 still cannot match inside 学校.
    """
    surface, kana = entry["surface"], entry["kana"]
    wanted = {surface, kana}
    out = []
    for mode in (SplitMode.C, SplitMode.A):
        tokens = list(tokenizer.tokenize(sentence, mode))
        for i, token in enumerate(tokens):
            if token.surface() in wanted or token.dictionary_form() in wanted:
                out.append(token)
                continue
            # Multi-token target: grow a run from here, up to the longest target.
            run = ""
            for j in range(i, min(i + 6, len(tokens))):
                run += tokens[j].surface()
                if len(run) > max(len(surface), len(kana)):
                    break
                if run in wanted or (run[:-len(tokens[j].surface())]
                                     + tokens[j].dictionary_form()) in wanted:
                    out.append(tokens[i])
                    break
        if out:
            break
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
    if not present:
        # The substring fallback that used to sit here (`gen.contains_target`) passed any
        # sentence merely CONTAINING the characters, which is how a sentence about 学ぶ can
        # be filed under 学校 — and, for a transitivity pair, how a sentence using 沈める can
        # be filed under 沈む. It was carrying real weight only because the morphological
        # matcher was weak: on the 779 reviewed sentences it covered 63 good ones (8.1%).
        # After teaching the matcher mode-A splits and multi-token runs that is 2 (0.3%),
        # both compounds Sudachi never splits (一億人, 南側), so the fallback is now paying
        # for imprecision it no longer prevents. Measured by scripts/gate_calibration.py.
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

    # Words the vocabulary has never heard of. The level check above can only judge tokens it
    # can find a level FOR, so a sentence built entirely from words outside every JLPT list
    # sails through with nothing flagged at all — that blind spot is what this closes. The cap
    # is measured, not chosen: across the 779 reviewed sentences the counts run 542/209/26/2
    # for 0/1/2/3 unknowns, so >2 rejects 0.3% of material a human already approved.
    # 非自立 tokens are skipped because the いる of ～ています is grammar, not vocabulary;
    # counting it repeated the first level gate's mistake of measuring its own tokenizer.
    unknown = []
    for token in tokenizer.tokenize(jp, SplitMode.C):
        if token.part_of_speech()[0] not in CONTENT_POS:
            continue
        if "非自立" in "".join(token.part_of_speech()):
            continue
        if token.surface() in target_surfaces or token.dictionary_form() in target_surfaces:
            continue
        if levels.get(token.dictionary_form()) is None and levels.get(token.surface()) is None:
            unknown.append(token.surface())
    if len(unknown) > UNKNOWN_CONTENT_CAP:
        bad.append(f"{len(unknown)} unknown content words: {' '.join(unknown)}")

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
            survivor = {**item, "surface": entry["surface"], "kana": entry["kana"]}
            if entry["surface"] in PAIRED_VERBS:
                survivor["reviewFlag"] = ("transitivity pair — check the particles: this "
                                          "verb has a partner one character away")
            survivors.append(survivor)
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
