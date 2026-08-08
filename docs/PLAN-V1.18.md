# v1.18 — the example sentences become typeable

v1.17 shipped 3,714 example sentences and then only *displayed* them. This release makes them
the material: a sentence typing mode, and furigana so the learner can read what they are
typing. Both need one thing the data does not have — the reading of a whole sentence — so the
data comes first and the two features fall out of it.

## §A The missing data: `exKana`

`KanaInputMatcher` types against a **kana target**. Words have `kana`; sentences have nothing.
So each sentence gets `exKana`, its full reading, and `exTokens`, a per-token
surface/reading pairing that furigana needs.

Generated with Sudachi, which is the right instrument here and was the wrong one in v1.17 §F:
a whole sentence in context is where a statistical tokenizer is *strong*. Where it is weak —
an isolated minority reading — is precisely what §F documented, and those 16 entries have no
sentence to read.

**This data is not trusted because it parsed.** Three gates before anything ships:

1. **Round-trip.** Strip the kana back through `KanaRomanizer` and it must be typeable —
   every character in `exKana` must be kana or sentence punctuation. Anything with a stray
   kanji is a tokenizer failure and is dropped, not patched.
2. **Token alignment.** Concatenating `exTokens` surfaces must reconstruct `exJP` exactly, and
   concatenating their readings must reconstruct `exKana` exactly. Furigana that drifts out of
   alignment puts the reading over the wrong character.
3. **Sample review.** A hand-read sample judged for whether the reading is the one a native
   would produce, with the negative control the v1.17 work says to build: seed it with
   sentences from the known-bad minority-reading set and confirm the judge flags them.

A sentence that fails any gate simply does not get `exKana`, and is invisible to the new mode.
Partial coverage is the correct outcome; a wrong reading is worse than an absent one, because
the learner types it and is told they are wrong.

## §B Sentence mode

A fifth `GameMode`. The learner types a whole sentence instead of a word.

- Queue is sentences, not words, drawn from the same level/list selection.
- The target is `exKana`; the display is `exJP` with the typed portion tracked across it.
- Scoring reuses the existing per-keystroke accounting; a sentence counts as one "word" for
  WPM so the existing stats stay comparable rather than silently changing meaning.
- SRS: a sentence run reviews **the word the sentence teaches**, so progress lands on the same
  cards as every other mode. No second scheduler.
- Only sentences with `exKana` are eligible. If a selection has too few, the mode says so
  rather than silently substituting words.

## §C Furigana

The reading over the kanji, from `exTokens`, on the example sentence in the existing modes and
on the sentence in §B.

This also closes a v1.17 finding: 16 N3 entries teach a minority reading no sentence can
force, and the reason the problem is real is that the learner cannot tell which reading the
sentence uses. Furigana tells them. It does not fix the entries — that is still a `kana`
question — but it removes the harm.

Off by default on the sentence being typed (it would give the answer away); on for the
display-only example in Journey/Time/Practice, behind a setting.

## §D Known issues from v1.17

- 56 N3 entries still have no example. 16 are the minority-reading set; the rest get another
  generation pass with the §A pipeline.
- The 35 Chinese corrections and 4 gloss corrections merged after v1.17 was submitted ship
  here.

## Stop rule

Sentence mode does not ship unless: `exKana` round-trips for every sentence it exposes, token
alignment is exact, the sample review finds no reading defect the negative control did not
also catch, `swift test` is green, and the Release launch crash gate passes on both platforms.
If coverage after gating is under 60% of the corpus, the mode ships anyway but the menu says
how many sentences are available — a smaller honest number beats a padded one.
