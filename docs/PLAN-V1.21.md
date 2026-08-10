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

- `check_translation_agreement.py` now only compares subjects and day-part words; its number
  half was deleted after seven failed attempts. The eight sentences it still flags across the
  corpus are unreviewed.
- The `i-adjective`/`adj-i` tag spelling is inconsistent in the vocabulary data (nine variants
  seen). The test now matches loosely, but the data itself is untidy and the next thing to
  read it will hit the same wall.
- 14 sentences have no `exKana` on purpose (12 contain digits, which Sudachi reads one digit
  at a time; 2 contain the katakana middle dot). They are display-only forever unless the
  reading is hand-written.

## Stop rule

Dictation does not ship unless: a sampled listening pass finds no sentence whose spoken form
contradicts its own `exKana`; the mode is visibly unavailable (not hidden) when no Japanese
voice is installed; `swift test` is green; and the Release launch crash gate passes on both
platforms. If the sampled pass finds a systematic mismatch, dictation ships restricted to the
sentences that passed — a smaller honest set, the same call made for `exKana` itself.
