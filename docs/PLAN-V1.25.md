# v1.25 — the sentence must read its own word

A card teaches a spelling and a reading. Its example sentence carries `exKana`, and `exKana` is
not decoration: it is the **literal typing target** the learner is graded against, and the
furigana printed over the sentence. For twenty-one entries the sentence reads the headword a way
its own card does not teach.

    n5-g021   card 何 / なに          「何を食べますか。」  types  なんをたべますか
    n3-b919   card 額 / ひたい        「…額の汗をぬぐう。」 types  …がくのあせ…
    n3-b017   card 御 / お           「御茶をどうぞ。」    types  ごちゃをどうぞ

`なんを` is not a possible reading of anything. 額/ひたい is glossed "forehead" and its sentence
types がく, which is an amount or a picture frame. In **eighteen of the twenty-one** the reading
the sentence uses is literally another entry's `kana` — the corpus contradicts itself, and can
therefore be asked about rather than argued about.

**Ten of the twenty-one are still offered in dictation**, where the learner neither sees the
spelling nor chooses the reading. The defence that "the card prints its reading beside the
spelling, so nobody is confused" is the argument v1.21 §C used to keep minority readings, and it
does not reach these ten. It does not reach 何 at all.

## Where this scope came from

Four independent lenses surveyed the codebase and corpus for v1.25 candidates, each required to
bring a measurement rather than an intuition; a judge then cut twenty candidates to five. Its
recommendation is followed here, with two departures recorded at the end — one of them a
verdict the judge got wrong on the Japanese, which is the reason this plan adjudicates per entry
instead of by rule.

## §A The gate, and the twenty-one it names

### The gate is the half that lasts, and it already exists

`ExampleSentenceTests.usesTheWord` has guarded "the sentence is about the right word" since
v1.19. It asks `jp.contains(surface)` — a substring test on the **written form that never
compares a reading**. That is why all twenty-one pass it today, and why they could ship.

Its reading-level counterpart is `readsItsHeadwordAsTaught`, already written and already green:
for every entry whose `exTokens` contain a token written exactly like the headword, the entry's
own `kana` must be among those tokens' readings, katakana folded through the same `KanaScript`
the typing matcher uses. Derived from the data, never a list of forms.

The twenty-one ship as `knownHeadwordReadingMismatch` — **named, not counted**, on the
`knownSharedExamples` model. A threshold would let a new offender in as an old one is fixed. A
companion test fails when the ratchet names an entry that no longer offends, so the list can
only shrink. Both directions are calibrated: dropping `n5-g021` reddens the gate, adding
`n5-hon` reddens the staleness check.

### The twenty-one are adjudicated one at a time, and the answer differs

Two outcomes are legitimate and the evidence decides which:

* **`exKana` is wrong; the sentence is fine.** 何 → なにを. 御茶 → おちゃ. 額 → ひたい. The
  sentence is natural Japanese and its transcription is simply not what it says.
* **The sentence is right; the card's minority reading cannot occur in it.** Then the sentence
  is **withdrawn** and the entry joins the 224-entry floor. Rewriting 「庭の芝生が所々枯れて…」
  to say しょしょ would author unnatural Japanese to satisfy a card, which is exactly what that
  floor exists to prevent.

There is a third answer and it must stay available: **the sentence is genuinely ambiguous** —
表を見る admits both おもて and ひょう — in which case the English gloss decides, or the sentence
goes.

Independent witnesses, none of them circular:

* eighteen of twenty-one name another entry's `kana`;
* the English gloss sides with the card in several (`n1-b039` 木綿/きわた is glossed "cotton
  plant" and its `exEN` says "cotton plant flowers", while `exKana` says もめん — cotton cloth);
* `check_dictation_readings` instrument 1 — byte-identical synthesised audio, which is proof of
  what the voice says rather than an inference — already disagrees with `exKana` for several.

A second opinion is taken per entry rather than per rule. It is evidence, not a verdict: the
judge that produced this scope classified `n1-b118` as "withdraw the sentence", and it is wrong.
床に就く is a fixed expression read とこにつく meaning to take to one's bed; the `exEN` says
"staying in bed"; ゆか is a floor. That entry is a `FIX_KANA`, in the opposite direction.

### Riding along, because they touch the same files

* **`reading-notes.json` is one note short of its own generator.** `gen_reading_notes.py` prints
  `notes: 65` today; the shipped resource holds 64. The rule was corrected in v1.22 §E and the
  file was never regenerated, and nothing compares the two. Regenerate, review the new note, and
  add a test that the resource equals what the generator emits.

* **Delete two credentials that could not have failed.** `STATE-2026-08-18.md`,
  `PLAN-V1.21.md` and `check_forces_reading.py` all record the dictation reading checker as
  scoring "100% recall / 0% false positives against 521 labelled sentences". The false-positive
  half is arithmetic. That population is *by definition* the sentences whose `exJP` audio is
  byte-identical to an `exKana` variant, so `own = dtw(x, x)`; the repo's own `dtw` over 200
  random L2-normalised matrices returns at most 8.9e-17 for a matrix against itself against a
  minimum of 0.445 for distinct pairs. `best < own` is unsatisfiable. **0/494 was guaranteed
  before a single clip was rendered**, and the figure has been cited as evidence for four
  releases — including in this session, approvingly, before it was checked.

  The recall half (27/27) stands: those are the proven positives and the instrument found them.
  Only the false-positive claim is vacuous, and only it is deleted.

## §B One predicate for the sentence/dictation results screen

v1.24 left this deliberately: "decide what replaces it rather than leaving a gap." The screen
now answers "what went wrong" three times, with three different predicates rendered together —
the `Struggled` tile, the review list, and the v1.24 chips. The review list is the worst of the
three: `GameSession.sentenceSession` wraps each sentence as a `VocabEntry` whose `surface` is the
whole sentence, so the list renders whole sentences in word-sized cells and VoiceOver announces
"Save 〈whole sentence〉".

Make the tile count what the chip row displays, re-scope or remove the sentence-shaped list, and
hold it with a check that **derives**: an accessibility string on a control that starts a run
either carries no digit-bearing interpolation or names the quantity the builder caps on. That
check must count what it inspected and fail below a known number, the way `ResolvesCallSiteTests`
does.

**Look at the screen at AX3 and AX5 before believing it.** It has never been seen at
accessibility sizes; v1.14 §C spilled tiles out of this exact panel; and the one device test
covering these chips was broken by the chips themselves in v1.24.

**This was attempted through the headless renderer and the attempt FAILED — recorded because it
nearly shipped as a passing gate.** `ImageRenderer` does not drive `@ScaledMetric`, which is
what `scaledSystemFont` is built on and therefore what nearly every size in this app is.
Injecting `dynamicTypeSize`, and then the legacy `sizeCategory`, produced AX3 and AX5 renders
that were **byte-identical to each other** (md5 `53bef237…` for both). The screen looked fine at
"AX5" because nothing had been made larger. `ScaledFont.swift` has said this since v1.7 Phase A
— "ImageRenderer ignores dynamicTypeSize, so only the default size is render-verifiable;
large-type layout is device-verified" — and the warning was nearly walked past.

The renders were deleted rather than kept as a partial check. A file named
`results-sentence-ax5.png` that cannot tell AX5 from AX3 is worse than no file: the next person
reads the name, not the caveat. **WAIVED by the owner for this release** (2026-08-21), after the failed render attempt was
reported. It is not closed and it is not quietly dropped: closing it needs a device or a
simulator with `xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`,
not a render. The layout risk it covers is real — v1.14 §C spilled tiles out of this exact panel
at AX5 — and v1.25 changed three labels and removed a list from it.

## §C Not in this release, and why

* **Re-deciding the 961 nearest-only dictation exclusions.** The criticism of the credential is
  right and is being recorded in §A, but the re-measurement is not this release. It may be
  undecidable with the instruments in the repo — instrument 1 only speaks where kanji and kana
  phrase identically, which is the easy case — its likely outcome REMOVES content, and §A
  changes its input: eleven of the twenty-one are already excluded, so any re-render must come
  after the corpus is right, not before.
* **The wider unattested-reading sweep.** Token readings unattested by any card for that
  spelling: 63 pairs / 295 tokens / 270 sentences. Most of it is correct Japanese — 二/ふた,
  日/か, 人/にん, 年/ねん, 時/じ. It is a triage queue, not a gate. A rule built on it would show
  a convincing block rate over a population that is mostly right, which is v1.24's mistake
  wearing new clothes.
* **Rewriting 私/わたくし (119 sentences), 明日/あす (95), 日本/にっぽん (52) where they are not
  the headword.** Register, not error. The corpus's own level signal refuses it: 私 ships both
  readings at N5 and 日本 ships both at N3, which is the "same level means no signal" rule
  v1.22 §E paid for. Their *own* cards' sentences are in scope; the other 266 are not.
* **The remaining entries with no example sentence.** Concluded on purpose across three
  releases; nothing new here.
* **釣 → 釣り.** Declined three times.
* **Pinning a TTS voice for the dictation exclusion list.** Declined in v1.24 §D; it would
  refuse a learner the enhanced voice they downloaded.

## Stop rule

Ships when:

* `swift test` is green, and every new test has been shown to fail — the gate by removing an id
  from the ratchet, the staleness check by adding one that no longer offends, and whatever §B
  adds by breaking the predicate it asserts.
* Every one of the twenty-one has a recorded verdict with its evidence, and the ratchet names
  exactly those still outstanding — no entry silently exempted.
* `check_vocab_diff` passes **with a manifest**: `exKana` and `exTokens` are write-once, so
  every edit and every withdrawal is declared, and the guard fails on anything the manifest did
  not predict as well as anything it promised that did not happen.
* `gen_sentence_kana`'s round-trip and alignment gates pass on every edited sentence — tokens
  must reconstruct `exJP` and `exKana` exactly.
* The pre-submission adversarial review has run, in isolated worktrees, and its blockers are
  fixed. It found the defect v1.24 was built around and then a defect in the fix; assume it will
  find something here too.
* `scripts/launch_gate.sh` passes on the archive **that was uploaded**, not one built beside it.


---

# What was decided, and by what evidence

## The twenty-one, resolved 13 / 8

**Fixed (13).** Five by byte-identical synthesised audio — instrument 1, proof of the phoneme
sequence rather than an inference — and in every one of the five the voice takes the CARD's
reading: 何 なに, 表 おもて, 御 お, 嘲笑う あざわらう, 弄る いじる. Ten more were classified
MEANING (the reading changes what the sentence says) **independently and identically by Codex
and Gemini 3.7 Flash**, with the English translation as a third, non-circular witness: 床 とこ,
縁 ふち, 洒落 しゃれ, 空 から, 仏 ほとけ, 方々 ほうぼう, 額 ひたい, 木綿 きわた, 弄る, 表.

The two models' partitions were identical — the same ten MEANING, the same eleven REGISTER —
which also resolved what an earlier pass had recorded as a split: 木綿 is not a split. Codex
hedged on the first, blunter question and answered MEANING on the sharper one.

**Kept (8), named in the ratchet with the reason.** 獣, 怒る, 大事, 消耗, 所々, 得る, 明日, 私 —
all in both models' REGISTER list. v1.21 §C has already decided a minority reading is not an
error; correcting these would overturn a recorded decision and author Japanese to satisfy a card.

## The axis question was missing a category, and the instrument covered for it

Both models put 何 (なん/なに), 御 (ご/お) and 嘲笑う in REGISTER, reasoning that the two readings
mean the same thing. Semantically that is right. But なんを is not a possible reading of anything,
御茶 is not ごちゃ, and あざけわらう is a blend of two verbs — these are not stylistic variants,
they are **not readings of that word in that position**. The question offered only MEANING and
REGISTER, so a wrong reading with an adjacent meaning had nowhere to go but REGISTER.

They were corrected anyway, because instrument 1 had already proved what the voice says. The
lesson is not that the models were weak; it is that **a question with the wrong categories will
be answered wrongly by anything honest**, and that having one instrument that can be asked
decisively is worth more than a third opinion.

## §B, decided by looking

The render is what settled it. A sentence run's results screen showed 「友達と映画を見ました。」
inside a 116pt word cell, wrapped over two lines, captioned "movie, film" — the gloss of 映画,
not of the sentence — with a star that saved 映画, a word the cell never named. Above it a tile
read "Words 4" for four SENTENCES, and "Struggled 1" sat five lines above "the words that
stopped you: 4".

Three numbers, two units, none of them labelled with the unit it counted.

Fixed with one predicate — `GameMode.lapsesAreWords` — which the tile and the list now share:

* the whole-sentence review list is **dropped** on sentence and dictation runs. Nothing replaces
  it because the chips already had: they name what went wrong per word, resolve to real entries,
  and are actionable. It was the same question answered worse.
* "Words" becomes "Sentences" where the queue holds sentences;
* "Struggled" becomes "Tough lines", so the sentence-level count and the word-level chips read
  as the different things they are.

The predicate is tested against what the session BUILDERS produce rather than against a list of
modes, and calibrated: making it `true` everywhere reddens.

---

# Shipped

Submitted 2026-08-23, macOS build 47 / iOS build 48, both platforms. 520 tests green;
`check_vocab_diff` clean under a 71-entry manifest; its own 18 probes behaved; no duplicate
source files; `launch_gate` passed on the binary that was actually uploaded.

| | v1.24 | v1.25 |
|---|---|---|
| tests | 518 | **520** |
| sentences corrected | — | **71**, all under one manifest |
| dictation pool | 5,720 | **5,762** |
| reading notes | 64 | **66** |
| new gates | 4 | **6**, each calibrated both ways |

## What actually happened to §A

The release set out to fix 21 sentences and a missing gate. It fixed 71, because each review
pass found the previous fix incomplete:

1. The plan's own layer-2 resolution rule was measured before building and both halves failed.
2. The first review found the gate matched a single token — 240 entries never inspected, 26
   offenders behind them, ten of them N5 counters and dates (四つ graded as よんつ).
3. The second review found the span gate still blind where the tokenizer splits across the
   headword boundary — 106 more entries, two of them misread.
4. It also found that correcting sentences by MERGING token spans had blinded the exclusion
   gate, because a merge deletes the very token a complaint names. Eight sentences had been
   released into dictation whose corpus reading disagrees with the measured audio.

The through-line is one sentence, and it is the thing to carry forward: **a gate validated by
what it CATCHES has not been validated.** Both gate versions were justified by their catch count
— 21, then 26 — and neither author measured the population the scan skipped. That is the
question that finds this class, and it is cheap: compute what the scan does not inspect, and
look at a sample of it.

## Open

* **Accessibility text sizes — WAIVED by the owner**, not closed. The headless renderer cannot
  verify them (`ImageRenderer` does not drive `@ScaledMetric`; AX3 and AX5 render byte-identical),
  and v1.25 changed three labels and removed a list from a panel that spilled tiles at AX5 in
  v1.14 §C. Closing it needs a device or `xcrun simctl ui <device> content_size …`.
* **The 961 dictation exclusions** whose complaint still matches the corpus. The criticism of
  their credential is recorded; the re-measurement is a release of its own, may be undecidable
  with the instruments in the repo, and its likely outcome removes content.
* **The eight sentences put back into exclusion**, plus fifteen records marked
  `stale-after-correction`. Their corpus readings are right; their audio has not been re-measured
  since. Instrument 1 is silent for all of them.
