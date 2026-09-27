# PLAN-V1.34 — the next phase: build for the rider who comes back, keep the window readable, and arrive at day 90 knowing why

Written 2026-09-24 (JST), day 15 of the pre-registered window, a week after v1.33 went on sale. Grounded in
a five-reader survey of the repo and its plans (`wf_df719bc7-168`: backlog, product plan, release record
and lessons, codebase, measurement — 14 agents, every claim quoted to file:line) and a three-angle panel
of candidate plans, each scored by two judges. **Rewritten after two adversarial reviews (Gemini 3.1 Pro,
Gemini 3.8 Flash); §K records what they changed.** This file covers three releases, v1.34 → v1.36,
roughly the six weeks to mid-November; each release still gets its own dated record when it ships.

---

## §A What this phase is — and what the survey said it must not be

**Build and measure do not compete for the same weeks.** `PLAN-WINDOW.md` already ruled on the
"the window forbids product work" framing, against it, and the owner's own words were *"我想多做功能"*.
The measurement is a purchase count pulled by `sales_report.py`; no feature makes it arrive later. What
binds is narrow and is restated in §I so nobody re-derives it: the offer, its price, its placement and
its presentation; en-US/zh-Hans/ja store metadata; register anything that changes how far people ride;
and the two owner-only actions that no agent may perform.

**Three tracks, because three different people are served.**

| track | who it is for | what it is |
|---|---|---|
| **T1 — the rider** | a learner who opened the app today and may or may not tomorrow | visible product work on open surfaces (§B) |
| **T2 — the window** | the person reading §K on the day the decision fires | the bookkeeping and instruments the pre-registration asks for and nobody built (§C) |
| **T3 — day 90** | the same person, deciding what to build next | the one instrument that can say *why* (moderated sessions), and the two documents the decision will need (§D) |

**What the panel found, and this file adopts:** the learner-value plan's best idea is a *passive*
"tomorrow line" — text, no button, no ask — composed once beside the numbers it reports; the
instrument plan's best ideas are a fixed home for checkpoint readings (`docs/measurements/stage1-checkpoints.md`,
committed 2026-09-24 before N = 35 was read), a reader for §K's one real guardrail (a negative purchase
review), and the render tool's honesty fix; the day-90 plan's best idea is registering moderated-session
participants in §K **before** anyone is recruited. Each judge also found the same three mistakes in the
candidates, and they are not repeated here: a system permission dialog placed on the menu one tap after
the rating prompt; §K rules written after a checkpoint has been read; and "proofs" naming renders or
harnesses that do not exist for the screen in question.

**What this phase does NOT try to do:** unlock the withheld bound. Only the owner's §K purchase can
(§H). Everything in T2 is written so that the day the owner walks, the record is ready to receive it.

---

## §B Track 1 — the rider (v1.34, with v1.35's one feature)

Each item: what a learner meets today (quoted to the code), the change, the size in agent-days, the proof,
the risk. Sizes are for implementation; §F budgets review and release separately, from measurement.

### B1 — "Tomorrow, said out loud": the results screen and the Ride Log state the streak and what comes due · *1 day*

`ResultsView` shows the flag, grade, tiles, stumbled words and three buttons — and not one word about the
streak (`RideJournal.streakDays`) or the review forecast (`DueForecast`), although both exist and the
Ride Log already draws both (its `streakCard`, and a three-row forecast card fixed for AX5 in v1.33). A
rider who just finished sees "You've arrived!" and nothing that says *come back tomorrow, 12 words are
due* — on the one screen every ride ends on. **The Ride Log is not touched** (the first draft proposed
replacing its forecast card; the Flash review read the code and it would have duplicated the streak and
discarded a v1.33 fix).

* **Change:** one composer in `AppModel` beside the numbers, `tomorrowLine(zh:)`, read by `ResultsView`
  under the stage line, from the same `dueForecast` and `streakDays` the Ride Log reads. **Text only. No
  button, no reminder prompt, nothing on the rating-prompt path** (`ReviewPrompt` fires on this screen; a
  second ask here is the v1.30 collision on the time axis). **The copy, decided before it is built** (the
  Flash review asked for the edge cases):

  | streak | due tomorrow | en | zh |
  |---|---|---|---|
  | ≥ 2 days | words and forms | "3-day streak · 12 words and 4 forms due tomorrow" | "连续 3 天 · 明天到期 12 个词、4 个变形" |
  | ≥ 2 days | words only / forms only | "3-day streak · 12 words due tomorrow" / "… · 1 form due tomorrow" | "连续 3 天 · 明天到期 12 个词" / "… 1 个变形" |
  | ≥ 2 days | nothing | "3-day streak · nothing due tomorrow" | "连续 3 天 · 明天没有到期的复习" |
  | 1 day (today only) | any | the due half alone: "12 words due tomorrow" | "明天到期 12 个词" |
  | any | any, run typed nothing | *(no line — the run recorded nothing)* | |

  Singular forms in English ("1 word", "1 form", "1-day" never shown); Chinese counts as the tiles do.
  "Tomorrow" is the same Pacific-independent local-day rule `DueForecast` already uses.
* **Proof:** a Swift Testing suite whose expected strings are derived from raw `RideRecord`s with known
  dates, **not** from `streakDays` (memory: a test that grades itself); one mutation per bucket
  (today/tomorrow swapped; streak off by one) shown red; a wiring test in the shape of
  `ReviewPromptWiringTests` driving a real ride through `finishGame` and reading `model.tomorrowLine(zh:)`
  afterwards (not off `lastSummary`, which carries the run and not the calendar) — **and, because a
  model-level test passes while the view draws nothing** (v1.26 §D's lesson, restated by the Pro
  review), the line must be seen: the headless `results.png` render differs from the 1.33 baseline in
  exactly the line's region and nowhere else, a source pin that `ResultsView` calls `tomorrowLine`
  (comment-stripped), and the simulator pass reads the line's text with `inspect`. The line sits in a
  `VStack`, which `HorizontalTextFitTests` deliberately does not scan, so that suite proves nothing here
  (the Flash review's point) — the AX5 simulator pass is the layout proof, and the `Text` still gets a
  `lineLimit` + floor so a long Chinese count cannot break mid-number. Simulator at default and AX5,
  en/zh, on the same 402pt device 1.33 used; a run that typed nothing shows no tomorrow line.
* **Registered under constraint 3:** a line that names tomorrow's due work can only raise days-ridden;
  direction up, magnitude unmeasurable, written in §K's template before `--submit` (§F).
* **Risk:** wrong-denominator copy (v1.32 §C2's class) — the line names *cards due*, never *rides*.

### B2 — Own text, kept: two defects now, two improvements when there is evidence anyone pastes · *0.5 + 1.0 days*

`CustomTextKit` shipped practice-only on purpose (`PLAN-ITERATION` §C3) and the question it exists to
answer — will anyone paste their own material — has no instrument yet (§D). The Pro review's objection
stands for the improvements and not for the defects: **items 2 and 4 are defects a rider who pasted once
already meets and ship in v1.34; items 1 and 3 are improvements and move to v1.35, conditional on
evidence that anyone pastes** — a session tally, or the owner's own report of using it. None is Stage 3,
none touches SRS or sync:

1. *(v1.35, conditional)* **A pasted text cannot be edited; a typo means delete and re-paste, losing every corrected reading**
   (`CustomSentence.source` is `let`, `CustomText.swift:23`; the store exposes add/remove/rename/
   setReading only). Add `edit(id:source:)` that re-splits and re-reads, keeping a corrected reading
   where the sentence is unchanged (by index) and where only its neighbours changed (by surface), and
   dropping it — visibly — where the sentence itself changed. *0.75.* Proof: `CustomTextStoreTests`
   edit → re-read → readings preserved / dropped per rule, mutation red; `JapaneseReadingTests` untouched.
2. **A paste over 20,000 characters or 200 sentences is cut silently** (`CustomText.swift:111-112`; no
   notice in `CustomTextsView`). Say so in the add sheet, with the count kept and dropped. *0.25.*
   Proof: a 201-sentence fixture; the notice string pinned in both languages.
3. *(v1.35, conditional)* **No "Practise this text" from the manager**: after correcting readings the rider closes the sheet,
   reopens the picker, then Starts (`CustomTextsView.swift:154-196` offers only Done). Add the action
   on the detail screen. *0.25.* Proof: `AppModelTests` — the tap selects the id, the next `startGame`
   rides it (assert on the session's `customtext-…` ids).
4. **On macOS a pasted text may have no delete affordance** (`.onDelete` on an unselectable `List`,
   `CustomTextsView.swift:76-81`). **Measure first on the Mac, then fix** with a context-menu Delete and
   a swipe action. *0.25 (0.1 if not real).* **Ordering:** the Mac check runs on a Debug build from a
   worktree — never `/Applications/Nihongo Ride.app` — and the walk card's rule holds: do not run the
   app from Xcode on this Mac before the owner's walk. The check waits for the walk or runs as a
   `swift run` from a worktree, which creates no StoreKit configuration (preflight is re-run after it).

Registered under constraint 3 (a rider with own material rides further; second-order, already registered
for §C3 and repeated). Risk: SRS boundary — every change stays in `.practice`; the app-level test that
rides a custom text and checks the review store by id, with its journey control, stays green.

### B3 — VoiceOver keeps the values 1.33 hid · *0.5 day*

At the accessibility sizes the ride HUD hides the score (Time Attack: the combo), and on iPad also
distance/accuracy/speed — a 1.33 change for large-text riders that took a value away from VoiceOver
riders at the same sizes (`PLAN-V1.33.md` §G, deferred by name). Expose the hidden pills' live values
through the remaining HUD element's `accessibilityValue` (or an accessibility-only element), so VoiceOver
reads "score 891, combo 6, 6 of 12" whichever pills are drawn. Proof: the spoken string is composed by a
pure function with its own table test (every hidden pill's number present, en/zh), and a comment-stripped
source pin that the HUD's `accessibilityValue` reads that function — **not a hosted test of the live
accessibility tree, which `NSHostingView` does not expose without an assistive client** (v1.33 §G measured
that; the Flash review caught the first draft claiming otherwise); the simulator's Accessibility Inspector
at AX5 reading the same tree VoiceOver reads — **stated as what it is, a simulator observation, not a
device one**;
default size byte-identical (the value changes only when a pill is hidden). The device check — VoiceOver
on with the ride HUD at an accessibility size on a physical iPhone — is an owner errand after the walk
(§H), because a development build must not land on a walk device before §L is recorded. Not touching
what is drawn.

### B4 — The small dim text still under 4.5:1, on About only · *0.25 day*

1.33 fixed Settings' captions and About's counter lines; About's footer note (2.79:1), contact line (3.23),
email (3.46) and credit URLs (3.91) are still below the line (`PLAN-V1.33.md` §G). Fix these four at their
call sites with the same computed-contrast test. **Not Settings' sync-status caption (3.91)** — it sits on
the screen that carries the frozen road card, and no headless Settings render exists to prove the card
did not move (1.33's proof for that screen was the simulator, at AX5 only); it waits for a release that
already re-shoots Settings. Proof: `V133SContrastTests` extended; `about.png` differs only in those pixels.

### B5 — Measure, then maybe fix: the Sentence-mode romaji hint on long sentences · *0.25 day*

`PLAN-V1.33.md` §C lists it as unchecked whether the hint scrolls with the cursor. Simulator, a 40-kana
sentence, three cursor positions. Fix only if it does not follow; then a source pin in the V133G shape.

*Addendum 2026-09-27 (review round 3), the decision:* the hint wraps to at most two lines
(`lineLimit(2)`, a 0.45 shrink floor; `V134B5RomajiHintTests` pins the chain). The card does not grow
for the second line, so with the keyboard up at the default size, near the end of a sentence longer than
about 55 romaji characters (88 of the corpus's 6,724 typeable sentences; 24 are longer than 59) the
typed-romaji row loses its second line and clips its last characters. 1.33 clipped the hint instead:
one 14pt line of the 402pt phone's keyboard-up card (354pt) holds 38 characters after the arrow (40 with
the arrow and its space), so 1.33 cut every hint longer than that — 2,540 sentences. Accepted, because
the rider needs the upcoming romaji more than the tail of what they already typed; the kana row's cursor
and the next-key chips stay visible. Revisit if the simulator pass shows the typed row unusable.

### B6 (v1.35) — Build a word list without riding into every word: search the corpus from Word Lists · *2 days, with a cut rule*

Today a list can only be built by meeting a word in a ride or on a results screen (`ListsView.swift:502-503`
says so in its empty-state copy); there is no search over the 7,072-entry corpus and no way to add "the N4
verbs I know I am weak on" before riding. Add a search field on the list detail screen over surface,
reading and gloss, with add-to-this-list on each result. **`VocabStore` has no search today** — its one
index is an exact surface+reading map for resolving lapses (the Flash review corrected the first draft's
"already indexes") — so a `search(_:)` over `surface`, `kana` and `meanings` (substring, kana-folded) is
part of the item. Registered under constraint 3 (a list built up front can be ridden — direction up).
Proof: pure search tests over a fixture (kana, kanji, romaji-hiragana and gloss queries; a mutation red);
a hosted layout test at AX sizes; **a dedicated XCUITest that types into the search field and adds a
result to a list** (the placement suite never visits Word Lists, so it proves nothing about this — it is
run anyway, as §G says for any UI change, to guard the offer's placement); simulator pass. Risk: a text
field on a screen reached from the menu — keyboard focus and Esc handling follow `ListsView`'s existing
rename field.
**Sizing, against the Pro review's "multi-week":** the comparable is `CustomTextKit` — tokenizer, store,
editor and practice screen in one day's 17 commits (2026-09-01) — and the store's indexes already exist;
two days is the budget, and **the cut rule is that if the feature is not green with its tests at the end
of day two it moves whole to v1.36 rather than stretching v1.35.**

---

## §C Track 2 — the window (spread across the three releases; docs and tools, no product change)

### C1 — Checkpoint readings, in one file, verbatim · *done 2026-09-24 (template); 0.25 per reading*

`docs/measurements/stage1-checkpoints.md` was committed before the N = 35 row was read (N = 34 through
Pacific 2026-09-22 that day). Its rules: the tool's lines verbatim, every `BOUND WITHHELD` reason word for
word, **no hand-computed bound while the tool withholds, no branch evaluated**, the owner's confirmation
that walk/session installs are registered before a run, and the earlier readings each entry shares cache
data with. **N = 35** is read the day the row prints "reached" (expected report day 2026-09-23 Pacific,
readable from JST 2026-09-24 ~16:00); **N = 100** is projected 2026-10-19 to 10-29 and lands in v1.35's
window; the **2026-12-08 interim** is written regardless of whether N = 200 (projected 2026-11-29 to
12-14) fired first — §K :425 already says so, and no new §K rule is written after a reading.

### C2 — A reader for the one guardrail with anything behind it · *0.5 day*

§K :567-568: *any new store review mentioning the purchase negatively is a stop-and-fix, regardless of
units* — and nothing in `scripts/` reads reviews. `scripts/review_watch.py`: a read-only ASC GET of
`customerReviews` for app 6777469778 that **prints every review since day 0 on every run** (no high-water
mark that can hide one), flags en/zh/ja purchase vocabulary (purchase, paid, refund, 购买, 付费, 退款,
購入, 課金, 返金), exits 2 (HARNESS ERROR) when the key cannot be loaded — never 0 for "no reviews" it
could not read. **Not a gate in `run_all_gates.sh`:** that runner's contract is "everything that runs
without a device, an account or a signature", and CI has no ASC key. Its fixture self-test
(`scripts/test_review_watch.py`: the one lifetime review as positive control, a 购买 fixture flagged, a
clean fixture not, a missing key → exit 2) **does** join the gates (FLOOR 13 → 14, headless 12 → 13); the
live read is a command run on every release day and every checkpoint day, its output pasted into the
checkpoint entry. Risk: the endpoint shows reviews visible to the API and may lag storefronts — the
output says so.
*2026-09-25: done — `scripts/review_watch.py` and `scripts/test_review_watch.py`; `run_all_gates.sh` FLOOR is 14
(headless 13) from this date. First live read (2026-09-24T15:54Z, read-only): 1 lifetime review, 2026-07-10 PT,
CHN, rating 5, before day 0, body contains 付费; 0 reviews since day 0. The Latin terms match at a word start
("repayment" does not flag), the CJK terms as substrings; the tool reports the READ in its exit code and the
flag in its text, and a person reads "negatively". Same day, after review: the vocabulary is wider than the
list in parentheses above — 收费 (the word the one real review uses twice), 买/買, 有料, 料金, 支払, 解锁, and
buy, bought, charge(d), price, cost, iap, in-app with any of three hyphens; "unpaid"/"prepaid" stay unflagged
by the word-start rule, written down in the tool's header. The collected count is reconciled with the API's
`meta.paging.total` (a mismatch is exit 2), and every failure — including one the tool never anticipated —
is exit 2 with the HARNESS ERROR line: the tool has exactly two exit codes.*

### C3 — The headless render tool stops lying · *0.5 day*

`Screenshot.swift` deletes and reuses one fixed temp directory and settings suite (`AppModel.launchIsolation`
names the same), so two captures at once clobber each other, and `render()` prints "wrote" after a
`try?` that may have failed — both bit v1.33 (its renders had to be re-run sequentially; two agents printed
24 "wrote" lines into a missing directory). Per-process directory and suite derived from the target;
`try` and a non-zero exit naming the path; "wrote" only after the file exists with size > 0. **Proof
order matters, because this tool is the constraint-1 proof for the Road and menu renders:** first the
new tool on the *unchanged* tree must reproduce 1.33's baseline pixel-for-pixel; only then are the
phase's UI diffs rendered with it. Mutations: a read-only target directory exits non-zero with no
"wrote"; two concurrent captures equal a sequential pair. `AppModelTests`' capture-isolation pins
(`supportBase.lastPathComponent == "NihongoRideCapture"`) are updated to the new shape, not weakened —
`touchesNothingOfTheUsers` must still flag capture.

### C4 — Release-day mechanics, every release · *0.1 each*

On the day a version goes on sale: the store's `currentVersionReleaseDate` for both platforms into
`FIRM_RELEASE_DATES_PT` (the tests are now graded under a frozen `FIRM_BASE`, so the line moves no
fixture — `bba723e`), `stage1_walk.py`'s `EXPECTED_*` and the walk card to the new builds, the cadence
table in `PLAN-ITERATION` §G, STATE, memory. **For 1.33 this was done on 2026-09-24, a week late:** no
session was running on release day, and a "release-day step" assumes someone is present. The backstop
held — `--checkpoint` withheld its bound with the registry WARNING until the line existed — and the
next session's first act is the same preflight + checkpoint pair, which is what surfaces a missed line.

### C5 — The second release-day control's 09-17/18 reading, appended honestly · *0.1 day*

`docs/measurements/2026-09-16-release-day-control.md` holds no reading with 1.33's days as exposure
days. Append one (2.55x updates / 1.58x downloads, 12 exposure / 13 other days, as `--checkpoint` printed
on 2026-09-24) — and say in the same paragraph that it is **not blind**: the 2026-09-24 survey run had
already printed it before this file was written (memory: written down first is not blind).

### C6 — Record hygiene the next session inherits · *0.25 day*

`STATE-2026-09-24` read from ASC (done); a dated §L addendum that the App Store build now on sale (1.33)
**does** contain the purchase adapter the 2026-09-17 note said 1.32 did not — appended, nothing
reworded, the protected sentence byte-identical; `PLAN-ITERATION` §E and `PLAN-WINDOW` §H carry two
stale facts ("while v1.30 is in review"; the install-denominated checkpoints as undecided, adopted
2026-09-09) — dated correction lines, not rewrites.

---

## §D Track 3 — day 90 (v1.34 registration; v1.35–v1.36 the rest, owner-gated)

### D1 — Register moderated-session participants in §K before anyone is recruited · *done 2026-09-24, before N = 35 was read*

*Addendum 2026-09-25:* the test half of this item landed in commit `c79d10a` — `test_sales_report.py`
section E1 plants five registered `first_download` entries in five distinct (day, platform, country)
cells across four countries and both platforms against a synthetic report, and grades the subtraction,
the withholding on an over-claim and on an empty cell, the false/null decisions, and entries outside the
window. `sales_report.py` itself is unchanged. The "done 2026-09-24" in the heading is the §K
registration; the sentence below about the test case is now past tense as of this addendum.

`PLAN-WINDOW` §E calls moderated sessions with 10–15 recruited users the most valuable item available
and says *register them now*; `PLAN-V2-PRODUCT` §H specifies the instrument (watch a session, then a
forced choice between concrete packages). Recruited users install the app, so clause two of §A's test
is touched. A dated box in §K, in the shape of the 2026-09-17 "DECIDED" items: participant installs are
registered by the owner as `first_download` the day they happen (the registry's existing mechanism —
`exclude_walk_first_downloads_from_N` is already `true`); a participant purchase is excluded via a
`kind=purchase` entry and GO never fires on it; participant counters are never "returned counters" for
the STOP branch; recruitment happens outside the App Store where possible, with counts by territory
recorded. **Written before the first recruit is contacted, or the sessions do not run** — and, the Flash
review's blocker, **written before the N = 35 row is read**, because a §K rule written after a reading is
the degree of freedom the pre-registration forbids: the box is in §K as of 2026-09-24 (the N = 34 reading
of that morning held no participant). Two caveats the same review found, now in the box: participants use
the existing `first_download` kind (a dedicated kind is an instrument change and waits for the
known-positive), and the registry's reconciliation rule — an entry claiming more units than the report's
cell holds withholds the bound — is not relaxed for them; the owner records real platform, country and
install day. Before the first participant installs, `test_sales_report.py` gains a case with several
registered `first_download` entries across countries and days against a synthetic report, so the
subtraction and the withholding are both seen to work (tests only; the instrument is unchanged).

### D2 — The session kit · *1.5 days, v1.34/v1.35 (owner recruits)*

`docs/SESSIONS-STAGE1.md`: a 45-minute protocol (en/zh) — watch a first ride; watch a return the next
day; then the forced choice between four packages described in the customer's terms (supporter ·
bring-your-own-material · structured course · listening), **with every price left blank for the owner
to fill** (the repo holds two owner inputs, ¥10 shipped and a ¥50/month *revenue floor*, which is not a
price — an agent invents no prices); card order rotates; no card carries the app's own offer wording or
"¥10"; a consent text; an observation checklist whose screen strings are grep-matched to source (the
walk card's convention); the two questions no other instrument can answer — *does anyone paste their own
text* (`PLAN-ITERATION` §F's falsifier) and *what a rider does when the queue is exhausted*. **A PII
rule:** per-participant notes never enter this public repository; only aggregates and quotes with
consent do (`docs/sessions/` holds the tally, not the people). Delivery mode: the participant's own App
Store install of the current release, registered the same day — never TestFlight (an ASC write and a
different StoreKit environment) and **never a walk device before §L is recorded**. Honest sizing of the
owner's part: 12–18 hours over 2–3 weeks, from an owner who has not yet found 70 minutes for the walk in
15 days; the kit costs nothing if it waits.

### D3 — Two documents the decision will need, written after the sessions, not code · *3.5 days, v1.35–v1.36*

* **`docs/DESIGN-F1-SRS.md`** — the expensive half of F1 (card identities for pasted words; sync), designed
  against the code it constrains (`SRSCard(id:)`, `SyncMerge`, `CustomText`'s refusals), with a falsifier
  keyed to the session tally ("fewer than 2 of n pasted anything → shelved"). Not built in the window: it
  changes how far people ride and gives away the Stage 3 catalogue to today's installs. *2.*
* **`docs/STAGE2-DECISION-PACK.md`** — the §E fork × §K's branches as a memo with **every decision cell
  blank**, the measurements each combination needs, the day-91 list (the offer screen at AX5, About's
  counter text, brand contrast, the zh Practice screenshot, the sync-status caption), and the readings it
  shares data with. `grep -c "DECIDED" ` of its decision cells is 0. *1.5.*

### D4 — CN search-result creative, designed and filed, never uploaded · *2 days, v1.36, optional*

`PLAN-WINDOW` §C's one evidenced gap (search-row impression → product page) may be designed during the
window and shipped on day 91. Drafts under `docs/store/drafts/` with a header naming the earliest ship
date; a dated ASC GET of the three locales' metadata captured first as the byte-identical baseline the
release diff is checked against. Only if the sessions or the owner want it.

### D5 — `ta_score`'s `totalPlayerCount`: the agent's half of a device errand · *0.5 day, v1.36, after the walk*

A DEBUG-only read on a never-merged branch, triggered nowhere near the Settings screen, run once by the
owner on a physical device with an authenticated Apple Account — after the walk, because it means running
a development build on a walk device. The number goes into `docs/measurements/`.

---

## §E Conditional on the owner's walk — the money's first automated observation · *1 day total*

Purchase-path automated coverage is zero on both platforms and every plan since v1.30 ranks fixing it
first. The cause is measured (`SKTestSession` is inert without `get-task-allow` on the test host) and the
fix is forbidden until the walk, because a live session stores a StoreKit configuration for the bundle id
whose effect on the App Store build is unmeasured. **Precondition, in writing:** the owner has recorded the
§K purchase (`--confirm-known-positive` exit 0) **and its refund row**, or has pasted DRAFTS §2/§4. Then:

* `project.yml`'s macOS test target signed with `get-task-allow` (ad hoc; `run_store_gates.sh` currently
  passes `CODE_SIGNING_ALLOWED=NO`, the probe's measured-inert row, so the script changes too);
  `run_store_gates.sh` exit 0 with nine gates *executed*; one gate mutated red (a refund that does not
  revoke); then the stored Octane configuration deleted **by the script itself — a `trap` in
  `run_store_gates.sh` that removes `…/Octane/com.jasonye.nihongoride` on every exit, live or inert, so a
  later `run_all_gates.sh` cannot leave one behind for preflight to trip on** (the Flash review's
  addition) — and `stage1_walk.py preflight` exit 0. *0.5.*
* **iOS: a re-probe, not a build.** The repo holds a measured negative (`StoreGateTests.swift:14-22`,
  2026-08-30: a local `.storekit` never reaches the app on the iOS simulator under `xcodebuild test`),
  so the item is half a day on the current toolchain with the entitlement, recorded either way; an iOS
  unit-test target is built only if the probe is live. *0.5.* If both stay inert: the honest exit-3 state
  stays, recorded in the probe document.

---

## §F Sequencing, budgets, and what each release is registered as

| release | target submit | contents | agent-days: build · verify+review · release |
|---|---|---|---|
| **v1.34** | ~2026-10-08 | B1 (1), B2's two defects (0.5), B3 (0.5), B4 (0.25), B5 (0.25), C2 (0.5), C3 (0.5), C5 (0.1), C6 (0.25); D2's kit (1.5, documents — written in the same window, not release-gating) | **3.85 code + 1.5 docs** · 2 · 0.5 |
| **v1.35** | ~2026-10-22 | B6 (2); B2's two improvements if there is evidence anyone pastes (1, conditional); the N = 100 record (C1, 0.25); session analysis if sessions ran (D2); the v1.26 headword residue (112 sentences a conjugated verb kept from dictionary matching — `docs/measurements/v126-uninspected-residue.json`) and the flagged `n5-kazoku` counter item, each correction by ear with its evidence; **two populations, not one gate** (`PLAN-WINDOW` §D item 3, `PLAN-ITERATION` §D; *1 day*); §E if the walk has happened | **3.25 firm + 2 conditional** · 2 · 0.5 |
| **v1.36** | ~2026-11-05 | D3 (3.5, documents), D5 (0.5); session-driven fixes on open surfaces (*1–2, conditional*); D4 (2, optional); whatever the N = 100 record and the walk surfaced | **0.5 firm code + 3.5 docs + 1–2 conditional + 2 optional** · 2 · 0.5 |

**The build column is the sum of the items, not a round number** (the Flash review found the first
draft's 4 against an itemised 6.85 for v1.34 — a 70% deficit that would have been paid in skipped review
rounds). **The review and release budget is measured, not hoped:** v1.33 needed four adversarial review rounds
and seven fix commits after its four implementation worktrees (`STATE-2026-09-18`); every release here
budgets two rounds with independent refuters and a frozen-surface lens, and a third is taken rather than
skipped when the second finds a SERIOUS. A release that carries nothing a rider can see is not shipped
(the cadence is a registered covariate — `PLAN-ITERATION` §G — and release days multiply first-time
downloads 1.58x in the second control).

**Registration:** v1.34 and v1.35 are registered under constraint 3 as *"may raise days-ridden; direction
up; magnitude unmeasurable"* in §K's template, before `--submit`; v1.36 is registered when its contents
are known. Each release's `PLAN-V1.3x` record states it.

**Order inside v1.34:** C3 first (the proof instrument, on the unchanged tree), then B1–B5 in worktrees
by file, then C2/C5/C6/D1/D2 as docs and tools, then the verification of §G, then the copy, then
build → upload → dry-run → metadata → submit, with `ListAgents` before any ASC write.

---

## §G The verification standard (from 1.33, kept)

1. `run_all_gates.sh` green at its floor; `HorizontalTextFitTests.accepted` never raised.
2. **Default size unchanged except where intended:** headless renders en + zh, three runs each, compared
   pixel by pixel against the 1.33 baseline — with C3 done, in parallel; until then sequentially. Every
   intended difference named per screen before the comparison is read. `road.png`, `road-iap-review.png`
   and `menu.png` identical.
3. **Accessibility sizes on a device:** the simulator pass at default and AX5, en/zh, on the same 402pt
   iPhone and the iPad mini, every changed screen before/after; the harness lives in the session
   scratchpad and is re-created from `PLAN-V1.33` §E's description (it is scratch by design — it drives
   the app and must never enter the repo).
4. `run_ios_placement_tests.sh` when UI changed (`SIM_NAME=NihongoRide-Placement` when the default
   device is busy).
5. Pre-submission review: a lens per file group, the purchase adapter if `RouteStore` changed (it should
   not), the frozen surfaces (`git diff` must not touch `RoadView.swift`, the Settings road card, the menu
   route strip, prices, About's counter text, store metadata), and a tests lens that mutates; each
   non-NOTE finding given independent refuters.
6. `launch_gate.sh` on the macOS export; curl the live privacy and support pages; byte-exact read-back of
   every ASC PATCH; the What's New copy checked sentence by sentence against the code (1.33's round 2
   found four inaccurate claims in a draft that read fine).

---

## §H Owner-only — unchanged, and still the most valuable hour in this plan

* **§K's day-0 known-positive purchase** (`WALKCARD-STAGE1`, steps 0–5 ≈ 65–75 minutes; steps 6–7 on
  D+1/D+2 are an agent's). It is the only action that removes today's one `BOUND WITHHELD` reason.
* **§L's three manual gates** on App Store 1.33 (macOS 57 / iOS 58) — signed-out App Store, Family
  Sharing, cross-platform restore with a cold install. Note the 2026-09-17 addendum: 1.33 carries the
  restructured purchase adapter; the walk observes that code.
* Registering every walk install and every session participant install in the registry before the
  next `--checkpoint` whose window contains it (no tool writes that file).
* Recruiting and moderating the sessions; supplying the package prices (D2).
* Deciding, after the walk, whether the store-gate harness is signed (§E).
* The `ta_score` device errand (D5), and the VoiceOver check of B3 on a physical iPhone — both after the
  walk, because both put a development build on a walk device.
* Approving any public-site change (none planned) and any ASC write (each release's upload and submit;
  `ListAgents` first).
* Reading §K's branches as a person when N = 100 and N = 200 fire.

---

## §I Deliberately NOT in this phase, with the reason

* **The offer screen and its entrances, at any size** — `RoadView`'s AX5 breakage, the buy button's
  "One- / time / purcha / se", the "Already bought it?" card width, the Settings road card, the menu route
  strip, About's counter text, the brand-colour contrast on the buy button, the menu credit line, the zh
  Practice store screenshot. All measured, all on the day-91 list (D3). Constraint 1 and 4.
* **A "Remind me" tap on the menu's "come back tomorrow" notice.** It puts a system permission dialog on
  the entrance-bearing screen, one tap after the rating prompt — the v1.30 collision on the time axis.
  Reminders stay opt-in from Settings. A learner who denied notifications once still meets a switch that
  flips itself back without a word (`AppModel.swift:746-747`) — a real gap, but the caption for it sits on
  the Settings screen above the frozen card and would move the card at the default size for that
  population; it waits for a release that re-shoots Settings.
* **A streak-keeper reminder.** The planner only schedules future slots when the app runs, so a "today's
  slot only" reminder reaches almost nobody it is for; a design that works would fire daily — a nag —
  and no instrument here can tell nagging from helping. After the sessions, if they say so.
* **A notification / widget deep link.** Its value rests on a grep (no `onOpenURL`, no `widgetURL`) and
  cold launches already land on the menu; it is a 0.1-day device check in v1.35, and an item only if warm
  launches do not.
* **The SRS half of F1, and sync for pasted texts** — Stage 3; changes how far people ride; gives away the
  catalogue to today's installs. Designed (D3), not built.
* **A Time Attack duration picker** — registerable, but it buys a distance change and no information.
* **CSV export** — free forever when built (`PLAN-WINDOW` §G); nobody has asked; after the window.
* **Localising the UI to Japanese** — touches the frozen strings and is "not window work".
* **The 522 dictation sentences** — closed by measurement; revisit only with a new instrument.
* **A second SKU, telemetry, TestFlight for participants, any store-metadata change** — `PLAN-WINDOW` §G.
* **A seam to unit-test the StoreKit → `PurchaseAnswer` translation** — purchase code changed mid-window
  without a walk observing it; the walk first.
* **Rewording the protected sentence or writing into §L's walked column** — dated addenda only.

---

## §J What would make this plan wrong

* **If the owner walks §K and §L in week 1**, §E moves into v1.34 and B6 slides — the money's first
  automated observation outranks a search field.
* **If the owner records DRAFTS §2 (no known-positive, ever)**, the bound is withheld for the window's
  life, N = 100 and N = 200 become records of N only, and D3's decision pack must say what that world's
  decision rule is — this plan does not.
* **If a stranger buys before the walk**, the tool prints that the zero-purchase bound would not apply
  anyway, GO on H1 is a person's reading, and C2's watch is the first thing to run.
* **If a store review mentions the purchase negatively**, stop-and-fix overrides every item here.
* **If traffic keeps doubling**, N = 200 lands inside these six weeks and the decision read — a person's,
  not scheduled here — comes before v1.36.
* **If the sessions say nobody pastes their own text**, B2 was polish on a stub and D3's design is shelved
  (cheap); if they say riders leave for reasons the app cannot see, B1 was the wrong lever.
* **If the tomorrow line cannot fit at AX5 without a `FlowLayout`**, it is the seventh instance of the
  most-shipped shape and gets that treatment before it ships, not a raised ceiling.
* **If sizing is wrong the way 1.33's was** (four review rounds on one HUD row), v1.35 absorbs the slip;
  nothing here is dated to a checkpoint except the readings themselves.

---

## §K What the two reviews changed

Both reviews ran in a throwaway copy of the repository (`agy`, sandboxed, the model reading the plan and
every constraint document it names, plus the memory notes), on the first draft (`4cc213e`). **Neither
would have approved that draft**; what each found, and what became of it:

**Gemini 3.1 Pro** (6 findings):
* *BLOCKER — B1's proof tested the model, not the screen.* Accepted: the proof now requires the line to be
  seen (the `results.png` render differs from the baseline only in the line's region; a source pin; the
  simulator reads it) — v1.26 §D's lesson, which the draft had cited elsewhere and forgotten here.
* *BLOCKER — B3's Accessibility Inspector on the simulator is not a device.* Accepted in substance: the
  proof is labelled as a simulator observation, and the device check is an owner errand after the walk
  (§H), because a development build must not land on a walk device before §L is recorded. Not a blocker
  for shipping: the accessibility tree the simulator shows is what the device speaks.
* *SERIOUS — B6 at 1.5 days is "multi-week".* Partly accepted: resized to 2 days with a cut rule (not
  green with its tests at the end of day two → moves whole to v1.36). The comparable is measured, not
  argued: `CustomTextKit` shipped tokenizer, store, editor and screen in one day's 17 commits.
* *SERIOUS — B2 polishes a feature nobody is known to use, before the sessions.* Accepted for the two
  improvements (edit-after-paste, "Practise this text" → v1.35, conditional on evidence anyone pastes);
  refused for the two defects (silent truncation, the macOS delete affordance), which a rider who pasted
  once already meets.
* *SERIOUS — B4 (About's remaining dim text) carries "the same risk" as Settings' caption, because About
  houses the frozen counters.* **Refuted, and the plan says why:** the counters' *text* is frozen, not
  About's layout; `about.png` is in the headless render set, so a pixel proof exists for About and not for
  Settings — 1.33 changed the counters' colour with exactly that proof. The asymmetry is the reason the
  plan splits the two, not an oversight.
* *MINOR — "release-day mechanics done 2026-09-24" for a release that went on sale 09-17.* Accepted, with
  the true story: done a week late because no session was running; the instrument's registry WARNING was
  the backstop that caught it (C4).

**Gemini 3.8 Flash** (13 findings):
* *BLOCKER — D1 would write a §K rule inside v1.34, after N = 35 has been read.* **Accepted and acted on
  the same night:** the participant-registration box is in §K, dated 2026-09-24, before the N = 35 row
  was read (D1).
* *SERIOUS — §F's build column understated the itemised sum by 70%.* Accepted: the column is now the sum,
  with documents, conditional and optional work shown separately.
* *SERIOUS — B6 cited the placement suite as proof, which never visits Word Lists.* Accepted: a dedicated
  XCUITest; the placement suite still runs as the offer's regression guard, not as B6's proof.
* *SERIOUS — B3's "hosted test" of the live accessibility tree is infeasible* (`NSHostingView` exposes none
  without an assistive client, as v1.33 measured). Accepted: a pure composer with a table test and a
  source pin; the tree is read on the simulator.
* *SERIOUS — B1 misread `JournalView`*: it already has a streak card and a three-row forecast fixed for
  AX5 in v1.33; replacing it would duplicate and degrade. Accepted: the line is confined to `ResultsView`.
* *SERIOUS — participants as `first_download` hit the registry's reconciliation rule.* Accepted into the
  §K box as a stated rule (withhold, never adjust), with the schema change deferred behind the known-
  positive; a reconciliation test before the first recruit installs.
* *MINOR × 5* — `lastSummary` does not carry the line (fixed: read `model.tomorrowLine`); `VocabStore` has
  no search index (fixed: `search(_:)` is part of B6); the 112-sentence residue is a headword population,
  not the counter gate's (fixed); `HorizontalTextFitTests` skips `VStack`s so it proves nothing about B1
  (fixed: the AX5 pass is the proof); STATE-2026-09-24 "(done)" — true on disk at `5e6deae`, written after
  the copy the review saw; the Octane teardown belongs in `run_store_gates.sh` as a `trap` (added to §E).
* *NOTE — the tomorrow line's edge cases.* Accepted: the copy matrix in B1.

**What neither review found, recorded because a clean review is a claim:** neither ran a line of code,
and neither checked the second-control reading in C5 against the cache — that stays the next session's
first act with the checkpoint pair.
