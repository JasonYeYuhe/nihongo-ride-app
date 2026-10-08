#!/usr/bin/env python3
"""Does any shipped sentence read a LEXICALISED counter as if it were two morphemes?
And does any read an INTERROGATIVE counter (何 + counter) with a reading that is not the question's?
And does any read a MONTH, HOUR, DURATION or 字 counter without the sound change at its last digit?
And does any read a SOUND-CHANGING counter (分 軒 階 回 歳 本 杯 匹 個 冊 点 泊), or 千 / 百 after
a digit, without its sound change?

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
What it cannot see: a number written in kana in exJP, a counter in neither this table nor the next
(年, 週, 人, 枚, 台 …), a wrong reading in the digits before the last, and a sense not listed above.

THE SOUND-CHANGING COUNTERS (v1.36, PLAN-V1.36 §I addendum 2)
--------------------------------------------------------------
Why: the data-lens review of the §I corrections scanned every numeral token followed by a counter and
found the same defect outside 月 / 時 / 時間 / 字: 三千円 taught さんせんえん (n1-b439, n3-b781, both in
the dictation pool), 三分 さんふん (n1-b1630), 三十分 さんじゅうぶん (n2-b449), 五分 ごぶん (n1-b327),
十分 'ten minutes' じゅうふん (n1-b1147, n1-b1841, n2-b311, n4-b127), 一軒 いちけん (n2-b479), 一階
いちかい (n1-b957); tolerated, 三階 さんかい (n4-g171) and 三十歳 / 八十歳 …じゅうさい (n3-b123, n1-b311,
n1-b1450). The fix review's own scan (§I) added 十分 'ten minutes' taught じゅうぶん (n3-b020, in the
pool).

It is the counter table above, extended: the same judge, population, output key and calibration. From
分 on the counter's own sound changes too (ふん / ぷん, ほん / ぼん / ぽん), so every row is the whole
reading of the final unit with its counter:
    分   1 いっぷん  2 にふん  3 さんぷん  4 よんぷん  5 ごふん  6 ろっぷん  7 ななふん  8 はっぷん | はちふん
         9 きゅうふん  10 じゅっぷん | じっぷん
    軒   1 いっけん  3 さんげん  6 ろっけん  8 はっけん  10 じゅっけん | じっけん
    階   1 いっかい  3 さんがい (さんかい tolerated)  6 ろっかい  8 はっかい | はちかい  10 じゅっかい | じっかい
    回   1 いっかい  6 ろっかい  8 はっかい | はちかい  10 じゅっかい | じっかい
    歳   1 いっさい  8 はっさい  10 じゅっさい | じっさい (…じゅうさい tolerated); 二十歳 also はたち
    本   1 いっぽん  3 さんぼん  6 ろっぽん  8 はっぽん  10 じゅっぽん | じっぽん
    杯   1 いっぱい  3 さんばい  6 ろっぱい  8 はっぱい  10 じゅっぱい | じっぱい
    匹   1 いっぴき  3 さんびき  6 ろっぴき  8 はっぴき  10 じゅっぴき | じっぴき
    個   1 いっこ  6 ろっこ  8 はっこ  10 じゅっこ | じっこ
    冊   1 いっさつ  8 はっさつ  10 じゅっさつ | じっさつ
    点   1 いってん  6 ろってん  8 はってん  10 じゅってん | じってん
    泊   1 いっぱく  3 さんぱく  6 ろっぱく  8 はっぱく  10 じゅっぱく | じっぱく
    千   after 3 さんぜん, 8 はっせん            百   after 3 さんびゃく, 6 ろっぴゃく, 8 はっぴゃく
The final unit "10" is a number ending in 十 (or, in digits, in 0 over a non-zero tens digit). The
tens digit is read plainly in front of the row, so 三十分 is さん + じゅっぷん and 八十歳 はち + じゅっさい.
A number ending in 百, 千 or 万 before a counter (百本, 千回, 100分) is not enumerated. 千 and 百 are
places, not counters: every 千 or 百 just after a listed digit, inside any kanji number, is judged from
the start of the number through the place, whatever follows (三千円 → 三千 さんぜん; 一万三千 いちまん
さんぜん). Unlisted digits are absent, as before (二本 にほん, 三冊 さんさつ read as they do alone).

分's sense. 分 is also ぶん (三分の一; 十分 'enough') and ぶ (五分 'even'; 一分 'a tenth'), and only
the English can tell them apart: exEN for a sentence, the meanings for a headword or a passage.
  * minutes: the text says so (時 or 時間 just before the number: 九時十分; 間 just after: 十分間), or
    the English names minutes (minute, min, or a clock time like 9:10). Judged as the table says, so
    n3-b020 「およそ十分歩きました」, 'about ten minutes', taught じゅうぶん is a mismatch.
  * 十分 'enough': the English names no minutes. じゅうぶん, the adjective, is accepted; a minutes
    reading is flag-only. n4-g178 「時間は十分にある」 ('plenty of time') is inspected and passes.
  * ambiguous, flag-only, never a mismatch: 十分 taught じゅうぶん with English that names minutes
    and 'enough' / 'sufficient' / 'plenty' / 'fully' … both; 十分 with no English at all (only a
    reading wrong in both senses, じゅうふん, is a mismatch); any other 分 whose English names no
    minutes and whose reading is not a minutes reading (五分 ごぶ).
  * absorbed: a fraction, 分 then の then a numeral (三分の一, 十分の一). 三分の休憩 is still judged.

Not a hit, and why:
  * absorbed, lexemes with their own reading, never judged: 八百屋 やおや, 八百長, 八千代, 一回り
    ひとまわり, 五分五分, 九分九厘, 七分袖, 八分目, 一個人 いちこじん.
  * flag-only, tolerated: 三階 さんかい; a ten before 歳 read …じゅうさい (十歳, 三十歳, 八十歳).
  * accepted: 二十歳 はたち, beside にじゅっさい | にじっさい.
  * judged and fine: 一杯 'full' is いっぱい, the counter's own reading; 一回 and 一階 are both
    いっかい; 一本気 and 一点張り are judged on their start (いっぽん…, いってん…).
  * never seen: 何分, 何本 … (何 is not a numeral; the 何 table reads them); 一人, 一番, 一生, 一緒;
    万歳; 百本, 千回.
What it cannot see, in addition: a wrong reading at a digit a row does not list (四本, 三冊 are never
judged), 才 for 歳, a counter in kana in exJP (いっぽん), the 千 / 百 of a number in digits (3000円),
and a sense of 分 the English does not reveal. It errs toward flagging, never toward a correction:
a legitimate form a row does not list (七分 しちふん) or a lexeme not in COUNTER_ABSORBERS (八百万
やおよろず) is a mismatch, for the 2-of-2 refuters to reject.

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
  (g) the working tree inspects n5-g079 七時, taught しちじ, and passes it in both fields;
  (i) on `3d891b9` — main when the sound-changing counters were added, every sentence of §I addendum 2
      as its review read it, pinned so the check survives their correction — the counter table flags
      the 17 known occurrences, each with the same verdict in exTokens and in exKana, exKana lined up
      with the tokens: 13 mismatches (三千 ×2, 三分, 三十分, 十分 ×5, 五分, 一軒, 一階, and 八十点, which
      this table found itself) and 4 flag-only (三階 さんかい, and the three …じゅうさい). The same 17 on
      `fdb2b5f`, the corpus 1.35 shipped, whose 17 sentences are byte-identical to 3d891b9's: the
      defects were on sale, not introduced since. Anything else either tree yields is listed, not
      failed (fdb2b5f also still holds §I's 8 month / hour corrections);
  (j) the working tree inspects 十分 and passes it for its sense: n1-b1516 じっぷん 'ten minutes'
      (v1.25's correction) and n4-g178 じゅうぶん 'enough', each in its sentence and its headword;
  (k) the working tree records its real lexemes, never judging them (n5-b364 八百屋, n1-b2056 一回り),
      and passes n5-b331 二十歳 はたち in both fields;
  (l) hits carry their English, and their dictation-pool membership agrees with what PLAN-V1.36 §I
      states from the review (n1-b439, n3-b781, n3-b020 and n4-g171 in the pool; n5-b334 withheld) —
      so an inverted or missing pool test cannot report quietly. Read on `3d891b9` with that tree's
      own dictation-exclusions.json, since §I described that tree and two of the five are corrected
      since; and on the working tree for the three that are still hits there (n3-b020 and n4-g171 in,
      n5-b334 withheld), so the pool lookup is also proven on the tree a sweep reports;
  (m) the working tree inspects every sentence §I addendum 2 corrected (v136-reading-manifest.json)
      and passes it in both fields, exKana lined up with the tokens, taught the corrected reading —
      not flagged because each was looked at and passed. n3-b020 is not among them: its correction
      was upheld but held back, because the voice is proven to say 十分 = じゅうぶん in that pool
      sentence (v136-dictation-remeasure.json), so it is still this table's one mismatch;
  (h) a PLANTED tree: the working tree's corpus copied, with one known-wrong occurrence per table
      planted in the example sentences of every n-file, and one headword and one passage for each
      table that reads them, all under ids no entry uses (`plant-…`). Every plant must be flagged
      by its own table, a mismatch (on exTokens and exKana for a sentence), and no plant by
      another table. Added after round 1 of the fix review: (c) counts what is HANDED to a table,
      so a narrowing placed after the count — a 何 table that judged only two ids, or only n2 and
      n5, a counter table that judged only the 9 known ids or no headwords — kept the full count
      and passed every check above. A plant in each file and each kind of field is what such a
      narrowing cannot pass. The counter plants include 七月 なながつ and 九月 きゅうがつ, which the
      corpus does not contain, so a 月 row dropped or inverted, or MONTHS narrowed, fails here too.
      Since §I addendum 2 every n-file has a second counter plant on a sound-changing row (三分, 一軒,
      八本, 三千, 六百), and a headword 三分 and a passage 十分 carry English that names minutes: if a
      headword's or a passage's meanings did not reach 分's sense, that plant would be flag-only, not
      a mismatch, and (h) fails.
Then synthetic logic checks for paths the real corpus does not exercise: for the 何 table an absorber,
何階's two readings, a prefix span, a counter split across two tokens, 何人 なにじん, 何人 なにん (a
mismatch on a second compound), and a regression in exKana alone; for the counter table both an
accepted and a rejected form of every row of the table above (月 4/7/9, 時 4/7/9, 時間 4/7/9, 字 4),
the tolerated and other-sense flags, and the absorbers; for the sound-changing rows, every row's
standard reading(s) and the reading without its sound change, written out by hand in
SOUND_CHANGE_ROWS (never derived from COUNTER_FINAL), 分's four senses and its fraction, the lexemes,
二十歳, the tolerated 三階 and …じゅうさい, compound numbers, 千 / 百 inside a number, digits, the
never-inspected forms and a regression in each field alone; and the exit-2 floor naming each short
table. They prove the code paths, not accuracy: accuracy is (a)–(l). A failed check exits 1 and
writes nothing.

What the population line does and does not say. A field is counted once its table's judge has run
on it, so a field skipped before the judge is not counted. A judge that returns early is still
counted — the count cannot see inside it, which is why (h) exists. The counter and 何 tables read
the same fields, so their two populations are always equal: which one a caller reads cannot be
told apart, and is not checked.

IT IS A SWEEP, NOT A GATE. `run_all_gates.sh` and CI do not run it (checked 2026-10-07: neither
names it, and it is not a `scripts/test_*.py`, the glob the runner turns into gates). Keep it that
way: a test_*.py for it would add a gate and move FLOOR.

A hit also carries its English and `inDictationPool`: true for an example sentence whose id the
tree's dictation-exclusions.json does not withhold (dictation draws from example sentences alone),
false for a withheld sentence or a headword or passage, null in a tree that has no such file.

    python3 scripts/check_counter_readings.py [--json out.json] [--resources DIR] [--calibrate]
    python3 scripts/check_counter_readings.py --calibrate --json docs/measurements/v136-counter-sweep-5.json
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

# ── the counter table (PLAN-V1.36 §I, and §I addendum 2) ──────────────────────────────────────
# counter -> {final unit: the standard readings of that unit WITH its counter}. The final unit is the
# last digit (1–9), or 10 for a number ending in 十 (三十分 is さん + じゅっぷん). Only the units whose
# sound changes are listed; the rest read as they do alone and are deliberately absent (see the
# docstring). A row is the whole reading of digit + counter because, from 分 on, the counter's own
# sound changes too (ふん / ぷん, ほん / ぼん / ぽん).
COUNTER_FINAL = {
    "月": {4: ("しがつ",), 7: ("しちがつ",), 9: ("くがつ",)},
    "時": {4: ("よじ",), 7: ("しちじ",), 9: ("くじ",)},
    "時間": {4: ("よじかん",), 7: ("しちじかん", "ななじかん"), 9: ("くじかん",)},
    "字": {4: ("よじ",)},
    # §I addendum 2: the sound-changing counters.
    "分": {1: ("いっぷん",), 2: ("にふん",), 3: ("さんぷん",), 4: ("よんぷん",), 5: ("ごふん",),
          6: ("ろっぷん",), 7: ("ななふん",), 8: ("はっぷん", "はちふん"), 9: ("きゅうふん",),
          10: ("じゅっぷん", "じっぷん")},
    "軒": {1: ("いっけん",), 3: ("さんげん",), 6: ("ろっけん",), 8: ("はっけん",),
          10: ("じゅっけん", "じっけん")},
    "階": {1: ("いっかい",), 3: ("さんがい",), 6: ("ろっかい",), 8: ("はっかい", "はちかい"),
          10: ("じゅっかい", "じっかい")},
    "回": {1: ("いっかい",), 6: ("ろっかい",), 8: ("はっかい", "はちかい"), 10: ("じゅっかい", "じっかい")},
    "歳": {1: ("いっさい",), 8: ("はっさい",), 10: ("じゅっさい", "じっさい")},
    "本": {1: ("いっぽん",), 3: ("さんぼん",), 6: ("ろっぽん",), 8: ("はっぽん",),
          10: ("じゅっぽん", "じっぽん")},
    "杯": {1: ("いっぱい",), 3: ("さんばい",), 6: ("ろっぱい",), 8: ("はっぱい",),
          10: ("じゅっぱい", "じっぱい")},
    "匹": {1: ("いっぴき",), 3: ("さんびき",), 6: ("ろっぴき",), 8: ("はっぴき",),
          10: ("じゅっぴき", "じっぴき")},
    "個": {1: ("いっこ",), 6: ("ろっこ",), 8: ("はっこ",), 10: ("じゅっこ", "じっこ")},
    "冊": {1: ("いっさつ",), 8: ("はっさつ",), 10: ("じゅっさつ", "じっさつ")},
    "点": {1: ("いってん",), 6: ("ろってん",), 8: ("はってん",), 10: ("じゅってん", "じってん")},
    "泊": {1: ("いっぱく",), 3: ("さんぱく",), 6: ("ろっぱく",), 8: ("はっぱく",),
          10: ("じゅっぱく", "じっぱく")},
    # 千 and 百 are places, not counters: the digit just before one changes its sound (the key is
    # that digit), inside any kanji number and whatever follows it (三千円, 一万三千).
    "千": {3: ("さんぜん",), 8: ("はっせん",)},
    "百": {3: ("さんびゃく",), 6: ("ろっぴゃく",), 8: ("はっぴゃく",)},
}
PLACES = {"千": 1000, "百": 100}
# A final unit's reading that is heard but not the standard: flag-only, for a person, never corrected.
COUNTER_TOLERATED = {
    "時": {7: {"ななじ": "tolerated: ななじ is common speech; しちじ is the textbook form"}},
    "階": {3: {"さんかい": "tolerated: さんかい is common speech; さんがい is the traditional form"}},
    "歳": {10: {"じゅうさい": "tolerated: …じゅうさい is heard; …じゅっさい / …じっさい is the standard"}},
}
# The same spelling read in another sense: flag-only. Keyed by the whole compound.
COUNTER_OTHER_SENSE = {
    "四時": {"しじ": "literary 'the four seasons' (四時)"},
    "四月": {"わたぬき": "the surname 四月一日 / 四月朔日"},
}
# A whole compound with a lexicalised reading accepted beside the table's (二十歳 はたち).
COUNTER_WHOLE = {"二十歳": ("はたち",)}
# Lexemes that contain a number + counter and have their own reading: recorded, never judged. Each
# holds an enumerated row (二回り ふたまわり does not: 二回 is never judged, so it is not listed).
COUNTER_ABSORBERS = ("八百屋", "八百長", "八千代", "一回り", "五分五分", "九分九厘", "七分袖", "八分目",
                     "一個人")
# The counter character is the first of another word: 時代, 時期, 時点; 月曜 (第四月曜日).
NOT_THE_COUNTER = {"時": ("代", "期", "点"), "月": ("曜",)}
MONTHS = range(1, 13)
# 分's sense, read from the English (PLAN-V1.36 §I addendum 2: "use exEN (minutes/min) and context").
MINUTES_EN = re.compile(r"\bmin(?:ute)?s?\b|\b\d{1,2}:\d{2}\b", re.IGNORECASE)
ENOUGH_EN = re.compile(r"\b(?:enough|sufficient(?:ly)?|suffices?|plenty|ample|amply|fully|thorough(?:ly)?|"
                       r"adequate(?:ly)?)\b", re.IGNORECASE)
ENOUGH = "じゅうぶん"   # 十分 the adjective, 'enough'

KANJI_DIGIT = {"〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
KANJI_UNIT = {"十": 10, "百": 100, "千": 1000}
FULLWIDTH = str.maketrans("０１２３４５６７８９", "0123456789")
NUMERALS = "〇一二三四五六七八九十百千万0123456789０１２３４５６７８９"
# The whole numeral run before a counter; 時間 is tried before 時.
COUNTER_RE = re.compile("([〇一二三四五六七八九十百千万0-9０-９]+)"
                        "(時間|時|月|字|分|軒|階|回|歳|本|杯|匹|個|冊|点|泊)")
# A kanji number, searched for a 千 or 百 after a digit.
KANJI_NUMBER_RE = re.compile("[〇一二三四五六七八九十百千万]+")

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
# §I addendum 2's corpus: main when the sound-changing counters were added, every sentence below
# still as the review read it. Pinned so (i) survives their correction.
SOUND_CHANGE_CALIBRATION_REF = "3d891b9"
KNOWN_SOUND_CHANGE_HITS = (   # (id, compound, verdict, taught) — PLAN-V1.36 §I and §I addendum 2
    ("n1-b439", "三千", "mismatch", "さんせん"),
    ("n3-b781", "三千", "mismatch", "さんせん"),
    ("n1-b1630", "三分", "mismatch", "さんふん"),
    ("n2-b449", "三十分", "mismatch", "さんじゅうぶん"),
    ("n1-b1147", "十分", "mismatch", "じゅうふん"),
    ("n1-b1841", "十分", "mismatch", "じゅうふん"),
    ("n2-b311", "十分", "mismatch", "じゅうふん"),
    ("n4-b127", "十分", "mismatch", "じゅうふん"),
    ("n3-b020", "十分", "mismatch", "じゅうぶん"),   # 'ten minutes' by exEN, taught the 'enough' reading
    ("n1-b327", "五分", "mismatch", "ごぶん"),
    ("n2-b479", "一軒", "mismatch", "いちけん"),
    ("n1-b957", "一階", "mismatch", "いちかい"),
    # Not from the review: this table found it on 3d891b9 (v136-counter-sweep-4.json), and it was then
    # upheld 2 of 2 and corrected like the rest. Pinned so a 点 row that went soft cannot pass.
    ("n3-b678", "八十点", "mismatch", "はちじゅうてん"),
    ("n4-g171", "三階", "flag-only", "さんかい"),
    ("n3-b123", "三十歳", "flag-only", "さんじゅうさい"),
    ("n1-b311", "八十歳", "flag-only", "はちじゅうさい"),
    ("n1-b1450", "八十歳", "flag-only", "はちじゅうさい"),
)
# (j) and (k): on the working tree, inspected and NOT flagged — (id, field, compound, verdict, taught).
# n1-b1516 is v1.25's correction to じっぷん; n4-g178 is the headword 十分 'enough', whose sentence's
# English ("plenty of time") names time but no minutes.
KNOWN_SOUND_CHANGE_PASSES = (
    ("n1-b1516", "exJP", "十分", "ok", "じっぷん"), ("n1-b1516", "surface", "十分", "ok", "じっぷん"),
    ("n4-g178", "exJP", "十分", "ok", "じゅうぶん"), ("n4-g178", "surface", "十分", "ok", "じゅうぶん"),
)
KNOWN_LEXEMES = (
    ("n5-b364", "exJP", "八百", "absorbed", None), ("n5-b364", "surface", "八百", "absorbed", None),
    ("n1-b2056", "exJP", "一回", "absorbed", None),
    ("n5-b331", "exJP", "二十歳", "ok", "はたち"), ("n5-b331", "surface", "二十歳", "ok", "はたち"),
)
# (i) again on the corpus 1.35 shipped (the v1.35 build commit, release_numbers.BASELINE_REF while v1.36
# is built). Pinned, not read from release_numbers: BASELINE_REF moves on with the next release.
SHIPPED_REF = "fdb2b5f"
# (l): dictation-pool membership as PLAN-V1.36 §I states it, measured by the review, not by this file:
# 三千円 n1-b439 and n3-b781 "both in the dictation pool", n3-b020 "in the dictation pool", n4-g171
# "in the pool"; n5-b334 among the 8 "already withheld from dictation". Read on 3d891b9, the tree §I
# described; the working tree still has three of them as hits.
KNOWN_POOL = (("n1-b439", True), ("n3-b781", True), ("n3-b020", True), ("n4-g171", True),
              ("n5-b334", False))
KNOWN_POOL_HEAD = (("n3-b020", True), ("n4-g171", True), ("n5-b334", False))
# (m): every sentence §I addendum 2 corrected, with the reading it was corrected to — (id, compound,
# corrected). Written out from v136-reading-manifest.json's 'corrected', never derived from COUNTER_FINAL.
# Where two forms are standard the corpus took the more common one (じゅっぷん, はちじゅってん). n3-b020 is
# absent on purpose: upheld, but held back (see (m) in the docstring).
KNOWN_CORRECTED = (
    ("n1-b439", "三千", "さんぜん"), ("n3-b781", "三千", "さんぜん"), ("n3-b678", "八十点", "はちじゅってん"),
    ("n1-b1630", "三分", "さんぷん"), ("n2-b449", "三十分", "さんじゅっぷん"), ("n1-b327", "五分", "ごふん"),
    ("n1-b1147", "十分", "じゅっぷん"), ("n1-b1841", "十分", "じゅっぷん"), ("n2-b311", "十分", "じゅっぷん"),
    ("n4-b127", "十分", "じゅっぷん"), ("n2-b479", "一軒", "いっけん"), ("n1-b957", "一階", "いっかい"),
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


def verdict_of(taught, alignment, accept, flag, fallback=None):
    """ok, flag-only (with the other sense) or mismatch, for one reading of one occurrence. With a
    `fallback` sense, a reading that is neither accepted nor flagged is flag-only, not a mismatch:
    the occurrence's sense is undecided, so nothing about it is a correction candidate."""
    if any(fits(taught, r, alignment) for r in accept):
        return "ok", None
    for r, sense in flag.items():
        if fits(taught, r, alignment):
            return "flag-only", {"reading": r, "sense": sense}
    if fallback:
        return "flag-only", {"reading": None, "sense": fallback}
    return "mismatch", None


def judge_occurrence(text, reading, tokens, start, end, accept, flag, fallback=None):
    """text[start:end] judged on the tokens AND on the reading. `accept` holds the right readings and
    `flag` {reading: sense} the ones legitimate in another sense or tolerated. `taught` is the
    tokens' reading when there are tokens, else the field's reading; `verdict` is the worse of
    verdictTokens and verdictKana."""
    span = cover(text, tokens, start, end)
    if span is None:      # a headword, a passage, or tokens that do not spell the text
        taught_span, taught, alignment = whole(text, reading, start, end)
        verdict, other = verdict_of(taught, alignment, accept, flag, fallback)
        record = {"taught": taught, "taughtSpan": taught_span, "alignment": alignment,
                  "verdictTokens": None, "verdictKana": verdict, "verdict": verdict}
    else:
        taught_span, taught, alignment = span
        v_tokens, o_tokens = verdict_of(taught, alignment, accept, flag, fallback)
        segment = kana_segment(reading, tokens, start, end)
        kana, kana_alignment = (reading, "kana-only") if segment is None else (segment, alignment)
        v_kana, o_kana = verdict_of(kana, kana_alignment, accept, flag, fallback)
        verdict = max(v_tokens, v_kana, key=VERDICT_RANK.get)
        other = o_tokens if v_tokens == "flag-only" else o_kana
        record = {"taught": taught, "taughtSpan": taught_span, "alignment": alignment,
                  "taughtKana": kana, "kanaAlignment": kana_alignment,
                  "verdictTokens": v_tokens, "verdictKana": v_kana, "verdict": verdict}
    if record["verdict"] == "flag-only":
        record["otherSense"] = other
    return record


def judge_field(text, reading, tokens, english=None):
    """One record per 何+counter in `text`: what the corpus teaches for it, and the verdict.
    `english` is accepted so every judge takes the same fields, and is not read: 何分's other
    sense (なにぶん) is flag-only whatever the English says."""
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


def final_key(run):
    """The final unit a counter's sound change hangs on: the last digit 1–9, or 10 for a number
    ending in 十 — or in 0, in digits, which is confirmed against the value's tens digit later.
    None (or 0) for a number ending in 百, 千, 万 or 〇: not enumerated."""
    if run[-1] == "十":
        return 10
    digit = last_digit(run)
    return 10 if digit == 0 and run[-1].translate(FULLWIDTH).isascii() else digit


def counter_occurrences(text):
    """(compound, counter, number, start, end) for every number + counter in `text`, and for every
    千 or 百 after a digit inside a kanji number — that one from the start of the number through
    the place (一万三千円 gives 一万三千), whatever follows. In text order."""
    found = [(m.group(0), m.group(2), m.group(1), m.start(), m.end()) for m in COUNTER_RE.finditer(text)]
    for m in KANJI_NUMBER_RE.finditer(text):
        run = m.group(0)
        for i in range(1, len(run)):
            if run[i] in PLACES and run[i - 1] in KANJI_DIGIT:
                found.append((run[:i + 1], run[i], run[:i + 1], m.start(), m.start() + i + 1))
    return sorted(found, key=lambda o: (o[3], o[4]))


def minute_sense(text, number_start, end, english):
    """Which 分 this is, and why: 'minutes' (the text or the English says so), 'ambiguous' (the
    English names minutes and 'enough' both), 'other' (the English names no minutes) or 'unknown'
    (there is no English). PLAN-V1.36 §I addendum 2."""
    if text[:number_start].endswith(("時", "時間")) or text[end:end + 1] == "間":
        return "minutes", "the text says minutes (時 before the number, or 分間)"
    if not english:
        return "unknown", "no English to read the sense from"
    if MINUTES_EN.search(english):
        if ENOUGH_EN.search(english):
            return "ambiguous", "the English names minutes and 'enough' both"
        return "minutes", "the English names minutes"
    return "other", "the English names no minutes"


def judge_counter_field(text, reading, tokens, english=None):
    """One record per number + counter in `text` whose final unit's sound changes, and per 千 / 百
    whose digit changes it: what the corpus teaches for it, and the verdict. `english` (exEN, or
    a headword's or passage's meanings) decides 分's sense and nothing else."""
    records = []
    lexemes = [(m.start(), m.end(), a) for a in COUNTER_ABSORBERS for m in re.finditer(re.escape(a), text)]
    for compound, counter, number, start, end in counter_occurrences(text):
        place = PLACES.get(counter)
        run = number[:-1] if place else number     # the numerals before the counter or place
        key = KANJI_DIGIT[run[-1]] if place else final_key(run)
        finals = COUNTER_FINAL[counter].get(key)
        if not finals:
            continue     # a final unit that reads as it does alone (or 百/千/万): not enumerated
        value, follower = numeral_value(number), text[end:end + 1]
        tens = None if place or key != 10 or value is None else value % 100 // 10
        lexeme = next((a for lo, hi, a in lexemes if lo <= start and end <= hi), None)
        if tens == 0:
            continue     # 100分, 2000本 in digits: ends in 百 or 千, not in a ten
        if lexeme:
            absorbed_by = f"{lexeme}: a lexeme with its own reading"
        elif follower in NOT_THE_COUNTER.get(counter, ()):
            absorbed_by = f"{counter}{follower}"
        elif counter == "分" and follower == "の" and text[end + 1:end + 2] and text[end + 1] in NUMERALS:
            absorbed_by = f"{compound}の…: a fraction, read ぶん"
        elif value is None:
            absorbed_by = f"{run}: not read as one number (a range such as 三四, or kanji mixed with digits)"
        elif counter == "月" and value not in MONTHS:
            absorbed_by = f"{compound}: no such month"
        else:
            absorbed_by = None
        if absorbed_by:
            records.append({"compound": compound, "verdict": "absorbed", "by": absorbed_by})
            continue
        if place:
            prefixes = number_readings(value - key * place)
        elif key == 10:     # the tens digit read plainly in front of the row: さん + じゅっぷん
            prefixes = {p + t for p in number_readings(value - 10 * tens)
                        for t in (("",) if tens == 1 else DIGIT_READINGS[tens])}
        else:
            prefixes = number_readings(value - key)
        expected = sorted({p + f for p in prefixes for f in finals} | set(COUNTER_WHOLE.get(compound, ())))
        flag = {p + r: sense for p in prefixes
                for r, sense in COUNTER_TOLERATED.get(counter, {}).get(key, {}).items()}
        flag.update(COUNTER_OTHER_SENSE.get(compound, {}))
        fallback, sense = None, {}
        if counter == "分":
            what, why = minute_sense(text, start, end, english)
            sense = {"sense": what, "senseFrom": why}
            if compound == "十分" and what == "other":         # 十分 the adjective, 'enough'
                flag = {r: f"a minutes reading, but {why}" for r in expected}
                expected = [ENOUGH]
            elif compound == "十分" and what == "unknown":
                flag = {ENOUGH: f"'enough' (十分 じゅうぶん); {why}",
                        **{r: f"'ten minutes'; {why}" for r in expected}}
                expected = []
            elif compound == "十分" and what == "ambiguous":
                flag[ENOUGH] = f"'enough' (十分 じゅうぶん): {why}"
            elif what in ("other", "unknown"):
                fallback = f"{why}: 分 may be ぶ (a tenth, 五分 ごぶ) or ぶん (a share), not minutes"
        records.append({"compound": compound, "counter": counter, "number": value,
                        "expected": expected, **sense,
                        **judge_occurrence(text, reading, tokens, start, end, expected, flag, fallback)})
    return records


def english_of(meanings):
    """A headword's or passage's English meanings as one string, or None."""
    en = (meanings or {}).get("en")
    return "; ".join(en) if isinstance(en, list) else en or None


def fields_of(resources):
    """Every field the 何 and counter tables read: (path, id, field, text, reading, tokens, english).
    english is exEN for a sentence, and the meanings for a headword or a passage."""
    for path in sorted(glob.glob(f"{resources}/n[1-5].json")):
        for entry in json.load(open(path, encoding="utf-8")):
            yield (path, entry["id"], "surface", entry["surface"], entry["kana"], None,
                   english_of(entry.get("meanings")))
            if entry.get("exJP") and entry.get("exKana"):
                yield (path, entry["id"], "exJP", entry["exJP"], entry["exKana"], entry.get("exTokens"),
                       entry.get("exEN") or None)
    passages = os.path.join(resources, "passages.json")
    if os.path.exists(passages):
        for p in json.load(open(passages, encoding="utf-8")):
            yield passages, p["id"], "display", p["display"], p["kana"], None, english_of(p.get("meanings"))


def dictation_excluded(resources):
    """The ids withheld from dictation, from the tree's own dictation-exclusions.json — or None when
    the tree has none (a calibration tree written from git), so no hit there claims to know."""
    path = os.path.join(resources, "dictation-exclusions.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return {e["id"] for e in json.load(f)["excluded"]}


def sweep(resources, judge):
    """Every field handed to `judge`. A field is counted after its judge has run on it, so a field
    skipped before the judge is not counted; a judge that skips a field from inside is, and only
    calibration (h), the planted tree, can see that. A hit carries its English and whether it is in
    the dictation pool: an example sentence (the pool is drawn from those alone) whose id
    dictation-exclusions.json does not withhold."""
    population = {"exJP": 0, "surface": 0, "display": 0}
    inspected, hits = [], []
    excluded = dictation_excluded(resources)
    for path, entry_id, field, text, reading, tokens, english in fields_of(resources):
        records = judge(text, reading, tokens, english)
        population[field] += 1
        for record in records:
            where = {"id": entry_id, "file": display_path(path), "field": field}
            inspected.append({**where, **record})
            if record["verdict"] in ("mismatch", "flag-only"):
                pool = None if excluded is None else field == "exJP" and entry_id not in excluded
                hits.append({**where, "sentence": text, "reading": reading, "english": english,
                             "inDictationPool": pool, **record})
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

def tree_at(ref, dest, extra=()):
    """The corpus as it was at `ref`, written into `dest`, with any `extra` resource files (the
    dictation-exclusions.json that (l) reads). A ref that does not resolve (a shallow clone) raises:
    a calibration that cannot see its tree must fail, not skip."""
    for name in CORPUS_FILES + tuple(extra):
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
    # Added in the fix round: until then no check reached the 月 7 and 9 rows, MONTHS beyond 4, or
    # the accepted side of 時 4, 時間 9 and 字 4, so dropping or inverting any of them passed.
    ("七月: しちがつ is right, なながつ is a mismatch (月 tolerates no なな)", "七月七月",
     "しちがつなながつ", [["七", "しち"], ["月", "がつ"], ["七", "なな"], ["月", "がつ"]],
     [("七月", "ok", "ok", "ok"), ("七月", "mismatch", "mismatch", "mismatch")]),
    ("九月: くがつ is right, きゅうがつ is a mismatch", "九月九月", "くがつきゅうがつ",
     [["九", "く"], ["月", "がつ"], ["九", "きゅう"], ["月", "がつ"]],
     [("九月", "ok", "ok", "ok"), ("九月", "mismatch", "mismatch", "mismatch")]),
    ("四時 よじ is right", "四時", "よじ", [["四", "よ"], ["時", "じ"]], [("四時", "ok", "ok", "ok")]),
    ("九時間 くじかん is right", "九時間", "くじかん", [["九", "く"], ["時間", "じかん"]],
     [("九時間", "ok", "ok", "ok")]),
    ("四字: よじ is right, よんじ is a mismatch", "四字四字", "よじよんじ",
     [["四", "よ"], ["字", "じ"], ["四", "よん"], ["字", "じ"]],
     [("四字", "ok", "ok", "ok"), ("四字", "mismatch", "mismatch", "mismatch")]),
    # §I addendum 2. An optional sixth element is the English (exEN) the field is judged with.
    ("十分 'ten minutes' by its English: じゅっぷん and じっぷん ok, the 'enough' reading じゅうぶん a mismatch",
     "十分十分十分", "じゅっぷんじっぷんじゅうぶん",
     [["十分", "じゅっぷん"], ["十分", "じっぷん"], ["十分", "じゅうぶん"]],
     [("十分", "ok", "ok", "ok"), ("十分", "ok", "ok", "ok"), ("十分", "mismatch", "mismatch", "mismatch")],
     "It takes ten minutes."),
    ("十分 'enough': English with no minutes, so じゅうぶん is ok and a minutes reading flag-only",
     "十分十分", "じゅうぶんじっぷん", [["十分", "じゅうぶん"], ["十分", "じっぷん"]],
     [("十分", "ok", "ok", "ok"), ("十分", "flag-only", "flag-only", "flag-only")],
     "There is plenty of time."),
    ("十分 with English naming minutes and 'enough' both: じゅうぶん flag-only, じっぷん ok",
     "十分で十分だ", "じっぷんでじゅうぶんだ",
     [["十分", "じっぷん"], ["で", "で"], ["十分", "じゅうぶん"], ["だ", "だ"]],
     [("十分", "ok", "ok", "ok"), ("十分", "flag-only", "flag-only", "flag-only")],
     "Ten minutes is enough."),
    ("十分 with no English: じゅうぶん and じっぷん flag-only, じゅうふん (wrong in both senses) a mismatch",
     "十分十分十分", "じゅうぶんじっぷんじゅうふん",
     [["十分", "じゅうぶん"], ["十分", "じっぷん"], ["十分", "じゅうふん"]],
     [("十分", "flag-only", "flag-only", "flag-only"), ("十分", "flag-only", "flag-only", "flag-only"),
      ("十分", "mismatch", "mismatch", "mismatch")]),
    ("分 whose English names no minutes: ごふん ok, 五分 ごぶ 'even' flag-only, never a mismatch",
     "五分、五分", "ごふんごぶ", [["五分", "ごふん"], ["、", "、"], ["五分", "ごぶ"]],
     [("五分", "ok", "ok", "ok"), ("五分", "flag-only", "flag-only", "flag-only")],
     "The odds are even."),
    ("分's sense from the text: 九時十分 and 十分間 are minutes, whatever the English says",
     "九時十分、十分間", "くじじゅうぶんじゅうぶんかん",
     [["九時", "くじ"], ["十分", "じゅうぶん"], ["、", "、"], ["十分間", "じゅうぶんかん"]],
     [("九時", "ok", "ok", "ok"), ("十分", "mismatch", "mismatch", "mismatch"),
      ("十分", "mismatch", "mismatch", "mismatch")],
     "It is quite enough."),
    ("a clock time in the English names minutes: 'at 9:10', 十分 じゅうぶん is a mismatch",
     "十分に出ます", "じゅうぶんにでます", [["十分", "じゅうぶん"], ["に", "に"], ["出", "で"], ["ます", "ます"]],
     [("十分", "mismatch", "mismatch", "mismatch")], "It leaves at 9:10."),
    ("a fraction is absorbed (三分の一, 十分の一); 三分の休憩 is still judged",
     "三分の一と十分の一と三分の休憩", "さんぶんのいちとじゅうぶんのいちとさんぷんのきゅうけい", None,
     [("三分", "absorbed", None, None), ("十分", "absorbed", None, None), ("三分", "ok", None, "ok")],
     "a three-minute break"),
    ("lexemes are absorbed: 八百屋 八百長 八千代 一回り 五分五分 九分九厘 七分袖 八分目 一個人",
     "八百屋、八百長、八千代、一回り、五分五分、九分九厘、七分袖、八分目、一個人", "", None,
     [("八百", "absorbed", None, None), ("八百", "absorbed", None, None), ("八千", "absorbed", None, None),
      ("一回", "absorbed", None, None), ("五分", "absorbed", None, None), ("五分", "absorbed", None, None),
      ("九分", "absorbed", None, None), ("七分", "absorbed", None, None), ("八分", "absorbed", None, None),
      ("一個", "absorbed", None, None)]),
    ("二十歳: はたち, にじゅっさい, にじっさい ok; にじゅうさい tolerated (flag-only)",
     "二十歳二十歳二十歳二十歳", "はたちにじゅっさいにじっさいにじゅうさい",
     [["二十歳", "はたち"], ["二十歳", "にじゅっさい"], ["二十歳", "にじっさい"], ["二十歳", "にじゅうさい"]],
     [("二十歳", "ok", "ok", "ok"), ("二十歳", "ok", "ok", "ok"), ("二十歳", "ok", "ok", "ok"),
      ("二十歳", "flag-only", "flag-only", "flag-only")]),
    ("a ten before 歳 read …じゅうさい is tolerated: 十歳 じゅうさい, 三十歳 さんじゅうさい flag-only",
     "十歳、三十歳、三十歳", "じゅうさいさんじゅうさいさんじゅっさい",
     [["十歳", "じゅうさい"], ["、", "、"], ["三十歳", "さんじゅうさい"], ["、", "、"], ["三十歳", "さんじゅっさい"]],
     [("十歳", "flag-only", "flag-only", "flag-only"), ("三十歳", "flag-only", "flag-only", "flag-only"),
      ("三十歳", "ok", "ok", "ok")]),
    ("三階: さんがい is right, さんかい is tolerated (flag-only)", "三階三階", "さんがいさんかい",
     [["三階", "さんがい"], ["三階", "さんかい"]],
     [("三階", "ok", "ok", "ok"), ("三階", "flag-only", "flag-only", "flag-only")]),
    ("a compound number is judged at its final unit: 三十分, 四十八本, 百十分",
     "三十分、三十分、四十八本、四十八本、百十分",
     "さんじゅっぷんさんじゅうぶんよんじゅうはっぽんよんじゅうはちほんひゃくじゅっぷん",
     [["三十分", "さんじゅっぷん"], ["、", "、"], ["三十分", "さんじゅうぶん"], ["、", "、"],
      ["四十八本", "よんじゅうはっぽん"], ["、", "、"], ["四十八本", "よんじゅうはちほん"], ["、", "、"],
      ["百十分", "ひゃくじゅっぷん"]],
     [("三十分", "ok", "ok", "ok"), ("三十分", "mismatch", "mismatch", "mismatch"),
      ("四十八本", "ok", "ok", "ok"), ("四十八本", "mismatch", "mismatch", "mismatch"),
      ("百十分", "ok", "ok", "ok")],
     "minutes"),
    ("千 and 百 inside a number: 一万三千 いちまんさんぜん ok, いちまんさんせん not; 二千三百 ok; 二三百 a range",
     "一万三千円、一万三千円、二千三百円、二三百円",
     "いちまんさんぜんえんいちまんさんせんえんにせんさんびゃくえんにさんびゃくえん",
     [["一万三千", "いちまんさんぜん"], ["円", "えん"], ["、", "、"], ["一万三千", "いちまんさんせん"],
      ["円", "えん"], ["、", "、"], ["二千三百", "にせんさんびゃく"], ["円", "えん"], ["、", "、"],
      ["二三百", "にさんびゃく"], ["円", "えん"]],
     [("一万三千", "ok", "ok", "ok"), ("一万三千", "mismatch", "mismatch", "mismatch"),
      ("二千三百", "ok", "ok", "ok"), ("二三百", "absorbed", None, None)]),
    ("digits: 30分 さんじゅっぷん and 8本 はっぽん ok; 100分 and 200本 end in 百, not enumerated",
     "30分、8本、100分、200本", "さんじゅっぷんはっぽんひゃっぷんにひゃっぽん",
     [["30分", "さんじゅっぷん"], ["、", "、"], ["8本", "はっぽん"], ["、", "、"], ["100分", "ひゃっぷん"],
      ["、", "、"], ["200本", "にひゃっぽん"]],
     [("30分", "ok", "ok", "ok"), ("8本", "ok", "ok", "ok")], "minutes"),
    ("never inspected: unlisted digits (二本 三冊 二回 三回 四杯 七匹 九点 五泊 二千 五百), 百本 千回 万歳, "
     "何分 何本 (the 何 table's), 一人 一番 一生 一緒",
     "二本、三冊、二回、三回、四杯、七匹、九点、五泊、二千、五百、百本、千回、万歳、何分、何本、一人、一番、一生、一緒",
     "", None, []),
    ("judged on their start: 一本気 いっぽんぎ, 一点張り いってんばり; 一杯 'full' いっぱい is the counter's reading",
     "一本気、一点張り、一杯", "いっぽんぎいってんばりいっぱい",
     [["一本気", "いっぽんぎ"], ["、", "、"], ["一点張り", "いってんばり"], ["、", "、"], ["一杯", "いっぱい"]],
     [("一本", "ok", "ok", "ok"), ("一点", "ok", "ok", "ok"), ("一杯", "ok", "ok", "ok")]),
    ("a regression in exKana alone is a mismatch for a sound-changing row: tokens いっけん, exKana いちけん",
     "一軒が", "いちけんが", [["一", "いっ"], ["軒", "けん"], ["が", "が"]],
     [("一軒", "mismatch", "ok", "mismatch")]),
    ("a regression in the tokens alone is a mismatch for a sound-changing row: tokens いちけん, exKana いっけん",
     "一軒が", "いっけんが", [["一", "いち"], ["軒", "けん"], ["が", "が"]],
     [("一軒", "mismatch", "mismatch", "ok")]),
)

# Every row of the sound-changing table, written out by hand: (compound, its standard reading(s),
# the reading without the sound change — "" where that reading is tolerated and checked above).
# Never derived from COUNTER_FINAL: a check computed from the table it checks passes any table.
# Each is judged alone, one token, with English that names minutes.
SOUND_CHANGE_ROWS = {
    "分": (("一分", "いっぷん", "いちふん"), ("二分", "にふん", "にぷん"), ("三分", "さんぷん", "さんふん"),
          ("四分", "よんぷん", "よんふん"), ("五分", "ごふん", "ごぶん"), ("六分", "ろっぷん", "ろくふん"),
          ("七分", "ななふん", "ななぷん"), ("八分", "はっぷん|はちふん", "はちぷん"),
          ("九分", "きゅうふん", "きゅうぷん"), ("十分", "じゅっぷん|じっぷん", "じゅうふん")),
    "軒": (("一軒", "いっけん", "いちけん"), ("三軒", "さんげん", "さんけん"), ("六軒", "ろっけん", "ろくけん"),
          ("八軒", "はっけん", "はちけん"), ("十軒", "じゅっけん|じっけん", "じゅうけん")),
    "階": (("一階", "いっかい", "いちかい"), ("三階", "さんがい", ""), ("六階", "ろっかい", "ろくかい"),
          ("八階", "はっかい|はちかい", "はちがい"), ("十階", "じゅっかい|じっかい", "じゅうかい")),
    "回": (("一回", "いっかい", "いちかい"), ("六回", "ろっかい", "ろくかい"),
          ("八回", "はっかい|はちかい", "はちがい"), ("十回", "じゅっかい|じっかい", "じゅうかい")),
    "歳": (("一歳", "いっさい", "いちさい"), ("八歳", "はっさい", "はちさい"), ("十歳", "じゅっさい|じっさい", "")),
    "本": (("一本", "いっぽん", "いちほん"), ("三本", "さんぼん", "さんほん"), ("六本", "ろっぽん", "ろくほん"),
          ("八本", "はっぽん", "はちほん"), ("十本", "じゅっぽん|じっぽん", "じゅうほん")),
    "杯": (("一杯", "いっぱい", "いちはい"), ("三杯", "さんばい", "さんはい"), ("六杯", "ろっぱい", "ろくはい"),
          ("八杯", "はっぱい", "はちはい"), ("十杯", "じゅっぱい|じっぱい", "じゅうはい")),
    "匹": (("一匹", "いっぴき", "いちひき"), ("三匹", "さんびき", "さんひき"), ("六匹", "ろっぴき", "ろくひき"),
          ("八匹", "はっぴき", "はちひき"), ("十匹", "じゅっぴき|じっぴき", "じゅうひき")),
    "個": (("一個", "いっこ", "いちこ"), ("六個", "ろっこ", "ろくこ"), ("八個", "はっこ", "はちこ"),
          ("十個", "じゅっこ|じっこ", "じゅうこ")),
    "冊": (("一冊", "いっさつ", "いちさつ"), ("八冊", "はっさつ", "はちさつ"), ("十冊", "じゅっさつ|じっさつ", "じゅうさつ")),
    "点": (("一点", "いってん", "いちてん"), ("六点", "ろってん", "ろくてん"), ("八点", "はってん", "はちてん"),
          ("十点", "じゅってん|じってん", "じゅうてん")),
    "泊": (("一泊", "いっぱく", "いちはく"), ("三泊", "さんぱく", "さんはく"), ("六泊", "ろっぱく", "ろくはく"),
          ("八泊", "はっぱく", "はちはく"), ("十泊", "じゅっぱく|じっぱく", "じゅうはく")),
    "千": (("三千", "さんぜん", "さんせん"), ("八千", "はっせん", "はちせん")),
    "百": (("三百", "さんびゃく", "さんひゃく"), ("六百", "ろっぴゃく", "ろくひゃく"), ("八百", "はっぴゃく", "はちひゃく")),
}

# (h) the planted tree. Each plant is a reading every table here must call a mismatch, under an id
# no entry uses. A sentence plant is (table, level, tokens): exJP is the token surfaces joined, and
# exKana the readings joined with punctuation dropped, so exKana lines up with the tokens. Every
# n-file gets one sentence plant per table; the 何 and counter tables, which also read headwords and
# passages, get one of each. A plant holds nothing another table reads — no plant may be flagged by
# a table other than its own. The counter plants carry 七月 and 九月, which the corpus does not.
PLANT_PREFIX = "plant-"
PLANTED_SENTENCES = (
    ("lexicalised", "n1", [["二", "に"], ["人", "にん"], ["で", "で"], ["行き", "いき"], ["ます", "ます"], ["。", "。"]]),
    ("lexicalised", "n2", [["三", "さん"], ["日", "にち"], ["かかり", "かかり"], ["ます", "ます"], ["。", "。"]]),
    ("lexicalised", "n3", [["四", "よん"], ["つ", "つ"], ["あり", "あり"], ["ます", "ます"], ["。", "。"]]),
    ("lexicalised", "n4", [["八", "はち"], ["日", "にち"], ["に", "に"], ["来", "き"], ["ます", "ます"], ["。", "。"]]),
    ("lexicalised", "n5", [["一", "いち"], ["人", "にん"], ["で", "で"], ["食べ", "たべ"], ["ます", "ます"], ["。", "。"]]),
    ("interrogative", "n1", [["何時", "なんどき"], ["です", "です"], ["か", "か"], ["。", "。"]]),
    ("interrogative", "n2", [["何", "なに"], ["人", "にん"], ["い", "い"], ["ます", "ます"], ["か", "か"], ["。", "。"]]),
    ("interrogative", "n3", [["何", "なん"], ["本", "ほん"], ["あり", "あり"], ["ます", "ます"], ["か", "か"], ["。", "。"]]),
    ("interrogative", "n4", [["何", "なん"], ["杯", "はい"], ["飲み", "のみ"], ["ます", "ます"], ["か", "か"], ["。", "。"]]),
    ("interrogative", "n5", [["何", "なん"], ["匹", "ひき"], ["い", "い"], ["ます", "ます"], ["か", "か"], ["。", "。"]]),
    ("counters", "n1", [["九", "きゅう"], ["月", "がつ"], ["に", "に"], ["入学", "にゅうがく"], ["し", "し"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n2", [["七", "なな"], ["月", "がつ"], ["に", "に"], ["旅行", "りょこう"], ["し", "し"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n3", [["九", "きゅう"], ["時間", "じかん"], ["働き", "はたらき"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n4", [["四", "よん"], ["字", "じ"], ["で", "で"], ["書き", "かき"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n5", [["四", "よん"], ["月", "がつ"], ["に", "に"], ["始まり", "はじまり"], ["ます", "ます"], ["。", "。"]]),
    # §I addendum 2: a second counter plant in every n-file, each a sound-changing row. A 分 plant
    # carries English that names minutes; without it its sense is undecided and it is no mismatch.
    ("counters", "n1", [["三", "さん"], ["分", "ふん"], ["待ち", "まち"], ["まし", "まし"], ["た", "た"], ["。", "。"]],
     "I waited three minutes."),
    ("counters", "n2", [["一", "いち"], ["軒", "けん"], ["あり", "あり"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n3", [["八", "はち"], ["本", "ほん"], ["買い", "かい"], ["ます", "ます"], ["。", "。"]]),
    ("counters", "n4", [["三千", "さんせん"], ["円", "えん"], ["です", "です"], ["。", "。"]]),
    ("counters", "n5", [["六", "ろく"], ["百", "ひゃく"], ["円", "えん"], ["です", "です"], ["。", "。"]]),
)
# (table, level, surface, kana[, English meaning]); (table, display, kana[, English]). The 分 plants'
# English is what proves a headword's meanings and a passage's meanings reach 分's sense.
PLANTED_HEADWORDS = (("interrogative", "n1", "何回", "なにかい"), ("counters", "n1", "九時", "きゅうじ"),
                     ("counters", "n2", "三分", "さんふん", "three minutes"))
PLANTED_PASSAGES = (("interrogative", "何歳ですか。", "なにさいですか"),
                    ("counters", "七月に行きます。", "なながつにいきます"),
                    ("counters", "駅から十分歩きました。", "えきからじゅうぶんあるきました",
                     "I walked ten minutes from the station."))
PLANT_FILLER = {"surface": "テスト", "kana": "てすと"}   # a sentence plant's own headword: no counter


def plant_tree(dest):
    """The working tree's corpus copied into `dest` with the plants added. Returns
    {table: {(id, field)}}, the plants each table must flag, or raises when an id is taken."""
    for name in CORPUS_FILES:
        shutil.copy(os.path.join(RESOURCES, name), dest)
    want = {"lexicalised": set(), "interrogative": set(), "counters": set()}
    for level in ("n1", "n2", "n3", "n4", "n5"):
        path = os.path.join(dest, f"{level}.json")
        with open(path, encoding="utf-8") as f:
            entries = json.load(f)
        if any(e["id"].startswith(PLANT_PREFIX) for e in entries):
            raise RuntimeError(f"{level}.json already has an id beginning {PLANT_PREFIX!r}")
        for k, (table, lvl, tokens, *english) in enumerate(PLANTED_SENTENCES):
            if lvl == level:
                eid = f"{PLANT_PREFIX}{table}-{level}-{k}"
                entries.append({"id": eid, **PLANT_FILLER, "exJP": "".join(s for s, _ in tokens),
                                "exKana": "".join(r for _, r in tokens).translate(KANA_DROPPED),
                                "exTokens": tokens, **({"exEN": english[0]} if english else {})})
                want[table].add((eid, "exJP"))
        for k, (table, lvl, surface, kana, *english) in enumerate(PLANTED_HEADWORDS):
            if lvl == level:
                eid = f"{PLANT_PREFIX}{table}-headword-{k}"
                entries.append({"id": eid, "surface": surface, "kana": kana,
                                **({"meanings": {"en": english}} if english else {})})
                want[table].add((eid, "surface"))
        with open(path, "w", encoding="utf-8") as f:
            json.dump(entries, f, ensure_ascii=False)
    path = os.path.join(dest, "passages.json")
    with open(path, encoding="utf-8") as f:
        passages = json.load(f)
    for k, (table, display, kana, *english) in enumerate(PLANTED_PASSAGES):
        eid = f"{PLANT_PREFIX}{table}-passage-{k}"
        passages.append({"id": eid, "display": display, "kana": kana,
                         **({"meanings": {"en": english[0]}} if english else {})})
        want[table].add((eid, "display"))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(passages, f, ensure_ascii=False)
    return want

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
        counted, planted = os.path.join(tmp, "counter-ref"), os.path.join(tmp, "planted")
        sounded, shipped = os.path.join(tmp, "sound-change-ref"), os.path.join(tmp, "shipped")
        for d in (old, small, counted, planted, sounded, shipped):
            os.mkdir(d)
        try:
            tree_at(CALIBRATION_REF, old)
            tree_at(COUNTER_CALIBRATION_REF, counted)
            tree_at(SOUND_CHANGE_CALIBRATION_REF, sounded, extra=("dictation-exclusions.json",))
            tree_at(SHIPPED_REF, shipped)
            plants = plant_tree(planted)
        except RuntimeError as e:
            return False, [f"[FAIL] cannot read a calibration tree: {e}"]
        shutil.copy(os.path.join(RESOURCES, "n5.json"), small)
        old_code, old_run = run_cli(tmp, "old", "--resources", old)
        head_code, head_run = run_cli(tmp, "head")
        small_code, small_run = run_cli(tmp, "small", "--resources", small)
        counted_code, counted_run = run_cli(tmp, "counted", "--resources", counted)
        planted_code, planted_run = run_cli(tmp, "planted", "--resources", planted)
        sounded_code, sounded_run = run_cli(tmp, "sounded", "--resources", sounded)
        shipped_code, shipped_run = run_cli(tmp, "shipped", "--resources", shipped)

    if (old_run is None or head_run is None or small_run is None or counted_run is None
            or planted_run is None or sounded_run is None or shipped_run is None):
        return False, [f"[FAIL] a calibration run wrote no output (exit codes: {CALIBRATION_REF} "
                       f"{old_code}, working tree {head_code}, n5-only {small_code}, "
                       f"{COUNTER_CALIBRATION_REF} {counted_code}, planted {planted_code}, "
                       f"{SOUND_CHANGE_CALIBRATION_REF} {sounded_code}, {SHIPPED_REF} {shipped_code})"]
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

    # (i) §I addendum 2's sentences, on the tree its review read and on the corpus 1.35 shipped: the
    # same shape as (f).
    for ref, run, what in ((SOUND_CHANGE_CALIBRATION_REF, sounded_run, "as its review read it"),
                           (SHIPPED_REF, shipped_run, "the corpus 1.35 shipped")):
        got = {(h["id"], h["field"], h["compound"], h["verdict"], h["verdictTokens"], h["verdictKana"],
                h["taught"], h.get("kanaAlignment") == h["alignment"])
               for h in run["counters"]["hits"]}
        want = {(i, "exJP", c, v, v, v, t, True) for i, c, v, t in KNOWN_SOUND_CHANGE_HITS}
        others = sorted(f"{h[0]} {h[2]} {h[3]} {h[6]}" for h in got - want)
        check(f"(i) {ref} ({what}): the counter table flags the {len(want)} known "
              f"sound-change occurrences in both exTokens and exKana "
              f"({sum(v == 'mismatch' for _, _, v, _ in KNOWN_SOUND_CHANGE_HITS)} mismatch, "
              f"{sum(v == 'flag-only' for _, _, v, _ in KNOWN_SOUND_CHANGE_HITS)} flag-only)",
              want <= got,
              f"missing: {sorted(f'{w[0]} {w[2]} {w[3]} {w[6]}' for w in want - got) or 'none'}; "
              f"also flagged (or flagged differently): {others or 'none'}")

    # (j) and (k): inspected on the working tree and not flagged — "not flagged" because each was
    # looked at and passed (or recorded as a lexeme), not because nothing was looked at.
    for label, known in (("(j) the working tree passes 十分 read for its sense: n1-b1516 じっぷん "
                          "'ten minutes' and n4-g178 じゅうぶん 'enough', each in its sentence and "
                          "its headword", KNOWN_SOUND_CHANGE_PASSES),
                         ("(k) the working tree records its lexemes and passes 二十歳 はたち: "
                          "n5-b364 八百屋, n1-b2056 一回り, n5-b331", KNOWN_LEXEMES)):
        ids = {k[0] for k in known}
        seen = sorted(((r["id"], r["field"], r["compound"], r["verdict"], r.get("taught"))
                       for r in head_run["counters"]["inspected"] if r["id"] in ids), key=str)
        flagged = sorted(f"{h['id']} {h['field']} {h['compound']}" for h in head_run["counters"]["hits"]
                         if h["id"] in ids)
        check(label, seen == sorted(known, key=str) and not flagged,
              f"inspected: {seen}; hits: {flagged or 'none'}")

    for label, run, known in ((f"(l) {SOUND_CHANGE_CALIBRATION_REF}, with its own dictation-exclusions."
                               f"json: the hits carry their English and say which are in the dictation "
                               f"pool (n1-b439, n3-b781, n3-b020, n4-g171 in; n5-b334 withheld), as "
                               f"PLAN-V1.36 §I states", sounded_run, KNOWN_POOL),
                              ("(l) the working tree: the three of those still hits there carry their "
                               "English and their pool membership (n3-b020, n4-g171 in; n5-b334 withheld)",
                               head_run, KNOWN_POOL_HEAD)):
        pool = sorted((h["id"], h["inDictationPool"], bool(h.get("english")))
                      for h in run["counters"]["hits"] if h["id"] in dict(known))
        check(label, pool == sorted((i, p, True) for i, p in known), f"hits: {pool}")

    # (m) every correction §I addendum 2 made, inspected on the working tree and passed in both fields
    # with exKana lined up — and none of those ids flagged by the counter table.
    ids = {i for i, _, _ in KNOWN_CORRECTED}
    seen = sorted((r["id"], r["field"], r["compound"], r["verdict"], r.get("verdictTokens"),
                   r.get("verdictKana"), r.get("taught"), r.get("taughtKana"),
                   r.get("kanaAlignment") == r.get("alignment"))
                  for r in head_run["counters"]["inspected"] if r["id"] in ids)
    want = sorted((i, "exJP", c, "ok", "ok", "ok", t, t, True) for i, c, t in KNOWN_CORRECTED)
    flagged = sorted(f"{h['id']} {h['field']} {h['compound']} {h['verdict']} {h['taught']}"
                     for h in head_run["counters"]["hits"] if h["id"] in ids)
    check(f"(m) the working tree passes the {len(want)} sentences §I addendum 2 corrected, each "
          f"inspected and taught its corrected reading in exTokens and exKana",
          seen == want and not flagged,
          f"not as corrected: {[s for s in seen if s not in want] or 'none'}; "
          f"not inspected: {[w[0] for w in want if w not in seen] or 'none'}; hits: {flagged or 'none'}")

    # (h) every plant flagged by its own table — a mismatch, on both fields where it has tokens —
    # and none by another table. A table that judges fewer files, ids or kinds of field than it
    # counts misses a plant here, whatever its population says.
    for table, hits in (("lexicalised", planted_run["hits"]),
                        ("interrogative", planted_run["interrogative"]["hits"]),
                        ("counters", planted_run["counters"]["hits"])):
        mine = {(h["id"], h["field"]) for h in hits if h["id"].startswith(PLANT_PREFIX)}
        bad = sorted(f"{h['id']} {h['field']} {h.get('verdict')} tokens {h.get('verdictTokens')} "
                     f"exKana {h.get('verdictKana')}" for h in hits
                     if h["id"].startswith(PLANT_PREFIX) and table != "lexicalised"
                     and (h["verdict"], h["verdictKana"],
                          h["verdictTokens"] if h["field"] == "exJP" else "mismatch")
                     != ("mismatch", "mismatch", "mismatch"))
        missed, extra = sorted(plants[table] - mine), sorted(mine - plants[table])
        check(f"(h) planted tree: the {table} table flags its {len(plants[table])} plants (every "
              f"n-file{', headwords and passages' if table != 'lexicalised' else ''}) and no other",
              planted_code == 0 and not missed and not extra and not bad,
              f"exit {planted_code}; missed {missed or 'none'}; another table's {extra or 'none'}; "
              f"not a mismatch in both fields: {bad or 'none'}")

    for what, text, reading, tokens, want in LOGIC_CHECKS:
        got = [r["verdict"] for r in judge_field(text, reading, tokens)]
        check(f"logic: {what}", got == want, f"{text} {reading}: {got}")
    for what, text, reading, tokens, want, *english in COUNTER_LOGIC_CHECKS:
        got = [(r["compound"], r["verdict"], r.get("verdictTokens"), r.get("verdictKana"))
               for r in judge_counter_field(text, reading, tokens, *english)]
        check(f"logic: {what}", got == want, f"{text}: {got}")
    for counter, rows in SOUND_CHANGE_ROWS.items():
        want, got = [], []
        for compound, accepted, unchanged in rows:
            for reading, verdict in ([(r, "ok") for r in accepted.split("|")]
                                     + ([(unchanged, "mismatch")] if unchanged else [])):
                want.append((compound, reading, verdict, verdict, verdict))
                got += [(r["compound"], reading, r["verdict"], r.get("verdictTokens"), r.get("verdictKana"))
                        for r in judge_counter_field(compound, reading, [[compound, reading]], "minutes")]
        check(f"logic: {counter} — every row's standard reading ok, the reading without its sound "
              f"change a mismatch ({len(rows)} rows)", got == want,
              f"{len(got)} judged; wrong: "
              f"{'; '.join(f'{g[0]} {g[1]} {g[2]}' for g in got if g not in want) or 'none'}; missing: "
              f"{'; '.join(f'{w[0]} {w[1]}' for w in want if w not in got) or 'none'}")
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
    # "read", not "judged": the count is taken after the judge has run on a field, and cannot see
    # a judge that skips one from inside. --calibrate's planted tree (h) is what shows each kind is
    # judged.
    print(f"population   : {population['exJP']} example sentences (exTokens and exKana), "
          f"{population['surface']} headwords, {population['display']} passages read by this table")
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
        if h.get("english") or h.get("inDictationPool") is not None:
            pool = {True: "IN the dictation pool", False: "not in the dictation pool",
                    None: "dictation pool unknown (no dictation-exclusions.json in this tree)"}
            print(f"      {h.get('english') or '(no English)'} — {pool[h.get('inDictationPool')]}"
                  + (f"; 分 read as {h['sense']} ({h['senseFrom']})" if h.get("sense") else ""))


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
    print_table("counters: month 月, hour 時, duration 時間, 字; the sound-changing 分 軒 階 回 歳 本 杯 匹 "
                "個 冊 点 泊, and 千 百", c_population,
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
                            "places": PLACES,
                            "tolerated": {c: {str(d): v for d, v in t.items()}
                                          for c, t in COUNTER_TOLERATED.items()},
                            "otherSense": COUNTER_OTHER_SENSE,
                            "whole": {c: list(r) for c, r in COUNTER_WHOLE.items()},
                            "absorbers": list(COUNTER_ABSORBERS),
                            "notTheCounter": {c: list(f) for c, f in NOT_THE_COUNTER.items()},
                            "minuteSense": {"minutes": MINUTES_EN.pattern, "enough": ENOUGH_EN.pattern},
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
