# v1.24 — do something about the word, and make the app layer arrangeable

v1.23 taught the app to say which word stopped the learner. It says it and stops there: the
chips are text. Every other place the app names a word it can also act on it — the lapsed-word
rows on a journey results screen carry a star and an add-to-list sheet — and the one screen
where the learner has just been shown their own gap is the one screen that offers nothing.

The second half is the debt v1.23 shipped with: the dead-tap fix went to the App Store with no
execution evidence, because nothing can arrange `AppModel` into the state that would prove it.

**This plan was rewritten after review.** The first draft was sent to Codex and to Gemini 3.1
Pro and 3.7 Flash. Both of its central premises were wrong, and the corrections below are the
ones that survived being re-measured here — two reviewer claims did not. What each got right
and wrong is recorded at the end, because the pattern is more useful than the verdicts.

## §A The named word becomes a word you can do something with

A chip should offer what the lapsed-word rows already offer — save it, add it to a list — and
one thing they do not: ride these words now. `GameSession.makeSaved(ids:)` and `makeWeak(ids:)`
already build a run from arbitrary ids and `AddToListsSheet` already exists, so none of that is
new machinery. Turning a chip into an id is.

### Resolution has three layers, and the first one is free

`StumbledWords` produces `(surface, reading)` read out of `exTokens`; saving or drilling needs a
`VocabEntry.id`.

**Layer 1 — the word the sentence was written to teach.** `StumbledWords.from` already resolves
`event.entryID` to the owning entry on the line where it validates the event. If the stumbled
token IS that entry's word, the id is in hand: exact, unambiguous, zero new code. Measured over
the 6,724 shipped sentences, the taught word appears as a bare token in **83.6%** by surface and
0.2% more by reading — **83.8%**. In the remaining 16.2% the taught word appears only inflected,
and the entry id is still known; what is missing is knowing that the stumble fell inside it.

**Layer 2 — other content words, by surface then reading.** Over all 41,224 content tokens
(particles excluded): **59.2%** resolve by surface, **22.9%** by reading only, **17.9%** do not.

**Layer 3 — do not build the inverse-conjugation index.** The first draft proposed generating
every form of every conjugable entry and indexing them. Measured before building, which is the
only reason it is not in this release: all 7 forms of all 2,317 conjugable entries produce
16,063 strings, and they cover **270 of the 7,399 unresolved tokens — 3.65%**.

The reason is structural and worth stating so nobody proposes it again. `exTokens` comes from
Sudachi in `SplitMode.C`, which emits bare morphological stems plus separate auxiliary tokens:
食べ + た. `Conjugator` emits complete words: たべた. The two never meet. An index built from a
forward conjugator cannot resolve stems it never generates.

### What the 17.9% actually is, and what to do with each part

Sorted by frequency: だ (504), です (441), ない (240), れ (240), なっ (134), しまっ (85),
あり (84), 食べ (66), まで (63), つい (59).

- **Function words and auxiliary fragments** — だ, です, まで, れ, しまっ. Not vocabulary anyone
  studies. Filter them, the way particles are already filtered in sentence mode. Note the trap:
  the auxiliary ない collides with the N5 i-adjective 無い, so a naive index will offer to save
  an adjective when the learner stumbled on a verb suffix. Filtering by token, not by lookup.
- **Inflected stems of entries the corpus has** — なっ, あり, 食べ. Layer 1 covers these when
  they belong to the taught word. When they do not, leave them unresolved rather than guessing:
  euphonic stems are genuinely ambiguous (かっ is 買う, 勝つ, 刈る and 飼う; いっ is 行く, 言う
  and 要る), and this app has twice been burned by a component that resolves ambiguity by
  regressing to the common answer.

### The rule that governs the UI

**Resolve first, render second, and count what the run will contain.** A chip that cannot be
saved must not show a star. A "ride these" button must apply *the run builder's own predicates*
— `resolves`, and `isTypeableSentence` if the drill is a sentence run — because a chip can
resolve to an id that the builder then drops, and 335 entries have no sentence at all.

Showing six words and riding four would be the fifteenth instance of this project's recurring
defect, and the first one introduced *after* the sweep that was supposed to end it.
`ResolvesCallSiteTests` will not catch it: there is no `resolves:` keyword on this path, which
is precisely the blind spot the v1.23 audit's own calibration named.

### The dictation tension, which has no obvious answer

Dictation deliberately keeps particles (`includesParticles: true`) because mishearing に for の
is a real listening result. But particles are exactly what cannot be saved or drilled. So a
dictation results screen will hold two kinds of chip — diagnostic-only and actionable — and the
plan does not get to pretend otherwise. Decide the visual treatment deliberately; do not solve
it by filtering, which would gut the dictation diagnostic v1.23 shipped.

## §B The app layer becomes arrangeable

The first draft said `AppModel` cannot be tested because `NihongoRideApp` is an
`executableTarget`, and proposed choosing between extracting a library and growing the XCUITest
suite. That framing was wrong twice over.

**It is already importable.** On Swift 6.3.3 a test target can `@testable import` an
`executableTarget`, `@main` and all. Verified against this package, not a toy: adding
`.testTarget(name: "NihongoRideAppTests", dependencies: ["NihongoRideApp"])` compiles and runs,
and `AppModel()` constructs inside a test. Four lines of `Package.swift`.

**The real obstacle is arrangement, not access.** A test that constructs `AppModel` and calls
`startGame()` to prove the dead-tap fix passes — and passes for nothing, because a fresh model
at N5 has a full pool, so the guard never fires and `screen != .results` is true for the wrong
reason. `AppModel` reaches for `VocabStore.shared` in 16 places. It can be imported and it
cannot be arranged, and only the second one is what a test needs.

So the work is:

1. Add the test target. Four lines.
2. Make the state worth testing reachable — inject the vocabulary store (and whatever else the
   guards read) rather than reading the global. Scope it to what the untested guards actually
   need; a general dependency-injection pass on a 1,600-line model is not this release.
3. Cover, with mutation calibration on each: the empty-pool guard's `screen = .menu` (revert the
   line, watch the test go red), and the §A count-vs-run contract.

The other debt this pays off: **"To review: N" on a sentence or dictation results screen counts
words nothing will review.** Found by the v1.23 audit and deliberately left: `persistsSRS` is
false for sentence, dictation and the weak-words cram, so `finishGame` merges nothing, while
`lapsedEntries` is appended with no `recordsSRS` gate. §A puts actionable chips directly beside
that tile, which makes the contradiction louder. Note the knock-on the reviewers caught: a
sentence results screen currently renders both `reviewList(summary.reviewWords)` and
`stumbledWords`, so fixing the tile changes that layout — decide what replaces it rather than
leaving a gap.

## §C Now included, having been wrongly deferred

**Make `resolves:` required in production.** v1.23 kept the `{ _ in true }` default and rejected
removing it on a count: 57 of 75 call sites are tests that build stores where everything
resolves. All three reviewers called that wrong, and they are right — the default is the trap
itself, since omitting the argument compiles clean and silently returns an unfiltered number.
The compiler is a stronger gate than a source-scanning lint, and the test noise has an answer
neither the lint nor the default needed: a test-only convenience (`dueCardsForTesting(...)` or
an extension in a test helper) so production APIs can require the argument.

Keep `ResolvesCallSiteTests` afterwards. It covers what the signature cannot: a *new* counting
method that never had the parameter.

## §D Not in this release, and why

- **The other 110 entries with no example.** Unchanged from v1.21 and v1.23: the corpus push was
  concluded on purpose, and four releases of spending what already exists have each found more
  than another content batch would.
- **釣 → 釣り.** Decided and declined three times. Read the earlier entries before re-deciding.
- **The dictation exclusion list is voice-calibrated.** Documented in `DictationSafety`, not
  fixable without pinning a voice — which would refuse a learner the enhanced voice they
  downloaded.

## Stop rule

Ships when:

- `swift test` is green, and every new test has been shown to fail: the dead-tap test with the
  guard's `screen = .menu` reverted, and the §A count-vs-run test with one filter removed. A new
  test that has never been red is not evidence.
- The §A resolution numbers are re-measured against the shipped corpus at build time, not quoted
  from this document.
- A check exists for `Sources/**/* [0-9]*.swift` — the Finder/iCloud duplicate trap that turned
  the build red on 2026-08-18 and would have failed a release build silently earlier in the day.
- `check_vocab_diff` is clean and its self-check passes all 18 probes.
- The pre-submission adversarial review has run and its blockers are fixed.
- `scripts/launch_gate.sh` passes on the signed archive with the Mac signed into iCloud.

## What the review got right and wrong

Worth keeping, because it is the same lesson this project keeps relearning: an outside review is
evidence, not a verdict, and its numbers need re-measuring even when its conclusions are sound.

- **Right, and decisive:** the inverse-conjugation index is useless (Gemini 3.7 Flash) — though
  it reported 0.3% coverage and the real figure measured here is 3.65%, an order of magnitude
  out, with the conclusion unaffected. And `executableTarget` is already test-importable
  (Codex) — the one claim that collapsed §B from a refactor to four lines, and the only one of
  the three reviews to get that right.
- **Right in substance, wrong in detail:** Gemini 3.1 Pro said the sentence's parent entry id is
  already available via a field called `exMeta`. No such field exists. The substance is correct
  and simpler than claimed: `event.entryID` is already resolved inside `StumbledWords.from`.
- **Right, and both Geminis converged on it:** the SwiftUI-coupling measurement §B proposed was
  measuring a known zero — `AppModel` imports SwiftUI nowhere.
- **Proposed but unnecessary:** both Geminis recommended extracting a library target. It works
  (verified with a probe) and it is not needed, because the executable is importable as is.
- **Missed by all three:** that importability is not the blocker — arrangement is. The dead-tap
  test compiles, runs, and passes vacuously.

---

# What was actually built, and where the plan was wrong

Written after the work, from measurements taken during it. The plan above is left unedited so
the difference stays visible.

## §A — the resolution rule is narrower than the plan, and the plan's layer 2 was unsafe

The plan proposed resolving "by surface then by reading". Both halves were measured against
the shipped corpus before either was built, and both failed:

* **By surface alone**: 1,362 tokens hit an entry whose reading disagrees with the token's.
  That is *100%* of the surface-only hits, and it is a tautology rather than bad luck — a
  token whose reading agreed would already have matched the pair. It names 二 for ふた, 来 for
  き, 時 for じ, 箱 for ばこ.
* **By reading alone** is worse, and worse in the direction that looks safest. A kana-only
  token has no written form that could contradict a reading match, so it reads like the safe
  case. In Japanese a kana-only token is usually a function morpheme, and the reading index
  always finds some rare noun spelled that way: て→手 2,130 times, し→死 1,202, ます→増す 655,
  な→名 563, から→空 297. Offering to save 死 because the learner stumbled on the し of します
  is the ない/無い trap the plan named, with three orders of magnitude more instances — and it
  is ~19% of all tokens, i.e. the bulk of what layer 2 claimed to buy.

**The rule that shipped: the written form and the reading must both agree.** Measured 58.4% of
content tokens and 74.1% of tokens containing kanji, with a residue that is almost entirely
function morphemes — the correct answer for them. It fails safe by construction.

Two consequences the plan did not anticipate:

* **The function-word blocklist is unnecessary.** だ, です, ない, まで, れ are not entry
  surfaces, so the pair rule already refuses them. Particles are still blocked explicitly,
  because the corpus contains exactly one entry whose surface is a bare particle — `n3-b612`,
  で/で, "and, then" — and a misheard で would otherwise be handed a conjunction card.
* **Layer 1 collapses into the same rule.** Requiring only the surface would name 生/せい for
  a token read なま whenever a sentence teaching one contains the other. Its net gain over the
  pair index was 7 tokens out of 41,222, every one a euphonic stem whose lemma is genuinely
  ambiguous. It survives as the *priority* path — the taught word's id is known rather than
  inferred, so it stays correct if a future entry makes a pair key ambiguous — but it checks
  both halves like everything else.

The plan's own numbers reproduced to the digit (83.8% of sentences contain their taught word
bare; 59.2/22.9/17.9 for surface/reading/none), so the disagreement is about what those
numbers *permit*, not about the arithmetic.

## §B — the arrangement problem was real, and there was a second one

`executableTarget` is `@testable import`-able, as the plan said, and the test target is four
lines. `AppModel` reached for `VocabStore.shared` in sixteen places **and handed `.shared` to
eighteen builders** — thirty-four sites, not sixteen; a model whose own store differs from the
store its runs are built from is a count-vs-run split by construction.

The plan missed a second blocker, and it is not cosmetic: **`AppModel()` reads the machine's
real Application Support directory, and `finishGame` writes back to it.** An app test target
without a redirect would assert against the owner's live, iCloud-synced review schedule and
log invented rides into it. `supportDirectoryOverride` exists for that, and
`AppModelTests.sandboxed` is the only way the target constructs a model.

## §C — removing the defaults found two live defects the rule could not see

Production needed none of the ten defaults; the app compiled unchanged. Removing them
surfaced `ConjugationReviewStore.reviewedCount` (an unfiltered public *property*) and
`.leeches()` (an unfiltered function), both read by the Stats screen, neither visible to a
scan that matches `.name(` with a parenthesis. Two more were latent and fixed:
`weakestFormCards` capped before filtering (the v1.23 weak-words bug verbatim) and
`reviewedIDs` handed the coach drill a pool that was correct only because its one caller
happened to filter afterwards.

## What the calibration cost, and what it caught

Every new test was shown to fail before being believed: 9 mutations on the resolution rule, 6
on the app layer, 3 on the §C gates, 0 undetected. Three findings came from that discipline
rather than from the code under test:

1. **The mutation harness reported a hole that was its own blind spot** — a `--filter` silently
   matched no tests and "the expected test did not go red" was indistinguishable from "the
   expected test never ran". It now runs the whole suite and asserts the test appeared.
2. **`try!` on `#require` aborts the process**, so one failing app test took twelve unrelated
   ones down and made the run unreadable.
3. **The sandbox assertion graded itself** — it read a shared static that a parallel test had
   also set, so it would have passed even if `makeModel` set nothing. It now asserts against
   its own directory.

And one that cost about an hour: adding a stored property to `VocabStore` changed the struct's
layout and left SPM's incremental build inconsistent, producing a SIGSEGV inside an unrelated
v1.23 test. `rm -rf .build` fixed it. Recorded under Traps in `STATE-2026-08-18.md`.

## Deferred, deliberately

The dictation tension the plan raised is answered by *treatment*, not by filtering: an
unresolvable chip keeps its place and offers nothing — no star, no gestures, a dimmer stroke.
The dictation diagnostic v1.23 shipped is intact.

"To review: N" was fixed as the **label**, not the behaviour, on the owner's decision.
`GameSummary` now carries `persistsSRS` from `RunCompletion` — the same value `finishGame`
gates the merge on — so a mode check in the view cannot drift. The first wording ("Missed")
was replaced after the headless render showed it reading as a contradiction beside the chips.
