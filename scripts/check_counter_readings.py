#!/usr/bin/env python3
"""Does any shipped sentence read a LEXICALISED counter as if it were two morphemes?
And does any read an INTERROGATIVE counter (何 + counter) with a reading that is not the question's?
And does any read a MONTH, HOUR, DURATION or 字 counter without the sound change at its last digit?

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

THE COUNTER TABLE (v1.36, PLAN-V1.36 §I: month, hour, duration and 字)
------------------------------------------------------------------------
Why: round 1 of v1.36's whole-release review (`fdb2b5f..ba77c13`) found 8 shipped sentences whose
number + counter reading neither table above can see — 四月 taught よんがつ (n5-b303, n2-b942), 九時
きゅうじ (n5-b071, n4-g180, n3-b750), 二十四時間 にじゅうよんじかん (n5-b018), 四時間 しじかん (n1-b615),
四字熟語 よんじじゅくご (n2-b072) — and 七時 ななじ (n5-b334), which is tolerated.

What it enumerates: only a LAST DIGIT whose sound changes before one of these counters.
    月    4 し   7 しち        9 く      四月 しがつ   七月 しちがつ             九月 くがつ
    時    4 よ   7 しち        9 く      四時 よじ     七時 しちじ               九時 くじ
    時間  4 よ   7 しち | なな  9 く      四時間 よじかん  七時間 しちじかん | ななじかん  九時間 くじかん
    字    4 よ                           四字 よじ (四字熟語 よじじゅくご)
Every other digit reads as it does alone (三時 さんじ, 十月 じゅうがつ) and is deliberately absent, as
三人 is from the lexicalised table. 一 is absent for a second reason too: 一時 is いちじ, いっとき or
ひととき and 一月 is いちがつ or ひとつき, which the surface cannot decide (the 一日 lesson above).

A number is read whole. An occurrence is the whole run of numerals before the counter (二十四時間,
十九時, ２４時間 — kanji, ASCII or full-width digits). The digits before the last are read as a plain
number (二十 にじゅう), so the expected reading is that + the last digit's form + the counter:
二十四時間 にじゅうよじかん. Those leading digits are read leniently (四 よん|し, 七 なな|しち, 九 きゅう|く):
this table judges the sound change at the counter and nothing before it.

Judged twice: on exTokens AND on exKana. Round 1's tests lens noted that a check on exKana alone (the
lexicalised table's `standard in exKana`) cannot see a regression in the tokens; a check on the tokens
alone (the 何 table as first written) cannot see one in exKana, which is what Sentence mode makes a
rider type. So every occurrence in an example sentence gets
  * verdictTokens  the covering tokens' reading, aligned as for the 何 table;
  * verdictKana    the stretch of exKana those tokens stand for. It is found by anchoring on the
                   readings of the tokens before and after them, because exKana is the token readings
                   with their punctuation dropped (on all 6,724 sentences, measured 2026-10-09, the
                   dropped characters were 。、「」！？). When the anchors do not hold, the kana is
                   judged by the weak substring rule and says so (kanaAlignment "kana-only");
and its verdict is the worse of the two. A field with no tokens (a headword, a passage) has only its
reading to judge, and verdictTokens is null. Since this change the 何 table is judged the same way.

Not a hit, and why:
  * flag-only, another sense: 四時 しじ (literary 'the four seasons'); 四月 inside the surname
    四月一日 / 四月朔日 わたぬき. The surname is NOT an absorber: 四月一日 is also the date — n5-b303 is
    exactly that — and an absorber would hide it.
  * flag-only, tolerated: 七時 ななじ (and so 十七時 じゅうななじ). しちじ is the textbook form and
    ななじ common speech; a person decides and nothing corrects it (PLAN-V1.36 §I).
  * absorbed (recorded, not judged): the 時 of 時代, 時期 and 時点, and the 月 of 月曜 (第四月曜日); a
    month above 12 (十四月); and a run of kanji digits with no 十/百/千/万 (三四時間, 六七時間 'three
    or four / six or seven hours'), which is a range, not one number, and whose sandhi this table
    does not claim to know.
  * never seen at all: 九州, 四季, 四ヶ月 / 四か月 (another counter, and regular), 十字路 (十 is
    regular), 四六時中 しろくじちゅう (its last digit, 六, is regular).
What it cannot see: a number written in kana in exJP, a counter not in the table (分, 年, 回, 週 …),
a wrong reading in the digits before the last, and a sense not listed above.

CALIBRATION BEFORE TRUST (`--calibrate`). It drives this file's documented entry point as a
subprocess, never its functions, on four trees:
  (a) the pre-v1.35 tree `281fc45` (git show into a temp dir): n5-g022 is flagged, a mismatch,
      何時 taught なんどき;
  (b) the working tree: n5-g022 is INSPECTED, taught なんじ, and not flagged — "not flagged" because
      it was looked at and passed, not because nothing was looked at;
  (c) the population floor, held on EACH table's own scan — round 1 found (c) reading the
      lexicalised table's count for the 何 table, so a 何 scan narrowed to n2 + n5, or to two
      entries, still printed PASS:
      (c0) the working tree exits 0, and a one-level tree (n5 only) exits 2 — the exit-2 floor now
           names every short table;
      (c1) the lexicalised table reads at least 6,000 example sentences;
      (c2) the 何 table reads at least 6,000 example sentences and 6,000 headwords, and every passage;
      (c3) the counter table, the same;
      and on the n5-only tree each of (c1)–(c3) falls below the floor;
  (d) on `281fc45`, n2-b937 (headword 何分 なにぶん, the adverb) is flag-only in both its fields,
      never a mismatch — the one real case of the flag-only path;
  (e) on `281fc45`, the lexicalised table flags n5-kazoku, 四人 taught よんにん;
  (f) on `29e4778` — the corpus of v1.36 item 3, which IS the working tree when this table was
      written, pinned so the check survives a correction — the counter table flags the 9 known
      occurrences, each with the same verdict in exTokens and in exKana, and exKana lined up with
      the tokens rather than found by the substring fallback: 8 mismatches, and n5-b334 七時
      flag-only. Anything else it finds is listed, not failed;
  (g) the working tree inspects n5-g079 七時, taught しちじ, and passes it in both fields.
Then synthetic logic checks for paths the real corpus does not exercise: for the 何 table an absorber,
何階's two readings, a prefix span, a counter split across two tokens, 何人 なにじん, 何人 なにん (a
mismatch on a second compound), and a regression in exKana alone; for the counter table every rule
above; and the exit-2 floor naming each short table. They prove the code paths, not accuracy:
accuracy is (a)–(g). A failed check exits 1 and writes nothing.

IT IS A SWEEP, NOT A GATE. `run_all_gates.sh` and CI do not run it (checked 2026-10-07: neither
names it, and it is not a `scripts/test_*.py`, the glob the runner turns into gates). Keep it that
way: a test_*.py for it would add a gate and move FLOOR.

    python3 scripts/check_counter_readings.py [--json out.json] [--resources DIR] [--calibrate]
    python3 scripts/check_counter_readings.py --calibrate --json docs/measurements/v136-counter-sweep-2.json
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

# ── the counter table (PLAN-V1.36 §I) ──────────────────────────────────────────────────────────
# counter -> its reading, and {last digit: that digit's form before it}. Only the digits whose sound
# changes are listed; the rest read as they do alone and are deliberately absent (see the docstring).
COUNTER_READING = {"時間": "じかん", "時": "じ", "月": "がつ", "字": "じ"}
COUNTER_FINAL = {
    "月": {4: ("し",), 7: ("しち",), 9: ("く",)},
    "時": {4: ("よ",), 7: ("しち",), 9: ("く",)},
    "時間": {4: ("よ",), 7: ("しち", "なな"), 9: ("く",)},
    "字": {4: ("よ",)},
}
# A last digit's form that is heard but not the standard: flag-only, for a person, never corrected.
COUNTER_TOLERATED = {"時": {7: {"なな": "tolerated: ななじ is common speech; しちじ is the textbook form"}}}
# The same spelling read in another sense: flag-only. Keyed by the whole compound.
COUNTER_OTHER_SENSE = {
    "四時": {"しじ": "literary 'the four seasons' (四時)"},
    "四月": {"わたぬき": "the surname 四月一日 / 四月朔日"},
}
# The counter character is the first of another word: 時代, 時期, 時点; 月曜 (第四月曜日).
NOT_THE_COUNTER = {"時": ("代", "期", "点"), "月": ("曜",)}
MONTHS = range(1, 13)

KANJI_DIGIT = {"〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
KANJI_UNIT = {"十": 10, "百": 100, "千": 1000}
FULLWIDTH = str.maketrans("０１２３４５６７８９", "0123456789")
# The whole numeral run before a counter; 時間 is tried before 時.
COUNTER_RE = re.compile("([〇一二三四五六七八九十百千万0-9０-９]+)(時間|時|月|字)")

# A digit read inside a larger number, leniently (the table judges only the last digit).
DIGIT_READINGS = {1: ("いち",), 2: ("に",), 3: ("さん",), 4: ("よん", "し"), 5: ("ご",), 6: ("ろく",),
                  7: ("なな", "しち"), 8: ("はち",), 9: ("きゅう", "く")}
PLACE_READING = {1000: "せん", 100: "ひゃく", 10: "じゅう"}
PLACE_SOUND_CHANGE = {(1000, 1): ("せん",), (1000, 3): ("さんぜん",), (1000, 8): ("はっせん",),
                      (100, 1): ("ひゃく",), (100, 3): ("さんびゃく",), (100, 6): ("ろっぴゃく",),
                      (100, 8): ("はっぴゃく",), (10, 1): ("じゅう",)}

# exKana is the exTokens readings with their punctuation dropped: on all 6,724 sentences (measured
# 2026-10-09) that was 。、「」！？; 『』!? are the same kind. A miss only sends the kana to the
# substring fallback, which the output counts.
KANA_DROPPED = str.maketrans("", "", "。、「」『』！？!?")
VERDICT_RANK = {"ok": 0, "flag-only": 1, "mismatch": 2}

CALIBRATION_REF = "281fc45"   # the v1.34 build commit: the last tree that taught 何時 as なんどき
# v1.36 item 3's corpus commit: the working tree when the counter table was written (round 1 found
# its 8 sentences there, all unchanged since fdb2b5f). Pinned so (f) survives their correction.
COUNTER_CALIBRATION_REF = "29e4778"
KNOWN_COUNTER_HITS = (   # (id, compound, verdict, taught) — each the same verdict in both fields
    ("n5-b303", "四月", "mismatch", "よんがつ"),
    ("n2-b942", "四月", "mismatch", "よんがつ"),
    ("n5-b071", "九時", "mismatch", "きゅうじ"),
    ("n4-g180", "九時", "mismatch", "きゅうじ"),
    ("n3-b750", "九時", "mismatch", "きゅうじ"),
    ("n5-b018", "二十四時間", "mismatch", "にじゅうよんじかん"),
    ("n1-b615", "四時間", "mismatch", "しじかん"),
    ("n2-b072", "四字", "mismatch", "よんじ"),
    ("n5-b334", "七時", "flag-only", "ななじはん"),   # the token is 時半, so the span runs on
)
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


def kana_segment(reading, tokens, start, end):
    """The stretch of `reading` (exKana) that stands for the tokens covering text[start:end], found by
    anchoring on the readings of the tokens before and after them — or None when those anchors do
    not hold, since then exKana cannot be lined up with the tokens."""
    pos, before, after = 0, "", ""
    for tok_surface, tok_reading in tokens:
        lo, hi = pos, pos + len(tok_surface)
        pos = hi
        if hi <= start:
            before += tok_reading
        elif lo >= end:
            after += tok_reading
    before, after = before.translate(KANA_DROPPED), after.translate(KANA_DROPPED)
    if (len(before) + len(after) <= len(reading)
            and reading.startswith(before) and reading.endswith(after)):
        return reading[len(before):len(reading) - len(after)]
    return None


def verdict_of(taught, alignment, accept, flag):
    """ok, flag-only (with the other sense) or mismatch, for one reading of one occurrence."""
    if any(fits(taught, r, alignment) for r in accept):
        return "ok", None
    for r, sense in flag.items():
        if fits(taught, r, alignment):
            return "flag-only", {"reading": r, "sense": sense}
    return "mismatch", None


def judge_occurrence(text, reading, tokens, start, end, accept, flag):
    """text[start:end] judged on the tokens AND on the reading. `accept` holds the right readings and
    `flag` {reading: sense} the ones legitimate in another sense or tolerated. `taught` is the
    tokens' reading when there are tokens, else the field's reading; `verdict` is the worse of
    verdictTokens and verdictKana."""
    span = cover(text, tokens, start, end)
    if span is None:      # a headword, a passage, or tokens that do not spell the text
        taught_span, taught, alignment = whole(text, reading, start, end)
        verdict, other = verdict_of(taught, alignment, accept, flag)
        record = {"taught": taught, "taughtSpan": taught_span, "alignment": alignment,
                  "verdictTokens": None, "verdictKana": verdict, "verdict": verdict}
    else:
        taught_span, taught, alignment = span
        v_tokens, o_tokens = verdict_of(taught, alignment, accept, flag)
        segment = kana_segment(reading, tokens, start, end)
        kana, kana_alignment = (reading, "kana-only") if segment is None else (segment, alignment)
        v_kana, o_kana = verdict_of(kana, kana_alignment, accept, flag)
        verdict = max(v_tokens, v_kana, key=VERDICT_RANK.get)
        other = o_tokens if v_tokens == "flag-only" else o_kana
        record = {"taught": taught, "taughtSpan": taught_span, "alignment": alignment,
                  "taughtKana": kana, "kanaAlignment": kana_alignment,
                  "verdictTokens": v_tokens, "verdictKana": v_kana, "verdict": verdict}
    if record["verdict"] == "flag-only":
        record["otherSense"] = other
    return record


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
            records.append({"compound": compound, "expected": list(expected),
                            **judge_occurrence(text, reading, tokens, start, end, expected,
                                               INTERROGATIVE_OTHER_SENSE.get(compound, {}))})
    return records


def numeral_value(run):
    """The number a numeral run spells, or None when this table does not read it as one number: a
    mix of kanji and digits, or kanji digits with no 十/百/千/万 (三四 'three or four')."""
    arabic = run.translate(FULLWIDTH)
    if arabic.isascii() and arabic.isdigit():
        return int(arabic)
    if any(c.isascii() for c in arabic):
        return None
    if not any(c in KANJI_UNIT or c == "万" for c in run):
        return KANJI_DIGIT[run] if len(run) == 1 else None
    total, section, digit = 0, 0, None
    for c in run:
        if c in KANJI_DIGIT:
            if digit is not None:
                return None
            digit = KANJI_DIGIT[c]
        elif c in KANJI_UNIT:
            section += (1 if digit is None else digit) * KANJI_UNIT[c]
            digit = None
        else:   # 万
            total += ((section + (digit or 0)) or 1) * 10000
            section, digit = 0, None
    return total + section + (digit or 0)


def number_readings(n):
    """Every reading this table accepts for n (a multiple of 10, or 0, which reads as '')."""
    if n >= 10000:
        return {m + "まん" + r for m in number_readings(n // 10000) for r in number_readings(n % 10000)}
    out = {""}
    for place in (1000, 100, 10, 1):
        d = n // place % 10
        if not d:
            continue
        if place == 1:
            parts = DIGIT_READINGS[d]
        else:
            parts = (PLACE_SOUND_CHANGE.get((place, d))
                     or tuple(r + PLACE_READING[place] for r in DIGIT_READINGS[d]))
        out = {o + p for o in out for p in parts}
    return out


def last_digit(run):
    last = run[-1].translate(FULLWIDTH)
    return int(last) if last.isascii() and last.isdigit() else KANJI_DIGIT.get(last)


def judge_counter_field(text, reading, tokens):
    """One record per number + month/hour/duration/字 counter in `text` whose last digit's sound
    changes: what the corpus teaches for it, and the verdict."""
    records = []
    for m in COUNTER_RE.finditer(text):
        run, counter = m.groups()
        compound, (start, end) = m.group(0), m.span()
        digit = last_digit(run)
        finals = COUNTER_FINAL[counter].get(digit)
        if not finals:
            continue     # a last digit that reads as it does alone (or 十/百/千/万): not enumerated
        value, follower = numeral_value(run), text[end:end + 1]
        if follower in NOT_THE_COUNTER.get(counter, ()):
            absorbed_by = f"{counter}{follower}"
        elif value is None:
            absorbed_by = f"{run}: not read as one number (a range such as 三四, or kanji mixed with digits)"
        elif counter == "月" and value not in MONTHS:
            absorbed_by = f"{compound}: no such month"
        else:
            absorbed_by = None
        if absorbed_by:
            records.append({"compound": compound, "verdict": "absorbed", "by": absorbed_by})
            continue
        prefixes, tail = number_readings(value - digit), COUNTER_READING[counter]
        expected = sorted({p + f + tail for p in prefixes for f in finals})
        flag = {p + r + tail: sense for p in prefixes
                for r, sense in COUNTER_TOLERATED.get(counter, {}).get(digit, {}).items()}
        flag.update(COUNTER_OTHER_SENSE.get(compound, {}))
        records.append({"compound": compound, "counter": counter, "number": value,
                        "expected": expected,
                        **judge_occurrence(text, reading, tokens, start, end, expected, flag)})
    return records


def fields_of(resources):
    """Every field the 何 and counter tables read: (path, id, field, text, reading, tokens)."""
    for path in sorted(glob.glob(f"{resources}/n[1-5].json")):
        for entry in json.load(open(path, encoding="utf-8")):
            yield path, entry["id"], "surface", entry["surface"], entry["kana"], None
            if entry.get("exJP") and entry.get("exKana"):
                yield path, entry["id"], "exJP", entry["exJP"], entry["exKana"], entry.get("exTokens")
    passages = os.path.join(resources, "passages.json")
    if os.path.exists(passages):
        for p in json.load(open(passages, encoding="utf-8")):
            yield passages, p["id"], "display", p["display"], p["kana"], None


def sweep(resources, judge):
    """Every field judged by `judge`. The population is counted where each field is judged, so it
    is this table's own count of what it read, not another table's."""
    population = {"exJP": 0, "surface": 0, "display": 0}
    inspected, hits = [], []
    for path, entry_id, field, text, reading, tokens in fields_of(resources):
        population[field] += 1
        for record in judge(text, reading, tokens):
            where = {"id": entry_id, "file": display_path(path), "field": field}
            inspected.append({**where, **record})
            if record["verdict"] in ("mismatch", "flag-only"):
                hits.append({**where, "sentence": text, "reading": reading, **record})
    return population, inspected, hits


def scan_interrogative(resources=RESOURCES):
    """Every example sentence (judged on exTokens and exKana), every headword, every passage."""
    return sweep(resources, judge_field)


def scan_counters(resources=RESOURCES):
    """The same fields, judged by the counter table."""
    return sweep(resources, judge_counter_field)


def below_floor(lexicalised, interrogative, counters):
    """Each table population under MIN_POPULATION, named. Every table is held to the floor on its
    own scan: one table having read the corpus says nothing about another (PLAN-V1.36 §I)."""
    short = [f"lexicalised {lexicalised}"] if lexicalised < MIN_POPULATION else []
    for name, population in (("interrogative", interrogative), ("counters", counters)):
        short += [f"{name} {field} {population[field]}" for field in ("exJP", "surface")
                  if population[field] < MIN_POPULATION]
    return short


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
    ("何人 taught なにん is a mismatch: the path is not proven on 何時 alone", "何人", "なにん",
     [["何人", "なにん"]], ["mismatch"]),
    ("a regression in exKana alone is a mismatch: tokens なんじ, exKana なんどき", "何時ですか",
     "なんどきですか", [["何時", "なんじ"], ["です", "です"], ["か", "か"]], ["mismatch"]),
)

COUNTER_LOGIC_CHECKS = (
    # (what it proves, text, reading, tokens, expected (compound, verdict, verdictTokens,
    #  verdictKana) in order)
    ("九時 taught きゅうじ is a mismatch in both fields", "九時に", "きゅうじに",
     [["九", "きゅう"], ["時", "じ"], ["に", "に"]],
     [("九時", "mismatch", "mismatch", "mismatch")]),
    ("七時: しちじ is right, ななじ is tolerated (flag-only)", "七時七時", "しちじななじ",
     [["七", "しち"], ["時", "じ"], ["七", "なな"], ["時", "じ"]],
     [("七時", "ok", "ok", "ok"), ("七時", "flag-only", "flag-only", "flag-only")]),
    ("七時間 accepts both しちじかん and ななじかん; 九時間 wants くじかん", "七時間七時間九時間",
     "しちじかんななじかんきゅうじかん",
     [["七", "しち"], ["時間", "じかん"], ["七", "なな"], ["時間", "じかん"], ["九", "きゅう"],
      ["時間", "じかん"]],
     [("七時間", "ok", "ok", "ok"), ("七時間", "ok", "ok", "ok"),
      ("九時間", "mismatch", "mismatch", "mismatch")]),
    ("a compound number is read whole: 二十四時間 にじゅうよじかん ok, にじゅうよんじかん not",
     "二十四時間、二十四時間", "にじゅうよじかんにじゅうよんじかん",
     [["二十四", "にじゅうよ"], ["時間", "じかん"], ["、", "、"], ["二十四", "にじゅうよん"],
      ["時間", "じかん"]],
     [("二十四時間", "ok", "ok", "ok"), ("二十四時間", "mismatch", "mismatch", "mismatch")]),
    ("a regression in the tokens alone is a mismatch: tokens よんがつ, exKana しがつ", "四月",
     "しがつ", [["四", "よん"], ["月", "がつ"]], [("四月", "mismatch", "mismatch", "ok")]),
    ("a regression in exKana alone is a mismatch: tokens しがつ, exKana よんがつ", "四月",
     "よんがつ", [["四", "し"], ["月", "がつ"]], [("四月", "mismatch", "ok", "mismatch")]),
    ("exKana is read where the tokens put it, not anywhere in the sentence", "九時と九時",
     "きゅうじとくじ", [["九", "きゅう"], ["時", "じ"], ["と", "と"], ["九", "く"], ["時", "じ"]],
     [("九時", "mismatch", "mismatch", "mismatch"), ("九時", "ok", "ok", "ok")]),
    ("an exact span must EQUAL an expected reading, not contain it", "四時", "ごごよじ",
     [["四時", "ごごよじ"]], [("四時", "mismatch", "mismatch", "mismatch")]),
    ("四時 しじ, 'the four seasons', is flag-only", "四時の移ろい", "しじのうつろい",
     [["四時", "しじ"], ["の", "の"], ["移ろい", "うつろい"]],
     [("四時", "flag-only", "flag-only", "flag-only")]),
    ("the surname 四月一日 わたぬき is flag-only; the date 四月一日 is still judged",
     "四月一日さん、四月一日", "わたぬきさんよんがつついたち",
     [["四月一日", "わたぬき"], ["さん", "さん"], ["、", "、"], ["四", "よん"], ["月", "がつ"],
      ["一日", "ついたち"]],
     [("四月", "flag-only", "flag-only", "flag-only"), ("四月", "mismatch", "mismatch", "mismatch")]),
    ("not the counter: 第四月曜日, 四時期, and 十四月 (no such month) are absorbed",
     "第四月曜日と四時期と十四月", "だいよんげつようびとよんじきとじゅうよんがつ", None,
     [("四月", "absorbed", None, None), ("四時", "absorbed", None, None),
      ("十四月", "absorbed", None, None)]),
    ("kanji digits with no 十/百/千 are a range, not one number: 三四時間, 六七時間",
     "三四時間、六七時間", "さんよじかんろくしちじかん", None,
     [("三四時間", "absorbed", None, None), ("六七時間", "absorbed", None, None)]),
    ("never inspected: 九州, 四季, 四ヶ月, 四か月, 十月, 一時, 一月, 十字路, 四六時中",
     "九州の四季、四ヶ月、四か月、十月、一時、一月、十字路、四六時中", "", None, []),
    ("ASCII and full-width digits are read: ４時 よんじ is a mismatch, 24時間 にじゅうよじかん ok",
     "４時、24時間", "よんじにじゅうよじかん",
     [["４", "よん"], ["時", "じ"], ["、", "、"], ["24", "にじゅうよ"], ["時間", "じかん"]],
     [("４時", "mismatch", "mismatch", "mismatch"), ("24時間", "ok", "ok", "ok")]),
    ("a field with no tokens is judged on its reading: 九時 きゅうじ", "九時", "きゅうじ", None,
     [("九時", "mismatch", None, "mismatch")]),
)

FLOOR_CHECKS = (
    # (what it proves, lexicalised, interrogative, counters, expected below_floor)
    ("the exit-2 floor names a short counter table", 6724,
     {"exJP": 6724, "surface": 7071}, {"exJP": 2, "surface": 7071}, ["counters exJP 2"]),
    ("the exit-2 floor names a short 何 table", 6724,
     {"exJP": 6724, "surface": 616}, {"exJP": 6724, "surface": 7071}, ["interrogative surface 616"]),
)


def calibrate():
    lines, ok = [], True

    def check(label, passed, detail):
        nonlocal ok
        ok = ok and passed
        lines.append(f"[{'PASS' if passed else 'FAIL'}] {label} — {detail}")

    with tempfile.TemporaryDirectory() as tmp:
        old, small = os.path.join(tmp, "pre-v135"), os.path.join(tmp, "n5-only")
        counted = os.path.join(tmp, "counter-ref")
        for d in (old, small, counted):
            os.mkdir(d)
        try:
            tree_at(CALIBRATION_REF, old)
            tree_at(COUNTER_CALIBRATION_REF, counted)
        except RuntimeError as e:
            return False, [f"[FAIL] cannot read a calibration tree: {e}"]
        shutil.copy(os.path.join(RESOURCES, "n5.json"), small)
        old_code, old_run = run_cli(tmp, "old", "--resources", old)
        head_code, head_run = run_cli(tmp, "head")
        small_code, small_run = run_cli(tmp, "small", "--resources", small)
        counted_code, counted_run = run_cli(tmp, "counted", "--resources", counted)

    if old_run is None or head_run is None or small_run is None or counted_run is None:
        return False, [f"[FAIL] a calibration run wrote no output (exit codes: {CALIBRATION_REF} "
                       f"{old_code}, working tree {head_code}, n5-only {small_code}, "
                       f"{COUNTER_CALIBRATION_REF} {counted_code})"]
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

    # (c) the floor on each table's own scan; n5-only must fall below it in each, and exit 2.
    check("(c0) the working tree exits 0 and the n5-only tree exits 2",
          head_code == 0 and small_code == 2, f"exit {head_code}; n5-only exit {small_code}")
    pop, small_pop = head_run["population"], small_run["population"]
    check(f"(c1) lexicalised table: its own scan reads ≥ {MIN_POPULATION} sentences; n5-only below",
          pop >= MIN_POPULATION and small_pop < MIN_POPULATION,
          f"working tree {pop}, n5-only {small_pop}")
    with open(os.path.join(RESOURCES, "passages.json"), encoding="utf-8") as f:
        passages = len(json.load(f))
    for label, key in (("(c2) 何 table", "interrogative"), ("(c3) counter table", "counters")):
        head_p, small_p = head_run[key]["population"], small_run[key]["population"]
        check(f"{label}: its own scan reads ≥ {MIN_POPULATION} sentences and headwords and all "
              f"{passages} passages; n5-only below",
              head_p["exJP"] >= MIN_POPULATION and head_p["surface"] >= MIN_POPULATION
              and head_p["display"] == passages
              and small_p["exJP"] < MIN_POPULATION and small_p["surface"] < MIN_POPULATION,
              f"working tree {head_p}, n5-only {small_p}")

    b937 = sorted((h["field"], h["verdict"], h["taught"]) for h in old_q["hits"] if h["id"] == "n2-b937")
    check(f"(d) {CALIBRATION_REF}: n2-b937 何分 なにぶん is flag-only in both fields",
          b937 == [("exJP", "flag-only", "なにぶん"), ("surface", "flag-only", "なにぶん")],
          f"hits for n2-b937: {b937}")

    kazoku = [(h["compound"], h["taught"]) for h in old_run["hits"] if h["id"] == "n5-kazoku"]
    check(f"(e) {CALIBRATION_REF}: the lexicalised table flags n5-kazoku", kazoku == [("四人", "よんにん")],
          f"hits for n5-kazoku: {kazoku}")

    # Each known hit: the same verdict on the tokens and on exKana, and exKana lined up with the
    # tokens (anchored), not found by the substring fallback.
    got = {(h["id"], h["field"], h["compound"], h["verdict"], h["verdictTokens"], h["verdictKana"],
            h["taught"], h.get("kanaAlignment") == h["alignment"])
           for h in counted_run["counters"]["hits"]}
    want = {(i, "exJP", c, v, v, v, t, True) for i, c, v, t in KNOWN_COUNTER_HITS}
    others = sorted(f"{h[0]} {h[2]} {h[3]} {h[6]}" for h in got - want)
    check(f"(f) {COUNTER_CALIBRATION_REF}: the counter table flags the {len(want)} known occurrences "
          f"in both exTokens and exKana",
          want <= got,
          f"missing: {sorted(f'{w[0]} {w[2]} {w[3]} {w[6]}' for w in want - got) or 'none'}; "
          f"also flagged (or flagged differently): {others or 'none'}")

    g079 = [(r["compound"], r["verdict"], r.get("verdictTokens"), r.get("verdictKana"), r.get("taught"))
            for r in head_run["counters"]["inspected"] if r["id"] == "n5-g079"]
    flagged = [h for h in head_run["counters"]["hits"] if h["id"] == "n5-g079"]
    check("(g) the working tree inspects n5-g079 七時 しちじ and passes it in both fields",
          g079 == [("七時", "ok", "ok", "ok", "しちじ")] and not flagged,
          f"inspected: {g079}; hits: {len(flagged)}")

    for what, text, reading, tokens, want in LOGIC_CHECKS:
        got = [r["verdict"] for r in judge_field(text, reading, tokens)]
        check(f"logic: {what}", got == want, f"{text} {reading}: {got}")
    for what, text, reading, tokens, want in COUNTER_LOGIC_CHECKS:
        got = [(r["compound"], r["verdict"], r.get("verdictTokens"), r.get("verdictKana"))
               for r in judge_counter_field(text, reading, tokens)]
        check(f"logic: {what}", got == want, f"{text}: {got}")
    for what, lexicalised, interrogative, counters, want in FLOOR_CHECKS:
        got = below_floor(lexicalised, interrogative, counters)
        check(f"logic: {what}", got == want, f"{got}")
    return ok, lines


def print_table(title, population, enumerated, inspected, hits):
    by_compound, by_alignment = {}, {}
    for r in inspected:
        by_compound[r["compound"]] = by_compound.get(r["compound"], 0) + 1
        key = r.get("alignment", "absorbed")
        by_alignment[key] = by_alignment.get(key, 0) + 1
    kana_alignment = {}
    for r in inspected:
        if r.get("kanaAlignment"):
            kana_alignment[r["kanaAlignment"]] = kana_alignment.get(r["kanaAlignment"], 0) + 1
    kinds = [h["verdict"] for h in hits]
    print(f"\n── {title} ──")
    print(f"population   : {population['exJP']} example sentences (judged on exTokens and exKana), "
          f"{population['surface']} headwords, {population['display']} passages")
    print(f"enumerated   : {enumerated}")
    print(f"inspected    : {len(inspected)} occurrences — "
          + (", ".join(f"{c} {n}" for c, n in sorted(by_compound.items(), key=lambda kv: -kv[1])) or "none")
          + "; alignment: " + (", ".join(f"{a} {n}" for a, n in sorted(by_alignment.items())) or "none")
          + "; exKana: " + (", ".join(f"{a} {n}" for a, n in sorted(kana_alignment.items())) or "none"))
    print(f"flagged      : {len(hits)} ({kinds.count('mismatch')} mismatch, "
          f"{kinds.count('flag-only')} flag-only)")
    for h in hits:
        note = f" — other sense: {h['otherSense']['sense']}" if h.get("otherSense") else ""
        fields = (f" [tokens {h['verdictTokens']}, exKana {h['verdictKana']} "
                  f"'{h.get('taughtKana')}']" if h.get("verdictTokens") else "")
        print(f"\n  {h['id']}  [{h['verdict']}]  {h['file']} {h['field']}  {h['compound']} taught "
              f"{h['taught']}, expected {' | '.join(h['expected'])}{fields}{note}")
        print(f"      {h['sentence']}")
        print(f"      {h['reading']}")


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
    print_table("interrogative: 何 + counter", population, inspected=inspected, hits=q_hits,
                enumerated=f"{len(INTERROGATIVE)} compounds, {len(INTERROGATIVE_ABSORBERS)} absorber, "
                           f"{len(INTERROGATIVE_OTHER_SENSE)} with another legitimate sense (flag-only)")

    c_population, c_inspected, c_hits = scan_counters(args.resources)
    print_table("counters: month 月, hour 時, duration 時間, 字", c_population,
                inspected=c_inspected, hits=c_hits,
                enumerated="; ".join(f"{c} " + ", ".join(f"{d} {'|'.join(r)}" for d, r in finals.items())
                                     for c, finals in COUNTER_FINAL.items())
                           + f"; tolerated {sum(len(v) for v in COUNTER_TOLERATED.values())}, "
                             f"other senses {sum(len(v) for v in COUNTER_OTHER_SENSE.values())}")

    if args.json:
        out = {"population": checked, "enumerated": len(LEXICALISED),
               "absorbers": list(ABSORBERS), "hits": hits,
               "interrogative": {"population": population,
                                 "enumerated": {c: list(r) for c, r in INTERROGATIVE.items()},
                                 "otherSense": INTERROGATIVE_OTHER_SENSE,
                                 "absorbers": list(INTERROGATIVE_ABSORBERS),
                                 "inspected": inspected, "hits": q_hits},
               "counters": {"population": c_population,
                            "enumerated": {c: {str(d): list(r) for d, r in finals.items()}
                                           for c, finals in COUNTER_FINAL.items()},
                            "counterReading": COUNTER_READING,
                            "tolerated": {c: {str(d): v for d, v in t.items()}
                                          for c, t in COUNTER_TOLERATED.items()},
                            "otherSense": COUNTER_OTHER_SENSE,
                            "notTheCounter": {c: list(f) for c, f in NOT_THE_COUNTER.items()},
                            "inspected": c_inspected, "hits": c_hits}}
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
    # A scan that inspected nothing must not report clean — and each table answers for itself.
    short = below_floor(checked, population, c_population)
    if short:
        print(f"\n!! below the {MIN_POPULATION} floor: {', '.join(short)} — "
              f"this scan is reading almost nothing")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
