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
