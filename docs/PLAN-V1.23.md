# v1.23 — say what went wrong, and stop the class that keeps coming back

v1.22 shipped a counting bug that had been wrong for three releases, and the review that
caught its other half found two more instances of the same shape. That class — **the number
shown and the run produced computed by different predicates** — has now bitten eight times.
This release does two things: gives sentence and dictation runs a diagnosis they never had,
and tries to make the class structurally harder to repeat.

## §A The words, not the count

Already on `main`.

The app has two ways of explaining a mistake and only one of them worked on sentences.
`DiagnosticsKit` classifies a refused keystroke by its typing MECHANICS — は written `wa`, a
missed sokuon, a small ゃ — and the coach drills the rule. That is right when the learner
knew the word and mistyped it, and `DiagnosticsKit` honestly returns `.unknown` when they
simply did not know it.

In a word run the gap hardly shows: the card IS the word, so the results screen lists it. In
a sentence run the target is twenty kana of prose, so the app could say "four mistakes" and
nothing about where — and in dictation, where the sentence is heard rather than seen,
**where is the entire diagnosis**. A learner who could not make out 潜入 needs to be told 潜入.

The data has been sufficient since v1.18 and nothing read it: a `MistakeEvent` carries a
position in the sentence's reading, and `exTokens` readings concatenate to that reading
exactly. `VocabEntry.exampleToken(atReadingIndex:)` walks it back to a word;
`StumbledWords.from(_:)` aggregates a run; the results screen shows up to six chips under
the coach line, each the word with its reading above it.

Two things worth keeping in mind about it:

- **Punctuation tokens consume no position.** `exKana` has none, because a romaji keyboard
  cannot produce 。 — get that wrong and every sentence with a mid-sentence comma names the
  word BEFORE the one that was mistyped. A test rebuilds the reading from the tokens for all
  6,724 shipped sentences and requires it to match byte for byte.
- **A journey run over the same entry must not contaminate it.** Those events carry the
  WORD's reading as their target, not the sentence's, so indexing `exTokens` with them would
  name a word at random. The attribution only fires when the event's target IS the
  sentence's reading.

## §B The class, swept and then made harder

An audit paired every learner-visible number with the run it promises. It was calibrated
first, by replaying an actual sweep against the commits before each of the eight known
fixes — all eight flagged.

The calibration also named its own blind spot, and that is the more useful half:

> Rule A works because the codebase adopted a distinctive parameter (`resolves:`) in response
> to this very defect. In a codebase that had never adopted it — or for a NEW promise built
> on a filter that has no keyword — it degenerates to "read everything".

So a sweep can find repeats of a known idiom and cannot find the next novel one. Which means
the durable answer is not a better sweep but a shape that cannot diverge: **the count and the
run should not be two predicates that agree, they should be one predicate used twice.**
`GameSession.sentenceEntries(ids:)` already works that way — the menu counts it and the run
consumes it — and every place that does not is where the next instance will come from.

The sweep returned 20 candidates. Each was re-verified here before becoming work, because an
audit report is evidence, not a conclusion — and the two most severely labelled findings did not
survive that step in the form they were reported.

**Fixed.**

1. **The streak number and the strip beside it disagreed.** `streakDays` credits both days of a
   ride that crosses midnight (deliberate, v1.15 §D: a rider who starts 23:50 and finishes 00:05
   did not miss a day). The 14-stud strip built its own set from the END timestamp alone. So the
   card read "Streak 5" above a strip with a dark stud punched into the middle of a chain the
   rider had not broken. Reproduced before fixing: `streak=5 lit=4, last five days ● ● ○ ● ●`.
   Fixed by extracting `RideJournal.riddenDays(calendar:)` and having both surfaces consume it —
   one predicate, used twice, which is the shape this section argues for. A test also pins that a
   day genuinely not ridden stays dark, because "light everything" would pass the other two.

2. **The passage screen never stopped the run clock.** `RunClock` exists to measure ridden time
   rather than wall clock, and `logRun` says so in a comment: "so the journal row and the live
   readout cannot drift apart." Every pause/resume call site was in `GameView`; `PracticeView`
   had none. Put the app down mid-passage and the Ride Log recorded the interruption as riding,
   with the WPM diluted to match. One `scenePhase` handler, matching the one `GameView` already
   had.

3. **The coach reported a capped number as a total.** `MistakeTrace` keeps 200 events and counts
   the overflow in `dropped`, whose comment since v1.15 says it exists "so the coach can say the
   trace is partial rather than quietly reasoning about a truncated sample." Nothing ever read
   it. The evidence line is the one place it matters — it is shown precisely so the learner can
   weigh the claim, and a silently capped number is not something they can weigh. It now says "at
   least N times" when the run out-typed the trace.

4. **Form tokens pinned.** The badge counts a conjugation card if its VERB still exists; the
   drill additionally needs `ConjugationForm(rawValue:)` to parse. See below for why that is not
   currently a bug — the pin is what keeps it from becoming one silently.

**Verified and NOT a bug, recorded so it is not re-found.**

- **The conjugation badge/push predicate** was reported as a blocker. It is not one today. For
  the badge to over-promise, a due card must exist that the drill cannot rebuild, which needs
  the form token to stop parsing, the entry to be withdrawn, or `vc` to change. Withdrawal fails
  both predicates alike; `vc` is frozen by the vocabulary guard; and `ConjugationPrompt`'s
  failable init depends only on `verbClass` and the conjugator — checked, because if it had
  depended on `languageCode` then switching the app to Chinese and back would have opened the
  gap for real. So the only live route is renaming a case, and a test now pins the seven raw
  values as storage. Widening `resolves:` to carry the form was rejected: a signature change
  across four methods and every call site, to close a hole nothing can currently walk through.

- **"N available" against a run of 5.** Reported repeatedly across the menu and list screens.
  The count is the pool; the run is the first five. That is how spaced repetition is supposed to
  work — you clear five, they reschedule, the next five come up — and the label says "available",
  not "in this ride".

- **100% accuracy on a run with no keystrokes.** Real, and it reaches the share card. It does
  NOT reach the journal: `logRun` refuses a run with no completed words and no correct
  keystrokes. Left alone this release as cosmetic; noted so the next person does not have to
  re-derive that the stats are safe.

**The one that matters most is none of these.** The calibration named a structural limit: the
sweep finds repeats of the `resolves:` idiom because the codebase adopted that word in response
to this very defect, and degenerates to "read everything" for a new promise built on a filter
with no keyword. Findings 1, 2 and 3 are all of exactly that kind — no keyword, found by pairing
a surface against its builder by hand — and all three had a comment somewhere asserting the
property the code lacked. That is the cheapest available detector: where a comment states a
contract, check whether anything enforces it.

## §C Not in this release, and why

- **The other 110 entries with no example.** 335 entries have no sentence; 225 are the
  structurally blocked ones and 110 are simply unserved. They could go through the normal
  pipeline and would push coverage past 97%. Deliberately not now: v1.21 concluded the corpus
  push on purpose, and three releases of spending what exists have found more than another
  batch of content would.
- **釣 → 釣り.** Decided twice, declined twice, recorded both times.
- **The dictation exclusion list is voice-calibrated.** Measured, documented in
  `DictationSafety`, and not fixable without pinning a voice — which would refuse a learner
  the enhanced voice they downloaded.

## Stop rule

Ships when: `swift test` is green; `check_vocab_diff` clean and its self-check passes every
probe; the pre-submission adversarial review has run and its blockers are fixed; and
`scripts/launch_gate.sh` passes on the signed archive with the Mac signed into iCloud.
