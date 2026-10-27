# Red-line review: DESIGN-E3-SAMPLER.md (branch docs/v137-e3-design, 31b9487)

*Adversarial, read-only review, 2026-10-27. The lens is the red line: no existing install may lose anything, ever (`PLAN-V2-PRODUCT.md:369-397`). Code citations are at the doc's HEAD, 9c09ab7, in `v137-docs-e3`, unless marked **[marker branch]**. Those come from `v137-marker` @ 56a2ebc (`feat(v1.37 P0-12)`), read only to check the §5.6 interface. Nothing was built or edited.*

**Verdict: I found a red-line breach.** One finding is a BLOCKER and four are SERIOUS. Each SERIOUS finding is a path by which an install loses depth, or would lose it under a plausible release event. All five sit in the threshold definition and the edges of rule 3. None is in the truth table's logic, which holds up. I found no price anywhere in the doc.

---

## BLOCKER

### B1. "E3's first build of any channel, TestFlight included" un-grandfathers pre-E3 installs if any ungated build ships after it

**Where.** §5.7 bullet 3, which says the threshold "must be the first E3 build of any channel, TestFlight included … Lowering it later would un-grandfather installs". §5.2 `Threshold` ("fixed before the first E3 upload of any kind and never lowered"). §5.3 rows 2 and 5–6.

**Scenario (iOS):**
1. An E3 build is uploaded to TestFlight for V2–V4, say 1.39 (66).
2. Before E3 reaches customers, a non-E3 build ships to the App Store. Plausible versions of this step:
   - a 1.38.1 hotfix (67);
   - v1.39 shipped without E3 because the C-2 box never came (PLAN-V1.37 §I says "E3 stays on its branch");
   - E3 rejected in review, with the rest of the release shipped.
3. A rider installs that build fresh. They have every level free, and their marker says build 67, `priorDataPresent` false.
4. E3 ships. Rule 1 fails: 67 ≥ 66. Rule 2 fails: PD is false. Rule 3 fails: on iOS `originalAppVersion` is `CFBundleVersion`, so "67" ≥ 66.
5. Row 6 returns **N**. This is permanent and correct by the table.

This person installed before E3 shipped and loses N3–N1. Build numbers come from one increasing counter (`scripts/check_versions.py:78`; history 1…62, all single integers), so any build released after the first E3 upload has a higher number.

On macOS the same install fails rule 1 too. Rule 3 rescues it only online, and only when the ungated build's marketing version is below E3's. A v1.39 shipped without E3, followed by E3 in a later 1.39 build, compares "1.39" < "1.39" = false, so it gets **N** on macOS as well.

**Fix:**
- Define the threshold per platform as **one more than the highest build (and, on macOS, the marketing version) ever released to App Store customers without the gate**. Fix it when the first gated build is submitted, not when it is uploaded.
- The threshold **may be raised, never lowered**. Raising only grants more.
- The release script asserts this before every submit by reading ASC's released builds. It refuses an ungated submit at or above the threshold, and a gated submit whose threshold is not above every ungated release.
- TestFlight sampler testing then goes through the DEBUG seam (§6.2 item 3). It does not go through a low threshold.
- Add a §9.2 mutation: "an ungated release after the first E3 upload → a fresh install of it must be G."

---

## SERIOUS

### S1. A rollback or kill switch after E3 un-grandfathers everyone who installed while the gate was off

**Where.** §2.2 (`depthIsOpen`). §5.4 ("Never revoked … three ways"). PLAN-V1.37 §E Sequence ("v1.39 can carry E3: a constant flip").

**Scenario:**
1. E3 ships in 1.39.
2. A defect leads to 1.39.1 with the gate flipped off, which opens everything for everyone.
3. Fresh installs during 1.39.1 get marker build ≥ threshold, PD false, and production `originalAppVersion` ≥ E3. They ride N3.
4. 1.40 turns the gate back on. Those installs reach row 6 and get **N**.

They had the content and lost it. The table cannot see that a gated build was preceded by an ungated one.

**Fix:**
- While the gate is off, `depthIsOpen` is true **and the grant key is written** on every launch, with a new `Reason.ungatedBuild`. The state "everything free" then becomes a grant in its own right.
- Better still, ship this writer on `main` in v1.38, the release where P1-5 ships dark. Every install that launches v1.38 or any later ungated build is then grandfathered whatever the threshold is.
- That also closes most of B1: a 1.38.1 hotfix built from `main` would carry the writer.
- Add a table row and a mutation: "gate off → grant written".

### S2. A pending or hanging `AppTransaction` is not "unavailable", and the state while it is pending is unspecified

**Where.** §5.1 ("Unreadable: AppTransaction throws"). §5.2 ("The caller reads AppTransaction only when offlineDecision returned nil"). §2.2 lists the swaps as purchase, restore and grace→grant only; it has no initial or pending state. The launch already runs `refreshReminders()` / `refreshWidgetSnapshot()` synchronously (`AppModel.swift:717-718`) before any async read could finish.

**Scenario:**
1. A legacy iOS rider deletes and reinstalls: row 9.
2. They are on hotel or captive-portal Wi-Fi. `AppTransaction.shared` neither returns nor throws for a long time.
3. The doc gives no timeout. Nothing says what `vocab` is meanwhile, and the natural default is the filtered store.
4. For the whole session the rider sees N3–N1 locked with a buy card. The widget and reminders publish filtered counts.

This breaks §E's own condition: "the failure must be 'assume entitled' when the transaction cannot be read, never 'assume not entitled'" (`PLAN-V2-PRODUCT.md:393-397`). Rows 5 and 13 behave the same way.

**Fix:**
- Add a `pending` state that **counts as open**, like grace.
- Add a bounded timeout (a few seconds) that converts to `sessionGrace`.
- Only an affirmative `production, ≥ E3` reading may close. It closes only when no run is in progress.
- Run the reminder and widget refresh after the decision settles.
- Add table rows: "pending → open" and "timeout → S".

### S3. Rule 3 reads the value with the *running* platform's meaning, so a reinstall on the second platform can get N

**Where.** §5.2 ("Rule 3 compares on macOS `Version(originalAppVersion) < threshold.macOSFirstVersion`, and on iOS … `Version([threshold.iOSFirstBuild])`"). §5.7 bullet 2 ("Either answer keeps the red line, because that iPhone is a new install that had nothing").

**Scenario.** The doc itself says universal-purchase behaviour is unmeasured. Suppose Apple reports the account's **first** platform's value.
1. An iPhone-first account has `originalAppVersion` "40".
2. That account also had the Mac app before E3.
3. Its Mac container is later removed, by a cleaner tool or by a fresh macOS user profile, and the app is reinstalled.
4. On macOS, `Version("40")` = [40] is compared with [1,39]. It is not below, so the result is **N**.

§5.7's argument covers only a *first* install on the second platform. It does not cover a *reinstall* of an install that existed. The mirror case also leaks the other way. An E3-era Mac-first account reports "1.39". On iOS that reads as [1,39] < [63], so it gets a grant. That is not a red-line problem, but it muddies Window 2's "clean denominator".

**Fix: classify the value by its shape, not by the running platform.** The repo history shows the two shapes are disjoint:
- every iOS and macOS `CFBundleVersion` ever shipped is one integer (1…62);
- every marketing version has two or more components ("1.0" … "1.36", "1.4.1", "1.8.1").

So:
- a one-component value is a build. It is below E3 if it is below **max**(macOSFirstBuild, iOSFirstBuild).
- a value with two or more components is a marketing version. It is below E3 if it is below macOSFirstVersion.

Pin both shapes with tests. Then drop §5.7's sentence "Either answer keeps the red line".

### S4. The free tier is defined by the `jlpt` field, so later corpus edits or a boundary change take content from sampler installs

**Where.** §2.2: "`VocabStore(entries: catalog.entries.filter { freeLevels.contains($0.jlpt) })`" and "`freeLevels` is one constant … The owner's C-2(d) answer changes this one line". §1's counts.

**Why it matters.** Once E3 ships, sampler installs are existing installs, and the red line says "ever". Two things can then take content away:
- **Corpus edits.** The corpus is actively corrected (v1.37's P0-2 re-reads sentences; a `v137-corpus` work clone exists). Any later release that moves an id from N4 to N3, or splits or renames an N5/N4 id, takes a word, and its SRS card, away from every sampler.
- **A boundary change.** Switching to candidate 2 after candidate 1 has shipped, "one line", takes all of N4 from every sampler.

Grandfathered installs are unaffected. This is outside the brief's literal population ("today or before E3"), but it is inside the red line's text. Today the doc describes the boundary as freely re-choosable.

**Fix:**
- Freeze the free set **by id** at the first gated release, as a golden list pinned by a test. Later releases may add ids to it and may never remove one.
- A corpus move into a paid level leaves the id free.
- `freeLevels` may only grow after the first gated release. Say so in §2.2 and §10 Q1: C-2(d) is a one-time choice before ship.

### S5. On a sampler device, existing copy invites deletions that sync to the grandfathered device

**Where.** §3 row 14 ("A list whose words are all paid shows the existing zero-playable state, plus one line"). Today that state is `unplayableHint`, which reads "These words aren't available on this device (they may come from a newer vocabulary)." (`ListsView.swift:844-849`, shown when `playableCount(in:) == 0`, `:390-391`). `playableCount` reads `vocab` (`AppModel.swift:1762-1763`), which §2.3 keeps on the rideable store.

**Scenario:**
1. A grandfathered Mac rider sets up a new iPhone. It is a sampler under rule 3 / Q3.
2. Their synced N3 list shows "aren't available on this device".
3. The doc moves word rows to the catalog. But a missed row (§2.3 is incomplete; see M1) would also show `.removed` with "No longer in the dictionary — you can remove it" (`ListsView.swift:1243-1245`).
4. The rider removes the words. Each removal stamps a tombstone (`WordListStore.swift:183-191`), sync merges it (`AppModel.swift:1424-1430`), and **the Mac loses those list entries**.

The rider pressed the button, but false copy led them there, and the loss lands on a grandfathered install.

**Fix:**
- For a sampler, replace `unplayableHint` with the true line ("N3–N1 words ride with the N3–N1 levels") rather than adding a line beside it.
- In the source scan (§9.3), assert that no `.removed` state or removal nudge is computed from the rideable store.

---

## MINOR

### M1. §2.3's catalog/rideable split misses readers

`CoachView.swift:171` reads `model.vocab.entry(id:)` to show the correct romaji. `AppModel.swift:1302` builds coach drill entries. On a sampler, an N3 headline example falls back to the accepted-key spelling. That is display-only, not a loss. Add both to the §2.3 table, and widen the §9.3 scan from builders to every `model.vocab` reader in `NihongoRideApp`.

### M2. P0-12 as built does not expose PD for `.absent`

§5.6 item 1 needs "absent (with this launch's PD)". On the marker branch, `Observation.absent` has no payload (`InstallCohort.swift:227`), and `AppModel` keeps only `installCohortAtLaunch` and discards the PD it computed **[marker branch]**. As built, row 4 (a legacy install that skipped 1.37/1.38, offline) degrades from G to S. It reaches G (row 3) the next launch, because the marker written this launch carries PD. No loss, but the interface gap is real. Either keep PD beside the observation, or let row 4 read the bytes this launch wrote.

### M3. Possible launches before first unlock on iOS (unverified)

If iOS prewarming or a background launch runs `AppModel.init` before the device's first unlock, `UserDefaults` may read empty. P0-12 would then see `.absent` and write a marker. The grant key would read absent. The outcome is still open (G or S, since `odometerLoad` would not be `.missing`, so PD is true), so this is not a loss as specified. The risk is in what the OS does with writes made at that moment. Not measured. Consider skipping both the marker write and the grant decision when `UIApplication.isProtectedDataAvailable` is false, and treating that launch as grace.

### M4. Reinstalling under a different Apple Account

Rows 1–2 protect the install while it exists. After a delete and reinstall under another account (common for learners who make a JP account), rule 3 reads that account's `originalAppVersion` ≥ E3 and returns **N**. This is arguably a new acquisition. Say it in §5.7 as an accepted cost rather than leave it implicit.

### M5. Quarantine key for the grant

§5.4 says unreadable grant bytes are copied to `<key>.unreadable`, "the house quarantine pattern (`Entitlement.swift:215-238`)". That helper's `quarantineKey` ignores its `key` parameter (`Entitlement.swift:222`, which §6.1 itself flags). Reusing it would write into `NihongoRide.entitlement.v1.unreadable`. Better, follow P0-12's rule: the grant key is never overwritten, so the key is its own quarantine and no copy is needed.

---

## NIT

- **N1.** §5.6 item 4 says a fresh marker over unreadable bytes "would turn row 16 … into rows 6–8 for a legacy rider". For a legacy rider PD is true (the settings blob exists), so it would be row 3, G. The rule is right; the stated consequence is overstated.
- **N2.** §8 "rows 1–5, 9, 13" omits row 17's grant cases.
- **N3.** §4.5 "after a restore of a refunded purchase": a refunded purchase restores nothing. The case meant is probably a refund after the rider picked N2.
- **N4.** §5.2: say what `installCohortAtLaunch == nil` maps to. That is the `touchesNothingOfTheUsers` case [marker branch]. It should map to `unreadable`. Rows 9–12 and 13–16 give the same answers, so this is a spec gap only.
- **N5.** Name the grant's scope as "everything the app contained at the install's first-seen build, plus later additions to those pools". A future E4 pack carved out of today's N1 pool would then still be covered.

---

## Checks that came out clean

- **Truth table vs PLAN-V1.37 §E: no contradiction that removes protection.** The doc's changes all make the table more generous, and each is labelled:
  - row 3 (PD on a present marker);
  - `.unverified` and unparseable values treated as `unavailable`;
  - row 17 (other-platform marker treated as unreadable);
  - `xcode` treated as nonProduction.

  §5.5's finding is correct: §E's stated reason for the order rule does not hold. Rows 8 and 12 both give S. I checked this against P0-12's real write path.
- **Is a persisted grant ever revocable? Not by the app.**
  - Row 1 returns first.
  - No production code removes defaults keys. The only `removePersistentDomain` calls are in UI-test and screenshot isolation (`AppModel.swift:2834`, `Screenshot.swift:571`).
  - The settings blob, ledgers and marker each write one key.

  The residual risk is the OS: deleting the app on iOS removes the grant, and only rule 3 can restore it (S2, S3, M4). On macOS, deleting the app normally leaves the container, so the grant survives.
- **Clock changes:** nothing in the grandfather path reads a date. Q3's ride-record idea would add one, and the doc already says so.
- **Refunding the road:** the road's update listener (`RouteStore.swift:395-404`) touches only the road ledger. The grant is a separate key with no revoked value.
- **Family Sharing off:** no path to loss. Every device's own marker or account decides.
- **Sandbox vs production:** handled correctly, rows 7, 11 and 15.
- **iCloud bringing N3 items to a non-entitled device:** kept, never pruned. Every `resolves:` use is a read, and sync merges never filter by vocabulary. The one way they leave a device is S5.
- **Version parsing:** integer components, with zero-padding, so "1.36" == "1.36.0", matching P0-12's `Version`.
- **File:line claims:** every one I sampled holds at 9c09ab7. That covers more than 60 AppModel lines, MenuView, ListsView, ResultsView, JournalView, AboutView, SettingsView, RoadView, RouteStore, Entitlement, GameSession, ConjugationSession, WordListStore, CloudKitSyncController:63, project.yml:133/136/272/275 and the cited plan lines.
- **Corpus counts:** recounted from the bundled JSON, all exact: 646/642/1,450/1,747/2,586 words; 6,724 sentences; 5,935 dictation; 2,317 verbs; passages 51/75/107.
- **Price:** none in the doc, and no placeholder. The buy button uses `product.displayPrice`.

---

## Summary

The design's core is sound. One predicate, a filtered rideable store, a write-once never-revoked grant, and a truth table that reads the pre-launch marker all hold against the code at 9c09ab7: every citation I sampled is accurate, and no persisted grant has a removal path in the app. But the red line can still be breached in five ways, all at the edges:

- **(B1)** Fixing the threshold at "the first E3 build of any channel" un-grandfathers, permanently on iOS, anyone who installs a build shipped without the gate after that upload: a hotfix, or a v1.39 released without E3.
- **(S1)** A rollback or kill switch has the same effect for installs made while the gate was off.
- **(S2)** A hanging `AppTransaction` has no timeout and no defined "pending = open" state, which breaks §E's "assume entitled".
- **(S3)** Rule 3 reads `originalAppVersion` by the running platform rather than by its shape, so a reinstall on the second platform of a universal purchase can get N. That contradicts §5.7's "either answer keeps the red line".
- **(S4)** Defining the free tier by `jlpt` level lets later corpus edits, or a boundary change, take words from sampler installs, which the red line also protects once E3 ships.

S5 adds a sync path: false copy on a sampler device invites deletions that reach the grandfathered device. Each fix is small:
- a threshold set from builds released to customers, that only ever rises, checked by the release script;
- a grant written by any ungated build, ideally on `main` from v1.38;
- `pending` and a timeout counted as open;
- rule 3 compared by the value's shape;
- a free set frozen by id;
- true copy for samplers.

None of the fixes changes the boundary or the purchase, and the doc proposes no price.
