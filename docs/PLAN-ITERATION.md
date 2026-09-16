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
| `run_store_gates.sh` | ~1 min | **exits 3 with zero coverage today.** Run it, but it is not evidence — see `PLAN-STAGE1` §L. **exit 4 is NOT the tolerated state**: it means the harness could not start (the generated scheme lost its `StoreKitConfigurationFileReference`), which is a failure. 65 = a gate genuinely failed. |
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
>
> **Made mechanical 2026-09-17 — a release step, not a reminder.** On the day a version becomes
> available, append its **Pacific** release date(s) to `FIRM_RELEASE_DATES_PT` in
> `scripts/sales_report.py` — one line per platform date if the two platforms differ — taken from the
> store's own release timestamp (`https://itunes.apple.com/lookup?id=6777469778` and
> `…&entity=desktopSoftware`, field `currentVersionReleaseDate`; it only shows the CURRENT version, so
> read it that day). PLAN-STAGE1 §K's "DECIDED 2026-09-17" item 11 builds the checkpoint's second
> release-day control from that list, and `--checkpoint` withholds its bound when a version appears in
> the sales reports with no date recorded. The previous hand-kept list, `RELEASE_DAYS`, went stale for
> three weeks because this was a sentence and not a step.

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

> **FOURTH PASS — the remaining screens.** Results, coach, Stats and Settings, walked at the
> default text size.
>
> **Three of the four are in good shape and it is worth saying so**, because a pass that only
> reports defects gives no sense of the base rate. The results screen carries no purchase
> affordance (the placement discipline holding, seen rather than asserted); the coach screen's
> "Drill 3 words" agrees with its own "across 3 words"; Stats renders cleanly.
>
> **One more of the same family in Settings.** The "Romaji assistance" segmented control shared a
> row with its label, and on a phone that left about sixty points per segment: it read
> **"Hints… / Whe… / Off"**, and "Whe…" does not tell a learner what the middle option is. The
> three words are deliberately identical to the menu's copy — *two spellings of one setting reads
> as two settings*, as the comment there says — so the **layout** yields instead: on a phone the
> picker gets its own full-width row. The options are written once and both layouts render that.
>
> *Looked at and deliberately not changed:* the iCloud card can show the toggle ON above the word
> "Off". That is the sync ENGINE's state, not the setting's, and it only diverges when CloudKit
> is unavailable — which is what the layout harness forces. There is already a dedicated
> `.noAccount` case reading "Not signed in to iCloud" for the one production path that matters.
> Recorded because a contradiction on screen is this repo's signature defect and the next person
> should know it was examined rather than missed.
>
> **The pattern across all five UI defects this pass found is one thing:** a `Text` whose content
> can grow, in a row with no `lineLimit` and no shrink allowance. The JLPT picker was the odd one
> out; the Ride Log capsule, the conjugation HUD, the conjugation form chip and this picker are
> all the same shape. **None is visible to any test this repo can run** — `ImageRenderer` does not
> lay out or shrink text the way a device does — which is precisely why they survived to be found
> by looking, and why "use the app" earned its place as a tier-1 item.

> **FIFTH PASS — Sentence mode, and it found the worst one yet.**
>
> **The typing target was truncated, and stayed truncated as the learner typed.** On a phone,
> 授業でこの新しい辞書を使います。 rendered as 「じゅぎょうでこのあたらしいじしょをつか…」 — and
> once the caret passed the ellipsis **the learner was typing blind**: the kana they still owed
> were off the end, the romaji buffer below was truncated too, and with the software keyboard up
> the card drops the full sentence it otherwise repeats underneath. Verified by typing past the
> cut and watching the caret disappear.
>
> **`PracticeView` fixed exactly this in v1.16 §D**, and its comment states the principle in words
> that apply here verbatim: SwiftUI *"resolved that by putting an ellipsis through the characters
> the learner is supposed to be typing — a typing app hiding the typing target."* **It was applied
> to one of the two screens that show a typing target.** *A fix applied to one call site is not a
> fix* — this repo's own first lesson, twenty releases on.
>
> The root cause is the shape this pass keeps finding, in its sharpest form. `kanaReading`'s doc
> comment says *"iPhone: one concatenated Text so a long reading scales down as a unit"* — correct
> for a WORD, which is the population it was written for in v1.7. v1.18 then sent whole SENTENCES
> through the same view and nobody revisited it: **a component correct for its original population,
> silently wrong on a new one.**
>
> Fixed on both branches: the phone's concatenated `Text` wraps to three lines, and the
> wider-screen per-character `HStack` — which cannot wrap at all and simply clipped — becomes the
> app's own `FlowLayout`, the one already carrying every furigana sentence in the corpus. The
> sentence line and the typed-romaji buffer wrap too. A short word still occupies one line because
> it fits, so the word modes are untouched.
>
> **This one is not cosmetic.** Sentence mode has shipped since v1.18 and Dictation reuses the same
> card.

> **WHAT THE PASS CHECKED AND FOUND CLEAN**, listed because six defect reports without a
> denominator give no sense of the base rate. Dictation gives nothing away before the learner
> asks — no sentence, no reading, no meaning, exactly as its comment promises — and its struggle
> detector fired at exactly three distinct refusals, *offering* the answer rather than injecting
> it; the reveal then shows the romaji, the next key, the sentence with furigana and the
> translation, all fully visible. Word Lists gates its play control on an empty list. Results,
> coach and Stats were clean. Menu, practice and the road screen were verified earlier.
>
> **SIXTH PASS — Time Attack.** The progress pill read **"0/300"** under a "Done" label. 300 is
> the queue `startGame` fills for that mode, and its own comment says what it is: *"plenty for a
> 60s sprint"* — a pool size, not a goal, and one nobody comes within an order of magnitude of in
> sixty seconds. Time Attack now shows a bare count; the timer bar directly above already carries
> that mode's progress.
>
> The rule lives on `GameMode` as `queueLengthIsTheTarget`, beside `hudProgressLabel`, for the
> reason that property's own comment gives: a view choosing this for itself is how the unit
> labels drifted the first time, and *"reverting the call site to a bare 'Words' left the entire
> suite green, because the test can only see this file."* Mutation-proven both ways — a constant
> true kills 4 assertions, a constant false kills 8. No store screenshot carries the Time Attack
> HUD, checked before touching it.
>
> **Not yet walked:** a full Journey ride to its results screen with real data.

The rest of this item is still open:


Tier 1 above is everything I can defend from the repo's own records. **The rest of the backlog
should come from using the app, not from reading it**, and that pass is itself the next work item.
`DiagnosticsKit`/`StumbledWords` is already built and wired to `ResultsView`; there is a widget, a
reminder scheduler, a share card, a coach view, six modes, and 21 kits. The question worth an
afternoon is which of those is underexposed rather than missing.

---

## §C2 What running the app found — v1.32 §F2's card, 2026-09-10

Two defects, one mine and one pre-existing, both on the Stats screen at AX5, and **neither is
visible to any test this repo can run** — `ImageRenderer` does not lay out or shrink text the way
a device does (`ScaledFont.swift` has said so since v1.7). This is the fifth and sixth instance of
the shape v1.31 found four of.

**Mine, and it is a caption that named the wrong population.** The new card printed
*"っ turned up in 7 of your 21 rides."* `StumbleLedger.runsRecorded` counts rides in which the
learner was refused at least once — a clean run folds nothing, deliberately, because an empty trace
is not a run. So a learner who rode fifty times and slipped in twenty-one would read "21 rides",
check the Ride Log, and find fifty. **A number labelled as something it is not**, written by the
session that spent the day cataloguing exactly that. Now *"…of the 21 rides where you slipped"*,
and `theDenominatorIsRidesWithAMistake` pins the FACT rather than the wording, by folding clean
runs and requiring the counter not to move.

**Pre-existing: `dueChip`'s label breaks mid-word at AX5** — "Tomorrow" renders as "Tomorr / ow" in
the Conjugation Review card, which has shipped that way. A `Text` in a row with no `lineLimit` and
no shrink allowance, which is the same sentence all six instances of this share. Fixed with
`lineLimit(1)` + `minimumScaleFactor(0.7)`, and verified on screen at AX5 rather than argued.

**What did NOT need fixing, said because a pass that only reports defects gives no base rate:** the
card's own chip row wraps correctly at AX5 onto two rows with no clipping. That is `FlowLayout`
doing its job — the layout `GameView:719` already reaches for, with its own comment explaining that
an HStack cannot wrap. Reusing the thing that already solved this beat deciding it would fit.

## §D Carried, and not tier 1

* **iOS StoreKit has no automated coverage at all** (`PLAN-STAGE1` §J/§L). The code now carrying
  money is the least-tested in the repo. Not tier 1 only because `SKTestSession` is measurably
  inert here — re-check on every toolchain bump, and it becomes tier 1 the day it works.
* **Accessibility (§E, carried since v1.26).**
* **Corpus:** ~~`n5-kazoku` reads 四人 as よんにん (standard is よにん)~~ — **swept 2026-09-04, and
  the assumption in this line was wrong.** `scripts/check_counter_readings.py` enumerates the 23
  counters that are single lexical items and sweeps all 6,724 sentences carrying an `exKana`.
  **One correction made and one refusal:**
  * **`n2-b304` corrected** — 三日 read as さん+にち in a sentence that means "at least three
    days". `check_forces_reading` puts みっか at DTW **0.00556** against さんにち at **0.06562**,
    with byte-identical proof silent. It independently reproduces that row's OWN v1.29 flag,
    *"三 さん -> み"*, which was filed **undecided** — one of the 522 `PLAN-WINDOW` §D closed with
    *"if a new instrument appears, revisit."* One did.
  * **`n5-kazoku` NOT corrected.** The arbiter's comparative marginally favours the TAUGHT
    reading (0.04290) over よにん (0.04354), and **both are far** — consistent with that row's
    recorded *"人 にん -> ひと"*: the voice is saying a third thing. The line above assumed a
    straightforward correction; it is not one, and it stays flagged.

  **Neither tokenizer can arbitrate this family and that is the point.** Sudachi gives
  四[ヨン]+人[ニン]; `CFStringTokenizer` gives 四[よん]+人[にん]; the corpus agrees with both. Two
  independent implementations agreeing here is **one architectural blind spot seen twice**, not
  two confirmations — STATE's *"a gate and the thing it gates can share a blind spot"*.

  *Calibrated before it was trusted:* the first version matched plain substrings and produced
  **9 hits of which 7 were false positives (78%)** in three causes — a counter absorbed by a
  longer word (真っ二つ, 三日月, 四つ角, 一日中), a substring match (二十日 contains 十日), and one
  wrong expectation (一日 is ついたち only as a DATE, so it is deliberately not enumerated). The
  refined scan finds **2 with 0 false positives against the pre-correction corpus and 1 after**,
  so the refinement removed the noise without losing the known positive.

  The 112 uninspected residue is untouched.
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
record was made, which is within minutes of submission for every row here **except macOS 1.31 —
see the warning below before re-pulling this table.**

> ⚠️ **`createdDate` is no longer a usable proxy for macOS 1.31's submission date, and re-pulling
> this table from ASC will silently get it wrong by seven days.** ASC reports macOS 1.31 as
> `created 2026-08-31`; it was submitted **2026-09-07**. The gap is not Apple's — it is mine.
> macOS 1.30 was withdrawn, and Apple then refuses to create a new version while the previous one
> is `DEVELOPER_REJECTED`, so the 1.30 record was reused by PATCHing its `versionString` to 1.31.
> The record therefore keeps 1.30's creation timestamp. Anything reading this table as a cadence
> series — which §B says day 90 will — must take macOS 1.31's date from the review submission
> (`submittedDate` 2026-09-07T12:37:50Z), not from the version record.
>
> The general form, worth more than the instance: **a reused record carries the old record's
> timestamps.** Any future withdraw-and-resubmit does this again.

| version | created (both platforms within 20 s of each other — **except 1.31**, see below) |
|---|---|
| 1.23 | 2026-08-17 |
| 1.24 | 2026-08-19 |
| 1.25 | 2026-08-22 |
| 1.26 | 2026-08-24 |
| 1.27 | 2026-08-26 |
| 1.28 | 2026-08-27 |
| 1.29 | 2026-08-29 |
| 1.30 | 2026-08-31 |
| 1.31 | iOS submitted **2026-09-05** (build 56, live 09-06); macOS submitted **2026-09-07** (build 55, live 09-09). **Both live 2026-09-09 = §K's day 0.** ASC's `createdDate` says 08-31 for macOS — wrong, see above |

**Superseded on 2026-09-05: the platforms have separated, and this table's header no longer
holds for every row.** Every release from 1.23 to 1.30 shipped both platforms together within
twenty seconds. 1.31 did not, and the reason matters for anything that reads this table as a
cadence series: **macOS 1.30 had then been IN_REVIEW for five days** (submitted 2026-08-31,
still in review on 09-05), and ASC refuses `--metadata` on a platform whose previous version is
in review. iOS was free, so iOS went alone.

The alternative — cancelling the macOS submission so 1.31 could take its place — was considered
and rejected on a fact read from ASC rather than assumed: **that submission carries two items,
`appStoreVersions 1.30` AND `inAppPurchaseVersions`**. Withdrawing it would have pulled the
purchase out of review with it, and the purchase is the app's first non-consumable, which Apple
accepts only riding a version submission. It would also have thrown away five days of queue
position on the hypothesis that the submission was stuck, for which there is no evidence: both
items report `READY_FOR_REVIEW`, with no rejection and no resolution.

So from 1.31 onward, **a row in this table may describe one platform**. Anything computing
exposure-per-install or cadence effects across this boundary has to read the per-platform dates,
not the row.

**2026-09-07 — macOS 1.30 was WITHDRAWN and 1.31 submitted in its place, on the owner's
instruction after the argument against it was put twice.** Recorded with what it actually cost,
because the estimate and the outcome differed in both directions.

*The feared tail did not happen.* The purchase settled to `READY_TO_SUBMIT` within minutes of the
withdrawal — not `MISSING_METADATA`, not `DEVELOPER_ACTION_NEEDED`, and the review screenshot's
odd `uploaded: null` (with `assetDeliveryState: COMPLETE`) turned out not to matter. The
unrecoverable branch that made this look severe was real but did not fire, and it is now an
observed state transition rather than an unknown one.

*Two things did bite, and neither was on the list.*

1. **`asc_release.py` would have submitted macOS 1.31 without the purchase.** `carried` and
   `stage_iap` both decided "already carried" from the purchase's own state string, and
   `IAP_ALREADY_IN` contains `IN_REVIEW`; Apple's cancel is asynchronous, so there is a real
   window where the purchase reads `IN_REVIEW` while belonging to nothing. Fixed in `91e3c87`
   before the withdrawal, and mutation-proven: reverting it makes the harness report
   `SUBMITTED ANYWAY`. Had this shipped, the notes would have advertised a purchase in no review,
   printing OK and exiting 0.
2. **Apple refuses to create a new version while the previous one is `DEVELOPER_REJECTED`** —
   "You cannot create a new version of the App in the current state", which reads like a
   permissions problem and is not. The rejected record is the one to reuse; it simply still
   carried `1.30`, so `find_version` did not recognise it. Resolved by PATCHing its
   `versionString` to `1.31` (the uploaded build's marketing version already said 1.31), with a
   byte-exact read-back. `ensure_version` now detects this case and names the fix instead of
   passing Apple's sentence through.

*What it did not cost:* the description text (0 edits, verified against live), the price, the
offer, the placement, and iOS — 1.31 and 1.30 both stayed `READY_FOR_SALE` throughout.

**MEASURED 2026-09-07, and it changes what macOS 1.30 costs: the Mac shares the dead
entrance.** `Sources/NihongoRideApp/MenuView.swift` compiles into both targets (`project.yml:39`
and `:178`) and `.contentShape(Rectangle())` landed in 1.31, so the question was whether AppKit
hit-tests the strip's empty middle the way UIKit did not. It does not. Synthesized `NSEvent`
clicks over a 15x26 grid, on the entrance's structure, reproduced exactly across two runs:

| variant | live cells | shape |
|---|---|---|
| no `contentShape` (= 1.30) | **53 / 390** | the four emoji, the stop labels, the 2-point connector line, the caption — and a dead band between them |
| `contentShape` (= 1.31) | **168 / 390** | one solid rectangle |

The instrument carries its own control: 53 is not zero, so the events reach the view and a plain
Button is clickable on its glyphs — it is the *gaps* that are dead. An earlier version of this
probe guessed a single caption point, missed it, reported "dead", and looked exactly like the
defect being hunted; the grid exists because of that.

**`NSView.hitTest` cannot see this.** It returns `NSHostingView` for every point in both variants
— SwiftUI renders into one view — so the cheap probe would have passed identically whether the
fix was present or absent. It was two lines from being written as the gate.

This is now `Tests/NihongoRideMacTests/MenuEntranceHitTests.swift`, the **macOS form of the
placement gate that this document recorded as missing**. Two tests, because they are two claims:
`test00` measures the platform behaviour on a reproduction; `test01` reads `MenuView.swift` to
assert the *shipping* entrance still carries the modifier, because a reproduction stays green
after somebody deletes it from the real view. `routePreview` is `private`, which `@testable`
does not reach, so source-reading is the same move `EntitlementSeamTests` already makes — and it
carries the same negative control.

**Consequence for §K.** macOS 1.30's `releaseType` is `AFTER_APPROVAL`, so approval ships it the
same minute, and day 0 starts on a binary whose offer entrance responds on roughly a third of
itself. `menuEntranceAppeared` fires on appearance while `offerAppeared` fires only when the road
screen renders, so those installs return "entrance seen, offer never appeared" — which is
indistinguishable from "saw it and chose not to open it", the exact inference §K's STOP branch
draws. Not a hypothetical heterogeneity; a measured one, on the platform holding the larger half
of the base that can reach Kyōto.

**State on 2026-09-05:** iOS **1.31 WAITING_FOR_REVIEW** (build 56, submitted 09-05) · iOS 1.30
READY_FOR_SALE · macOS **1.30 IN_REVIEW** since 08-31 · the in-app purchase **IN_REVIEW**,
attached to that macOS submission.

Three consequences, and the second is the one with a deadline on it:

1. **v1.31 shipped on iOS and waits on macOS.** iOS 1.31 is WAITING_FOR_REVIEW with build 56;
   the submission carries the version *only* — verified by reading its items back and confirming
   one item against the macOS submission's two, so the count is calibrated rather than assumed.
   macOS 1.31 stays unsubmitted until 1.30 clears; its archive is built (1.31/55) and passed
   `launch_gate.sh`. Note that gate has **no iOS form**: it reads `$APP/Contents/Info.plist` and
   launches the binary on this Mac, which is the macOS bundle layout, so the iOS artifact that
   actually shipped was never launch-tested. The applicable iOS gate is
   `run_ios_placement_tests.sh` (8/8).
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
