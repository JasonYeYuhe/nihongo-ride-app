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
in this release depends on the answer, but the queue does not shrink on its own:

- If they keep their readings: mark them in the data so the UI can say "no example — this
  entry teaches the less common reading of 鼠", which is more honest than a blank.
- If any are retired: the retirement path exists and is tested (`--manifest` with `retire` +
  `replacedBy`, and the orphaned-card fix that stops a retired entry inflating the due badge).
- Three are not readings at all but invalid headword spellings — 擽ぐったい, 引受る, ぺん — and
  those are a straightforward data fix in any scenario.

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
