# v1.29 — the 910 re-decision

**Submitted 2026-08-28, macOS build 53 / iOS build 54, marketing 1.29 — both platforms
WAITING_FOR_REVIEW, verified by querying ASC directly.** `swift test` **571 green**; launch gate
passed on the uploaded archive with the Mac signed into iCloud; What's New read back from ASC in
all three locales **by its numbers**. No store metadata beyond release notes, so v1.28's `ja`
listing stays readable as its own experiment.

| | v1.28 | v1.29 |
|---|---|---|
| dictation pool | 5,770 | **5,931** |
| withheld | 954 | **793** |
| …of which **proven** misread | 21 | **248** |
| …of which undecided | 3 | 522 |

## §A The 910 `nearest` exclusions, re-decided

They were withheld by instrument 2, which v1.26 measured at **42/63 = 67%** agreement with
adjudication *on this very population*, with a median margin **larger when it is wrong** (0.0240)
than when it is right (0.0177). PLAN-V1.27 recorded that re-deciding them "needs an instrument
this repo does not have".

**Instrument 1b is that instrument.** The sentence stays in kanji and exactly one contiguous span
of tokens is replaced by kana, so word boundaries and accent context elsewhere are unchanged; a
byte-identical render is proof about that span in that sentence, and a non-match is **silence**.

**161 released · 227 proven misread · 522 undecided.** Three numbers, never collapsed into two.
The 227 are the quieter half: they were withheld correctly, and are now withheld for a reason
that can be checked rather than for a verdict from an instrument whose margin carries no signal.
Instrument 2 was right 227 times and wrong 161.

## What the run found in itself

**The release predicate was right for one population and silently vacuous on another.** It
required the DISPUTED word to be confirmed — the fix v1.28's review produced — but took
"disputed" from one global set built from rows whose evidence begins `proven`. Correct for the
`propagated` class, which inherited a verdict about one of *those* words. Every `nearest` row
carries its own complaint instead (`紙 かみ -> がみ`), none of which is in that set, so `here` came
out empty and **the coverage check was skipped for 382 of 388 releases**. Fixed to read each
row's own complaint: RELEASE fell **388 → 161**, and the 236 it would have shipped each carried a
real, never-confirmed complaint — 別 べつ→べち, 古い ふるい→ふりい, 家 いえ→け, 明日 あす→あした.

**Seven torn WAVs were cached forever.** The synthesizer writes `AVAudioFile` straight to the
final path and finalises the header on close, so a killed render leaves a truncated file exactly
where a complete one belongs. `render()` skipped anything that merely existed. The damage is
one-sided and therefore invisible: a wrong sha matches nothing, reads as SILENCE, and withholds
content for a reason that is not true.

**`None == None` was a byte-identical match.** `sha()` returns None for a missing or torn clip;
comparing two of those proved a pronunciation from audio that does not exist. Measured before
fixing: 0 of 910 rows had a None target, so no verdict rested on it.

## The door on the remaining 522, closed with a number

The obvious next move was to make 1b always test the hypothesis instrument 2 named for each
sentence. Measured *before* implementing: **Sudachi had already proposed it for 518 of the 523**,
and testing the missing five converted **one** sentence and released none.

So the silence is not a coverage gap a longer candidate list narrows — it is 1b's recall limit.
Substituting kana at a span changes prosody, so neither reading renders byte-identically and byte
identity has nothing to say. **Moving those 522 needs a different instrument, and this repo does
not have one**: `AVSpeechSynthesisMarker`'s phoneme marks are empty for every Japanese voice and
`NSSpeechSynthesizer.phonemes` returns empty even for English, both checked in v1.21.

## Open

* **522 undecided**, above. Not chaseable with what is here.
* **`n5-kazoku` reads 四人 as よんにん**, where standard Japanese lexicalises よにん. Correcting it
  would not release the sentence — Kyoko says ひと either way — so it belongs to a reading-gate
  release.
* **The CN search-result row**, from `v2-acquisition-funnel.md`. Untouched here on purpose.
* **§R is closed**: two macOS exports succeeded with the console locked, one at 82/82 in-run
  samples and one at 47/76. The sampler is permanent.
