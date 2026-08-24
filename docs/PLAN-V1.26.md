# v1.26 — the third blind spot, and the screens nothing tests

v1.25 ended with one sentence: **a gate validated by what it CATCHES has not been validated.**
This release is what happens when that sentence is turned on v1.25's own gate.

`readsItsHeadwordAsTaught` asks: does the sentence read its headword the way the card teaches?
It answers that question for **5,864 of 6,738 sentences**. The other 874 it cannot see at all,
because it needs the headword to appear as a contiguous run of tokens — and a verb in a sentence
is conjugated, so its dictionary form never appears. **724 of the 874 are verbs.** v1.25's
boundary-crossing walk (`coveringReading`) rescues 104 of them. **770 are inspected by nothing.**

Three of them teach a reading that is not the word:

    n1-g305   card 潜る / くぐる     「暖簾を潜って老舗の蕎麦屋に入った。」  types  …をもぐって…
    n1-b045   card 汚れる / けがれる  「…純粋な心は汚れてしまった。」        types  …こころはよごれて…
    n1-b393   card 捲る / まくる     「シャツの袖を捲って作業を始めた。」    types  …そでをめくって…

暖簾を**くぐる** is to duck under a shop curtain; もぐる is to dive underwater. They are two
different verbs sharing a spelling, and the corpus has a separate card for each — `n2-g127`
潜る/もぐる, whose own sentence 「海に潜って魚を見る。」 is correct. The learner studying くぐる
is graded against the other verb. 心が**けがれる** is to be defiled; よごれる is to get dirty,
and it is the commoner reading — this is the regress-to-the-common-answer failure that has cost
this project two releases already. 袖を**まくる** is to roll up a sleeve; めくる is to turn a page.

None of these could have been caught, because nothing looked. That is the release.

The second half of the release is a different shape with the same cause, and it is worth naming
because it is new to this project's list:

> **A unit test on a predicate is not a test of the screen that uses it.**

`ConjugationSRSCard.quality` is tested with a `durationRatio` the test supplies — production
never supplies one, so the rubric's last line is a constant (§C). `GameMode.lapsesAreWords` is
tested well — `LapsesAreWordsTests` (`GameSessionTests.swift:766`) checks the predicate against
what the session builders actually queue, deliberately "rather than restating the list of modes"
— and **every one of its consumers is in `ResultsView`, which no test in this repository
mentions**, so the entire visible outcome of v1.24 §B and v1.25 §B can be deleted with 520 tests
still green (§D). Both suites are honestly green. Neither proves what a learner sees.

## Scope and order

| | what | size |
|---|---|---|
| **§A** | 3 corpus corrections + the stem-aware gate + its ratchet | ~2–3 h |
| **§B** | B1, B3, B4 + the accessibility-string check v1.25 specified | ~3 h |
| **§C** | wire the conjugation drill's timing, through a paused clock | ~2 h |
| **§D** | `ResultsView` rendered-text tests; restore the deleted gate; two ratchet companions | ~3 h |
| ~~§E~~ | **cut to backlog** — do the static scan only if §A–§D land early | — |

Do them in that order. §A is the only one a learner can be harmed by today; §D is the only one
that makes the others hard to break later. All three reviews converged on §A–§D as a two-day
release and on cutting §E.

## Where this scope came from

Six independent lenses surveyed the repo — learner-facing gaps, the three open items, the
recurring count-vs-run defect, what every gate cannot see, tests that cannot fail, and release
machinery — each required to bring a measurement rather than an intuition. Six adversaries then
re-ran every measurement with a default verdict of REFUTED; five candidates died there, two of
them on the repo's own record (the `exMeta.sense` proposal was already adjudicated 856 times in
v1.19–v1.21, accepted 41 times; a part-of-speech display proposed exactly the `inflectionalTails`
calibration mistake v1.24 paid for). Every number below was then re-measured a third time by
hand for this document. Where my number disagrees with the survey's, mine is the one written.

---

## §A The stem-aware reading walk

### The population, computed before the rule

The question is not "what does the gate catch" but "what can it not see". Measured over the
shipped corpus:

| | sentences |
|---|---|
| carry an example | 6,738 |
| headword IS a contiguous token span → `readsItsHeadwordAsTaught` inspects it | 5,864 |
| headword is NOT → **invisible to it** | **874** |
| of those, rescued by `coveringReading` (v1.25) | 104 |
| **inspected by nothing** | **770** |

What the 874 are, **classified by any part-of-speech tag** (not by the first tag — see below):
**778 are verbs or i-adjectives**, 96 are not. By level: N1 294, N2 215, N4 134, N3 129, N5 102 —
**236 are N4 or N5**, so this is not an N1-only tail.

> Counting these by *first* tag gives 724 verbs instead of 778, and an earlier draft of this plan
> published the first-tag breakdown beside an any-tag filter. Gemini 3.1 Pro caught the 42-entry
> discrepancy between them. Nothing was lost — but two numbers in one document computed by two
> predicates is exactly the defect §B is about, committed in the plan that describes it. One
> classification, stated once: **any tag beginning with `v`, or `adj-i`.**

### The rule

A verb's dictionary form does not appear in a sentence, but its **kanji stem** does. 潜る → 潜,
汚れる → 汚, 捲る → 捲. So: for an entry whose part of speech is a verb or an i-adjective, whose
headword is not a contiguous span, and whose stem contains kanji, find the token written with
that stem and require its reading to agree with the card's — prefix-compatible in either
direction, katakana folded through the same `KanaScript` the typing matcher uses.

Derived from the corpus, not listed. There is no table of conjugations to be wrong about, which
is the v1.24 `inflectionalTails` lesson: a list of surface forms is a claim about the data, and
two of that list's members occurred zero times.

### What it finds, and the two false-positive classes

Five flagged. **Three are genuine** (above). **Two are not, and both must be named rather than
thresholded:**

* **`n5-kuru` 来る/くる — 「友達が来ます。」 types きます.** Correct Japanese. 来る is one of the
  two irregular verbs; its stem is こ/き/く depending on the form. The rule cannot know that, so
  the irregulars are named in the gate: 来る, する, and the -ずる/-じる alternation STATE already
  records as a place the Swift and Python copies of a rule drifted apart.
* **`n1-b269` 湿気る/しける — 「湿気でせんべいが湿気ってしまった。」** The sentence contains the
  stem 湿気 twice: first as the noun しっけ, then as the verb しけって. My scan takes the first
  match and compares against the noun. **The gate must compare against every token bearing the
  stem and pass if any agrees**, not against the first.

Calibrated both directions before it is believed: reverting `n1-g305`'s `exKana` to もぐって must
redden the gate, and naming an entry in the ratchet that no longer offends must redden the
staleness companion. A gate that has never been red is not evidence.

### What this gate still cannot see — 205 sentences, sampled

The same question, asked of the new rule. It reaches 669 of the 874:

| still uninspected | why |
|---|---|
| 85 | not a verb or i-adjective — a noun whose surface the tokenizer split |
| 57 | kana-only stem: ちぎる, ぼやく, おどかす, しくじる, プラス |
| 49 | the stem does not appear as a token: 逞しい written たくましい, 存ずる → 存じて |
| 14 | no `exTokens` at all (the 14 with digits, deliberately) |

Sampled ten by hand, all correct. **57 of the 205 are structurally safe** rather than merely
unsampled: a kana-only headword has no kanji whose reading could disagree. The 85 nouns overlap
the population `coveringReading` already covers. This residue is stated here so the next release
can start from it instead of rediscovering it — which is exactly what v1.25 could not do.

### The corrections

Three, under one `check_vocab_diff --manifest`, `exKana` and `exTokens` only, `kana` frozen. All
three are N1.

**Two of the three are live dictation targets.** `n1-g305` (潜る) and `n1-b393` (捲る) are not on
the exclusion list, so learners hear those sentences today and are graded against もぐって and
めくって — with no spelling on screen to argue with. That makes these worse than typing-target
defects, and it is the same argument v1.25 used for its ten.

**The third is not, and it costs more than the other two put together.** `n1-b045` (汚れる) **is
excluded**, on a `nearest` record whose stored `exKana` is byte-identical to the corpus. Two
consequences, and the second is the one that matters:

1. Changing the corpus without updating `docs/measurements/dictation-reading-mismatches.json`
   turns `exclusionEvidenceIsCurrent` red and breaks `swift test`. That is the gate working.
2. **The exclusion may have been measuring the corpus's error rather than the voice's.** It was
   excluded because the synthesizer disagreed with よごれて. If よごれて was never the right
   reading, the disagreement says nothing about the voice, and the record cannot be re-stamped —
   it has to be **re-measured** against けがれて. Re-stamping it would be manufacturing agreement,
   which is precisely what "evidence must match the data it describes" was written to forbid.

**And that re-measurement is currently un-runnable.** `check_dictation_readings.py` imports
`sudachipy`, and **no interpreter on this machine has it** — `/usr/bin/python3`,
`/opt/homebrew/bin/python3` and the anaconda python3 all raise `ModuleNotFoundError`, and the
package is not on disk. Seven scripts are affected: `pilot_gate`, `gen_sentence_kana`,
`apply_batch`, `check_dictation_readings`, `check_example_readings`, `check_forces_reading`,
`gate_calibration`.

The first two corrections do **not** need any of them — they are point edits to `exKana`/`exTokens`
guarded by `check_vocab_diff.py --manifest` (no tokenizer) with a string round-trip that is pure
Python. Both of those import cleanly; I checked rather than assumed.

So `n1-b045` is either **an install** (`pip install sudachipy sudachidict_core` — a change to the
machine, ask first) **or a deferral**. Ship the two live dictation defects either way; they are the
ones a learner is being harmed by today.

> Worth recording as method, not trivia: in the survey that produced this plan, one agent **and its
> adversary** both reported "81 shipped sentences rejected by `pilot_gate`" — from a module that
> cannot be imported here. It was refuted on other grounds before I found this. The number was
> never real. That is the project's own thesis arriving from the direction nobody was watching.

So: diff the exclusion list before and after, and treat `n1-b045` as a re-measurement rather than
an edit. v1.25's most expensive mistake was that correcting sentences by merging token spans
deleted the very token an exclusion complaint named, so the complaint stopped matching and eight
unpassable sentences were released into dictation. These are single-token reading edits rather
than merges — a weaker version of that hazard, not an absent one.

### Two constraints on the rule, from review

* **Restrict the selector to inflecting verbs.** Filtering on any `pos` beginning with `v` pulls in
  `vs` verbal nouns, where a compound's reading legitimately does not start with the headword's —
  選挙 inside 市議会議員選挙, 就業 inside 就業規則. Key on `vc != nil` or on a `v`/`adj-i` tag that
  is not `vs`. Gemini 3.7 Flash raised this and put the count at nine; **measured, it is two**
  (`n1-b846` 選挙, `n1-b817` 就業). Directionally right, numerically wrong — the pattern
  PLAN-V1.24 recorded for outside reviews, so the constraint is adopted and the number is not.
* **Compare against every token bearing the stem, and pass if any agrees.** This is the `n1-b269`
  false positive stated as a rule rather than an exception.

---

## §B Instance nineteen of the count-vs-run defect, and two of its cousins

Eighteen are on record in STATE. B1 is the nineteenth. B3 and B4 are the same shape one level out —
not a count against a run, but a label against what the run is, and a live readout against the
number the same run records. A fourth candidate was withdrawn under review; it is kept below,
because how it died is more useful than it was.

**B1 — the weak-words button announces the pool and rides fifteen.** `MenuView.swift:452-454`
speaks `"Weak words drill, \(model.weakWordsPoolCount) words"`; `weakWordsPoolCount`
(`AppModel.swift:1421`) is `reviewStore.reviewedCount(resolves:)` — **every card ever reviewed,
uncapped**. The run is `weakestCards(limit: weakWordsRunSize = 15)`. A learner with 300 reviewed
words is told three hundred and rides fifteen. **The visible label carries no number at all**, so
this is audible only to VoiceOver — which is also why it survived every headless render this
project has taken. Same file, same release: `weakWordsPoolCount` is *correctly* used as the
visibility gate (`>= weakWordsMinimum`); it is the interpolation that is wrong.

The suite that should hold this **names the promise in its own doc comment and then approves its
violation**. `Tests/ReviewKitTests/ReviewKitTests.swift:217` opens "The menu promises
`weakWordsPoolCount` weak words and the cram used to ride fewer…" and tests only whether the cap
comes before or after the filter. Its fixture is `store(count: 20)` against `limit: 15` — a case
where the promise is twenty and the run is fifteen — and it asserts `cards.count == 15` as the
correct answer. The contract is written down, the test is green, and nothing checks the contract.

**~~B2 — the results screen counts uncapped and draws twelve.~~ WITHDRAWN.** A survey agent, its
adversary, and I all read `ResultsView.swift:488` (`ForEach(words.prefix(12))`) beside the tile's
uncapped `summary.reviewWords.count` and called it instance twenty. **Gemini 3.1 Pro read eight
lines further and found `ResultsView.swift:539-541`, which renders `+\(words.count - 12) more…`
(and 还有 N 个… in Chinese).** The count and the grid are reconciled on screen. It is not a defect.

Kept in the plan rather than deleted, because the near-miss is the lesson: four passes agreed, and
the one that disagreed was the one that read the next paragraph. The others stopped at the line
that matched the pattern they were hunting.

**B3 — v1.25 §B's predicate reached three call sites and missed two.** `GameMode.lapsesAreWords`
has exactly three consumers, all in `ResultsView`. `GameView.swift:268` (the ride HUD) and
`ShareCard.swift:106` still label the count "Words" unconditionally, so one sentence run shows
three units for one number: "Words 2/5" mid-ride, "Sentences 5" on results, and a card the learner
**posts publicly** saying "Words 5". Note the Chinese HUD already says 进度 ("progress"), which is
mode-neutral and therefore right in all six modes — one language solved this and the other did not.

**B4 — practice mode's live WPM is wall clock; the WPM it records is ridden time.** `RunClock.wpm`
carries the contract in its own doc comment: it "lives here rather than at the call site **so the
Ride Log, the sparkline and the live readout cannot drift into three different definitions of the
same number.**" `PracticeView.swift:333-334` computes the live readout at the call site, dividing
by `now.timeIntervalSince(startedAt)` with `startedAt` set once in `onAppear` (`:14`, `:86`) — the
third definition the comment says cannot exist. v1.23 §B fixed the recorded half and left the
readout. The recorded number is the larger one, so a learner's lifetime **Best WPM can be set by a
run whose own screen showed something much smaller.**

This is the cheapest detector this project has — *where a comment states a contract, check whether
anything enforces it* — landing on a comment that names the exact call site that violates it.

**And the check that was specified and never built — with its specification corrected.**
PLAN-V1.25 §B promised "a check that derives: an accessibility string on a control that starts a
run either carries no digit-bearing interpolation or **names the quantity the builder caps on**."
It does not exist, and **as written it would mandate a fresh instance of the defect**: the builder
caps on `weakWordsRunSize = 15`, so a learner with five weak words would be promised fifteen and
ridden five. Gemini 3.1 Pro found this.

The label must speak **`min(pool, cap)`** — the length of the queue the button actually produces —
and the check must assert the interpolated expression *is* that quantity, not that it names the
cap. Best shape: the one `StumbledWords.rideableIDs` already uses in v1.24 — a single function both
the number and the run call, so they cannot be derived separately.

Three further constraints on the check, all from review:
* **It must read the Chinese string too.** `MenuView.swift:453` is
  `"弱词练习,\(model.weakWordsPoolCount) 个薄弱词"`. A scan keyed on the word `words` passes the
  English fix and leaves the Chinese wrong — one rule written twice, in two languages.
* **It must discover its own call sites**, not read a hard-coded list of identifiers. A list means
  the next run-starting button is exempt by omission, which is the ratchet-staleness failure again.
* **It must print the population it skipped** and fail below a floor, so a scan that inspects
  nothing cannot report clean — the shape `ResolvesCallSiteTests` already uses.

---

## §C The conjugation drill cannot award a 4

`ConjugationSRSCard.quality(from:)` ends `return outcome.durationRatio <= 1.5 ? 5 : 4` under a
doc comment reading "Same rubric as `SRSCard.quality(from:)` (kept in sync intentionally)".

`ConjugationSession` constructs its `TypingOutcome` at `ConjugationSession.swift:252` and `:281`
**without `durationRatio`**, so it takes the default 1.0 and the last line is a constant. Every
clean conjugation answer is graded 5.

Measured, not read. A probe drove a real `ConjugationSession` with an injected clock advancing
30 seconds per keystroke — **240 seconds to type たべます — and the reported ratio was 1.0,
quality 5.** The negative control matters more than the result: the identical slow typing driven
through `GameSession`, which does compute a ratio, left the SM-2 ease factor at 2.5 (q=4) instead
of 2.6 (q=5). So the probe can see timing when timing is supplied. It is not supplied here.

The consequence is a schedule that drifts apart from the one it claims parity with: q=5 adds
0.10 to the ease factor and q=4 adds nothing, so a form the learner labours over is treated as
instant recall and leaves the rotation faster than a vocabulary card would.

`ConjugationSession` already holds the seam — an injectable `now: () -> Date` it uses at line 218.
The fix is a `promptStartedAt` and a baseline, mirroring `GameSession.durationRatio(for:)`.

**The baseline is the real decision, and both reviews stopped here.** `secondsPerKanaBaseline` is
0.8 s/kana for a word the learner can *see and copy*; a conjugation prompt requires recalling and
producing a form first. Gemini 3.7 Flash flagged it as a blind spot; Gemini 3.1 Pro went further
and said cut §C entirely, because "learners will fail the baseline, score a 4, and permanently
suppress their ease factors."

**That danger is measured and it is false.** In this SM-2 implementation (`SRSCard.swift:103-106`)
the ease-factor delta at q=4 is exactly **0.000**, and EF is updated only on success. A q=4 cannot
lower an ease factor; it can only decline to raise it. So the failure mode of a too-tight baseline
is that conjugation ease factors stop *growing* — intervals rise more slowly and the learner sees
the form more often. For a drill whose purpose is fluency that is the safe direction, and it is the
opposite of the current bug, which is a schedule that runs away upward on a grade nobody earned.

Deltas, for the record: q=5 +0.100, q=4 0.000, q=3 −0.140, q=2 −0.320, q=1 −0.540, q=0 −0.800.

**Recommend reusing 0.8 unchanged.** One rule written twice will drift, and this section is what
that looks like. The change is one-directional and safe; a second constant invented without data
would be the `inflectionalTails` mistake — a number written from intuition and validated by its
effect.

**Flash's other catch is real and must be handled: `ConjugationSession` has no `RunClock`.**
A bare `promptStartedAt` measures wall clock, so a learner who backgrounds the app mid-prompt
returns to a ratio that counted the interruption — **which is B4, re-introduced in a new place by
the fix for §C.** Either drive the ratio through a `RunClock` the way the ride does, or pause the
prompt clock on `scenePhase`. Do not ship the naive version.

The test must drive the SESSION, not the rubric. The existing
`ConjugationReviewKitTests.swift:61-62` passes today and would pass with the wiring still absent.

---

## §D `ResultsView` is not tested at all

`grep -rl ResultsView Tests/` returns nothing. Nor does `MenuView`, `StatsView`, `JournalView`,
or `CoachView`. The app test target added in v1.24 contains exactly two files, `AppModelTests`
and `StumbleChipLabelTests`.

Every consumer of `lapsesAreWords` and every consumer of `GameSummary.persistsSRS` is in
`ResultsView`. **The headline behaviour of the last two releases — the whole-sentence review list
being dropped, "Words" → "Sentences", "Struggled" → "Tough lines", "To review" not being promised
on a run that persists nothing — can be deleted in five lines with the suite still green.**

The v1.24 target already proves an app-layer test can run and can be sandboxed (`sandboxed(vocab:)`,
`nothingOutsideTheSandboxIsWritten`, and the write detector that is itself calibrated). What is
missing is a *rendered-text* assertion: build a `GameSummary` per mode and assert the labels the
screen produces. Every assertion here must be shown to go red by reverting the corresponding fix
— that is the whole point of the section, and a green new test is not evidence.

⚠️ **The App Group hazard is live for anything that builds an `AppModel`.** v1.24's first app-layer
tests stamped fourteen days of zeros onto the owner's real home-screen widget, because
`refreshWidgetSnapshot` writes outside `supportDirectoryOverride`. Use `sandboxed(vocab:)`; do not
construct `AppModel` any other way.

### Two gates the suite is quietly missing

**A gate v1.25 promised, built, and deleted.** PLAN-V1.25 §A specified "add a test that the
resource equals what the generator emits" for the reading notes — the exact defect being that the
shipped resource had been one note short of its own generator for three releases. The test was
written (`readingNotesMatchTheirGenerator`, commit `e71e7be`) and **removed in `fafae5a`, whose
message is about a different subject and does not mention it.** It is absent at HEAD. Its
neighbour `exclusionResourceMatchesItsMeasurement` was removed in the same commit, but that one
was properly *superseded* by `exclusionEvidenceIsCurrent` and the message says so. One deletion
was a decision; the other was an accident, and PLAN-V1.25's shipped table still counts both.

Restore it. And note the process finding underneath, which is the cheaper lesson: **nothing counts
the gates**, so a gate can leave the suite inside the release that added it and the release notices
nothing.

**Two of the four ratchets can never go stale.** `ExampleSentenceTests` holds four named-id
exemption lists. `knownHeadwordReadingMismatch` (line 270) has `ratchetIsNotStale` (277);
`knownSharedExamples` (297) checks staleness inline (321). `knownVariantSpelling` (86, **4 ids**)
and `knownCompoundReadings` (195, **3 ids**) have no companion at all — so **7 entries are
exempted forever**, and if one is fixed the exemption stays and hides the next offender. That is
verbatim the rationale the file's own doc comment gives at line 275 for why the other two have
companions. One rule, applied to half the places it applies to: this project's oldest shape.

---

## §E Close the accessibility waiver — feasibility is measured, the comparator is not

The AX item has been carried as "waived by the owner, not closed" since v1.25. Its cost is now
known rather than estimated, because I ran it.

**What is already in the repo.** `AppModel.jumpToDebugScreen` (`AppModel.swift:584`, gated
`#if DEBUG && targetEnvironment(simulator)`) drops the app straight onto a populated screen from
`NIHONGO_DEBUG_SCREEN`. Its own doc comment says why it exists: "`ImageRenderer` does not honour
`dynamicTypeSize` … so the headless gate cannot see large-text layout at all, and the alternative
was tapping through the app by hand once per text size." **The instrument was built for this
problem and never wired to anything.**

**What I measured.** In a clean copy outside `~/Documents`, `xcodegen generate` +
`xcodebuild -scheme NihongoRideiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
builds. `xcrun simctl ui <dev> content_size accessibility-extra-extra-extra-large` is real and
reaches `@ScaledMetric`: the menu at AX5 renders visibly larger, wraps the mode chips to two rows,
and **nothing is clipped or overlapped**.

**Three findings that decide the design, and two of them are traps:**

1. **The app cannot launch in that build without the harness variable.** `CODE_SIGNING_ALLOWED=NO`
   strips entitlements, `CKContainer.init(identifier:)` traps, and the app dies in
   `AppModel.init` before any UI — `CloudKitSyncController.init` ← `startSyncIfEnabled` ←
   `iCloudSyncEnabled.didSet`. Setting `NIHONGO_DEBUG_SCREEN` fixes it, because `isLayoutHarness`
   already guards `startSyncIfEnabled`. This is why Gate E has stayed manual for eighteen releases.
2. **My first three runs screenshotted the home screen and my md5 comparison reported a clean,
   control-passing verdict about it.** Changing `content_size` backgrounds the app; the harness
   compared SpringBoard's icon labels scaling and called the instrument validated. The gate must
   assert the app is frontmost before it believes a pixel. Recorded here because it is this
   project's exact signature failure, committed by its own author while writing the section
   against it.
3. **md5 is not a valid comparator for the app's UI.** Two launches at the *same* content size
   produce different bytes — the menu animates. The AX gate therefore cannot be
   "screenshots differ/match"; it needs either a frozen-animation harness mode or a structural
   assertion. **This is the open design question and it should be answered before the section is
   scheduled, not during it.**

**And the harness reaches five screens, not the app.** `jumpToDebugScreen` handles `menu`,
`results`, `conj-results`, `coach`, `practice`. Counting `scaledSystemFont` per file: the
reachable screens hold about 60 occurrences and **94 sit in seven views the harness cannot
reach** — Journal 20, ConjugationGame 17, Stats 15, Lists 15, About 13, Settings 9, Onboarding 5.
An AX gate built on this harness would inspect a minority of the type in the app and report green.

**The cheaper instrument, which needs no simulator at all.** AX5 spill is not caused by how many
`scaledSystemFont` calls a file has — it is caused by type that does not scale and by boxes that
do not grow. Those are statically greppable, and the counts are already in hand:

| | occurrences |
|---|---|
| fixed `.frame(width:` / `.frame(height:` | **37** |
| `.font(.system(size:))` — bypasses `@ScaledMetric` entirely | **15** |
| `.lineLimit(1)` — truncates rather than wraps | **25** |

Recommendation: **do the static scan, treat the simulator as the confirmer, and keep §E a stretch
rather than a commitment.** The scan is hours, covers every screen including the seven the harness
cannot reach, and produces a ranked list of suspects; the simulator then confirms the handful that
matter on the five screens it can reach. The comparator problem does not have to be solved to get
the first useful answer — and shipping a screenshot gate whose comparator is unvalidated would be
this same mistake in a third costume.

---

## §F Not in this release, and why

* **The 962 dictation exclusions.** Two numbers in PLAN-V1.25's Open section are wrong and are
  corrected here. The resource holds **962**, not 961 (961 is the v1.22-era figure, still true at
  commit `336ed4c` where it was 961 of 1,004). Its composition: **nearest 913 + proven 19 +
  propagated 15 + stale-after-correction 15**. And "the eight sentences put back into exclusion,
  plus fifteen records marked stale-after-correction" reads as 23 and is **15** — the eight
  (`n1-b1516`, `n1-b526`, `n2-b593`, `n3-b215`, `n3-b518`, `n5-b040`, `n5-b147`, `n5-b218`) are a
  strict subset of the fifteen. Re-deciding the 913 is a release of its own, may be undecidable
  with the instruments in this repo, and its likely outcome removes content.
* **The 15 `propagated` exclusions rest on a comment.** `check_dictation_readings.py:468` excludes
  every sentence containing a (surface, reading) pair that was proven wrong *in one sentence*,
  justified by "A voice does not change its mind between sentences." Nothing enforces it, and it
  is not obviously true — a Japanese speech front-end disambiguates by context, which is the whole
  reason 何 is なに before を and なん before で. Instrument 1 (byte-identical synthesis, the one
  credential this project never had to withdraw) can decide each of the fifteen directly. **Small,
  decidable, and it releases content rather than removing it** — the opposite of the 913. Worth
  scheduling ahead of them, and out of scope only because §A already spends this release's content
  budget.
* **The `exMeta.sense` display.** Refuted on the repo's own record: 856 sense proposals were
  adjudicated in v1.19–v1.21 and 41 were accepted. Re-proposing the other 815 as display copy is
  re-litigating a decided question.
* **A part-of-speech label on the card.** Refuted: the calibration proposed for it was the
  `inflectionalTails` mistake verbatim.
* **Corpus expansion / the ~110 entries with no example / 釣 → 釣り.** Settled four times. See
  PLAN-V1.24 §D.

### Carried forward, not in scope, and worth writing down

* **The release copy's numbers are written by hand and nothing checks them.** v1.25's What's New
  told users "Fifty more sentences are available in Dictation". The measured figure is
  **42** — the dictation pool went 5,720 → 5,762, and eight sentences were put back into exclusion
  by the final review pass *after* the copy was written. The repo disagrees with itself in three
  places (5,747 in STATE's corpus section, 5,762 in PLAN-V1.25's table, 5,770 in STATE's release
  row and in `submit_1_25.py`'s docstring). Only 5,762 is correct. This is the count-vs-run defect
  wearing marketing copy, and the fix is that any number in release copy must be derived from the
  corpus at submit time.
* `submit_1_25.py`'s `submittable()` turns an unrecognised version state into a friendly skip and
  a zero exit, so a run that submits nothing looks like a clean run.
* Nothing cross-checks `project.yml`'s eight version/build numbers against the submit script's
  three. The check that caught v1.25's crossed build numbers was run by hand and never committed.

---

## What the three reviews changed

Kept in the house style of PLAN-V1.24, because the pattern repeats and is worth watching.

**Decisive, and it removed a section.** Gemini 3.1 Pro read eight lines past
`ForEach(words.prefix(12))` and found the overflow marker at `ResultsView.swift:539-541`. Four
earlier passes — a survey agent, its adversary, and me twice — had stopped at the line that matched
the pattern we were hunting. **The only reviewer that disagreed with the premise was the one that
read the next paragraph.** That is exactly what PLAN-V1.24 recorded about its own most valuable
review, and it is the argument for running these at all.

**Decisive, and it corrected a specification.** PLAN-V1.25 §B's unbuilt check would have mandated
that a run-starting label "name the quantity the builder caps on" — which for a learner with five
weak words promises fifteen. Gemini 3.1 Pro caught that the specification itself encodes the defect.
`min(pool, cap)`, and the check asserts the expression rather than the constant.

**Decisive, and it saved a red build.** Gemini 3.7 Flash found that `n1-b045` carries a dictation
exclusion record whose stored `exKana` is byte-identical to the corpus, so §A's edit would have
turned `exclusionEvidenceIsCurrent` red. Following that thread produced the harder finding: the
exclusion may have been measuring the corpus's error, so it needs re-measuring, not re-stamping —
and that re-measurement is currently un-runnable.

**Right in substance, wrong in the number — twice, in both directions.** Flash put the `vs`
verbal-noun false positives at nine; measured, it is two. Gemini 3.1 Pro said §A's residue math
loses 42 entries; nothing was lost, but it had found a real inconsistency — two tables in the plan
classifying the same population by different predicates, which is the defect §B is about, in the
document describing it. Both constraints adopted, neither number.

**Wrong, and checkable.** Gemini 3.1 Pro said §C would "permanently suppress ease factors". In this
SM-2 implementation the q=4 delta is exactly 0.000 and EF moves only on success, so a q=4 cannot
lower an ease factor. §C survives with its risk analysis written down instead of being cut.

**All three converged** on §A–§D as a two-day release and on cutting §E, and all three independently
reproduced §A's population figures (6,738 / 5,864 / 874 / 104 / 770) to the digit.

## Stop rule

Ships when:

- `swift test` is green **and every new test has been shown to fail** — the §A gate with
  `n1-g305`'s `exKana` reverted, the §B accessibility check with B1's label restored, the §C test
  with the timing wiring removed, each §D assertion with its corresponding v1.24/v1.25 fix
  reverted. A test that has never been red is not evidence.
- §A's population numbers are re-measured against the shipped corpus at build time, not quoted
  from this document — and **the new gate's own skipped population is computed and printed**,
  not asserted to be empty.
- `check_vocab_diff` is clean under the manifest — **three entries if `n1-b045` is re-measured, two
  if it is deferred** — and its 18 probes behave. Note the guard silently de-duplicates manifest ids
  (v1.25 declared 71 entries, 69 unique); at this size that is harmless, but do not rely on it.
- The dictation exclusion list is diffed before and after §A's corrections, and any change is
  explained rather than absorbed. **`n1-b045` ships only with a fresh measurement behind it** — if
  `sudachipy` is not installed, it does not ship, and the plan says so rather than the release
  quietly dropping it.
- No `Sources/**/* [0-9]*.swift` duplicates.
- The pre-submission adversarial review has run and its blockers are fixed.
- `scripts/launch_gate.sh` passes on the archive that was actually **uploaded**, not one built
  beside it.
- The What's New copy's numbers are checked against the corpus, not against this plan.
