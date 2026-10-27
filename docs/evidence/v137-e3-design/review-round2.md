# Red-line review, round 2: DESIGN-E3-SAMPLER.md (branch docs/v137-e3-design, a6a6f26)

*Adversarial, read-only review, 2026-10-27. The lens is the red line: no existing install loses anything, ever (`PLAN-V2-PRODUCT.md:369-397`), and §E's grant definition (`PLAN-V1.37.md:275-289`). Doc line numbers are at a6a6f26. Code citations are at the doc's code HEAD, 9c09ab7 (`v137-docs-e3`), unless marked **[marker]**: those are `v137-marker` @ 56a2ebc. Nothing was built or edited. The only file written is this one.*

**Verdict: one red-line breach remains, and round 1 introduced it.** It is the latch (§5.6). The latch is keyed to the container, but the fact it records (`originalAppVersion` "not below") belongs to an Apple Account. A container can outlive the account that produced that reading. When it does, an account that §E rule 3 grandfathers gets **N** permanently, without the app ever reading `AppTransaction` again. That is S-new-1 below, rated SERIOUS. Every other round-1 fix holds against the attacks I tried. Each one has small residual gaps, all MINOR or NIT. **The claim that the v1.37 marker needs no change is true at 56a2ebc.** It holds for the stored format and for every field E3 reads from a marker that v1.37 or v1.38 wrote. The E3 *build* must still change the marker's *call site* (MINOR-2). No v1.37 change is required.

Counts: 0 BLOCKER, 1 SERIOUS, 7 MINOR, 8 NIT.

---

## (1) Did each round-1 fix close its breach?

### B1: the threshold and release check. **Closed.** Two residual gaps.

I tried four attacks. Each one ends in **G**:
- **Hotfix after the gated upload.** Step 3 forces `T_build` above the hotfix (doc :186). Its fresh installs then pass rule 1.
- **v1.39 shipped without E3, then E3 in a later 1.39.x.** `T_version` must be strictly above "1.39", so the macOS rule 3 compare no longer ties.
- **"Rollback" by re-releasing v1.38's code as 1.39.1.** That build has no writer. But the next gated submit fails step 3 until `T` is raised above it. Its installs' markers are then below `T`.
- **A raised threshold.** It only grants more. A latch stored at the old `T` is ignored once `T` rises, because row L requires equality.

The residual gaps are MINOR-1 (ungated TestFlight uploads) and NIT-1 (cross-platform staleness between submit and release).

### S1: the gate-off writer. **Closed.**

- **Every gated-era install that launches a gate-off build:** row 0 writes the grant, and row 0 sits above the latch.
- **Gate-off builds without the writer:** they can only be pre-E3-branch builds, and the threshold check covers those.
- **Users who update through the ungated build without launching it:** they never had depth open, so they lose nothing.

One cost is not stated. After any ungated release in the E3 era, the next gated release must raise `T` above it. Every earlier sampler's marker then sits below `T` and gets rule 1 **G**, including samplers that never launched the ungated build. That is generous and red-line-safe, but it is a revenue and Window-2 cost the doc should name (NIT-2).

### S2: pending, timeout, latch. **Pending and timeout are closed. The latch opens a new path (S-new-1).**

- **Pending.** Pending counts as open (:301). The timeout converts to **S** (:302). A late reading may only upgrade (:303). The widget and reminders refresh after the decision settles (:305). The case round 1 raised, a captive-portal hang, now stays open throughout.
- **The latch, against your specific case** ("a reinstall whose first verified reading was taken wrongly"):
  - On iOS, delete-and-reinstall wipes the container. The latch goes with it, so every reinstall takes a fresh reading. On that path a wrong reading costs one install, not forever.
  - The lock-out happens where the container survives and the *account* changes. That is S-new-1.
  - The latch also turns any transient wrong production value from Apple into a permanent **N** on that container. Under §E exactly, the app would retry that reading at every launch.

### S3: rule 3 read by the value's shape. **Closed.**

I tried both directions:
- **A build read as a version.** Every one-component value from a legacy account is ≤ 62, which is below max(`T_build`).
- **A version read as a build.** Every multi-component legacy value is below "1.39".

So no legacy value compares "not below" in the wrong frame. A value that does not parse (whitespace, a suffix) is `unavailable`, which gives **S** and never **N**. Sandbox "1.0" is excluded by environment. A production "1.0" would be version-shaped and below `T_version`, so it would grant. The two pins (§5.3 :207) keep the shapes disjoint going forward.

One revenue-side gap: MINOR-5 (an iOS gated build numbered below max(`T_build`)).

### S4: the frozen free-id set. **Closed for loss.** One copy gap.

- **A corpus move from N4 to N3 leaves the id free**, and a sweep fixture pins that (§9.2 :502).
- **Due reviews draw from every level** (`GameSession.swift:605-622`). So a free id that moved into a locked level stays reachable through reviews and Mix.
- **The copy gap.** :79 says only that a *new* N5/N4 entry is added. It says nothing for an id moved *down* from N3 to N4. After such a correction, "N4 stays free" (§7.2) is false for that word, and a count derived from `jlpt` would not equal what the purchase opens (MINOR-6).
- **The frozen-copy test can grade itself** (NIT-3).

### S5: the sampler list line. **Closed.**

- **The false hint is replaced**, not added to (§3 row 14, :120).
- **`.removed` is computed from the catalog** (§2.3 :93).
- **A mutation pins both** (:504).

The remaining destructive actions on a sampler are clear-list, delete-list and the per-word minus. All three are user-initiated. The two list-wide ones already warn that they propagate: "removed across your devices" (`ListsView.swift:102-103`, `:116-117`). I found no other copy that invites a removal. Every `resolves:` use in `Sources/` is a read (grep: `AppModel.swift:746…2393`, `ConjugationReviewStore.swift:81-222`, `DueReminderPlanner.swift:87`).

---

## (2) New paths for loss introduced by the revision

### S-new-1. SERIOUS. The latch is per container, but its fact is per account. It suppresses rule-3 grants for good.

**Where.**
- §5.6 :308-314, which says "It never blocks a grant: rows 0–4 come before it."
- §5.5 row L (:276), which comes before rows 5 and 10, the rule-3 grants.
- §10 Q4 (:544).

**Why the safety argument fails.** The doc argues that `originalAppVersion` "remains constant … so the reading cannot become 'below' later for this account" (:309). That is true per Apple Account. The latch is stored in the container's `UserDefaults` (§5.7 :323), and the latch skips the read entirely. A container can outlive the account that produced its reading:
- **macOS.** Deleting a sandboxed app leaves `~/Library/Containers/<id>`, so the latch survives (round 1's clean-checks section said the same of the grant).
- **iOS.** "Offload App" keeps documents and data. Re-downloading an offloaded free app takes the account currently signed in to the App Store.
- **Both.** A device restored from another device's backup carries its latch.

Rows 0–4 come before L, but rule 3 (rows 5 and 10) comes after it. So "never blocks a grant" is false for the one rule that grants by account.

**Scenario (macOS):**
1. A legacy rider's Mac dies.
2. On the new Mac, the Mac App Store is signed in to a second Apple Account (a JP-storefront or work account). The rider installs the app.
3. The new container gets: marker = gated build, PD false. The reading is for the second account, so it is "not below". Row 6 returns **N** and writes the latch.
4. The rider notices the paywall, signs in to their original account, then deletes and re-downloads the app. The container stays.
5. Row L returns **N**. `AppTransaction` is never read again on that Mac until `T` rises.

Under §E exactly, step 5 reads the original account's `originalAppVersion`, which is below `T`, and grants. This install satisfies §E rule 3 and is not grandfathered. That is a breach of §E's grant definition (`PLAN-V1.37.md:275-279`).

Round 1's M4 accepted the *opposite* direction: switching *to* a post-E3 account gives **N**. This direction, switching *back to* the legacy account, has no counterpart in §5.10, and it did not exist before round 1.

**Fix.** The latch may decide the *session* but never skip the read:
- With a valid latch, the launch starts **closed**: no pending-open window, no offline grace. That keeps every benefit the doc wanted from the latch (:314).
- `AppTransaction` is still read in the background at every launch.
- Any verified "production, below" reading → **G**, persisted, at once.
- Swap the `vocab` store as a purchase does.

Then:
- Reword row L as "start closed; still read".
- Drop "never blocks a grant" or make it true.
- Add a §9.2 mutation: "latch present, reading for a legacy account → must be G".
- Add the account-switch case to §5.10.

The cost is a cached `AppTransaction` read per launch for samplers.

### MINOR-1. Ungated TestFlight uploads above every released build are not in `T_build`

**Where.** §5.2 :172 ("released to App Store customers"), :181 (TestFlight), and steps 1–5 (:183-188, which read released versions only).

**Scenario.**
- Build numbers outrun releases. macOS has 37 releases with a highest build of 61 (:179), so many uploads never shipped.
- Suppose an ungated build is uploaded for TestFlight with a number above every ungated *release* and never ships. It might be a 1.39 candidate cut before E3 merged.
- Its fresh TestFlight installs record marker build ≥ `T`, PD false. They are sandbox, so rule 3 is ignored and they get **N**.
- If the tester later moves to the App Store build, the container keeps that marker. Rows 2–4 stay closed, and only an account-level rule 3 can rescue the install.

Today this is the owner's devices only: I found no external testers in `docs/` or `scripts/`.

**Fix.**
- Compute `T_build[p]` over every ungated build **uploaded** on p (`/v1/builds`, which `asc_release.py:520-536` already queries), not only released ones.
- The cost is only that more TestFlight installs of gated builds become grandfathered, which §5.2 :181 already calls harmless.

### MINOR-2. Row 0a says "nothing written", but the P0-12 marker write in the same `init` is unguarded; and the probe may not be callable there

**Where.**
- §5.5 row 0a (:271).
- §5.9 :357 and §5.10 :367.
- **[marker]** `AppModel.swift:620-636`: the marker is written whenever `!touchesNothingOfTheUsers`, with no protected-data check.
- **[marker]** `InstallCohort.swift:281-284`: `.absent` always writes.

**Scenario (gated build, iOS):**
1. The rider skipped 1.37 and 1.38, or has a v1.37 marker on disk.
2. The first gated launch after a reboot is a prewarm before first unlock.
3. `defaults.object` reads nothing, so the observation is `.absent`.
4. The marker step writes {gated build, PD = odometer?}. The settings blob reads as absent.
5. If cfprefsd later persists that write, the legacy rider's rule-1 proof is replaced by a post-`T` marker.

Harm is bounded:
- When `odometer.json` exists but cannot be read, `LossyLoad` returns `.unreadable` (`PersistKit/LossyLoad.swift:64-70`). `odometerStored` is therefore true, so PD is true and row 3 grants.
- A rider who never rode falls back to rule 3.

Still, the doc promises "nothing written", and the code it says needs no change writes. The overwrite is harmless in v1.37 and v1.38, because any marker those builds write is below `T` → rule 1 **G**. It matters only in a gated build.

There is also a separate risk. `@State private var model = AppModel()` (`NihongoRideApp.swift:16`) can run before `UIApplicationMain`. If so, `UIApplication.shared.isProtectedDataAvailable` may not exist yet in `init`.

**Fix (E3 build only, no v1.37 change):**
- Wrap the P0-12 call in the same 0a condition.
- Define 0a by evidence `init` already has, and not only by `UIApplication`: any store load returning `.unreadable` (the odometer above, the review stores), or a settings key that reads nil while a support file exists.
- Pin it with a source scan: the marker call and the grant write sit behind one predicate.

### MINOR-3. The two grant copies are never repaired, so they protect against one loss event, not two

**Where.** §5.7 :321-329, and §9.1 :480 ("`alreadyGranted` writes nothing").

**Scenario.**
1. An OS event drops the defaults plist. The file copy carries the grant: row 1.
2. Nothing rewrites copy 1, because only `grant(_)` writes.
3. A later event loses the file. One example is an Application Support restore that excludes it. The grant is gone.
4. A legacy reinstall-class rider is back on rule 3 alone, or on **N** under S-new-1.

**Fix.**
- On `alreadyGranted`, write a missing copy if absent, and never overwrite a present one, readable or not.
- Add a `Reason` such as `restoredFromOtherCopy`, or copy the surviving bytes verbatim.
- Add a §9.1 test: "copy 1 absent, copy 2 present → copy 1 recreated; neither overwritten".

### MINOR-4. Long session grace that ends in N, for an E3-era install, is not addressed

**Where.** §5.10 :365, which states the never-online cost but not what happens at the end of it, and §4.1 :139.

**Scenario.** The account may be signed out of the App Store, the reading may be unverified on a wrong clock, or the iPad may be offline for weeks. The install gets **S** at every launch and rides N3–N1 for weeks. It builds N3 SRS cards. Then one launch reads "production, not below": **N** and a latch.

§E's red line is about *existing* installs, and this one is new. But the doc itself argues (§2.2 :80, §1 :52) that sampler installs "are existing installs once E3 ships", and this rider has had depth for weeks.

**Fix.** Choose and state one:
- (a) Accept the cost, with copy at the transition. For example, the depth card says the levels were open "while the App Store could not be reached".
- (b) Cap grace in wall-clock terms, so that long-lived grace never quietly becomes "what the install has".

Either way, name it in §5.10.

### MINOR-5. An iOS gated build numbered below max(`T_build`) grants every fresh iOS install online. This is not a red-line issue

**Where.** §5.3 :204 (max of both platforms), and step 3 (:186).

**Scenario.** Build counters are per target (`check_versions.py:78`). If macOS gets more bumps than iOS (mac-only rebuilds), `T_build[macOS]` can exceed the iOS gated build. A fresh iOS install then reports its own build, for example "66", which is below max(65, 67) → **G**. The gate goes silently dead on iOS for every online install, and Window 2's denominator is wrong.

**Fix.** Release-check step 3 also asserts that each platform's gated build is ≥ max(`T_build[macOS]`, `T_build[iOS]`), bumping the lagging counter if needed.

### MINOR-6. The free set grows only by new entries, so "N4 is free" can become false

**Where.** §2.2 :79, and §7.2 :413-418.

**Scenario.** A corpus correction moves an id from N3 to N4. The id is not new, so it is not added. A sampler sees an N4-tagged word that does not ride, under copy that says N4 is free. A depth-card count by `jlpt` would also differ from what the purchase opens.

**Fix.**
- State that any id whose `jlpt` becomes a free level is added in the same commit, not only new entries.
- Compute the card's counts as catalog minus `DepthFreeSet`, never by `jlpt`.
- Pin both with one test.

### MINOR-7. The release registry is written by the script that checks it

**Where.** §5.2 :185 ("appended by the release script at each submit").

**Scenario.** Suppose an ungated build is recorded as gated because of a flag typo or a wrong branch. Step 3 then never forces `T` above that build, and B1 returns. This is the same failure as `feedback-a-test-that-grades-itself`.

**Fix.**
- Derive "gated" from the archived binary: a plist key emitted from the gate constant, read out of the `.xcarchive` the script uploads.
- Say explicitly that a build absent from the registry counts as **ungated**, the direction that raises `T`. That covers every pre-E3 build, none of which will be in a new file.

---

## (3) "No change to the v1.37 marker is needed": **true at 56a2ebc**

What E3 reads from a marker that **v1.37 or v1.38** wrote:
- **firstSeenBuild and platform.** Rule 1 needs only these, and any such marker is below `T`, so it grants **G** whatever its PD says.
- **Decodability.** v1.37 pins this.

Each property E3 needs from the v1.37 marker holds at 56a2ebc:

| E3 needs | at 56a2ebc |
|---|---|
| written for every legacy install that launches 1.37/1.38 | one call, `AppModel.swift:625-636` **[marker]**, every non-isolated launch |
| never overwritten (write-once, so v1.37's rule-1 proof survives every later build) | the only write is in `.absent` (`InstallCohort.swift:281-284`). `.present` and `.unreadable` write nothing (`:285-287`) |
| the build per platform, as `CFBundleVersion` | `Running` from `Bundle.main` (`AppModel.swift:627-631` **[marker]**). `project.yml:59, 206` map `CFBundleVersion` to `CURRENT_PROJECT_VERSION`. Non-digit builds are refused (`InstallCohort.swift:134-138`) |
| a strict, frozen, decodable format | schema 1, every field required (`:172-187`). Golden bytes are pinned (`InstallCohortTests.swift:18, 242, 260`) |
| the pre-launch observation | `recordLaunch` returns it (`:308-316`). Kept as `installCohortAtLaunch` (`AppModel.swift:420-424` **[marker]**) |
| PD computed before this launch's settings save | the read is at `:634` **[marker]**, and the save is at `:742`. `AppSettings.load` does not write (`AppSettings.swift:266-271`) |
| local only | `theKeyIsReachedFromNowhereElse` (`InstallCohortTests.swift:273-310`) |

A wrong PD in a v1.37 marker cannot hurt. That includes a PD from a prewarm before first unlock: rule 1 decides before PD is read. Within v1.37 the marker write adds no prewarm risk that `settings.save` at `:742` does not already carry.

**One correction to the doc's reasoning (NIT-4).** §5.9 :359 and §12 M2 say that keeping PD beside the observation "would have to land before v1.37 ships". It would not. Row 4 is exactly the case where the marker was absent before the *gated* launch. So the PD it needs is computed by the gated build's own `init`, and the gated build can keep it in memory itself. §5.9 step 3, the re-read accepted only if build and platform match, is therefore an unneeded workaround with its own failure path: "the write did not happen → PD false". Replace it in E3 with a kept PD. v1.37 is unaffected either way.

**Optional v1.37 hardening (NIT-5), not required.**
- **The problem.** `Marker.encoded()` returns `Data()` if encoding fails (`InstallCohort.swift:198-202`), and `decide` would store those empty bytes. Every later read would then be `.unreadable`, and that state is permanent.
- **How likely it is.** Encoding these types cannot fail in practice.
- **The fix.** A one-line guard (no write when encoding yields empty data) costs nothing, and the format becomes permanent at ship.

**What must never change after v1.37 ships.** The `InstallCohort.Marker` decoder and the three golden strings in `InstallCohortTests`. If any E3-era edit to them makes v1.37 bytes undecodable, every legacy install drops to rows 10–14: no offline protection, and rule 3 only. Say so in §5.9 (NIT-6).

---

## NITs

- **NIT-1.** Thresholds are checked at `--submit` (:183), but customers receive the build at *release*. An ungated release on the **other** platform in between (allowed, since in-flight versions are per platform) leaves the gated binary's `T_build[other]` and `T_version` stale. Re-run step 3 at manual or phased release, and block ungated releases on either platform while a gated one is pending.
- **NIT-2.** State the cost found under S1: an ungated release in the E3 era plus the forced rise of `T` grandfathers every earlier sampler, whether or not it launched the ungated build.
- **NIT-3.** The `DepthFreeSet` "frozen copy" (:79, :518) lives in the same repo as the list. Pin its hash in the release registry, or compare with `git show <first-gated-tag>:<path>`, so that one commit cannot change both.
- **NIT-4.** See (3): §5.9 step 3 and its "must land before v1.37" are unnecessary.
- **NIT-5.** See (3): the `encoded()` empty-data write.
- **NIT-6.** See (3): declare the marker's decoder and its golden bytes frozen.
- **NIT-7.** Spec gaps around the latch:
  - Say that unreadable latch bytes mean **absent**. They must not follow the grant's "presence is truth" rule (:327), which an implementer may copy.
  - §5.6 :310 says the latch is written "only over a present, readable marker". But §5.9 step 3's fallback routes a failed marker write into rows 5–9, which include row 6's latch write. It is harmless, because row L requires a present marker, but the two statements contradict each other.
- **NIT-8.** Four smaller points:
  - **Row 3's justification is false.** :294 says a post-`T` marker with PD true "only a pre-marker install can have". A sampler whose defaults plist was dropped while `odometer.json` survived also qualifies. So does a macOS sampler who runs `defaults delete … NihongoRide.installCohort.v1` (row 4). Both errors are generous.
  - **"Presence of any bytes is a grant" (:327)** makes the depth one `defaults write` away on macOS. That is a product choice, not a red-line issue, and it should be stated as one.
  - **The App Review note's "delete the app and install fresh" (:434)** does not reset a sandboxed Mac app, whose container survives deletion. Say "a new macOS user account" for the Mac reviewer.
  - **§5.4 :213 contradicts itself.** `DepthGrandfather` "imports neither … SettingsKit" yet "can reuse the marker's integer `Version`". If the rules are copied instead, add one table test that both `Version` types agree on, for example on "1.36" == "1.36.0".

## Checks that came out clean

- **Offline.**
  - A legacy rider who launched 1.37: row 2.
  - A legacy rider who skipped 1.37 and 1.38: row 4, through this launch's PD (settings blob present).
  - A legacy iOS reinstall: **S** until online, then rule 3.
  - Nothing in rows 0–4 reads the network or a clock.
- **Reinstall** on the same account: rule 3 by shape → **G**. See S-new-1 for an account change.
- **The other platform.**
  - A first install on the second platform never had anything.
  - A reinstall there is covered by S3.
  - Another platform's marker is unreadable, so rows 10–14 apply.
- **iCloud sync.**
  - No key that decides access is a CloudKit record type (`CloudKitSyncController.swift:63`).
  - Nothing sweeps defaults into KVS: the scan at `InstallCohortTests.swift:303-309`.
  - Merges never filter by vocabulary.
- **Backup and restore.** Both grant copies, the marker and the latch restore together. A restored legacy marker is below `T` → rule 1 survives a restore even when the App Store account differs.
- **Downgrade** (macOS: running an old binary).
  - v1.38 ignores the grant and latch keys and writes only its own key (`AppSettings.swift:273-275`).
  - It never touches the marker, because the marker is write-once.
  - Upgrading again finds the grant: row 1.
- **Corrupted marker.** `.unreadable` leads to rows 10–14 (rule 3 only, or **S**). Neither ever gives **N** offline. Corrupted grant bytes still count as a grant.
- **Launches before first unlock.** Row 0a gives **S** and comes before row 1, so a grandfathered rider is open while the grant is unreadable. The gap is MINOR-2.
- **Deletion paths.** No production code removes defaults keys or support files belonging to the user. The only `removeItem` / `removePersistentDomain` calls are in capture, UI-test isolation and CloudKit's own state files (`Screenshot.swift:564-571`, `AppModel.swift:1096, 2834`, `CloudKitSyncController.swift:208, 565-567`).
- **Background launch paths on iOS.** None: no `UIBackgroundModes`, BGTask or AppIntents in `Sources/` or `project.yml`. A prewarm is the only launch that can come before first unlock.
- **Citations I re-checked**, all accurate:
  - at 9c09ab7: `ListsView.swift:390-391, 844-849, 871-876, 1243-1245`; `WordListStore.swift:183-191`; `AppModel.swift:1424-1430`; `check_versions.py:65-90, 78`; `asc_release.py:520-536`; `project.yml:136, 275`.
  - on the marker branch: `InstallCohort.swift:86-96, 134-138, 193-196, 215-264, 278-289, 308-316`; `AppModel.swift:420-428, 625-636`.
- **No price and no price placeholder** in the revision.

---

## Summary

Round 1's fixes hold on the paths it found.
- **The threshold.** Defined above every ungated release and rising only, enforced before each submit. It survives a hotfix, a v1.39 released without E3, a rollback re-release and a raised literal.
- **The gate-off writer.** It turns any kill switch into grants.
- **Pending and the timeout.** Pending is open, and the timeout ends in session grace. That closes the hanging-`AppTransaction` hole.
- **Rule 3 by shape.** No legacy value can compare "not below" in the wrong frame.
- **The frozen free set.** Corpus moves can no longer take a word from a sampler.
- **The sampler list line.** No false copy invites a synced deletion.

**One red-line breach remains, and the revision introduced it.** The latch (S-new-1) stores an account-level fact in a container that can outlive the account. On macOS, where deleting the app keeps the container, and on iOS through offload or restore, a rider who switches back to their legacy Apple Account is permanently refused the rule-3 grant §E promises them. The fix keeps everything the latch was for: a latched launch starts closed but still reads `AppTransaction`, and a verified "below" reading grants at once.

The other new findings are MINOR. They cover:
- `T_build` ignoring ungated TestFlight uploads;
- the marker write that row 0a's "nothing written" does not cover;
- grant copies that are never repaired;
- long grace that ends in N for an E3-era install;
- an iOS gated build below the cross-platform max;
- "N4 is free" drifting after corpus moves;
- a registry the release script grades itself on.

The v1.37 marker at 56a2ebc needs no change. Every marker v1.37 or v1.38 writes sits below `T`, so rule 1 decides from its build and platform alone. Its write-once rule, strict schema, per-platform build and golden bytes are already pinned. The doc's re-read workaround for PD is unnecessary, because the gated build can keep PD itself. One one-line hardening, no write when encoding yields empty bytes, is worth considering before the format becomes permanent.
