# Fast iteration — the backlog, and what actually makes it fast

Written 2026-08-31, after the owner chose speed: *"快速迭代,把功能做得更多更好."*

`PLAN-WINDOW.md` holds the constraints and why they are so few. **This file is the work.** One
rule lives in one place: constraints there, backlog here.

---

## §A The bottleneck is the release, not the ideas — and it is measurable

Every release in this repo currently hand-copies a submit script. Measured on the newest one:

```
scripts/submit_1_30.py     792 lines
  per-release config       162   VERSION, TARGETS, What's New, review notes, description edits
  copied machinery         630   identical every release, retyped or copy-pasted by hand
```

There are **28 such scripts on disk.** The duplication is deliberate in origin — each file is that
release's record, and its docstring carries defects that are *properties of the template* — but the
consequence is that shipping costs an hour of careful, error-prone work before a single line of the
new feature is involved. **v1.30 proved the risk is not theoretical:** its `do_submit` carried the
ordering rule in a comment and not in the code, both platforms went to Apple without the purchase,
and both submissions had to be cancelled and rebuilt.

**Nothing else on this list changes the iteration rate as much as fixing that.** It is also the
safest item here: it touches no app code, so it cannot affect the measurement or a user.

### The gates, and which are load-bearing every time

| gate | cost | every release? |
|---|---|---|
| `swift test` | ~45 s | **yes** |
| `launch_gate.sh` on the uploaded archive | ~20 s | **yes** — it exists because v1.4 shipped a launch crash that only a signed build on an iCloud-signed Mac reproduces |
| build + upload ×2 | ~8 min | **yes** |
| `run_ios_placement_tests.sh` | ~4 min | **only when UI or placement changed** |
| `run_store_gates.sh` | ~1 min | **exits 3 with zero coverage today.** Run it, but it is not evidence — see `PLAN-STAGE1` §L |
| byte-exact read-back of every ASC PATCH | seconds | **yes, always** — it is what caught the star-glyph rejection before review |

---

## §B What still binds (short — the argument is in `PLAN-WINDOW.md`)

1. **Do not touch the offer, the price, or the placement.** Voids the pre-registration.
2. **Do not change store metadata for `en-US` / `zh-Hans` / `ja`.**
3. **A feature that substantially changes how far people ride** moves exposure-per-install.
   Register it; do not avoid it.
4. **Anything shipped free can still be sold later** — `PLAN-V2-PRODUCT` §E's red line is
   *grandfather on `originalAppVersion`*, not *freeze forever*. This is the correction that
   unblocked this whole plan; two external reviews found it independently.

> **And shipping frequently is itself a mild acquisition intervention, so register the cadence.**
> `PLAN-V2-PRODUCT` §L already recorded that **seven releases in fourteen days** coincided with the
> traffic tripling, and deliberately filed it as *one candidate among four* rather than a lever —
> *"it is also the one with a perverse incentive attached."* Fast iteration is now that perverse
> incentive arriving on purpose. **Write the release dates down** so day 90 can see them; do not
> claim the cadence caused anything.

---

## §C The backlog, tier 1 — each of these is days, not weeks

Ranked by visible improvement per day of work, with the risk named.

### 1. Extract the release template (§A) — **DONE 2026-09-01, `scripts/asc_release.py`**

Leave each `submit_<version>.py` as its 162 lines of config, importing the 630 lines of machinery
from one module. **Do not delete the old files** — they are the record of what was sent for each
release. Zero app-code risk. Pays back on every item below.

> **How it was held to the script it was ported from, because a plausible port is the whole
> risk here.** `scripts/test_asc_release.py` drives BOTH `submit_1_30.py` and the extracted
> module against one stateful fake App Store Connect, configured from v1.30's own constants, and
> requires the same calls with the same bodies in the same order, the same failure ledger and the
> same end state — across **eleven scenarios**, not one, because a differential over the happy
> path is a differential over the branch nobody doubted. The matrix deliberately includes the
> branches that have cost something: the purchase that cannot be staged, a description whose
> sentence is no longer there, a store locale the release writes no copy for, one platform
> already in review, an orphan submission container.
>
> **Both comparisons are controlled.** Dropping the byte-exact read-back from the port must make
> the call-log comparison go red; making `fail()` swallow its argument must make the ledger
> comparison go red. Both fire. The end-state comparison is *not* independently controlled and is
> kept as a cheap redundancy rather than as evidence — said out loud because an uncontrolled
> check that passes looks exactly like a controlled one.
>
> **And then against the real thing.** `--dry-run` issues GETs only, so both implementations were
> run against live App Store Connect and their output diffed: **73 lines, identical**, one
> deliberately generalised header aside. That is the half the fake cannot give — that the port's
> endpoint strings are the ones Apple answers.
>
> **One ledger message differs on purpose** (v1.30's text names v1.30) and is *enumerated* in the
> test rather than normalised away by a regex, because a regex tolerant of "any version-shaped
> difference" would also tolerate the next difference, which nobody has read.

**It also closed a rule that had been a comment since v1.5.** `# What's New — MUST NOT contain
the literal star glyph (ASC rejects it)` has ridden along in twenty-plus submit scripts and
`docs/ASC_METADATA.md` records the rejection twice; **nothing had ever checked it.** `preflight`
now does, along with four other contracts that were also only comments — What's New and review
notes against ASC's 4000-character limit (the description was the only field checked), and, new,
**a description edit whose OLD sentence is a substring of its NEW one**, which would re-apply on
every run and grow the paragraph without bound. v1.30's pair happens not to trip that; nothing
stopped the next one from doing so.

*What the star-glyph check does NOT cover, stated because this repo pays for unstated scopes:*
U+2605 is the only glyph this project has **measured** a rejection for, so it is the only one
asserted. Other glyphs ASC may dislike are unmeasured, and this check says nothing about them.

**`iap=` is a required argument with no default.** The gate cannot tell "this release sells
nothing" from "somebody forgot to wire the purchase up", and those must not be the same
keystroke — v1.24 §C's move, applied to the release path.

### 2. The conjugation prompt clock — **DONE 2026-09-01**, a live defect and a visible feature

`ConjugationSRSCard.quality(from:)` grades **every clean answer 5**, because `ConjugationSession`
never supplies a `durationRatio` and the default 1.0 makes `<= 1.5` always true. Measured with an
injected clock advancing 30 s per keystroke — 240 s to type たべます, reported ratio 1.0 — against
a negative control where the identical typing through `GameSession` graded 4. `NoPromptTimingTests`
holds the finding.

**Why it is a feature and not a chore:** the learner's hardest conjugations are being scheduled as
instant recall and leaving the rotation faster than a vocabulary card, and that wrong schedule is
durable and syncs to every device they own. The code already scopes the fix — *a paused prompt
clock, a baseline chosen against data, and the live-WPM readout routed through `RunClock`* — and
the last of those is user-visible.

*Risk:* it rewrites SM-2 schedules. Choose the baseline against data, not intuition; the existing
`secondsPerKanaBaseline` (0.8 s/kana) was calibrated for copying a word the learner can SEE, and a
conjugation prompt is recall plus production.

> **WHAT SHIPPED, AND THE ONE THING THAT COULD NOT BE DONE AS ASKED.**
>
> `PromptClock` — `RunClock` restarted per prompt — is now held by both sessions, so **two
> defects closed with one clock**. `ConjugationSession` supplied no timing at all (every clean
> answer graded 5); `GameSession` supplied *raw wall time*, so a rider who paused mid-word was
> graded on the pause while the ride's own clock had already stopped for it. `PLAN-V1.26` §C
> named that second one as the reason it could not fix the first: *"there is no correct clock to
> copy."* There is now.
>
> `AppModel.pauseRunClock()` drives both clocks from one place, so one signal cannot again reach
> one destination and not the other — and `ConjugationGameView`, which called only
> `resetStruggle()`, now sends its two signals through it as well.
>
> **The baseline is two terms of different evidential status, and that is deliberate.**
> `baseline = allowance + kana × secondsPerKanaBaseline`. The production term applies the
> existing 0.8 s/kana to the task it was actually calibrated on — the learner presses the same
> romaji keys for the same kana as in a ride — which answers the ⚠️ above for that half. The
> **allowance is zero when the answer is on screen** (`assistance == .always`, or a revealed
> prompt), because then there is nothing to recall.
>
> ⚠️ **`recallAllowanceSeconds = 2.0` is a CHOICE and not a measurement, and no amount of care
> makes it one.** `PLAN-V1.26` §C refused this whole item because *"the threshold cannot be
> calibrated with anything in this repo"*, and that is still true: the app transmits no
> telemetry, so no distribution of real prompt times exists anywhere. What made shipping it
> defensible rather than reckless is that **the harm is bounded and asymmetric**, which is
> measured: the ease factor moves +0.100 at q=5 and exactly **0.000** at q=4, so a q=4 cannot
> lower an ease factor — it can only decline to raise one. Too small an allowance costs an
> effortless answer one increment; too large reproduces the defect being fixed. So it errs small.
> **Anyone with real prompt-time data should re-derive it; nothing here should be read as having
> measured it.**
>
> **Mutation-proven, because everything passed first try.** Five mutations, each reverted from a
> file backup rather than `git checkout` (which would have wiped the uncommitted work):
> conjugation timing removed → 11 assertions fail; the ride clock ignoring pause → 4; the
> allowance granted whatever is on screen → 6; the app never pausing the session → 6.
> **The fifth survived, and that is the useful one.** "A restart forgets the app is away" killed
> nothing — the boundary test paused *after* the prompt boundary rather than across it, so it
> asserted the right sentence about the wrong moment and no defect could have broken it. It was
> rewritten around `skip()` (the reachable route: `PracticeView` binds it to Enter and has no
> pause overlay) and backed by `PromptClockTests` at the unit level. It now kills the mutation.
>
> **Registered under §B3.** The HUD gains a live speed pill, on the same width rule as distance
> and accuracy — Mac and iPad only; the phone HUD fits about four pills and cannot reflow. A
> speed readout is the kind of thing that could make people ride further, which moves
> exposure-per-install. Second-order, written down rather than avoided. It reads `RunClock`, so
> it is the same quantity the Ride Log will record, and a pause freezes it rather than letting it
> decay.

### 3. "Type your own text" in Practice — **BUILT 2026-09-01**, the bounded half of F1

The flagship's promise, at a fraction of its cost, because two blockers turned out to be softer
than the plan recorded:

* **There IS an on-device tokenizer.** `PLAN-STAGE1` §N said *"there is no tokenizer on the device
  at all"*; that is false and is now corrected there. `CFStringTokenizer` with a `ja` locale and
  `kCFStringTokenizerAttributeLatinTranscription` returns readings offline, on both platforms,
  with no dependency. Verified by running it.
* **Its quality problem does not bind here.** The same run splits 日本語 into 日本[nippon] +
  語[go] — exactly the compound-splitting this project measured in Sudachi. **But a wrong reading
  in the curated corpus is a *taught error*, while a wrong reading in text the learner pasted is
  visible to them and theirs to correct.** Different standard. Show the reading, let them edit it.

**Scope it so it does not touch SRS.** `SRSCard(id: entryID)` keys review cards on corpus ids, and
`SyncMerge` merges them across devices through CloudKit; giving pasted words card identities is the
expensive, dangerous half of F1 and it is what makes the full feature weeks rather than days. Ship
practice-only first. It already answers the question that matters — *will anyone paste their own
material* — and that answer is what decides whether the SRS half is worth building.

> **THE TOKENIZER IS NOW MEASURED, not asserted — `scripts/measure_tokenizer_readings.swift`,
> `docs/measurements/tokenizer-reading-accuracy.json`.** Against **6,724 corpus sentences whose
> `exKana` went through a three-lens human review** — the best labelled Japanese in reach —
> `CFStringTokenizer` + `.latinToHiragana` gets **96.9% of whole sentences exactly right and
> 99.1% of kana positions**, offline, on both platforms, with no dependency.
>
> **Two findings changed the number, and the second one matters more than the first.**
>
> 1. *Kana tokens must read as themselves.* The naive pipeline scored 88.6%, and most of the gap
>    was the prolonged-sound mark: the corpus writes スープ as すーぷ and the transcription route
>    returns すうぷ. `gen_sentence_kana.py` had already found and documented this **about
>    Sudachi** — *"taking Sudachi's reading here would normalise ー and the small kana away"* — and
>    it is true of `CFStringTokenizer` for the same reason. Applying the repo's existing rule took
>    it to 96.9%.
> 2. **The first version of the measurement was wrong and its positive control could not have
>    said so.** It filtered both sides to U+3041–U+3096, which silently deleted every ー — and
>    the control compared the corpus to *itself through the same filter*, so it read 100% for any
>    normaliser, destructive ones included. The control proved the comparison could tell apart
>    the two things it was handed; it said nothing about whether the right answer survived being
>    handed over. **This is STATE's second family, produced while measuring.** The replacement
>    control asserts a property that can fail — the normaliser deletes nothing but punctuation —
>    and the negative control (surface used as the reading) sits at 0.7%.
>
> **What the 3.1% residue actually is: homograph ambiguity, not breakage.** 私 as わたくし where
> the corpus wrote わたし, 木綿 as もめん where it wrote きわた, 汚れる as よごれる against けがれる,
> 床 as ゆか against とこ. Both readings are real Japanese in every one of those. **The corpus is
> itself inconsistent on 私**, which is the clearest possible statement of what kind of
> disagreement this is. In curated content a wrong reading is a taught error; in text the learner
> pasted it is visible to them and theirs to correct — which is the plan's own argument, now with
> a number behind it.
>
> ⚠️ **What the measurement does NOT cover, stated because this repo pays for unstated scopes:**
> these are short curated sentences built around JLPT vocabulary. News, lyrics, forum posts and
> above all **proper names** are a different population, and 96.9% does not describe them. Names
> are the predictable weak spot and none of this population tests them.

> **WHAT SHIPPED.** `CustomTextKit` — the reading pipeline, a sentence splitter, and a local
> store — plus a three-option Practice source (Passages · Words · **My text**), an editor that
> shows every reading and lets the learner change any of them, and a practice screen that draws
> their sentence with furigana above the line they type.
>
> **It stays outside the SRS by construction, and that is observed rather than asserted.**
> `makeCustomText` runs in `.practice`, where `RunCompletion.persistsSRS` is false; the app-level
> test rides a custom text to completion, checks the review store by **id** for every sentence,
> and carries a control — an ordinary journey run through the same harness that MUST write SRS,
> or the first assertion is about the harness rather than about the feature.
>
> **Four things the tests found that reading the code did not.**
>
> 1. **`ABCを見る。` reads as あぶくをみる.** The transcription leaves Latin alone and
>    `latinToHiragana` then reads it as romaji, so the target is valid kana, perfectly typeable,
>    and a reading of nothing. **A check on the target passes it** — the check has to be on the
>    source. `gen_sentence_kana.py` refuses this exact class for this exact reason and records
>    Sudachi turning 10 into いちれい; the pipeline changed and the failure did not.
> 2. **The splitter broke 「おはよう。」と彼は言った。 in two**, leaving a practice screen showing
>    one clause. Fixed with quote depth.
> 3. **`recordsSRS = false` on the builder looked like belt-and-braces and was a bug.**
>    `RunCompletion` reads `!recordsSRS` as *weak-words cram*, which also switches off ride
>    logging — five hundred characters typed and the road does not move, with nothing saying why.
>    The SRS guarantee comes from the mode, not from that flag.
> 4. **`CustomTextKit` was missing from the app target in `Package.swift` AND from both app
>    targets in `project.yml`.** The first failed at link, loudly. The second would have passed
>    `swift test` completely and failed only when an archive was cut — or on one platform only,
>    which is v1.25's crossed build numbers wearing a module graph. `ModuleDependencyTests` now
>    holds both files against each other, with a floor so a parser that reads nothing cannot
>    report clean — **and that floor immediately caught its own first draft**, which anchored on
>    the `products:` entry instead of the target and parsed one dependency out of nineteen.
>
> **Registered under §B3.** A custom-text run logs a ride like any other practice run, so a
> learner with their own material can ride further than one without. That moves
> exposure-per-install. Second-order, written down rather than avoided.
>
> **The caret and the engine are a count-and-run pair here**, closed by a property rather than by
> inspection: `CustomSentence.hasNoUncountedCharacters` asserts every character of the displayed
> reading is either punctuation or kana with nothing in between, so the view's allow-list and the
> engine's target partition the same string.
>
> **What is NOT built, deliberately:** no SRS cards for pasted words, no CloudKit sync for the
> texts, no translation. The question this answers is *will anyone paste their own material*,
> and that answer is what decides whether the expensive half is worth building.

### 4. Whatever a pass over the app finds — **one pass done 2026-09-01, and it found one**

> **The first thing running the app found was a defect the 674 tests could not see.** With *My
> text* selected, the **JLPT level picker came back** — a control that decides nothing, because a
> custom run draws from the learner's own sentences and never touches a level pool. `MenuView`
> asked `!(mode == .practice && practicePassages)`, and when `practicePassages` narrowed from
> "this practice run is sentence-shaped" to "the BUNDLED passages specifically", the question
> silently changed under it. One name answering two questions, one release after this file's own
> v1.15 §L note about a header claiming every passage was N5.
>
> The predicate moved to `AppModel.showsJLPTPicker` so it could be asserted for every mode and
> source — a `some View` cannot be — with the control that matters: the word stream must KEEP the
> picker, or the suite would pass while a real control disappeared.
>
> **What else the pass verified, in the running app rather than in a test:** the three-way picker,
> the empty state, the add sheet, and the whole guarded path — pasting non-Japanese produced
> *"0 of 1 typeable · the rest contain letters or digits"* on the text and *"Nothing in this text
> can be typed"* on the menu, with the text kept and the queue empty. That is `canRead` and
> `customTextRunCount` firing end to end.
>
> *Harness note for whoever does this next:* the simulator can only type ASCII, and both
> `simctl pbcopy` and `simctl pbsync` mangle UTF-8 into MacRoman, so **Japanese cannot be got into
> the simulator by either route.** The Latin path was exercised by accident because of it. The
> Japanese path is covered by `CustomTextRunTests`, which drives a real session and asserts the
> kana it produces.

> **SECOND PASS, same day, with the app SEEDED so the Japanese path could actually be walked.**
> The harness note above said Japanese cannot be got into the simulator; the way round it is to
> seed the store through **its own writer** (`scripts/`-style throwaway compiled against
> `CustomTextKit`, asserting the seed round-trips before the app ever sees it — the rule that
> exists because a hand-rolled encoder once made a seed load as an empty journal while every
> assertion passed for the wrong reason).
>
> **What that verified, on a real device run rather than in a test:** the sentence renders with
> furigana above the typing line; typing it advances 1/3 → 2/3 → 3/3; the run returns to the menu
> (practice shows no results screen); the Ride Log gains a row and the odometer moves 0.5 km; and
> **`review.json` does not exist at all afterwards** — no `customtext-` id in any persisted
> store. The SRS red line, observed rather than argued.
>
> **And it found a defect I had shipped into the Ride Log.** `JournalView.levelLabel` maps the
> passage lengths to ONE character (S / M / L) because that row is width-constrained, and its
> `default:` passed anything else through raw. v1.31's `level: "custom"` was the first string
> long enough to matter: a six-character capsule squeezed the score, WPM and accuracy columns
> until they wrapped character by character. Fixed with an explicit `MINE` / 自选 **and a cap on
> the default**, which is the durable half — the next level string somebody adds gets an ugly
> label instead of a broken row.
>
> ⚠️ **A finding NOT mine, and the reason it took a while to separate: the simulator was at
> AX5** (`accessibility-extra-extra-extra-large`). At that size the Ride Log does not survive —
> and the evidence that this is pre-existing is that the **Review Forecast** rows, which this
> release never touched, run off the right edge too. At the default size the same screen is
> clean: `Today · MINE · ★651 · WPM 13 · 100%`. `ImageRenderer` cannot see this class of problem
> at all (`ScaledFont.swift` has said so since v1.7), which is exactly why it is Gate E's
> territory and why it survived to be found by looking.
>
> *This also corrected a claim I had already written into the code.* The practice header's
> comment said the truncation was "measured on a phone", which was true and incomplete — it was
> measured at AX5. At the default size `PRACTICE · MY TEXT` fits comfortably. The comment now
> says which.

> **THIRD PASS — the conjugation drill, run for the first time.** v1.31's other headline change
> had never been executed in the app.
>
> **The prompt clock is live, observed in the store the app itself wrote.** Three answers, three
> cards, every one `easeFactor = 2.5` — graded **4**. Before v1.31 every clean answer graded 5
> and would have written 2.6. That is the defect closing, seen from outside the code.
>
> ⚠️ **What could NOT be demonstrated through this harness, stated rather than glossed:** that a
> *pause* excludes its time. The grading budget for a prompt is 1.5 × (2.0 + 0.8 × kana) — about
> 8–12 seconds — and a screenshot-plus-type round trip through the simulator costs comparable
> time, so a q=5 is not reachable here even with the pause working perfectly. The experiment was
> run anyway and came back inconclusive **as predicted in advance**, which is the only reason it
> was worth running. The pause exclusion is proven at the unit level with an injected clock, a
> paired control and a mutation (`PromptTimingTests`).
>
> **Two pre-existing defects on that screen, both phone-only, both found by looking:**
>
> 1. **The HUD wrapped mid-word.** No `lineLimit` anywhere in that row, and "Conjugate" is nine
>    characters where the ride's equivalent pill holds "N5" — so at ★230 the mode capsule read
>    "Conjuga / te" and the progress pill broke into "2/1 / 2". Fixed with `lineLimit(1)` plus a
>    shrink allowance.
> 2. **The form chip truncated the PROMPT.** In English it renders `japaneseLabel / englishLabel`,
>    and the longest of the seven — ない形（否定） / Negative (-nai) — does not fit a phone at
>    18pt. It was showing "… / Negative (…". That is the one string on the screen the learner
>    cannot do without: it names the form they are being asked to produce. Fixed the same way.
>
> Neither is v1.31's doing — the conjugation screen dates from v1.8 — and neither is visible to
> any test the repo can run, because `ImageRenderer` does not lay out or shrink text the way a
> device does. **This is the third and fourth defect this pass has found that only running the
> app could surface**, after the JLPT picker and the Ride Log capsule.

The rest of this item is still open:


Tier 1 above is everything I can defend from the repo's own records. **The rest of the backlog
should come from using the app, not from reading it**, and that pass is itself the next work item.
`DiagnosticsKit`/`StumbledWords` is already built and wired to `ResultsView`; there is a widget, a
reminder scheduler, a share card, a coach view, six modes, and 21 kits. The question worth an
afternoon is which of those is underexposed rather than missing.

---

## §D Carried, and not tier 1

* **iOS StoreKit has no automated coverage at all** (`PLAN-STAGE1` §J/§L). The code now carrying
  money is the least-tested in the repo. Not tier 1 only because `SKTestSession` is measurably
  inert here — re-check on every toolchain bump, and it becomes tier 1 the day it works.
* **Accessibility (§E, carried since v1.26).**
* **Corpus:** `n5-kazoku` reads 四人 as よんにん (standard is よにん); the 112 uninspected residue.
* **NOT the 522 undecided dictation sentences.** `PLAN-V1.29` closed that with a measurement.
* **`ta_score`'s `totalPlayerCount`** — never read since v1.3; one physical-device errand closes a
  class of future proposals.

---

## §E Owner-only, and expiring

Unchanged and repeated because a fast cadence is exactly when these get skipped:

* **`PLAN-STAGE1` §L's three manual purchase gates**, still unwalked. While v1.30 is in review a
  failed gate costs a cancel and a resubmit — minutes, measured. After `READY_FOR_SALE` it costs a
  whole new version with live customers meeting a broken purchase.
* **§K's day-0 known-positive purchase.**
* **Whether to denominate §K's checkpoints by installs rather than dates** — free to decide only
  before day 0.

---

## §H The placement gate was flaky, and the flakiness WAS the defect — **RESOLVED 2026-09-01**

`scripts/run_ios_placement_tests.sh` was failing on the menu-entrance test. It had passed 7/7
three times the same afternoon and then failed six times running, including **at `2722dd1`,
before any of this session's code**. The obvious reading — an unreliable gate on a churned
machine — was wrong, and it took an hour to stop believing it.

**What it actually was: v1.30's second purchase entrance is dead to the touch in its middle, and
has been since it shipped.** The route strip's connectors are `Rectangle().frame(height: 2)`, so
between the four stops there is a two-point line and a great deal of empty space. Empty space in
a SwiftUI stack is not content, and a plain `Button` does not hit-test it. Only the emoji, the
stop labels and the caption row ever responded. **A rider tapping the road itself — the obvious
target — got nothing.** One line fixes it: `.contentShape(Rectangle())` on the label.

**How it was finally cracked, because the method is the transferable part.** Every hypothesis
about the environment died first: simulator state, Dynamic Type at both ends, the UI-test
defaults suite, inter-test contamination, launch timing, tap delivery, this session's code. What
cracked it was tapping **the element's own centre** by hand — `(201, 265)`, the point XCUITest
computes — instead of `(201, 293)`, where I had happened to tap earlier and which had "proved"
the app worked. The centre did nothing; the caption 28 points lower opened The Road. Two taps,
28 points apart, opposite outcomes.

> **The lesson, and it is a new one for this file: a flaky test can be a real defect sampled
> twice.** *`element.tap()` chooses its own point*, so the suite was sampling a button that
> worked on part of its area and not the rest, and reporting the sample. "Passed three times,
> failed six" was not noise around a working feature — it was the *measurement* of a feature that
> works about a third of the time. **The reflex this file has to unlearn is treating
> non-determinism as an environment problem.** It is a signal about the thing under test until
> something rules that out, and here nothing had.
>
> The second habit worth keeping: **my by-hand check "proving the app worked" was itself the
> uncalibrated instrument.** It tapped a point I chose, not the point the failing test chose, and
> it produced a confident wrong conclusion that survived four rounds of investigation.

**Pinned so it cannot come back.** `testTheMenuEntranceIsTappableInItsMiddleAndNotOnlyOnItsText`
taps the centre **explicitly** via `coordinate(withNormalizedOffset:)` — `element.tap()` cannot
pin this property, because the point it is free to choose is exactly the thing being asserted.
Removing `.contentShape` fails that test and only that test. The suite is now 8 tests, exit 0.

> ⚠️ **REGISTERED AGAINST STAGE 1, and the timing is lucky.** This makes the offer's second
> entrance *work*, so more devices will reach the road screen and `offerAppeared` will count more
> events than it would have. That changes the instrument — and **§K's day 0 has not started**
> (macOS 1.30 is still in review and the purchase is not approved), so amending it now is free,
> which it will not be in a week. The alternative — shipping the measurement on an entrance that
> responds on a caption line — would have biased it the other way and been invisible.

---

## §G The release cadence, written down as §B asks

**§B says to record the dates and NOT to claim the cadence caused anything**, because
`PLAN-V2-PRODUCT` §L already filed "seven releases in fourteen days coinciding with the traffic
tripling" as *one candidate among four — and the one with a perverse incentive attached*. Fast
iteration is that incentive arriving on purpose, so the dates are kept where day 90 can see them.

Pulled from App Store Connect on 2026-09-01, not from memory. `created` is when the version
record was made, which is within minutes of submission for every row here.

| version | created (both platforms, within 20 s of each other) |
|---|---|
| 1.23 | 2026-08-17 |
| 1.24 | 2026-08-19 |
| 1.25 | 2026-08-22 |
| 1.26 | 2026-08-24 |
| 1.27 | 2026-08-26 |
| 1.28 | 2026-08-27 |
| 1.29 | 2026-08-29 |
| 1.30 | 2026-08-31 |
| 1.31 | prepared 2026-09-01, **not submitted** — see below |

**State on 2026-09-01, and it moved during the session:** iOS 1.30 is **READY_FOR_SALE**, macOS
1.30 is **IN_REVIEW**, and the in-app purchase is **IN_REVIEW**.

Three consequences, and the second is the one with a deadline on it:

1. **v1.31 cannot be submitted yet.** ASC refuses `--metadata` on a new version while the
   previous one is in review, and macOS 1.30 is. The release is prepared —
   `scripts/submit_1_31.py`, `check_versions.py` green at mac 55 / iOS 56, `--dry-run` clean
   against live ASC — and waits.
2. **§L's manual purchase gates just got more expensive on iOS.** While a version is in review a
   failed gate costs a cancel and a resubmit, measured in minutes. **iOS 1.30 is live**, so on
   that platform a failed gate now costs a whole new version. macOS is still in review. This is
   the asymmetry §H flagged, and half of it has now expired.
3. **§K's day 0 has NOT started.** It counts from *both* platforms being `READY_FOR_SALE`, and
   the purchase itself is still in review — so the offer on live iOS currently shows *"Prices are
   unavailable right now"*, which the app handles as designed and the counter records as
   `offerUnavailable` rather than as an offer nobody took. Verified by reading `RoadView`, not
   assumed.

---

## §F What would make this plan wrong

* **If the release-template extraction turns out to be more than a day.** It is proposed as the
  first item *because* it is cheap; if it is not, it loses its place rather than growing.
* **If practice-only custom text turns out to need SRS to be worth anything.** Then item 3 is not
  the bounded half of F1, it is a stub, and the honest move is to build F1 properly after the
  window rather than ship something nobody returns to.
* **If the cadence itself moves installs.** That would be good news and a confound at once —
  which is why §B says to write the dates down now.
