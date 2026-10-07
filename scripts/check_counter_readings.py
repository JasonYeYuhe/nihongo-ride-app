#!/usr/bin/env python3
"""Does any shipped sentence read a LEXICALISED counter as if it were two morphemes?
And does any read an INTERROGATIVE counter (何 + counter) with a reading that is not the question's?

WHY A SCAN CAN SEE THIS AND NO TOKENIZER CAN. A handful of Japanese counters are single lexical
items — 二人 is ふたり, not に+にん — and **every tokenizer this project has tried splits them and
reads each half in isolation**. Measured 2026-09-04 on 四人:

    Sudachi            四[ヨン] + 人[ニン]
    CFStringTokenizer  四[よん] + 人[にん]
    the corpus         四[よん] + 人[にん]

Two independent implementations agreeing is normally strong evidence. **Here it is one
architectural blind spot seen twice** — STATE's "a gate and the thing it gates can share a blind
spot", and the reason this family needs an enumerated list rather than a parser. The same two
tools also give よんつ for 四つ, ふたか for 二日 and よんにち for 四日, all wrong.

WHAT THIS SCAN COSTS, MEASURED BEFORE IT WAS TRUSTED. The first version enumerated 24 compounds
and matched them as plain substrings. It produced **9 hits of which 7 were false positives — a
78% false-positive rate** — from three distinct causes, each fixed below:

  * **absorbed** (4): the counter sits inside a LONGER lexical item with its own correct
    reading — 真っ二つ まっぷたつ, 三日月 みかづき, 四つ角 よつかど, 一日中 いちにちじゅう.
  * **substring** (2): 二十日 contains 十日, and both readings were already correct.
  * **wrong expectation** (1): 一日 is ついたち as a DATE and いちにち as a DURATION. Surface
    alone cannot decide it, so 一日 is deliberately NOT enumerated — a rule that cannot be right
    from the surface does not belong in a surface scan.

WHAT IT STILL CANNOT SEE, stated because this repo pays for unstated scopes: a counter written
in a form this list does not contain, a compound absorbed by a word not in ABSORBERS, and any
reading error outside this family. It is a sweep of one closed set, not a reading gate.

THE INTERROGATIVE TABLE (v1.36, PLAN-V1.36 §C item 4: "measure first", time-boxed)
-------------------------------------------------------------------------------------
Why: `n5-g022` 「今、何時ですか。」 shipped 何時 as なんどき until v1.35 round 3 (`52ffe6b`). No
tokenizer saw it, for the reason above. The table below enumerates 何 + counter as a question.

How it reads the TAUGHT reading, and why that differs from the lexicalised table. The table above
asks `standard in exKana`, which passes when the right kana appear ANYWHERE in the sentence. This
one reads the reading the corpus actually teaches for the compound: the `exTokens` that cover the
compound's characters, concatenated. Each judgement records its alignment:
  * exact   the tokens cover exactly the compound, so the taught reading must EQUAL an expected one;
  * prefix  the tokens begin with the compound and run on (何時間 なんじかん), so the taught reading
            must BEGIN with one;
  * inside / kana-only   the compound starts inside a token, or the field has no tokens (headwords,
            passages, a sentence without exTokens): the weak substring rule of the table above.
            Every judgement made on it is counted in the output, so a reader sees how many.

Three outcomes besides "ok", and only the first is a correction candidate:
  * **mismatch**  the taught reading is neither expected nor a known other sense. Still not a
                  correction: §C item 4 changes nothing that is not upheld 2 of 2.
  * **flag-only** the taught reading is a LEGITIMATE reading of the same spelling in another sense
                  (何分 なにぶん the adverb, 何人 なにじん "what nationality", 何時 いつ). The surface
                  cannot choose between them — the 一日 lesson above — so these are flagged for a
                  person and NEVER auto-corrected.
  * **absorbed**  the compound sits inside a longer item with its own reading (いつ何時 いつなんどき).
                  Recorded, not judged.
なんどき is deliberately NOT an other sense of 何時: outside いつ何時 it is archaic, v1.35 corrected
exactly that, and calibration (a) depends on it being a mismatch.

What it cannot see, in addition to the above: 何 written in kana (なんにん), a counter not in the
table (何か月, 何週間, 何秒 …), and a sentence whose sense wants なにぶん but is taught なんぷん —
taught == expected is accepted without asking what the sentence means.

CALIBRATION BEFORE TRUST (`--calibrate`). It drives this file's documented entry point as a
subprocess, never its functions, on two trees:
  (a) the pre-v1.35 tree `281fc45` (git show into a temp dir): n5-g022 is flagged, a mismatch,
      何時 taught なんどき;
  (b) the working tree: n5-g022 is INSPECTED, taught なんじ, and not flagged — "not flagged" because
      it was looked at and passed, not because nothing was looked at;
  (c) the population is at least 6,000 example sentences, and a one-level tree (n5 only) exits 2;
  (d) on `281fc45`, n2-b937 (headword 何分 なにぶん, the adverb) is flag-only in both its fields,
      never a mismatch — the one real case of the flag-only path;
  (e) on `281fc45`, the lexicalised table flags n5-kazoku, 四人 taught よんにん.
Then five synthetic logic checks for paths the real corpus does not exercise (an absorber, 何階's
two readings, a prefix span, a counter split across two tokens, 何人 なにじん). They prove the code
paths, not accuracy: accuracy is (a)–(e). A failed check exits 1 and writes nothing.

IT IS A SWEEP, NOT A GATE. `run_all_gates.sh` and CI do not run it (checked 2026-10-07: neither
names it, and it is not a `scripts/test_*.py`, the glob the runner turns into gates). Keep it that
way: a test_*.py for it would add a gate and move FLOOR.

    python3 scripts/check_counter_readings.py [--json out.json] [--resources DIR] [--calibrate]
    python3 scripts/check_counter_readings.py --calibrate --json docs/measurements/v136-counter-sweep.json
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(REPO, "Sources", "VocabKit", "Resources")
MIN_POPULATION = 6000

# surface -> the standard lexicalised reading. Regular compounds (三人 さんにん, 五人 ごにん) are
# deliberately absent: they are not lexicalised and the split reading is correct.
LEXICALISED = {
    "一人": "ひとり", "二人": "ふたり", "四人": "よにん",
    "一つ": "ひとつ", "二つ": "ふたつ", "三つ": "みっつ", "四つ": "よっつ", "五つ": "いつつ",
    "六つ": "むっつ", "七つ": "ななつ", "八つ": "やっつ", "九つ": "ここのつ",
    "二日": "ふつか", "三日": "みっか", "四日": "よっか", "五日": "いつか",
    "六日": "むいか", "七日": "なのか", "八日": "ようか", "九日": "ここのか", "十日": "とおか",
    "二十日": "はつか", "二十歳": "はたち",
}

# Longer lexical items that CONTAIN a counter and have their own reading. A sentence is not
# flagged for a counter whose every occurrence is inside one of these.
ABSORBERS = ("真っ二つ", "三日月", "四つ角", "一日中", "二十日", "十日町", "二人三脚", "一人前")

# 何 + counter asked as a question -> the readings standard for it: なん + the counter with its
# sound change (本 ぼん, 杯 ばい, 匹 びき, 分 ぷん, 階 がい). 何階 is both なんがい and なんかい, and
# neither is flagged. The list is PLAN-V1.36 §C item 4's, closed on purpose.
INTERROGATIVE = {
    "何時": ("なんじ",), "何分": ("なんぷん",), "何人": ("なんにん",), "何日": ("なんにち",),
    "何回": ("なんかい",), "何歳": ("なんさい",), "何年": ("なんねん",), "何月": ("なんがつ",),
    "何度": ("なんど",), "何本": ("なんぼん",), "何枚": ("なんまい",), "何冊": ("なんさつ",),
    "何個": ("なんこ",), "何杯": ("なんばい",), "何匹": ("なんびき",), "何台": ("なんだい",),
    "何番": ("なんばん",), "何階": ("なんがい", "なんかい"), "何曜日": ("なんようび",),
}

# Readings that are legitimate for the same spelling in ANOTHER sense. Taught one of these, an
# occurrence is flag-only: a person decides from context, and nothing corrects it automatically.
INTERROGATIVE_OTHER_SENSE = {
    "何分": {"なにぶん": "adverb 'anyway; please' (何分よろしく)"},
    "何人": {"なにじん": "'what nationality'",
             "なんぴと": "literary 'whoever' (何人も…ない)", "なにびと": "literary 'whoever'"},
    "何時": {"いつ": "the kanji spelling of いつ (何時も, 何時か)"},
}

# Longer items containing an interrogative compound, with their own reading (いつ何時 いつなんどき).
INTERROGATIVE_ABSORBERS = ("いつ何時",)

CALIBRATION_REF = "281fc45"   # the v1.34 build commit: the last tree that taught 何時 as なんどき
CORPUS_FILES = ("n1.json", "n2.json", "n3.json", "n4.json", "n5.json", "passages.json")


def outside_absorbers(sentence, compound):
    """`sentence` with every longer lexical item containing `compound` blanked out."""
    masked = sentence
    for absorber in ABSORBERS:
        if compound in absorber and absorber != compound:
            masked = masked.replace(absorber, "　" * len(absorber))
    return masked


def occurrences_outside_absorbers(sentence, compound):
    """Does `compound` appear anywhere that is not inside a longer lexical item?"""
    return compound in outside_absorbers(sentence, compound)


def display_path(path):
    path = os.path.abspath(path)
    return os.path.relpath(path, REPO) if path.startswith(REPO + os.sep) else path


def cover(sentence, tokens, start, end):
    """The tokens the corpus uses for sentence[start:end], as (surface, reading, alignment) — or
    None when the tokens do not spell the sentence, since then no span can be read off them."""
    if not tokens or "".join(t[0] for t in tokens) != sentence:
        return None
    pos, first, surface, reading = 0, None, "", ""
    for tok_surface, tok_reading in tokens:
        lo, hi = pos, pos + len(tok_surface)
        pos = hi
        if hi <= start or lo >= end:
            continue
        if first is None:
            first = lo
        surface += tok_surface
        reading += tok_reading
    if first != start:
        return surface, reading, "inside"
    return surface, reading, "exact" if len(surface) == end - start else "prefix"


def whole(text, reading, start, end):
    """No tokens: the field's whole reading, aligned only when the compound starts the field."""
    if start == 0:
        return text, reading, "exact" if end == len(text) else "prefix"
    return text, reading, "kana-only"


def fits(taught, reading, alignment):
    if alignment == "exact":
        return taught == reading
    if alignment == "prefix":
        return taught.startswith(reading)
    return reading in taught


def scan(resources=RESOURCES):
    hits, checked = [], 0
    for path in sorted(glob.glob(f"{resources}/n[1-5].json")):
        for entry in json.load(open(path, encoding="utf-8")):
            jp, kana = entry.get("exJP"), entry.get("exKana")
            if not jp or not kana:
                continue
            checked += 1
            for compound, standard in LEXICALISED.items():
                if not occurrences_outside_absorbers(jp, compound):
                    continue
                if standard in kana:
                    continue
                start = outside_absorbers(jp, compound).index(compound)
                span = cover(jp, entry.get("exTokens"), start, start + len(compound))
                hits.append({"id": entry["id"], "compound": compound, "standard": standard,
                             "exJP": jp, "exKana": kana,
                             "file": display_path(path), "field": "exJP", "sentence": jp,
                             "taught": span[1] if span else None, "expected": [standard]})
    return checked, hits


def judge_field(text, reading, tokens):
    """One record per 何+counter in `text`: what the corpus teaches for it, and the verdict."""
    masked = text
    for absorber in INTERROGATIVE_ABSORBERS:
        masked = masked.replace(absorber, "　" * len(absorber))
    records = []
    for compound, expected in INTERROGATIVE.items():
        for m in re.finditer(re.escape(compound), text):
            start, end = m.span()
            if masked[start:end] != compound:
                records.append({"compound": compound, "verdict": "absorbed"})
                continue
            taught_span, taught, alignment = (cover(text, tokens, start, end)
                                              or whole(text, reading, start, end))
            record = {"compound": compound, "taught": taught, "taughtSpan": taught_span,
                      "alignment": alignment, "expected": list(expected)}
            if any(fits(taught, r, alignment) for r in expected):
                record["verdict"] = "ok"
            else:
                other = [(r, sense) for r, sense in INTERROGATIVE_OTHER_SENSE.get(compound, {}).items()
                         if fits(taught, r, alignment)]
                record["verdict"] = "flag-only" if other else "mismatch"
                if other:
                    record["otherSense"] = {"reading": other[0][0], "sense": other[0][1]}
            records.append(record)
    return records


def scan_interrogative(resources=RESOURCES):
    """Every example sentence (judged on exTokens), every headword, every passage."""
    population = {"exJP": 0, "surface": 0, "display": 0}
    fields = []
    for path in sorted(glob.glob(f"{resources}/n[1-5].json")):
        for entry in json.load(open(path, encoding="utf-8")):
            population["surface"] += 1
            fields.append((path, entry["id"], "surface", entry["surface"], entry["kana"], None))
            if entry.get("exJP") and entry.get("exKana"):
                population["exJP"] += 1
                fields.append((path, entry["id"], "exJP", entry["exJP"], entry["exKana"],
                               entry.get("exTokens")))
    passages = os.path.join(resources, "passages.json")
    if os.path.exists(passages):
        for p in json.load(open(passages, encoding="utf-8")):
            population["display"] += 1
            fields.append((passages, p["id"], "display", p["display"], p["kana"], None))
    inspected, hits = [], []
    for path, entry_id, field, text, reading, tokens in fields:
        for record in judge_field(text, reading, tokens):
            where = {"id": entry_id, "file": display_path(path), "field": field}
            inspected.append({**where, **record})
            if record["verdict"] in ("mismatch", "flag-only"):
                hits.append({**where, "sentence": text, "reading": reading, **record})
    return population, inspected, hits


# ── calibration: the documented entry point, on trees whose answer is already known ──────────

def tree_at(ref, dest):
    """The corpus as it was at `ref`, written into `dest`. A ref that does not resolve (a shallow
    clone) raises: a calibration that cannot see its tree must fail, not skip."""
    for name in CORPUS_FILES:
        blob = subprocess.run(["git", "-C", REPO, "show", f"{ref}:Sources/VocabKit/Resources/{name}"],
                              capture_output=True)
        if blob.returncode != 0:
            raise RuntimeError(f"git show {ref}:…/{name} failed: {blob.stderr.decode().strip()}")
        with open(os.path.join(dest, name), "wb") as f:
            f.write(blob.stdout)


def run_cli(tmp, label, *args):
    """This file, run as a user runs it: (exit code, its --json output or None)."""
    out = os.path.join(tmp, f"{label}.json")
    proc = subprocess.run([sys.executable, os.path.abspath(__file__), *args, "--json", out],
                          capture_output=True, text=True)
    data = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else None
    return proc.returncode, data


LOGIC_CHECKS = (
    # (what it proves, text, reading, tokens, expected verdicts in order)
    ("an absorber is recorded, not judged", "いつ何時でも", "いつなんどきでも",
     [["いつ何時", "いつなんどき"], ["でも", "でも"]], ["absorbed"]),
    ("何階 accepts both なんがい and なんかい", "何階何階", "なんがいなんかい",
     [["何階", "なんがい"], ["何階", "なんかい"]], ["ok", "ok"]),
    ("a prefix span is judged on its start", "何時間", "なんじかん",
     [["何時間", "なんじかん"]], ["ok"]),
    ("a counter split over two tokens is read whole", "何回", "なんかい",
     [["何", "なん"], ["回", "かい"]], ["ok"]),
    ("何人 なにじん is flag-only, never a mismatch", "何人ですか", "なにじんですか",
     [["何", "なに"], ["人", "じん"], ["です", "です"], ["か", "か"]], ["flag-only"]),
)


def calibrate():
    lines, ok = [], True

    def check(label, passed, detail):
        nonlocal ok
        ok = ok and passed
        lines.append(f"[{'PASS' if passed else 'FAIL'}] {label} — {detail}")

    with tempfile.TemporaryDirectory() as tmp:
        old, small = os.path.join(tmp, "pre-v135"), os.path.join(tmp, "n5-only")
        os.mkdir(old)
        os.mkdir(small)
        try:
            tree_at(CALIBRATION_REF, old)
        except RuntimeError as e:
            return False, [f"[FAIL] cannot read the calibration tree: {e}"]
        shutil.copy(os.path.join(RESOURCES, "n5.json"), small)
        old_code, old_run = run_cli(tmp, "old", "--resources", old)
        head_code, head_run = run_cli(tmp, "head")
        small_code, small_run = run_cli(tmp, "small", "--resources", small)

    if old_run is None or head_run is None or small_run is None:
        return False, [f"[FAIL] a calibration run wrote no output (exit codes: {CALIBRATION_REF} "
                       f"{old_code}, working tree {head_code}, n5-only {small_code})"]
    old_q, head_q = old_run["interrogative"], head_run["interrogative"]

    g022 = [(h["verdict"], h["compound"], h["taught"]) for h in old_q["hits"] if h["id"] == "n5-g022"]
    check(f"(a) {CALIBRATION_REF} flags n5-g022", g022 == [("mismatch", "何時", "なんどき")],
          f"hits for n5-g022: {g022}")

    seen = [(r["verdict"], r["compound"], r.get("taught")) for r in head_q["inspected"]
            if r["id"] == "n5-g022"]
    flagged = [h for h in head_q["hits"] if h["id"] == "n5-g022"]
    check("(b) the working tree inspects n5-g022 and does not flag it",
          seen == [("ok", "何時", "なんじ")] and not flagged,
          f"inspected: {seen}; hits: {len(flagged)}")

    pop = head_run["population"]
    check(f"(c) population ≥ {MIN_POPULATION}, and a one-level tree exits 2",
          head_code == 0 and pop >= MIN_POPULATION and small_code == 2
          and small_run["population"] < MIN_POPULATION,
          f"working tree {pop} sentences, exit {head_code}; n5-only "
          f"{small_run['population']} sentences, exit {small_code}")

    b937 = sorted((h["field"], h["verdict"], h["taught"]) for h in old_q["hits"] if h["id"] == "n2-b937")
    check(f"(d) {CALIBRATION_REF}: n2-b937 何分 なにぶん is flag-only in both fields",
          b937 == [("exJP", "flag-only", "なにぶん"), ("surface", "flag-only", "なにぶん")],
          f"hits for n2-b937: {b937}")

    kazoku = [(h["compound"], h["taught"]) for h in old_run["hits"] if h["id"] == "n5-kazoku"]
    check(f"(e) {CALIBRATION_REF}: the lexicalised table flags n5-kazoku", kazoku == [("四人", "よんにん")],
          f"hits for n5-kazoku: {kazoku}")

    for what, text, reading, tokens, want in LOGIC_CHECKS:
        got = [r["verdict"] for r in judge_field(text, reading, tokens)]
        check(f"logic: {what}", got == want, f"{text} {reading}: {got}")
    return ok, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="write the hits here")
    ap.add_argument("--resources", default=RESOURCES, help="the corpus directory to scan")
    ap.add_argument("--calibrate", action="store_true",
                    help="prove the scan on trees with known answers first; exit 1 if it fails")
    args = ap.parse_args()

    calibration = None
    if args.calibrate:
        calibrated, calibration = calibrate()
        print("calibration")
        for line in calibration:
            print(f"  {line}")
        if not calibrated:
            print("\n!! calibration failed — the sweep below would not be trustworthy; nothing written")
            return 1
        print()

    checked, hits = scan(args.resources)
    print(f"population   : {checked} sentences carrying an exKana")
    print(f"enumerated   : {len(LEXICALISED)} lexicalised counters, {len(ABSORBERS)} absorbers")
    print(f"flagged      : {len(hits)}")
    for h in hits:
        print(f"\n  {h['id']}  {h['compound']} -> expected …{h['standard']}…")
        print(f"      {h['exJP']}")
        print(f"      {h['exKana']}")

    population, inspected, q_hits = scan_interrogative(args.resources)
    by_compound, by_alignment = {}, {}
    for r in inspected:
        by_compound[r["compound"]] = by_compound.get(r["compound"], 0) + 1
        key = r.get("alignment", "absorbed")
        by_alignment[key] = by_alignment.get(key, 0) + 1
    kinds = [h["verdict"] for h in q_hits]
    print("\n── interrogative: 何 + counter ──")
    print(f"population   : {population['exJP']} example sentences (judged on exTokens), "
          f"{population['surface']} headwords, {population['display']} passages")
    print(f"enumerated   : {len(INTERROGATIVE)} compounds, {len(INTERROGATIVE_ABSORBERS)} absorber, "
          f"{len(INTERROGATIVE_OTHER_SENSE)} with another legitimate sense (flag-only)")
    print(f"inspected    : {len(inspected)} occurrences — "
          + (", ".join(f"{c} {n}" for c, n in sorted(by_compound.items(), key=lambda kv: -kv[1])) or "none")
          + f"; alignment: " + (", ".join(f"{a} {n}" for a, n in sorted(by_alignment.items())) or "none"))
    print(f"flagged      : {len(q_hits)} ({kinds.count('mismatch')} mismatch, "
          f"{kinds.count('flag-only')} flag-only)")
    for h in q_hits:
        note = f" — other sense: {h['otherSense']['sense']}" if h.get("otherSense") else ""
        print(f"\n  {h['id']}  [{h['verdict']}]  {h['file']} {h['field']}  {h['compound']} taught "
              f"{h['taught']}, expected {' | '.join(h['expected'])}{note}")
        print(f"      {h['sentence']}")
        print(f"      {h['reading']}")

    if args.json:
        out = {"population": checked, "enumerated": len(LEXICALISED),
               "absorbers": list(ABSORBERS), "hits": hits,
               "interrogative": {"population": population,
                                 "enumerated": {c: list(r) for c, r in INTERROGATIVE.items()},
                                 "otherSense": INTERROGATIVE_OTHER_SENSE,
                                 "absorbers": list(INTERROGATIVE_ABSORBERS),
                                 "inspected": inspected, "hits": q_hits}}
        if calibration is not None:
            out["calibration"] = calibration
        if os.path.abspath(args.resources) == RESOURCES:
            # Which tree these hits describe: the last commit that touched the corpus, and whether
            # the working tree differs from it.
            git = lambda *a: subprocess.run(["git", "-C", REPO, *a, "--", "Sources/VocabKit/Resources"],
                                            capture_output=True, text=True).stdout.strip()
            out["corpus"] = {"lastCommit": git("log", "-1", "--format=%H"),
                             "uncommittedChanges": bool(git("status", "--porcelain"))}
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"\nwrote {args.json}")
    # A scan that inspected nothing must not report clean.
    if checked < MIN_POPULATION:
        print(f"\n!! only {checked} sentences inspected — this scan is reading almost nothing")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
