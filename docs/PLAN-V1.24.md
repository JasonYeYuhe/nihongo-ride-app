# v1.24 — do something about the word, and make the app layer checkable

v1.23 taught the app to say which word stopped the learner. It says it and stops there: the
chips are text. Every other place the app names a word it can also act on it — the lapsed-word
rows on a journey results screen carry a star and an add-to-list sheet — and the one screen
where the learner has just been shown their own gap is the one screen that offers nothing.

The second half of this release is the debt v1.23 shipped with. Six defects were fixed and one
of them, the dead tap on the results screen, went to the App Store with no execution evidence
at all, because the app layer has no test target. That is not a gap in a test suite; it is a
whole layer nobody can check.

## §A The named word becomes a word you can do something with

A chip should offer what the lapsed-word rows already offer — save it, add it to a list — and
one thing they do not: ride these words now, which is the reason a learner reads the list at
all. `GameSession.makeSaved(ids:)` and `makeWeak(ids:)` already build a run from arbitrary ids,
and `AddToListsSheet` already exists, so none of that is new machinery. One thing is.

**A stumble is not an entry.** `StumbledWords` produces `(surface, reading)` read out of
`exTokens`. Saving or drilling needs a `VocabEntry.id`. Measured over all 41,224 content tokens
in the shipped corpus (particles excluded):

| | tokens | share |
|---|---|---|
| resolve by surface (食べ物 → the 食べ物 entry) | 24,389 | 59.2% |
| resolve by reading only (kana spelling differs) | 9,436 | 22.9% |
| do not resolve | 7,399 | 17.9% |

The 17.9% is not random. Sorted by frequency it is auxiliaries and inflected stems: だ (504),
です (441), ない (240), れ (240), なっ (134), しまっ (85), あり (84), 食べ (66), まで (63),
つい (59).

That splits into two different problems and they should not be solved the same way:

- **だ / です / ない / まで** are function words. They are not vocabulary a learner studies, and
  offering to add です to a word list is offering nonsense. Treat them like particles are
  already treated — filtered, not failed.
- **なっ / しまっ / 食べ / あり** are inflected forms of entries the corpus HAS. 食べ is the
  ren'yōkei of 食べる, which is an N5 card. These are the ones worth recovering, and recovering
  them is the actual engineering in this release.

`ConjugationKit` conjugates forward — `Conjugator.conjugate(kana:verbClass:lemma:form:)`. The
obvious move is to invert it, and the obvious move should be measured before it is built:
generate every form of every conjugable entry, index the results, and see what fraction of the
unresolved tokens that index covers. If it is most of them, the inverse index is the answer and
it is cheap and exact. If it is not, say so and ship the 82% honestly rather than adding a
deinflection heuristic that is right most of the time — this app has been bitten twice by
components that regress to the common answer.

**The rule that governs the UI, and it is not negotiable.** Resolve first, render second. A chip
that cannot be saved must not show a star; a "ride these" button must count what it will
actually ride. Showing six words and riding four is the defect class this project has now hit
fourteen times, wearing a new costume — and it would be the first instance introduced AFTER the
sweep that was supposed to end it. `ResolvesCallSiteTests` will not catch it: there is no
`resolves:` keyword here, which is exactly the blind spot the audit's own calibration named.

## §B The app layer stops being unverifiable

`NihongoRideApp` is an `executableTarget`. Nothing can `@testable import` it, so `AppModel` —
which owns every screen transition, every start path, and every count the menu shows — has zero
unit tests. v1.23 fixed a dead tap by adding one line to a guard and shipped it on a reading.

The XCUITest scaffolding does work: `StumbledWordsFlowTests` drives a real run in the simulator
and was calibrated by mutation. But a UI test costs ~30 seconds and a simulator, and cannot
reach a state like "every word at this level has been typed" without hours of setup.

Two ways out, and this release should pick one on evidence rather than taste:

1. **Extract the model.** Move `AppModel` (or the part of it that is not SwiftUI) into a library
   target that a test target can import. Cost: a real refactor of the largest file in the app,
   touching every view. Benefit: the screen-transition and start-path logic becomes ordinary
   unit-testable code, and defects like the dead tap become one-line tests.
2. **Grow the UI suite.** Keep the executable as is and cover the transitions through XCUITest.
   Cost: slow, and some states are unreachable. Benefit: no refactor risk to a shipping app.

Before choosing, measure: how much of `AppModel` is SwiftUI-coupled and how much is plain logic?
Count the members that touch `View`, `@Environment`, or SwiftUI types versus those that do not.
If the plain-logic share is large, (1) is smaller than it looks and worth the risk. If AppModel
is SwiftUI all the way down, (1) is a rewrite pretending to be a refactor and (2) is the answer.

The concrete debts this pays off, in order:

- The dead tap (`startGame`'s guard now sets `screen = .menu`) has no test.
- **"To review: N" on a sentence or dictation results screen counts words nothing will review.**
  Found by the v1.23 audit, deliberately not fixed then, and it belongs here: `persistsSRS` is
  false for sentence, dictation and the weak-words cram, so `finishGame` merges nothing, while
  `lapsedEntries` is appended with no `recordsSRS` gate. The tile uses the menu's own icon and
  wording for a number that means something different. §A will put actionable chips directly
  beside that tile, which makes the contradiction louder, so it should not survive this release.

## §C Not in this release, and why

- **The other 110 entries with no example.** Unchanged from v1.21 and v1.23: the corpus push was
  concluded on purpose, and four releases of spending what already exists have each found more
  than another content batch would.
- **釣 → 釣り.** Decided and declined three times now. If it comes up again, read the earlier
  entries before re-deciding.
- **The dictation exclusion list is voice-calibrated.** Measured, documented in `DictationSafety`,
  not fixable without pinning a voice — which would refuse a learner the enhanced voice they
  downloaded.
- **Removing the `resolves:` default.** Considered in v1.23 and rejected on a count: 57 of the 75
  call sites are tests that build stores where everything resolves. Revisit only if a production
  site forgets it again despite the lint.

## Stop rule

Ships when: `swift test` is green; the §A resolution numbers are re-measured against the shipped
corpus and stated in the release notes' terms (what the learner can and cannot act on);
`check_vocab_diff` is clean and its self-check passes all 18 probes; the pre-submission
adversarial review has run and its blockers are fixed; `scripts/launch_gate.sh` passes on the
signed archive with the Mac signed into iCloud; and — new this release — at least one of §B's
two paths is in place, with the dead tap covered by an executable test.

## Before starting, read

- `docs/STATE-2026-08-18.md` — especially "The one class of defect this project keeps hitting"
  (fourteen instances, and what is and is not in place against it) and "Traps this project has
  already paid for".
- `scripts/check_vocab_diff.py` — the vocabulary rules, if any data is touched at all.
