# PLAN-V1.32 — features, two live defects, and the gates that cannot fail

Written 2026-09-10, the day after §K's day 0. Grounded in a six-reader survey (`wf_204bc61e-7be`,
112 items) and **rewritten after two adversarial reviews** (Gemini 3.1 Pro, Gemini 3.8 Flash) that
between them refuted eight of its claims, including its entire opening premise. §J records what
they changed.

---

## §A What this stage is — and the mistake this file made first

> ### ⚠ The first draft of this file repeated an error the owner already corrected, in writing, on 2026-08-31
>
> It opened by arguing that because §K's window freezes the price, the offer, the placement and the
> store metadata, that *"removes most product work from the table for ~90 days"* and this stage is
> internal work *"because the window forbids the alternative"*.
>
> **`PLAN-WINDOW.md:99-131` had already ruled on exactly that framing, against it.** The owner's
> response to that draft was *"I'd rather build more features"*, and the recorded correction is
> structural, not a matter of taste: the measurement is a purchase count pulled by
> `sales_report.py`. **It costs zero engineering, it runs whether anybody writes code or not, and
> no feature work makes it arrive later or noisier.** Build and measure do not compete for the same
> 90 days.
>
> The real constraints are four and they are narrow — offer/price/placement, permanently-free,
> register anything that changes ride distance, and no store-metadata changes for en-US/zh-Hans/ja.
> **Everything else — modes, review scheduling, stats, widgets, UI, accessibility, content — is
> open.** Written at the top because a plan that silently re-derives a rejected premise is worse
> than one that never had it.

So this stage has **two tracks that run together**, and the feature track is not the junior one.

The hardening track earns its place on its own merits rather than on a false scarcity, because the
survey found this repo's signature defect — *a guard stated in prose that nothing enforces, a
control that cannot fail* — **inside its own gates**. That is worth doing now regardless of what
the window permits.

---

## §B Track 1 — features · *the half the owner asked for*

Both reviewers attacked the first draft for having no feature content. They were right, and so was
`PLAN-WINDOW`'s correction.

### F1 — the underexposed-feature audit · *days*

`PLAN-ITERATION.md:457-461` names this as the next work item and it has never been done.
`DiagnosticsKit`/`StumbledWords`, a widget, a reminder scheduler, a share card, a coach view, six
modes and 22 directories under `Sources/` are **already built**. The question is which of them
nobody ever sees.

This is cheap, it is the kind of thing that only comes from using the app, and it produces the
backlog the next several releases run on. Do it before committing to F2.

### F2 — analyse which token a learner actually stumbles on · *week+*

The survey flags it as open: *nothing analyses which token a learner stumbles on, though
`DiagnosticsKit` exists.* The data is already collected locally and already feeds `ResultsView`.
This is the largest genuinely-new feature available that touches none of the four constraints.

**Constraint 3 applies**: if it changes how far people ride, **register it in `PLAN-STAGE1` §K
before the release ships — do not avoid it.**

---

## §C Track 2 — the two live defects

### C1 — `conjugationDueCount` counts a card the drill cannot clear · *hours*

**The first draft misdiagnosed this and the review corrected it.** The defect is real; its
mechanism is not what was written.

`ConjugationReviewStore.dueCards`/`dueCount` (`:47-62`) filter on `dueDate` and `resolves(sourceID)`
and never parse `formToken`. `ConjugationSession` (`:484-505`) drops a due card whose token is not a
`ConjugationForm` raw value — **but then backfills the slot with a fresh weak-form prompt**, so the
run is not short. And `MenuView:255` gates *visibility* on `conjugationDueCount` while the label the
user reads is `conjugationReviewButtonText` → `conjugationReviewQueue.count` (`AppModel:1885, :2037`).

**So the real failure mode is a permanently-due card that no review can clear**, keeping the button
visible forever with nothing behind it — not a short run and not a wrong number on the button.

> **Do not "make one predicate the source of truth" as the first draft said.**
> `ConjugationReviewKit` is a deliberately zero-dependency kit (`Package.swift:135`,
> `HANDOFF-V1.8-PROMPT.md:29`) and cannot import `ConjugationKit` to reach `ConjugationForm`.
> The fix is an **injected validator closure** from `AppModel`, or nothing.

Reachable only because no `ConjugationForm` case has ever been removed or renamed — a property of
history, not of the code.

> ### ✅ DONE 2026-09-10 (`331d85a`) — and this section was wrong about the scope, the door and the fix
>
> Kept unedited above, because a plan quietly reworded after it is executed stops being a record of
> what was believed. Four corrections, in the order they cost time:
>
> **1. It is six readouts, not one.** The same unfiltered count feeds the menu button, the run's own
> label, the Stats forecast (`dueForecast`), "N tough forms" (`leeches`), the home-screen widget
> (`dueByDay`) and the **app-icon badge** (`ReminderScheduler`). The badge was found by the
> *compiler*, not by the sweep that listed the other five — making the new parameter required is
> what turned "remember every call site" into a build failure. This is v1.22's *"a fix applied to
> one call site is not a fix"* arriving on the same store a second time.
>
> **2. "Nothing behind it" is false.** `makeReview` backfills, so the run is a full twelve real
> prompts. The harm is different and worse: the stranded card **displaces** a genuinely due one out
> of the twelve, because it only grows more overdue and therefore sorts first.
>
> **3. The reachable door is not a renamed enum case.** `ConjugationPrompt.init?` is *failable* and
> fails for an entry that exists and a token that parses: `verbClass` reads the corpus's opaque `vc`
> field, and `Conjugator` fails per-form on a reading whose class has no stem for it. **A corpus
> edit can strand a card whose verb is perfectly present.** Measured over all 56 corpus commits:
> `780d40d` (v1.14) changed three entries' `vc` — `n1-b479`, `n2-g040`, `n2-g058`, all
> `godan_u` → `suru`. They landed on a class that conjugates every form, so nothing stranded;
> nothing about the edit made that the likely outcome. The corpus is edited most releases.
>
> **4. The fix this section specified would have missed that door.** An injected *token* validator
> — the shape §C1 asks for, and what the survey recommended as `formResolves:` — cannot express
> conjugability, which is a property of the (entry, form) **pair**. The shipped fix injects
> `ConjugationSession.reviewPrompt(entryID:formToken:vocab:languageCode:)`, extracted from
> `makeReview`'s own skip, so the count and the run **share the function** instead of agreeing with
> each other. Mutation **M8** is exactly the token-only re-derivation: it passes every arithmetic
> assertion in the suite and the shared-predicate test kills it.
>
> `reviewedCount` deliberately keeps counting a stranded card — "forms practised" is history, and
> the learner did practise it. Asserted, not left to a comment.
>
> Evidence: **8/8 behaviour mutations and 3/3 gate mutations killed**; `swift test` 693. The first
> mutation harness reported 4/8 survivors with every mutation at exit 1, because it asked one suite
> about another suite's test name — a broken instrument inside the harness written to enforce that
> rule. And the paired control caught the *test's* own defect first: its "conjugable" arm used あかい
> with an `ichidan` class, which needs a る ending, so both arms measured the same thing.
>
> Two gates strengthened rather than merely extended: the declaration rule now requires the new
> predicate (declared **and** called) on outstanding-work counts, and the anti-default rule was
> re-keyed from the *name* `resolves` to the *structure* (`-> Bool` closure with an `=`), which is
> what a second predicate needed and what a third will inherit.

### C2 — the iCloud card can show the toggle ON above the word "Off" · *hours, and probably a decision not a fix*

`AppModel:730` sets `syncStatus = .off` while `iCloudSyncEnabled` stays true;
`SettingsView:63/:230` render the contradiction. This was examined and deliberately left in the
v1.31 pass (`PLAN-ITERATION.md:387-393`).

**A reviewer argues it is busywork**: the divergence needs CloudKit to be unconstructible, which on
a real device is the `.noAccount` path that already has its own message. That is a strong argument
and it may be right. **Re-check it once; if it holds, close the item in writing rather than leaving
it to be re-examined a fourth time.** The cost here is the re-examination, not the fix.

> ### ✅ CLOSED 2026-09-10, on the fourth examination. Not reachable in a shipped build — and the reviewer's REASON was wrong, which is why it kept reopening.
>
> **The conclusion holds. The mechanism everyone kept writing down does not**, and that is the part
> worth recording: three examinations agreed on an answer while describing a path the code does not
> have, so each one left the next reader with nothing to check.
>
> **The enumeration, and why it is complete.** `syncStatus` is `private(set)`
> (`AppModel.swift:302`), so the only writers are inside `AppModel.swift` plus the one door it
> opens, `updateSyncStatus` (`:1141`). That is a *structural* argument, not a grep — which matters,
> because a grep here is exactly the instrument that would answer for a population smaller than the
> question. Six writes:
>
> | line | writes `.off` when | `iCloudSyncEnabled` there | reachable in a shipped app |
> |---|---|---|---|
> | `:302` | the declaration default | — | overwritten inside `init` before any view body reads it |
> | `:723` | `!cloudSyncAvailable` | true | **no** — `static let cloudSyncAvailable = true` (`:705`), and `SettingsView:61` hides the whole card when it is false |
> | `:728` | `!currentIsolation.syncAllowed` | true | **no** — UI test, capture, or layout harness only (`:782-810`) |
> | `:731` | `CloudKitSyncController(model:)` returned nil | true | **no** — see below |
> | `:729`, `:747` | the user turned the toggle off | **false** | yes, and honest |
>
> So the contradiction is `:728` and `:731`, and both need a launch that is not the App Store's.
>
> **What `init?` actually consults** (`CloudKitSyncController.swift:71-72`) is
> `Bundle.main.bundleIdentifier != nil` and `!Screenshotter.isCapturing` — **it never asks about an
> iCloud account, and `CKContainer(identifier:)` is constructed unconditionally.** So "CloudKit is
> unconstructible" is not a state this code can be in, and `.noAccount` is not that path: it comes
> from an already-running controller, via `CKError.notAuthenticated` (`:578`) or a `.signOut` event
> (`:524`). The capture half of `:731` is dead too — `currentIsolation` reads the same
> `Screenshotter.isCapturing` (`:814`) and the capture branch sets `syncAllowed: false` (`:804`),
> so `:728` fires first.
>
> **The controller can never write `.off` at all.** All eight `updateSyncStatus` call sites pass
> `.syncing`, `.synced`, `.waiting`, `.noAccount` or `Self.status(for:)`, and `status(for:)`
> (`:575-586`) returns only `.noAccount`, `.waiting` or `.error(...)`. A real device with a real
> account problem therefore reads "Not signed in to iCloud", "Waiting to sync…" or "Sync error: …"
> — **never "Off"**.
>
> **Two things fixed rather than filed.** The comment on `:731` said *"CloudKit unavailable (dev /
> no entitlement)"*. Both halves are wrong, and a wrong comment at the exact line under examination
> is a good part of why this item kept coming back — a reader checks the comment, it names a
> production-sounding cause, and the item reopens. It now says what the guard does.
> (`project.yml:447-450` records, as measured, that a missing iCloud entitlement makes
> `CKContainer.init` **trap** — the process dies well before this line. That is a recorded
> measurement in a comment, not re-run here, and it is cited as such.)
>
> **What would reopen this** — stated so the close has an expiry rather than being permanent by
> omission:
> 1. `init?` gaining an availability/account check, which would make `:731` a production path.
> 2. `cloudSyncAvailable` becoming anything other than `true`.
> 3. Any new `syncStatus = .off` write, or `updateSyncStatus` being passed `.off` from the
>    controller.
>
> **And a trap for whoever "fixes" it anyway:** `AppModelTests.swift:476` asserts
> `model.syncStatus == .off` for a UI-test launch and is load-bearing — it is the assertion that
> proves an isolated launch does not start CloudKit. Making the harness stop showing `.off` breaks
> the guard that keeps test runs out of the owner's real iCloud database.

---

## §D Track 3 — the gates, in severity × probability order

The first draft led with the entitlement seam. **Both reviewers said that is the wrong first item**
— it is unreachable unless someone regresses a specific line — and both ranked the untested
data-merge paths above it, because a dropped field in a CloudKit converter corrupts user data
across every device and passes every gate in the repo. They are right. Reordered.

### D1 — testability seams first, because D2/D3 are impossible without them · *days*

A review found the sequencing inverted. Three of the proposed tests **cannot compile today**:

* `CloudKitSyncController`'s six converter pairs are `private nonisolated static` (`:603-754`) —
  unreachable from any test without a visibility change.
* `AppModel.syncController` is private and `currentIsolation.syncAllowed` is false in every test
  (`:727`), so `syncController` is **always nil** under test. The rule "a failed save must not queue
  the change for CloudKit" cannot be asserted at all until a seam exists — today you could delete
  `AppModel:1598` and the suite stays green.
* `ReminderScheduler.body` is `private` (`:94`).

**Do this first and do it deliberately**: widen only what a test needs, and prefer an injected seam
over `internal` where the repo already has that pattern.

### D2 — `CloudKitSyncController` round-trip tests · *days*

756 lines, zero tests: six `fill`/decode pairs, the `serverRecordChanged` merge that guards against
clobbering a newer remote `lastReviewed` (`:427-462`), the `.unknownItem` cache-drop, the
zone-deleted rebuild. `check_prod_schema.sh:31-36` proves the **field names** exist in Production
and says nothing about whether a value round-trips. **A converter that wrote the wrong type or
dropped a field would pass every gate in this repo.** No CloudKit account needed.

### D3 — `AppModel.applyCloudChanges` · *days*

`:1155-1215`, called by no test, and its comments encode three shipped defects: tombstone compaction
only after a cloud merge (v1.10 §A3), reminders rescheduled after **both** SRS merges (v1.14 §B),
widget republished when the journal or odometer branch fires alone (v1.12 §C). All three assertable
once D1 lands.

### D4 — the two debug-seam negative controls · *hours*

`EntitlementSeamTests`' control (`:56-75`) re-implements the scanner **without** the `#else` rule the
real scanner has (`:39-42`). Same pair at `:128`, `:159-177`.

> **The first draft's acceptance criterion was impossible and the review caught it.** It said
> "delete the `#else` rule and the control must go red". It cannot: the planted sample
> (`:59-65`) contains **no `#else` block at all**, so pointing the control at the real scanner still
> leaves it green.
>
> **The repair therefore has two halves, and the second is the one that matters:** call the real
> scanner, *and* rewrite the planted sample to hide a seam inside an `#else` branch. Acceptance is
> the mutation: delete the `#else` rule, watch the control go red, restore, watch it pass. Record
> both in the commit.

### D5 — the orphaned iOS UI tests · *days, not hours*

**Five** test methods, not four: `TouchFlowTests` (3), `StumbledWordsFlowTests` (1),
`StoreScreenshotTests` (1). `run_ios_placement_tests.sh:73` restricts to `PaidRouteRowTests`.

Three corrections the reviews forced:

1. **The first draft misattributed the script's header.** `run_ios_placement_tests.sh:6-13` is about
   `testAnOwnedDeviceStillSeesTheRowAndStillHasRestore` and **App Review 3.1.1** (Restore Purchases
   rendered only `if !entitled`), not about `TouchFlowTests`. `TouchFlowTests` is separately about
   **rejection 2.1(a)**, per its own header.
2. **`TouchFlowTests` needs an iPad simulator** (`:3-12`) — running it on the iPhone 17 Pro clone
   the placement gate uses would defeat its purpose entirely.
3. **Size it as days.** These were written 2026-06-10 and have never run. XCUITest against a view
   hierarchy that has moved through six releases will not pass first try, and the software-keyboard
   precondition (`ConnectHardwareKeyboard` off) has to be asserted rather than assumed.

### D6 — one aggregate entry point, and **no git hook** · *hours*

`scripts/run_all_gates.sh` calling `swift test`, the four python self-tests (all currently run by
nothing), `check_versions.py`, `check_vocab_diff.py --manifest`, and `run_store_gates.sh` — the last
**accepting exit 3 as its documented no-coverage state, never absorbing it into a green**.

> **The pre-push hook is dropped.** Both reviewers attacked it and the arguments are decisive:
> a 4–8 minute hook gets `--no-verify`'d, which is worse than no hook because it looks like
> coverage; `.git/hooks` is global to a working tree that **multiple agent sessions share**; and
> two concurrent `xcodebuild test` runs fight over one simulator and manufacture failures shaped
> like real defects — measured, `742c38e`.
>
> One reviewer argues the real answer is CI as a service, since agents will not reliably run local
> scripts. That is probably right and it is **an owner decision, not this plan's** — recorded in §H.

**Correction to the first draft's claim that "every gate is a person remembering":** overstated.
`check_prod_schema.sh` is hardwired into both upload paths (`build-appstore.sh:52`,
`build-appstore-ios.sh:41`) and fails the build. The claim is true of the *test* gates, not of all
of them.

---

> ### ✅ §D5 DONE 2026-09-10 — all 13 methods run, and three of the plan's claims were wrong
>
> The script ran 8 of the target's 13 methods. It now runs all of them, across **two destinations**,
> and every one passes: iPhone 9/9 (`PaidRouteRowTests` + `StumbledWordsFlowTests`), iPad 3/3
> (`TouchFlowTests`), plus `StoreScreenshotTests` opt-in behind `--with-screenshots`.
>
> **1. "They have never run" is false.** `f311520` (2026-08-25) records *"Full iOS UI target:
> 4 passed, 1 skipped, exit 0"*. The drift window is 26 app-layer commits, not six releases — the
> difference between an audit and a diff, and why this took hours rather than the days §D5 sized.
>
> **2. The predicted iPad regression does not exist.** The survey expected `c66e338`'s
> GeometryReader+ScrollView on the non-phone branch to break `TouchFlowTests`. It passed 3/3 on
> the first honest run. The adversarial verifier had already said why: the iPhone branch has had a
> ScrollView the whole time, so the mechanism fails its own negative control.
>
> **3. Two real breakages WERE in the window, and neither was the one predicted.**
> `StumbledWordsFlowTests` indexed `element(boundBy: 2)` into whichever of five conditional
> segmented controls happened to render; `StoreScreenshotTests` asked for a button INSIDE a button,
> left over from when the mode row was a segmented control — eleven lines under the comment block
> that diagnoses that very change and says *"a fix applied to one call site is not a fix"*. Both
> fixed and both now proven by execution, not by reading: the screenshot walk's log carries
> `Tap "Journey" Button`.
>
> **4. And the harness gained the preconditions §D5 asked for — minus one that was wrong.** Device
> exists, nobody else is driving it, software keyboard, `caffeinate` present and still wrapping the
> run. A fifth check refused to start with the console locked; **measured, that is not a hazard** —
> the suite passes with the screen locked AND the display asleep, because `caffeinate` is what does
> the work. Blocking every locked-screen run would have disabled the gate for its normal operating
> condition in an agent-driven repo. Recorded in `STATE-2026-08-18.md`.

## §E Carried, honestly bounded

* **Accessibility** (v1.26 §E). **Answer the comparator question before scheduling the work** —
  `md5` is not a valid comparator, and the harness reaches 5 screens while 94 `scaledSystemFont`
  occurrences sit in 7 it cannot. The unblocked first step is the **static scan**, which needs no
  comparator. Measured and unfixed: Ride Log *and* Review Forecast rows run off the right edge at
  AX5 (`PLAN-ITERATION.md:328-334`).
* **The 112 sentences no reading gate inspects** (`PLAN-ITERATION.md:497`). Two limits up front: the
  ratchet cannot detect a gate being *weakened*, and this population is defined by what every gate
  skips, so it cannot be validated by what it catches.
* **iOS StoreKit coverage.** `SKTestSession` is inert for this bundle id (`SKInternalErrorDomain
  Code=3`) and its initialiser does not throw. A reviewer argues the plan should investigate *why*
  rather than accept a permanent blind spot on the only code that makes money — a fair challenge,
  and it is worth one bounded timebox. Meanwhile: **re-check on every toolchain bump, never weaken
  the skip, and add a dated line to §J each time**, so "still broken" is a measurement with a date.
* **`n5-kazoku`** stays flagged; the arbiter refuses to settle 四人 and both candidates are far.

---

## §F Sequencing, because four items touch one file

`AppModel.swift` is 2,465 lines and appears in **C1, C2, D1 and D3**, all with tests landing in
`Tests/NihongoRideAppTests/AppModelTests.swift`. Staging them as separate sequential milestones
invites repeated conflict, especially with concurrent sessions in one tree.

**Order:** D1 (seams) → C1 + C2 + D3 as **one AppModel pass** → D2 → D4 → D6 → D5.
F1 runs alongside from the start; it touches none of these files.

---

## §G Ongoing, and one thing that is not ongoing but blocking

* **Checkpoints.** N = 35 (~2026-09-26), N = 100 (~2026-10-29), interim record 2026-12-08, decision
  at N = 200 or 2027-03-08. Carry the **+114 legacy-base ceiling** on the N = 35 and N = 100 rows.
* **Release dates**, taking macOS 1.31's from `submittedDate` — the version record says 08-31
  because it was reused.
* **Store reviews**: any negative mention of the purchase is a stop-and-fix regardless of units.

> ### The day-0 calibration purchase is not a side-note, and the first draft filed it as one
>
> A reviewer put this sharply and it is correct: **`sales_report.py` prints "zero is a RESULT only
> if calibration passed", and calibration has not been done.** Until the owner makes one real ¥10
> purchase in production, confirms `--calibrate` reports it, refunds it and records the date, the
> chain StoreKit → Apple's report → `sales_report.py` has never been shown capable of reporting a
> non-zero. **A 90-day window whose instrument was never proven able to move produces an
> uninterpretable result no matter how much engineering happens beside it.**
>
> It is late already. It belongs above every item in this plan.

---

## §H Owner-only

1. **§K's day-0 known-positive purchase** — see the box above. Late.
2. **§L's three manual gates** — signed-out account · Family Sharing non-inheritance · macOS ↔ iOS
   cross-platform restore. The cheap window closed when both platforms went live.
3. ~~**CI as a service** — whether to adopt it.~~ **DECIDED 2026-09-10: adopt, in two phases.**
   Second opinions taken from Gemini 3.7 Flash and Codex, read-only against the tree; they
   converged on the same hybrid from different starting points. Phase 1 shipped:
   `.github/workflows/gates.yml` runs `scripts/run_all_gates.sh --headless` on `macos-26`.
   * **Why the split is the decision rather than a limitation.** Headless logic and data gates run
     hosted; anything needing a booted simulator, the login keychain, an Apple credential or a
     signed `.app` stays local at the release boundary, where those things exist. Neither
     consultant argued for moving signing or production credentials into CI.
   * **Phase 2 (the iOS placement XCUITests) is deferred, and the reason is narrow.** Codex argued
     for including them now, and the argument is good — hosted isolation is exactly what fixes the
     shared-simulator collisions this repo has measured. But those tests assert HIT REGIONS, so the
     simulator model is part of the instrument, and a runner image on a different device turns the
     gate red for an environmental reason. A gate that goes red without a defect teaches everyone
     to ignore red. Phase 2 lands once phase 1 has been green for a couple of weeks and the image
     is confirmed to carry an iPhone 17 Pro.
   * **One trap the consult caught that a generic answer would not have.** `check_vocab_diff.py`
     defaults to `--base HEAD`. On a clean CI checkout that compares HEAD with itself and is green
     whatever the commit changed — this repo's oldest defect, arriving in CI. The workflow computes
     an explicit base and fails if it does not resolve; `run_all_gates.sh` gained `--vocab-base`
     and refuses a base that is not a commit. `fetch-depth: 0` is likewise required rather than
     cautious: `test_check_vocab_diff.py` replays four historical commits and their parents.
   * **`.claude/` was not in `.gitignore`** — found while checking what a checkout would carry.
     Nothing under it was tracked, but nothing stopped it while several sessions ran `git add -A`.
     Fixed in the same pass.
   * The remote (`JasonYeYuhe/nihongo-ride-app`, verified **private**) was 147 commits behind, so
     adopting CI meant pushing three weeks of history. Owner authorised it.
4. `ta_score`'s `totalPlayerCount` — physical device, before anything is built on leaderboards.

---

## §I Explicitly not in this stage

* The price, the offer, the placement, the store metadata for en-US/zh-Hans/ja.
* **A second SKU.** `UnlockOfferLedger.counts` has no product dimension; splitting it is a
  prerequisite and must never ship in the same release as a second offer.
* **Any transmitted telemetry.** `Data Not Collected` stays; local counters are fine — the
  prohibition is on collection, not counting.
* **The expensive half of F1** (SRS, sync and translation for pasted text) and
  **`recallAllowanceSeconds` re-derivation** — both need usage data the app deliberately never
  transmits.
* **`CountLabelTests` re-pointing.** Dropped, not deferred: it is architecturally impossible as the
  first draft wrote it (`NotificationKitTests` depends only on `NotificationKit`, `Package.swift:113`
  — it cannot import the app target) *and* both reviewers called it busywork on a stable 23-line
  file. If it is ever done, it means moving the test, not adding an import.
* **`AppGroup.identifier` consistency test.** Demoted from the first draft: a reviewer notes the
  value has been stable since v1.11 and is not under modification. The four-way invariant is real
  (`AppGroup.swift:6-19`, `project.yml:86/197/308/342`) — revisit if anything touches it.

---

## §J What the two reviews changed, kept in the house style

Both were run read-only against the working tree at `d3744d2`; the tree was verified unchanged
afterwards.

**Refuted, and the plan changed:**

1. **The opening premise.** The window does not forbid feature work; the owner corrected exactly
   this on 2026-08-31 and this file re-derived it. Restructured into two tracks. *(Flash)*
2. **D4's acceptance criterion was unachievable** — the planted sample has no `#else`, so repairing
   the control is necessary and not sufficient. *(Pro, confirmed by reading `:59-65`)*
3. **Priority inverted.** Hypothetical seam regression was first; live defects and data-corruption
   risk are now. *(Both)*
4. **C1 misdiagnosed.** `makeReview` backfills, the button reads the queue not the count, and
   `ConjugationReviewKit`'s zero-dependency rule forbids the proposed fix. *(Flash)*
5. **A4 impossible and busywork** — dropped. *(Flash for the mechanism, both for the value)*
6. **"Every gate is a person remembering" overstated** — `check_prod_schema.sh` is wired into both
   upload paths. *(Flash)*
7. **The orphaned-test item was wrong three ways** — five methods not four, a misattributed header
   quote (3.1.1 vs 2.1(a)), and an iPad requirement the proposed fix would have broken. Resized to
   days. *(Flash for 1–3, Pro for the sizing)*
8. **The pre-push hook dropped**, and CI raised as an owner decision. *(Both)*
9. **Sequencing inverted** — the testability seams must precede the tests that need them. *(Flash)*
10. **A phantom citation removed** — `PLAN-WINDOW` has no §L; it ends at §J. *(Flash)*

**Not accepted:** the argument that C2 is pure busywork. It may well be, and the plan now says so —
but the item is *one re-check and a written close*, and leaving it unclosed is what guarantees a
fourth examination.

---

## §K How this plan could still be wrong

* **If F1's audit finds nothing underexposed.** Then the feature track has no cheap start and F2
  becomes the whole of it — a much bigger commitment, and worth re-deciding rather than drifting
  into.
* **If D1's seams widen more than a test needs.** Widening visibility to make tests compile is how a
  codebase's boundaries erode one `internal` at a time. If a seam looks like it wants three
  declarations opened, stop and inject instead.
* **If the day-0 calibration comes back negative** — i.e. a real purchase does *not* appear in
  `--calibrate`. Then the window is not merely uncalibrated but broken, every item here is
  secondary, and the plan should be suspended until it reports.
