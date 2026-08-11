# v1.21 — the corpus starts earning its keep

Five releases went into building 6,737 example sentences. Two features consume them: Sentence
mode types one, and furigana annotates one. Everything else the data makes possible is still
sitting unused, and one of those things is a skill the app cannot currently teach at all.

So this release adds no new content. It spends what is already there.

## §A Dictation — hear it, type it

The app is entirely visual. A learner can read Japanese and type Japanese and never once find
out whether they can *hear* it. `SpeechKit` already speaks offline `ja-JP` and degrades
silently when no voice is installed; `exKana` is already the exact string a dictation answer
must match; `KanaInputMatcher` already grades it. The mode is mostly wiring.

- A sixth `GameMode`, `.dictation`. The sentence is SPOKEN, not shown. The learner types what
  they heard; the target is `exKana`, the same as Sentence mode.
- Replay is free and unlimited — this trains listening, not memory. Count replays and show
  them in the results, because a run that needed twelve replays and one that needed none are
  different outcomes and the score alone hides that.
- Reveal shows `exJP` with furigana, which is the moment furigana earns the most.
- **Gate on voice availability, not on hope.** `SpeechSynthesizer.isJapaneseAvailable` is
  false on a device with no Japanese voice installed, and today the read-aloud button just
  hides. A whole mode cannot hide silently: the menu entry must be visibly unavailable with
  the reason, or a learner picks it and gets a run of silence they cannot distinguish from a
  bug.
- Writes no SRS, for the reason Sentence mode does not: mistakes are counted across a whole
  sentence and would land on one word's card.

**The risk worth naming.** The synthesizer reads `exJP`, the kanji, and it may pronounce a
minority reading the way every other tool does — the exact failure that cost 225 entries. But
here it is bounded and checkable: `exKana` says what the sentence should sound like, and a
sentence whose spoken form cannot match its own `exKana` should not be offered for dictation.
There is no API that returns what AVSpeech *will* say, so this needs a sampled listening pass
before the mode ships, not a rule.

**MEASURED — and it did not need to be a sample.** The premise held: the marker API carries a
`.phoneme` mark but every Japanese voice emits only word markers with an empty phoneme, and
`NSSpeechSynthesizer.phonemes(from:)` is dead on macOS 26 (it returns empty for an ENGLISH
voice too — checking only Japanese would have produced a confident wrong conclusion). So the
reading was measured instead of read out, over all 6,723 sentences.

Kyoko is deterministic, and two texts that render to the same WAV bytes were converted to the
same phonemes — so byte-identity is PROOF of what she said. It is decisive but quiet: kanji
and kana can differ in phrasing while saying the same words, so it speaks for only 521
sentences. Within those, 494 match their `exKana` and **27 are proven to say something else**
(私 as わたし where the corpus says わたくし, 何 as なに, 風車 as ふうしゃ …). A second pass —
render every single-token reading variant, ask which the kanji audio is nearest — covers
everything, and against those 521 labelled sentences it scores **100% recall (27/27) and 0%
false positives (0/494)**.

That calibration is the part worth keeping. An earlier one used synthetic decoys (a reading
replaced by random kana) and put the false-positive rate at 4.7%, which made a working
instrument look like mostly noise. Random kana are a harder test than real alternative
readings; calibrating on the wrong population nearly threw away the right answer.

**1,003 sentences (14.9%) are withheld from dictation** — the flagged set, plus every sentence
using a word-reading pair proof showed is spoken differently, because a voice does not change
its mind between sentences. 5,720 remain, no level below 80%. They stay fully available in
Sentence mode, where the reading is shown rather than spoken and the disagreement never
reaches the learner. `scripts/check_dictation_readings.py`,
`docs/measurements/dictation-reading-mismatches.json`.

**Also measured, and it changed the design:** Kyoko reads a bare hiragana は as "ha" in some
parses, so speaking `exKana` — the obvious safe choice, since it IS the answer — would
mispronounce the topic particle in ~2,900 sentences. Dictation speaks `exJP` and lets her
parser resolve the particles, which is what puts the kanji readings in play in the first
place.

## §B Sentence mode should follow what the learner is studying

Today it draws from a level pool and ignores everything the learner has done. A saved word
list and a stack of due SRS cards both exist, and neither reaches Sentence mode.

- `makeSentence(fromList:)` — sentences for the words on a saved list, mirroring
  `startListGame`.
- `makeSentence(due:)` — sentences for words whose review is due, so the sentence run doubles
  as review reading even though it writes no SRS.
- Both must handle the pool being too small honestly: if a list has 20 words and 6 have
  typeable sentences, say six, do not silently pad from the level pool. The v1.15 empty-pool
  regression is the precedent — the menu explains rather than starting a hollow run.

## §C The kana decision, whichever way it goes

225 entries cannot carry an honest example. The list, the causes and both external opinions
are in `docs/measurements/entries-no-sentence-can-teach.json` and the v1.19 commits. Nothing
in this release depends on the answer, but the queue does not shrink on its own.

**DECIDED (2026-08-11).** Codex and Gemini were both asked again, and both said retire. Both
argued from the same premise: that a card asks "given this spelling, what reading?" and these
cards leave that underdetermined, so drilling them teaches over-application of a minority
reading. **That premise is false for this app**, which is why neither answer was taken. Every
mode PRINTS the reading beside the spelling — the word card renders `kanaReading`
unconditionally (assistance gates the romaji, not the kana), the conjugation drill prints the
dictionary reading, and dictation cannot draw these entries at all because it needs an example
sentence they do not have. A learner types a reading they can see; they are never asked to
choose one. Retiring 222 entries and every learner's progress on them, to fix a problem the
interface already prevents, is the more expensive mistake.

What the reviewers' critique DID earn is the shape of the fix. Codex: "a sentence could not
be generated is implementation history, not information useful to the learner." So the notes
say nothing about sentences. They say the thing measurement showed was actually missing:
**29 of the 98 sibling pairs ship byte-identical English glosses** — 鼠/ねず and 鼠/ねずみ are
two cards with the same kanji and the same definition, and nothing on either says which one an
ordinary sentence would use.

- **87 cards gain a reading note** (`Sources/VocabKit/Resources/reading-notes.json`), rendered
  under the gloss: "Usually read ねずみ — that reading has its own card."
- **129 do not, and the cut is the point.** A second note kind was built from the measurement
  file's `defaultReading` and thrown away: the field name promises "the everyday reading of
  this spelling" and holds whatever the pipeline's tokenizer produced. On the first six N5
  cards it was backwards three times — it would have printed "言う is usually read ゆう" on the
  very card v1.18 created by RETIRING 言う/ゆう as the colloquial form. Checking those claims
  against the corpus's own 6,737 reviewed sentences contradicted only one outright and had no
  evidence at all for 99 of 118, so "one contradiction" was not a pass. A note ships only when
  a sibling ENTRY attests the reading AND that sibling carries a reviewed sentence reading the
  spelling that way.
- **Three headwords resolved as data**, three different ways
  (`docs/measurements/v121-section-c-manifest.json`):
  - `ぺん` **retired**, `replacedBy` the N5 `ペン` that already ships with an example. Not an
    orthography to correct — a duplicate whose correct form was already in the app at an
    easier level. This is the case `retire` + `replacedBy` exists for.
  - `擽ぐったい → 擽ったい` and `引受る → 引き受ける`: `surface` corrections. `kana` does not
    move, so the SM-2 card keeps testing exactly the answer it was scheduled on — categorically
    unlike the kana edit both reviewers refused in v1.19. The guard now permits a
    manifest-declared surface change and refuses one where `surface` and `kana` move together.
  - `釣 → 釣り` was proposed by Codex and **not** taken: 釣 CAN be read つり, where 引受る cannot
    be read ひきうける. The bar for moving a frozen field is that the value is wrong, not that
    another is better.

**And the thing this section actually found.** Checking whether a retirement was safe showed
it was not: `resolves:` — the check that stops a retired entry counting toward work that no
longer exists — was added to `dueCards`/`dueCount` in v1.12 and wired into ONE of the five
places that count due cards. The app badge, the widget histogram, the reminder body and the
Ride Log forecast all still counted every stored card, so the two entries **v1.18 already
retired** have been inflating those numbers for every learner who studied them, permanently,
because a card whose entry is gone can never be reviewed away. `ReviewStore`'s own doc comment
describes this exact failure. All five call sites now filter, and a test holds each one.

## §D Maintenance the corpus work left behind

- ~~`check_translation_agreement.py` … the eight sentences it still flags are unreviewed.~~
  **Done.** All eight reviewed by three independent lenses plus an adversary, against a
  negative control that proved the panel fires (12/12 on deliberately-broken pairs). None
  changed: every one has a zero-subject Japanese sentence, so the two translations differ
  only inside the space the source leaves open — and the app shows one translation at a
  time, so the "disagreement" is never on screen together. Three of the eight are the
  checker's `\bmy\b` clause firing on a possessive. Record:
  `docs/measurements/translation-agreement-adjudication.json`.
- ~~The `i-adjective`/`adj-i` tag spelling is inconsistent (nine variants seen).~~
  **Done, and the plan had the number wrong**: three spellings across nine entries, not nine
  variants. It was also the smallest of six families with the same problem — `noun`/`Noun`
  against `n` alone accounts for 620 occurrences. All 42 spellings collapsed to a canonical
  26-tag vocabulary (`scripts/normalize_pos_tags.py`, 770 entries), and a data test now
  fails on any tag outside it — `check_vocab_diff.py` never looked at `pos` and still does
  not, so the test is the only thing holding this.
- 14 sentences have no `exKana` on purpose (12 contain digits, which Sudachi reads one digit
  at a time; 2 contain the katakana middle dot). They are display-only forever unless the
  reading is hand-written — and six of the twelve are unit words (キロ, グラム, メートル…) where
  writing it means committing to じゅっキロ over じっキロ, which is the contested-reading
  judgment that put 225 entries beyond teaching. **Now pinned by id in a test**, failing in
  both directions, so neither a fifteenth nor a thirteenth can appear unnoticed.
- **Added on measurement, not in the original plan:** `exKana` and `exTokens` were guarded by
  nothing. `check_vocab_diff.py` froze identity and made examples write-once, but its
  example set was `exJP`/`exEN`/`exZH` — so the string sentence mode grades typing against,
  and the answer a dictation prompt is marked against, could be silently rewritten. Both are
  now write-once, the manifest hole that switched off the append-only rule for a declared
  entry's other languages is closed, and `scripts/test_check_vocab_diff.py` proves each rule
  fires (and that the permitted changes still pass) instead of trusting the word "clean".

## Stop rule

Dictation does not ship unless: a sampled listening pass finds no sentence whose spoken form
contradicts its own `exKana`; the mode is visibly unavailable (not hidden) when no Japanese
voice is installed; `swift test` is green; and the Release launch crash gate passes on both
platforms. If the sampled pass finds a systematic mismatch, dictation ships restricted to the
sentences that passed — a smaller honest set, the same call made for `exKana` itself.
