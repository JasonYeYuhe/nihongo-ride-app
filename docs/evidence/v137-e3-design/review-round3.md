# Red-line review, round 3: how DESIGN-E3-SAMPLER.md answered it (branch docs/e3-r3, from main a34769c)

*Written 2026-10-30. The review is the round-3 red-line review of `docs/DESIGN-E3-SAMPLER.md` at `release/v1.37` @ 25a472e (the file is identical at `main` @ a34769c). Its findings are copied byte for byte beside this file, as `review-round3-findings.json`: 0 BLOCKER, 1 SERIOUS, 4 MINOR, 5 NIT. This file records, for each finding, what was checked, the disposition, and what changed, with section references into the design.*

*Where checks were made.* Doc lines are the file at a34769c, before this round. **`main` does not have the v1.37 marker.** `Sources/SettingsKit/InstallCohort.swift`, its tests and `AppModel`'s marker call exist only on `release/v1.37`. So the marker checks were read at 25a472e with `git show`, and are tagged **[25a472e]**. Other code was read at a34769c. ASC was read by GET only, through `scripts/asc_api.sh`, on 2026-10-30. Apple's documentation was read the same day. Nothing was built.

*Unchanged by this round.* Nothing ships before the owner's C-2 box (PLAN-V1.37 Appendix A-1). No price, no price placeholder, and no decision cell. New owner questions go to §10 with a default on silence (the brief said "§11 (open questions)"; the design's open questions are §10, and §11 is "where the plan and the code disagree").

**Verdict.** Every finding holds against the code and the doc. All ten are taken. Three are taken with a change to what the review proposed, each for a stated reason (r3-S1, r3-M3, r3-N5). None is rejected outright. Two of the review's supporting claims are corrected below: one about what Apple's page says (r3-M3), and one about which numbers are stale (r3-N5).

| # | sev | disposition | design sections changed |
|---|---|---|---|
| r3-S1 | SERIOUS | **ACCEPT**, other-platform marker placed differently | §5.4, §5.5 (row 4a, rows 10–14, notes), §5.9 items 2/4/5, §8, §9.1, §9.2, §11 item 6, §12 |
| r3-M1 | MINOR | **ACCEPT** | §5.5 row 4, §5.9 item 3, §9.1, §9.2, §11 item 10, §12 |
| r3-M2 | MINOR | **ACCEPT** | §5.5 notes, §5.6, §5.7, §5.10, §9.1, §9.2, §9.3, §12 |
| r3-M3 | MINOR | **ACCEPT**, one refinement | §5.3, §5.4, §5.5 rows 5/6/8/11, §5.10, §9.1, §9.2, §10 Q7, §11, §12 |
| r3-M4 | MINOR | **ACCEPT** | §5.1, §7.4, §8, §9.4 V2, §10 Q8, §12 |
| r3-N1 | NIT | **ACCEPT** (the review's second option) | §5.5 row 0a, §5.9 item 1, §5.10, §9.1, §9.2, §12 |
| r3-N2 | NIT | **ACCEPT** | §2.2, §9.2, §9.3, §12 |
| r3-N3 | NIT | **ACCEPT** | §7.1, §10 Q9, §12 |
| r3-N4 | NIT | **ACCEPT** | §7.4, §11, §12 |
| r3-N5 | NIT | **ACCEPT in part** | header, §1, §5.1, §5.2, §5.3, §5.4, §5.7, §5.9, §9.2, §11, §12 |

---

## SERIOUS

### r3-S1. An unreadable marker has no offline route to a grant. **ACCEPT.**

**Checked.**
- Doc :363 (§5.9 item 4) admits the gap and leaves it as "should … before E3 ships". Rows 10–14 (:290-294) offer rule 3 only. §9.1 (:498-508) has no test for "unreadable marker + PD true".
- `InstallCohort.Observation.unreadable` covers corrupt bytes, a non-`Data` value (`Stored.notData`) and a schema or platform value a later build wrote (`InstallCohort.swift:225, 243-281` **[25a472e]**). Its own comment says this state is worse than no marker, and that closing the gap is E3's job (`:263-274`).
- `decide` writes nothing on `.present` or `.unreadable` (`:312-314`), so the state never heals.
- PLAN-V1.37 §K lists "Grandfathering that depends on the network" as not done (`docs/PLAN-V1.37.md:438`).
- The path holds. A pre-E3 rider with a bad marker, signed in to a non-legacy App Store account, gets row 11 **N** on every online launch. The same install with no marker gets row 4 **G**.

**Disposition.** Accepted, decided in the table rather than in prose.

**What changed.**
- **§5.4.** `Cohort.unreadable` becomes `.unreadable(priorDataPresent:)`, and a new case, `.notRecorded`, covers isolation only. A new grant reason, `priorDataUnreadableMarker`, records why.
- **§5.5, new row 4a.** "Marker unreadable before this launch, and the kept PD is true" → **G**, decided offline, on the same evidence row 4 accepts. Rows 10–14 now read "marker unreadable and kept PD false; or `notRecorded`". The notes say rows 0–4a never read the network, and name the generous error (a sampler whose marker went bad after riding also gets G, as with rows 3 and 4).
- **§5.9.** Items 2, 4 and 5 map other-platform markers and unreadable bytes to `.unreadable(<kept PD>)`, and `nil` to `.notRecorded`.
- **§8.** Row 4a joins the granting rows.
- **§9.1.** New test: "corrupt marker bytes + settings blob present, `AppTransaction` production and not below → G, decided offline", plus non-`Data` and other-platform variants, and `notRecorded` never reaching 4a.
- **§9.2.** Mutations: drop row 4a; map unreadable to `notRecorded`; let `notRecorded` grant or write. Each must go red.
- **§11 item 6.** Updated to match.

**Where this differs from the review's fix.** The review put another platform's marker under `.notRecorded`, with isolation. Here it goes with the unreadable bytes and carries PD *(agent's choice, 2026-10-07 delegation)*.
- **Why.** It is write-once and never heals, exactly like corrupt bytes, so the review's own argument applies to it word for word. Carrying PD into it can only add a G.
- **What is unchanged.** Isolation stays unable to grant offline or to write, as the review asked.

---

## MINOR

### r3-M1. §9 and §11 still specified the removed re-read. **ACCEPT.**

**Checked.**
- Doc :504: "`.absent` with no readable write → rows 5–9". Doc :521: "Drop the row-4 read of this launch's own marker". Doc :598: "E3 reads PD from this launch's own write instead".
- All three contradict §5.9 items 1 and 3 (:360-362), which round 2 rewrote.
- At 25a472e, `Running` nil or `encoded()` nil makes `decide` write nothing (`InstallCohort.swift:308-311, 210-214` **[25a472e]**). Under the stale spec, a pre-E3 rider who skipped 1.37 and 1.38 would get S offline and N online, on every launch.

**What changed.**
- **§5.5 row 4** now says "the PD this gated build computed and **kept** … whether or not this launch wrote a marker".
- **§5.9 item 3** names the no-write case and records that §9 and §11 described round 1 until now.
- **§9.1**: "`.absent` + kept PD true → row 4 G, including when this launch wrote no marker (`Running` nil; `encoded()` nil)".
- **§9.2**: the mutation is now "derive row 4's PD from the key after the write instead of the kept local". It must go red when the write is suppressed.
- **§11 item 10** is rewritten: E3 computes PD before the marker call, keeps it, and never reads it back.

### r3-M2. "Exactly once" needs persisted state the scans forbade. **ACCEPT.**

**Checked.**
- Doc :390 requires the grace line to show "exactly once" after "a session that was in grace". Both facts span processes.
- Doc :322 pins that "no other E3 key is written". Doc :551 pins "the grant key appears in one write and no remove".
- Doc :337 (round 2's copy repair) is a second write site, so the tests as written forbade both features.

**What changed.**
- **§5.7** adds one display-only key, `NihongoRide.depthGraceNotice.v1`, in settings `UserDefaults`, never synced. It holds two flags, `graceSeen` and `shown`. §5.7 also adds one grant-writing function, `writeGrantCopies(_:)`, called from `grant(_)` and from the copy repair.
- **§5.10** specifies the notice key:
  - `graceSeen` is set at rows 8 and 13 and at the timeout. Pending does not set it, and neither does row 0a, which writes nothing.
  - `shown` is set when the depth card renders the line.
  - Unreadable bytes mean "shown", and they are left alone.
  - Its writes sit behind the same predicate as every other E3 write.
- **§5.6** says what the scan now allows: two grant copies and this one key, by name.
- **§5.5** now says "no access state" is written on N.
- **§9.3** restates the scan: one writing function with two callers and no remove; the notice key allowed by name; `DepthGrandfather` and `depthIsOpen` never mention it.
- **§9.1 and §9.2** add the matching tests and mutations.

### r3-M3. `AppTransaction.originalPlatform`. **ACCEPT, with one refinement.**

**Checked (Apple's documentation JSON, read 2026-10-30).**
- **`originalPlatform`** (https://developer.apple.com/documentation/storekit/apptransaction/originalplatform):
  - abstract: "The platform on which the customer originally purchased the app";
  - declaration: `let originalPlatform: AppStore.Platform`;
  - introduced in iOS 18.4, iPadOS 18.4, Mac Catalyst 18.4, macOS 15.4, tvOS 18.4, visionOS 2.4 and watchOS 11.4.
- **`AppStore.Platform`** has the values `iOS`, `macOS`, `tvOS` and `visionOS`.
- **`originalAppVersion`** gives `CFBundleShortVersionString` "for apps running in macOS", and `CFBundleVersion` "for apps running on all other platforms".
- **Deployment targets:** macOS 14.0 and iOS 17.0 (`project.yml:20-22`).

**One correction to the review's claim.** The review says that with `originalPlatform` "the app can know which platform's numbering the value uses". Apple's text does not say that. It ties the numbering to the platform the app is *running* on, and `originalPlatform` names only where the purchase was made. So the design uses the field as a **detector** of cross-platform readings, not as a statement of numbering.

**What changed.**
- **§5.4.** `AppTransactionReading.production` carries `originalPlatform: OriginalPlatform?`. It is nil below iOS 18.4 / macOS 15.4, where shape decides alone.
- **§5.3, the rule.**
  - `macOS` expects a version; any other platform expects a build.
  - Platform and shape agree → decide as the shape rule does.
  - They disagree and the value is not below → `unavailable` → **S**. Never N.
- **The refinement** *(agent's choice, 2026-10-07 delegation)*. The review proposed S for every disagreement. Here a disagreement whose value is **below by its shape** stays **G**.
  - **Why it is sound.** The shapes are disjoint, every legacy value is below in its own frame, and every gated build is ≥ max(`T_build`) (§5.2 step 3). So a below-by-shape value can only come from a pre-E3 build.
  - **Why it matters.** Making it S would turn a round-2 grant into session grace. That is a regression.
  - **The invariant, pinned by a test:** `originalPlatform` can only turn an N into an S.
- **The cost, stated in §5.3.** If Apple numbers by the running platform, every account's first install on its other platform disagrees. E3-era accounts then get S there on every launch, so the gate is open on the other platform for cross-platform accounts. That is the price of "never N on a disagreement", which the brief requires.
- **§10 Q7** asks whether to settle disagreements by `AppTransaction.originalPurchaseDate` (Apple-signed; https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate, read 2026-10-30). That would grant a legacy account's first install on its other platform (before the first gated release → G), and close the leak (on or after → N). Default on silence: §E's rules as written, no date rule.
- **Also updated:** §5.5 rows 5, 6, 8 and 11; §5.10; §9.1 (an eight-case table and the invariant); §9.2 (two mutations); §11 ("not verified").

### r3-M4. App Review on a reused device. **ACCEPT.**

**Checked.**
- Doc :459 *asks* for a fresh install or a new macOS user account.
- A sandboxed Mac container survives deletion (`project.yml:74`).
- ASC GET 2026-10-30 (`/v1/apps/6777469778/appStoreVersions?include=build`): 37 macOS and 39 iOS versions, all `READY_FOR_SALE`.
- Rules 1–2 grant a reused device in the sandbox (doc :162).
- Guideline 2.1(b), read 2026-10-30 (https://developer.apple.com/app-store/review/guidelines/), asks that IAPs be "visible to the reviewer", and that one which "cannot be found or reviewed in your app" be explained in the review notes.

**What changed (§7.4).**
- **A screen recording** of the sampler flow, attached through the version's App Review attachments. The endpoint is confirmed by GET 2026-10-30; 1.36's Mac review detail has 0 attachments. **The owner makes the recording**, because it contains a purchase and PLAN-V1.37 §K forbids any purchase by an agent in any environment (`docs/PLAN-V1.37.md:431`).
- **The IAP review screenshot** shows the depth card. The road IAP's screenshot record exists (GET 2026-10-30).
- **One line in the review note** points at the attachment.
- **The 2.1 reply**, drafted now, to post only if that rejection comes and only after the owner reads it.
- **What the plan does not do:** no hidden reviewer path, which guideline 2.5.19 forbids, and no build switch, which §5.2 would turn into grants.
- **§5.1** notes that a reused review device is grandfathered.

**The read-only "included" Settings line** for grandfathered installs is **not decided**. It breaks "existing riders' UI byte-identical to v1.38" (§8; §9.4 V2), so it is **§10 Q8**, an owner choice for C-2. Default on silence: **not shown**. §8 and §9.4 V2 point to it.

---

## NIT

### r3-N1. Row 0a pre-empts the broader PD; "support files" was undefined. **ACCEPT** (the review's second option).

**Checked (all at 25a472e).**
- A 1.0/1.1 install has `review.json` and `history.json` and no settings key. Row 0a's clause 2 catches it, so the first gated launch is **S**.
- The end-of-`init` save writes the key (`AppModel.swift:754`). Launch 2 is row 4 **G**.
- `supportFileURL` creates the `NihongoRide` directory on every launch (`AppModel.swift:2894-2895`). If "support files" counted the directory, every fresh install would hit 0a on launch 1 and get row 4 **G** on launch 2.
- The six `LossyLoad` stores are loaded at `:540-547, 551-568` and listed at `:576-582`. Word lists load later, at `:708`.

**Why the second option.** The review's first option was to narrow clause 2 to "settings nil AND a store `.unreadable`". That reduces clause 2 to clause 1. Clause 2 is the guard for a launch where defaults read empty while files exist. That is what a launch before first unlock looks like, and the design calls such a launch unmeasured (§5.9, §11). Keeping the clause costs a 1.x rider one launch of S, which is open anyway.

**What changed.**
- **§5.10** defines `supportStoresPresent` exactly:
  - the six stores, counted when their outcome is not `.missing`;
  - `word-lists.json` and `saved-words.json`, counted by existence;
  - not counted: the directory, `cksync-state.json` and `.corrupt` siblings.
  - One function feeds both row 0a and §5.9's broad PD.
- **§5.9 item 1** drops round 2's false claim. It states the two-launch sequence, and that the two PD expressions agree on every launch past 0a.
- **§5.5 row 0a** cites the definition.
- **§9.1** adds the two-launch test and "a fresh install is not row 0a". **§9.2** adds a mutation that counts the directory.

### r3-N2. The free-set golden test conflicted with corpus withdrawals. **ACCEPT.**

**Checked.**
- Withdrawals are handled at read time by `resolvesID` (`Sources/VocabKit/VocabStore.swift:172-185`).
- No recorded withdrawal list exists anywhere in `Sources`, `Tests`, `scripts` or `docs/measurements` (grep, 2026-10-30).

**What changed.**
- **§2.2.** The commit that removes a corpus entry appends its id to `DepthFreeSet.withdrawn`, a grow-only list. The id stays in `DepthFreeSet`.
- **§9.3.** The golden test now reads "resolves in the catalog **or** is a recorded withdrawal".
- **§9.2.** A mutation removes a withdrawn id from the set; it must go red.

### r3-N3. The 0 km reading of §K was not labelled. **ACCEPT.**

**Checked.** §K's line, "A 0 km entrance (P1-9), or any entrance to a purchase that shows nothing on purchase" (`docs/PLAN-V1.37.md:434`), and its ban on agent-authored meaning (`:430`).

**What changed.**
- **§7.1** labels the reading *(agent's reading, 2026-10-07 delegation)*. It also names the stricter reading and what it would cost: both entrances behind a distance, the Settings row included.
- **§10 Q9** asks the owner. Default: the agent's reading, labelled; the owner's word at C-2 replaces it either way.

### r3-N4. Nothing said the depth IAP is never promoted. **ACCEPT.**

**Checked.**
- There was no "promot" or "PurchaseIntent" in the doc at a34769c (grep).
- §K bans a Promoted IAP without handling (`docs/PLAN-V1.37.md:436`).
- ASC GET 2026-10-30, `/v1/apps/6777469778/promotedPurchases`: `total 0`.

**What changed.**
- **§7.4.** "Never promoted", with the reason. The release script reads back `promotedPurchases` (GET) before submit, and stops if the depth product is there.
- **§11.** The empty list is recorded under "state read 2026-10-30".

### r3-N5. Stale citations and "today" numbers. **ACCEPT in part.**

**Checked.** Every marker behaviour the design states holds at 25a472e, as the review says. Re-cited by symbol:

| symbol | lines **[25a472e]** |
|---|---|
| `Observation` | 243-281 |
| `decide` | 305-316 |
| `recordLaunch` | 352-359 |
| `Running.init?` | 141-146 |
| `firstSeenBuild(isBefore:on:)` | 202-205 |
| `encoded()` | 207-214 |
| `Marker.init(from:)` | 181-196 |
| `Version` `<` / `==` | 93-103 |
| `installCohortAtLaunch` | `AppModel.swift:424` |
| the marker call | `AppModel.swift:627-648` |
| `writtenBytesReadBack` | `InstallCohortTests.swift:353` |
| `noLaunchBeforeFirstUnlock` | `InstallCohortTests.swift:389` |
| `markerJSON137` / `markerJSON137iOS` | `InstallCohortTests.swift:19, 23` |

**Dictation, recounted 2026-10-30** from the corpus at 25a472e:
- 796 exclusions; N4 554, N2 1,509, N1 2,119; total **5,928**.
- Candidate 1: free 1,072 and paid 4,856. Candidate 2: paid 5,410.
- `main` @ a34769c still has 789 exclusions and 5,935, because P0-2's withholdings are on the release branch only.

**The part not taken as stated.** The review lists "macOS 61 and iOS 62 today" as stale, "now 62 / 63".
- As the **highest released builds**, 61 / 62 are still correct today. ASC GET 2026-10-30: the highest released and the highest uploaded builds are 61 / 62, and no 1.37 version record or build exists yet.
- 62 / 63 are v1.37's own builds in `project.yml` at 25a472e. `main` still reads 61 / 62.
- So the design keeps 61 / 62 as "highest released", adds 62 / 63 as "v1.37's builds", and says where each lives (§5.1, §5.2). Git history of `CURRENT_PROJECT_VERSION` is now 1…63, all integers (§5.2, §5.3).

**What changed:** the header (where citations point), §1, §5.1, §5.2, §5.3, §5.4, §5.7, §5.9, §9.2, §11. Round 1 and 2 tables in §12 keep their original citations as the historical record.

---

## Rejected

Nothing outright. In three places the design takes a finding but not exactly as proposed. Each is labelled as the agent's choice or reading under the 2026-10-07 delegation:
1. **r3-S1.** Another platform's marker carries PD (with unreadable bytes), not `notRecorded` (with isolation). Reason: it is write-once and never heals, like corrupt bytes. The change only adds G.
2. **r3-M3.** A platform–shape disagreement that is below by shape stays G, not S. Reason: such a value can only be pre-E3, and S would regress a round-2 grant. The claim that `originalPlatform` tells the numbering is not in Apple's text.
3. **r3-N5.** "61 / 62 today" is kept as the highest released builds, which is still true by ASC GET 2026-10-30. 62 / 63 are added as v1.37's own builds.
