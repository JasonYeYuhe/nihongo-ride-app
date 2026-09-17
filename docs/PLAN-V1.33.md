# v1.33 — readable at the largest text sizes, everywhere a rider looks except the offer

Written 2026-09-17 (JST), after the owner said *"你全权负责吧 继续推进到发布下一个版本"*. The scope is
measured, not imagined: two read-only passes the same evening
(kept outside the repo in the session scratchpad) — a CoreText measurement of all 39 findings of
`HorizontalTextFitTests` at AX5 on a 393pt phone (13 break with ordinary content, 10 depend on the data,
16 are fine), and a simulator pass over every reachable screen at the default size and at AX5, in English
and Chinese (76 simctl screenshots + 395 UI-test screenshots on a 402pt iPhone 17 Pro, driven by a
scratch-only UI-test target that refuses to tap the purchase or Restore buttons): 29 visible defects,
the worst only at AX5, and one (a run ended before any word, shown as a success) at every size.

## §A Why this, and not a new mode

`PLAN-ITERATION` §C's tier 1 is done, and its item 4 says the next list should come from *using* the
app. Using it at AX5 found the core loop's results screen unreadable ("Word / s", "Accu- / racy"), the
journey HUD wrapping its progress ("0/1" over "2"), Word Lists names stacking three letters a line, and
the Settings title breaking ("Setting / s") — on the device setting a real low-vision learner uses. v1.32
fixed the Ride Log and wrote a scan pinned at a ceiling; this release pays that ceiling down.

## §B In scope — by file group (the groups are also the parallel work units)

**R — Results** (`ResultsView`, `ConjugationResultsView`, `MenuView`'s `MenuFlow`)
* Tile captions break mid-word at AX5 and grid rows misalign → one column at accessibility sizes.
* Review word grid stacks kanji one per line (図/書/館) → one column at accessibility sizes.
* Stumbled-word chips wider than the screen are clipped on both edges → `MenuFlow` proposes the row's
  width to an item that is wider than the row, so its text wraps (a no-op for every item that fits, which
  is every menu chip at every size).
* **A run ended before anything was typed shows "You've arrived!" / "Drill complete!", a grade, and 100%
  accuracy** — at every size (the ride log already refuses to record it, `AppModel.logRun`). Say what
  happened instead, with the same "nothing typed" rule the log uses written once; the buttons, the review
  prompt's rule and what gets recorded do not change.

**G — Ride and drill** (`GameView`, `ConjugationGameView`, `CoachView`)
* Journey HUD: the progress/level values wrap at AX5 → the conjugation HUD's own v1.31 fix, and hide the
  least essential pill at accessibility sizes if the row still overflows.
* Conjugation answer kana (the typing target) overflow on long forms, at default size too with the
  keyboard down → wrap the glyph row instead of shrinking the thing being typed.
* Conjugation HUD mode badge collapses to "…"; the prompt's dictionary-form verb is the only text allowed
  to shrink and ends up smaller than its reading.
* Coach: the correct-spelling pill and the kana row wrap/overflow at AX5.
* Sentence mode at AX5: the save star sits on the sentence text.

**S — Settings and About** (`ScreenHeader`, `SettingsView`, `AboutView`)
* Settings and About headers → the shared `ScreenHeader` (Back first at accessibility sizes), as the Ride
  Log and Stats already do.
* Settings "Language" row breaks "Lan / gua / ge" beside a 200pt picker → stack at accessibility sizes.
* About credits: names and licence capsules break mid-word → name above licence at accessibility sizes;
  "ACKNOWLEDGEMENTS" breaks.
* About copy: the Chinese disclosure's missing character (…母语审仍是…), English that reads unfinished.
* Contrast of the small dim text measured failing: Settings captions (2.75:1) and About's counter block
  (2.78:1 — its colour, not its text). Fixed at those call sites, to ≥ 4.5:1 computed from the colours.
* **The "The Road" card in Settings is not touched** (§C).

**L — Lists, Ride Log, Stats, Practice** (`ListsView`, `JournalView`, `StatsView`, `PracticeView`)
* Word Lists row: name + count on line 1, play and menu on line 2 at accessibility sizes; detail title.
* Ride Log: odometer and forecast rows (the Stats "Tomorr / ow" bug's twin at 100+ due), the speed-trend
  header, the recent-ride icon overlapping "Today".
* Stats: the Conjugation card's two stats stack at accessibility sizes; a one-ride accuracy trend draws a
  point instead of an empty chart.
* Practice top bar (BLIND badge) at accessibility sizes; the Chinese UI's untranslated "PRACTICE",
  "BLIND", "ACC".

**A — App shell** (`NihongoRideApp.swift`, with group L)
* The status bar is invisible on the light Practice screen (white on cream, 1.15:1) — **only if** it can be
  fixed without changing the software keyboard's appearance on that screen; otherwise deferred and said so.

## §C Deliberately NOT in scope, with the reason

* **The offer screen and its entrances** — RoadView's stretch rows, its buy button ("One- / time /
  purcha / se" at AX5), the "Already bought it?" card width, the Settings "The Road" row, and the menu
  route strip (its stop names stay English in the Chinese UI). All are measured defects. `PLAN-WINDOW`
  constraint 1 freezes the offer and its placement, and an AX-only layout change would still show
  large-text users a different offer screen partway through the observation window. **Deferred to the
  first release after §K's decision fires (N = 200 or 2027-03-08).** Written here so it is a decision,
  not an omission.
* **About's on-device counter text** (English camelCase at every size). It is the format a customer would
  copy and return — §K's STOP branch reads returned counters — so its format does not move mid-window.
* **Primary button contrast** (white on coral, 2.70:1) and the sky-blue "Sentences" button (1.88:1) —
  brand colours used across the app including the offer screen; a colour decision, not a layout fix.
* **The menu's credit line** (2.43:1, English-only). The menu is the one screen whose default-size render
  this release keeps pixel-identical (the `MenuFlow` change is a no-op there), which makes it the control
  that proves the offer entrance on it did not move.
* Low-severity items left for a later release: results scrolling under the clock (the fade would sit over
  the arrival sky — a design question), the Sentence-mode romaji hint truncating on long sentences (whether
  it scrolls with the cursor is unchecked), Stats tile alignment and chart axes at AX5, list-detail rows
  without a reading, the saved list's double star (the name is stored data), Practice's translation below
  the keyboard at AX5 (unconfirmed), the About Chinese text naming a repo file, and "Start ride" three
  screens down at AX5 (an observation, not a defect).
* Store metadata of any kind (constraint 4) — What's New is version text, not listing metadata.

## §D The purchase adapter ships in this release — decided under the owner's delegation

`751a37a` restructured `RouteStore.purchase()` (a pure, tested `purchasePlan`; a re-purchase after a
known refund stamped with `observedNow`). §L's 2026-09-17 note left "whether the release carrying it needs
§L walked again" to the owner; the owner has now delegated the release. Decision: **include it**, because
(1) §L has not been walked in the eight days since day 0, so the walk will most likely happen on whatever
is live when the owner does it — shipping the adapter now means the walk observes the code customers run,
while holding it back means walking code that is about to be replaced; (2) reading `git diff 0d98a20 HEAD
-- Sources/NihongoRideApp/RouteStore.swift` branch by branch while writing this (2026-09-17): every
StoreKit result maps to the same notice, the same `lastOutcome`, the same ledger signal and the same
settle as in 1.32, in the same order (finish → apply → settle → notice → outcome), `isPurchasing` is
untouched on the product-missing path as before, and the only difference is the documented stamp; (3) the
mapping is table-tested and `purchase()` is held to it by source scans each shown to go red. `purchase()`
is the only production code that changed on main since the 1.32 bump (the rest is comments, docs, tests,
the local `.storekit` description and the support page). **Cost, stated:** until the owner walks §L, live
customers run an adapter whose StoreKit → `PurchaseAnswer` translation no test observes (a `.pending` read
as `.userCancelled` would pass every check). The pre-submission review gets a dedicated lens that repeats
(2) independently; if it finds any other behaviour change, the adapter is reverted for 1.33 rather than
argued. The walk card and preflight move to the 1.33 builds when 1.33 is live.

## §E How it is verified

1. `run_all_gates.sh` (floor 13) green; `HorizontalTextFitTests`'s ceiling lowered to the new count — a
   ratchet, never raised.
2. **Default size unchanged except where intended**: headless macOS renders (`NIHONGO_SHOT`, en + zh)
   compared against the baseline rendered from `3d6c59f` before any change (`scripts/compare_renders.py`,
   pixels, candidate rendered twice more as controls). **Menu identical.** Settings and the coach are not
   in the headless set, so they are compared on the simulator at the default size.
   Intended differences at the default size, all of them, as shipped (corrected after the pre-submission
   review — the first version of this list named only About and Practice):
   * About: the counter lines' colour; the Chinese disclosure's 核.
   * Settings: the three captions' colour.
   * Practice: the Chinese labels 练习 / 提示已关 / 正确率; with hints off the badge no longer shrinks — the
     label does.
   * A ride or drill that typed nothing: a new headline, no flag or check mark, no grade, no Share button;
     its accuracy tile reads "—" only when no key at all was pressed.
   * A drill that completed no prompt grades "Another set".
   * A one-ride accuracy chart draws its point.
   * Content wider than its container wraps instead of overflowing: a conjugation answer (e.g. 8+ kana
     with the keyboard down on a 393pt phone), the coach's replay word, and any `MenuFlow` item wider
     than its row (a stumbled-word chip).
3. **AX5 fixed on a device**: the same scratch UI-test pass re-run after the change, English and Chinese,
   default size and AX5, screenshots before/after side by side for every §B item — sequentially, on one
   simulator no other session is driving.
4. `run_ios_placement_tests.sh` (UI changed): the placement assertions still hold.
5. A pre-submission adversarial review with a lens per group plus the adapter and the frozen surfaces
   (`git diff` must not touch `RoadView.swift`, the Settings road card, the menu route strip, prices,
   `AboutView`'s counter text, or store metadata).
6. `launch_gate.sh` on both uploaded archives; curl the live privacy and support pages before submitting.
7. On release day: the Pacific release date(s) into `FIRM_RELEASE_DATES_PT`; the walk card and
   `stage1_walk.py`'s expected version/builds moved to 1.33.

## §F Registered under PLAN-WINDOW constraint 3

Nothing in §B changes how far anyone rides. The refused-run headline changes a screen shown after a run
that recorded nothing. Registered as "no exposure change" so a later reader does not have to re-derive it.

## §G What was built, what the pre-submission review found, and what became of it (2026-09-17/18)

Built in four worktrees (groups R, G, S, L) on 2794507, merged 2d297e1. Two review rounds before upload:
round 1 (five lenses) on 2d297e1, fixed in 336a754, 68f2214 and 0024cd5; round 2 (three lenses, every
non-NOTE finding given independent refuters) on f9cd5f8, fixed on the branch `v133-round2-fixes`.

**Fixed**
* Round 1, SERIOUS: the ride HUD's one-line limits applied at every size and pushed the pause button off
  iPad mini portrait and Split View at the default size, and off phones at xxLarge / xxxLarge. The limits
  now apply at the accessibility sizes only; below them the HUD is 1.32's (0024cd5).
* Round 2, SERIOUS (found by two lenses independently, confirmed by four refuters): on an iPad at the
  accessibility sizes the same one-line HUD row still needed ~760–850pt, so iPad mini portrait, 11-inch
  iPads late in a ride and Split View windows lost the pause button — a touch-only rider's only way to
  pause or end. `RideHUDLayout`'s arithmetic had covered phones only. **Decided:** at the accessibility
  sizes an iPad shows the phone's pill set (distance, accuracy and speed hidden, as on phones, by the same
  "informational, not actionable mid-ride" rule); values stay on one line. Chosen over restoring 1.32's
  wrapping on iPad, which kept the button only at ≥678pt and brought back "0/1" over "2".
* Round 2, NOTE made cheap: at the accessibility sizes the HUD's spacer may collapse (as the drill HUD's
  already does), for 320pt Display Zoom iPhones.
* Round 1, MINOR: a run of only wrong keys showed "—" / "Nothing typed" for a real 0% — the tile now asks
  `pressedNoKey`. A drill with a correct key but no answer graded STEADY — `ConjugationSummary.grade` now
  requires a completed prompt for Steady and Building.
* Round 1, MINOR: the placement UI test only ever reached the typed-nothing results screen; it now types a
  word first and proves it reached results (336a754); round 2 added a keyboard wait before typing.
* Round 1 tests MINOR 1–7 (68f2214) and round 2 MINOR (group S/L pins read raw source, so a switch turned
  off with its old condition left in a comment passed): each fixed with the mutation that now fails.
* Round 1 S/L NOTE 3: three accessibility-size switches had no test — pinned (336a754). NOTE 1: Practice's
  badge comment corrected (default size on phones: the label, not the badge, takes the squeeze).
* The submit copy: "the default text sizes are unchanged", a contrast claim broader than the fix, the
  Chinese "骑行或练习" (which names Practice mode, not the drill), and review notes that said the purchase
  was unchanged "for a customer" before describing an unlock difference — all corrected before sending.
* §D: the purchase lens re-derived `purchase()` path by path and found no behaviour change besides the
  stamp, so the revert condition did not fire.

**Deferred, by name**
* Drill card at AX1: with the keyboard up an answer that wraps to a second row (11+ kana on a 402pt phone)
  leaves the card ~30pt taller than its space even at every shrink floor (replica against the 386pt card
  in the AX5 screenshot); keyboard-down unmeasured. Not yet seen on a device.
* At the accessibility sizes VoiceOver no longer hears the hidden pills' live values (score in a ride,
  combo in Time Attack, and on iPad now distance / accuracy / speed); they are on the results screen.
* `ConjugationHUD` has had one-line limits at every size since v1.31, so a drill in a very narrow iPad
  window can clip at the default size. Predates 1.33; unchanged.
* Small dim text still below 4.5:1: About's footer note (2.79:1), contact line (3.23), email (3.46),
  credit URLs (3.91); Settings' sync status (3.91). 1.33 fixed Settings' three captions and About's two
  counter lines only.
* §B S "English that reads unfinished" in About's disclosure: not changed; only the Chinese 核.
* Group A, the Practice status bar: not changed — every lever found either flips the software keyboard's
  appearance or rewrites the app shell (6e7e292's message lists them).
* `isPurchasing`'s reset has no test (purchase lens NOTE); some new source pins match exact lines and will
  go red on reformatting (tests lens NOTE).
* The headless render tool shares one temp directory and settings suite between processes and prints
  "wrote" on a failed write — a separate task, not in this release; this release's renders were run
  sequentially.

**Registered under PLAN-WINDOW**
* Constraint 1: at the accessibility sizes Settings' header (Back above the title) and Language row stack,
  so the "The Road" card sits lower for large-text users. The card, its text, identifier and counter
  timing are unchanged; the Road screen renders pixel-identical at the default size and unchanged at AX5.
* Constraint 3 (§F): "nothing changes how far anyone rides" is about mechanics — no queue, distance,
  unlock or ride-length rule changed. The screens around a ride did change (typed-nothing results; one or
  more HUD pills hidden at the accessibility sizes), which can only make large-text riding easier.
* Constraint 4: the zh App Store screenshot of Practice still reads "PRACTICE" while the app now says 练习.
  No screenshot is recaptured inside the window.
* `site/` changed on 2026-09-11 (814f185, "works offline" wording), after day 0; not in the binary.
