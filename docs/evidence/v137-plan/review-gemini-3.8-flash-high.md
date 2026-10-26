### Verdict

[`docs/PLAN-V1.37.md`](../../../docs/PLAN-V1.37.md) is technically meticulous on debt cleanup, contrast measurements, and instrument mechanics, but **commercially delusional and strategically paralyzed**. The owner said: *"我想把我们目前付费的功能都做得更好一点 想要开始盈利了"* (make current paid features better; we want to start making money). In response, this plan constructs an elaborate procedural maze that defaults to doing nothing commercial: it locks the project into 4 more weeks of an already uninterpretable Window 1, follows a "STOP BUILDING" prescription that forbids raising price or adding Pro in v1.38, and makes **E1 (adding another road of cosmetic scenery into the same ¥10 SKU)** the default Phase 2 strategy. Selling cosmetic scenery for ¥10 after 48 rides cannot reach ¥50/month by the plan's own arithmetic; doubling down on scenery guarantees that months of engineering will yield zero revenue. Furthermore, the plan hinges its entire measurement validity on a 75-minute manual walk by an owner who has repeatedly declined manual tasks for 48 days, introduces an inverted statistical decision row ($N_2 = \lceil 3/c^*\rceil$) that terminates Window 2 after just 15 days at ¥10, and exposes the app to App Store Review rejection by putting a 0 km entrance in front of an IAP that unlocks nothing until 28 km.

---

### Numbered Findings

#### 1. BLOCKER — §E / §B: Phase 2 Defaults to Scenery (E1) at ¥10, Which the Plan Already Proved Cannot Monetize
* **Plan Section:** [§E:198-202](../../../docs/PLAN-V1.37.md#L198-L202), [§B:123](../../../docs/PLAN-V1.37.md#L123), [§F:241-246](../../../docs/PLAN-V1.37.md#L241-L246).
* **The Claim:** The default next commercial step is E1 (*"A second road inside the existing SKU, advertised as part of it (default)"*), keeping price unchanged at ¥10 unless overridden.
* **The Evidence:**
  1. [§B:123](../../../docs/PLAN-V1.37.md#L123) explicitly acknowledges: *"¥10 scenery cannot reach the floor at today's traffic however well it is presented, because it needs 7.6% of all installs."*
  2. [`docs/PLAN-STAGE1.md:155-167`](../../../docs/PLAN-STAGE1.md#L155-L167): At ~2.6 installs/day (~78/mo) and ¥8.42 net, reaching ¥50/mo requires 5.94 sales/mo (7.6% of all installs). Because Kyōto requires 25,000 m (48 rides in Journey mode, [`PLAN-STAGE1.md:617`](../../../docs/PLAN-STAGE1.md#L617)), if even 10% of installs reach Kyōto, conversion among arrivers must be 76%—an impossible rate for background palettes.
  3. Market comparables ([§F:220-230](../../../docs/PLAN-V1.37.md#L220-L230)): Rail Typing (¥128 lifetime), 日语打字通 (¥66.80), TypeAll (¥68), MARU (¥148), MOJi (¥228), Kanji Study ($29.99). **Zero competitors sell scenery.** Every single comparable sells core learning depth (JLPT levels, vocabulary packs, passage sets, review modes).
  4. Adding a second road (E1) into the existing SKU gives away more engineering effort for ¥0 marginal revenue, locking the project into a product type that cannot reach the floor.
* **Recommended Change:** Kill E1 as the default. Make **E3 (Free sampler + Paid depth unlock, e.g. JLPT N4–N1 levels or full sentence database with grandfathering)** the explicit Phase 2 goal. At a standard indie one-time tier (e.g. ¥68 lifetime, net ~¥57.26), reaching ¥50/mo requires only 0.87 sales/mo, or **1.1% conversion** ([§F:244](../../../docs/PLAN-V1.37.md#L244)), which is realistic for educational software.

---

#### 2. BLOCKER — §H: Window 2 Decision Row ($N_2 = \lceil 3/c^*\rceil$) is Inverted and Statistically Flawed
* **Plan Section:** [§H:272-274](../../../docs/PLAN-V1.37.md#L272-L274), [§Q-7:402](../../../docs/PLAN-V1.37.md#L402).
* **The Claim:** The Window 2 decision fires at *"N₂ = ⌈3 / c*⌉ or day 90, whichever comes first, where c* is the floor conversion at the price in force (so at ¥10, c* = 7.6% and N₂ = 40; at ¥68, about 273). A zero at that N is exactly the bound that rules out reaching the floor."*
* **The Evidence:**
  1. At ¥10, $c^* = 0.076$, so $N_2 = \lceil 3 / 0.076 \rceil = 40$. At 2.6 installs/day ([`docs/measurements/stage1-checkpoints.md:228-232`](../../../docs/measurements/stage1-checkpoints.md#L228-L232)), 40 installs accumulate in just **15.4 calendar days**.
  2. In 15.4 days, almost zero new users will complete the 48 rides needed to reach Kyōto ([`Sources/SceneryKit/RideRoute.swift:200-203`](../../../Sources/SceneryKit/RideRoute.swift#L200-L203)). Even with the 0 km menu entrance (P1-9), testing at $N_2 = 40$ produces massive false-negative risk: if true conversion was 3%, $P(\text{0 sales in 40}) = (1 - 0.03)^{40} \approx 29.6\%$. At $p = 0.02$, $P(0) \approx 44.6\%$.
  3. The rule is perverse: the cheaper the product (and the higher the required conversion), the *shorter* the window and the *smaller* the sample size. Conversely, at ¥68, $N_2 = 273$ takes 105 days, which exceeds day 90 anyway.
* **Recommended Change:** Replace the formula with a fixed minimum sample and calendar floor: **$N_2 = \max(100, \lceil 3/c^*\rceil)$ with a minimum calendar exposure of 60 days**, ensuring users have time to reach journey milestones.

---

#### 3. SERIOUS — §1 / §0 / §M: Hard Dependency on Owner Walk (O-1) Paralyzes Engineering Against User Intent
* **Plan Section:** [§1:53, 63-69](../../../docs/PLAN-V1.37.md#L53), [§0:36, 45](../../../docs/PLAN-V1.37.md#L36), [§M:371](../../../docs/PLAN-V1.37.md#L371).
* **The Claim:** The owner's 65–75 minute walk (O-1) must precede everything; without it, purchase improvements (P1-3, P1-4) cannot ship and Window 2's zeros are uninterpretable.
* **The Evidence:**
  1. [`docs/WALKCARD-STAGE1.md:14-23`](../../../docs/WALKCARD-STAGE1.md#L14-L23) notes that on 2026-10-07 the owner explicitly said: *"你想办法自己做掉 你全权负责 没办法再找我"* (figure out a way to do it yourself, take full responsibility, don't come to me unless there's no other way). On 2026-10-26 the owner said: *"你继续做到收尾吧"*.
  2. The walk has been pending since day 0 (2026-09-09, **48 days ago**; [`docs/STATE-2026-10-27.md:49-51`](../../../docs/STATE-2026-10-27.md#L49-L51)). The owner has actively avoided it for 7 weeks.
  3. Conditioning P1-3 (restore feedback) and P1-4 (StoreKit test seam) on O-1 means engineering fixes for user-facing bugs remain held indefinitely if the owner continues to ignore O-1.
* **Recommended Change:** Decouple code implementation and automated test seams from O-1. Implement pure unit tests for [`RouteStore`](../../../Sources/NihongoRideApp/RouteStore.swift) translations immediately. Compress O-1 into a single **5-minute live purchase on macOS** (to verify report code and ring the till) and drop the 60-minute multi-device family sharing and logout checklist.

---

#### 4. SERIOUS — §D (P1-6–P1-9) / App Review: 0 km Entrance (P1-9) with Delayed Value (P1-8) Triggers Guideline 2.1 / 3.1.1 Rejection
* **Plan Section:** [§D:175-179](../../../docs/PLAN-V1.37.md#L175-L179).
* **The Claim:** The menu strip opens the Road screen at 0 km (P1-9), while P1-8 (*"Immediate payoff on purchase"*) is marked *"Second to cut"* and P1-7 (*"West landmarks"*) is *"First to cut"*.
* **The Evidence:**
  1. [`Sources/SceneryKit/RideRoute.swift:207-210`](../../../Sources/SceneryKit/RideRoute.swift#L207-L210): The first paid stage (Ōsaka) begins at 28,000 m.
  2. [`Sources/NihongoRideApp/AppModel.swift:1725-1730`](../../../Sources/NihongoRideApp/AppModel.swift#L1725-L1730) & [`RideRoute.swift:357-363`](../../../Sources/SceneryKit/RideRoute.swift#L357-L363): A rider below 28,000 m resolves strictly to Tōkaidō stages.
  3. When an Apple App Reviewer installs a fresh build (0 km) and purchases the IAP via the newly opened menu strip, [`RouteStore.purchase()`](../../../Sources/NihongoRideApp/RouteStore.swift#L324) sets entitlement, but returning to the game produces **zero change in gameplay or visual scenery**. The reviewer will not type 48 rides (28 km) to see Ōsaka.
  4. App Review routinely rejects apps under Guideline 2.1 (App Completeness) or 3.1.1 (In-App Purchase) when purchasing an IAP unlocks no immediately observable content.
* **Recommended Change:** If P1-9 (0 km entrance) ships, **P1-8 (immediate visible unlock/payoff) MUST NOT BE CUT**. It is an App Review compliance requirement, not an optional enhancement.

---

#### 5. SERIOUS — §0 / §B: Option A Traps the Owner in a Procedural Freeze and Delays Monetization to 2027
* **Plan Section:** [§0:30-46](../../../docs/PLAN-V1.37.md#L30-L46), [§B:118-123](../../../docs/PLAN-V1.37.md#L118-L123), Appendix A line 434.
* **The Claim:** Option A is recommended as default because waiting to $N=200$ *"costs under ¥25"* and preserves the pre-registration.
* **The Evidence:**
  1. The pre-registered branch for a zero without arrivers is STOP BUILDING ([`docs/PLAN-STAGE1.md:550-554`](../../../docs/PLAN-STAGE1.md#L550-L554)), which explicitly prescribes: *"instrumentation and placement, not price and not Pro."*
  2. Under Option A, v1.38 cannot change the price and cannot sell Pro. It ships Offer v2 at ¥10.
  3. Then Window 2 opens to observe Offer v2 at ¥10 for another 90 days.
  4. As established in Finding 1, ¥10 scenery cannot make money. Thus, Option A forces the project to spend November through February running tests on a known-unviable product.
  5. The pre-registration rules explicitly allow ending early: [`docs/PLAN-WINDOW.md:345-351`](../../../docs/PLAN-WINDOW.md#L345-L351) states that treating Stage 1 as answered and moving on *"is not chosen here, but it is not stupid, and if the owner prefers it the cost is one paragraph in §K rather than a rebuild."*
* **Recommended Change:** Since the owner explicitly said *"想要开始盈利了"*, recommend **Option B** (end Stage 1 now with a dated §K box). If Option A is retained, pre-register an explicit owner override so v1.38 can introduce depth pricing or content SKUs immediately upon reaching $N=200$.

---

#### 6. SERIOUS — §D (P1-13) / §H: Window 2 Confounds Distribution with Paywall Conversion
* **Plan Section:** [§D:183](../../../docs/PLAN-V1.37.md#L183), [§H:269, 284](../../../docs/PLAN-V1.37.md#L269).
* **The Claim:** Window 2 measures Offer v2 as an inseparable package while also updating store descriptions, promotional text, and screenshots (P1-13).
* **The Evidence:**
  1. [`docs/PLAN-WINDOW.md:24-29, 39-48`](../../../docs/PLAN-WINDOW.md#L24-L29): The two-clause test explicitly separates *"what a device is offered"* (in-app paywall) from *"which devices arrive"* (store metadata). Changing store screenshots and descriptions directly shifts arrival intent and volume.
  2. Shipping P1-13 alongside P1-1..P1-10 in v1.38 blends search/conversion selection with in-app paywall efficacy. If conversion shifts, the instrument cannot distinguish whether better screenshots brought paying users or whether the in-app thumbnails worked.
* **Recommended Change:** Pre-register P1-13 explicitly as a confounding co-intervention in Window 2, or hold store creative until v1.38.1 after the in-app baseline is established.

---

#### 7. MINOR — §E (E3) / §K: Grandfathering via Offline `AppTransaction` is Structurally Flawed
* **Plan Section:** [§E:204](../../../docs/PLAN-V1.37.md#L204), [§K:348](../../../docs/PLAN-V1.37.md#L348).
* **The Claim:** Grandfathering existing installs on `originalAppVersion` can resolve offline by specifying *"unreadable must mean entitled"*.
* **The Evidence:**
  1. [`docs/PLAN-STAGE1.md:282-286`](../../../docs/PLAN-STAGE1.md#L282-L286): Measured under simulated offline conditions, `AppTransaction.shared` throws `networkError(-1009)` when not cached.
  2. If "unreadable must mean entitled", **any fresh user who launches the app in Airplane mode receives full Pro entitlement for free**, bypassing the paywall entirely.
  3. If unreadable does not entitle, an existing user launching on a plane loses their grandfathered access, violating the non-negotiable red line (*"no existing install loses anything, ever"*, [`PLAN-V2-PRODUCT.md:387`](../../../docs/PLAN-V2-PRODUCT.md#L387)).
* **Recommended Change:** Do not rely on runtime `AppTransaction` network queries for grandfathering. Use local data migration: on first launch of the update, if existing app records exist (e.g. legacy [`OdometerLog`](../../../Sources/SettingsKit/AppSettings.swift#L89) or [`AppSettings`](../../../Sources/SettingsKit/AppSettings.swift#L13) created prior to the update), persist a local grandfathered token to Keychain/UserDefaults.

---

#### 8. MINOR — Appendix A / §Q-3: Delegated Box Commitment Breaches Governance Boundaries
* **Plan Section:** Appendix A lines 423-424, 433-438; [§Q-3:386](../../../docs/PLAN-V1.37.md#L386).
* **The Claim:** If the owner does not answer by 2026-11-20, the agent may commit Appendix A's "restating parts" under "delegation", defining what happens at $N=200$.
* **The Evidence:**
  1. [`docs/HANDOFF-STAGE1-GATES-PROMPT.md:212-214`](../../../docs/HANDOFF-STAGE1-GATES-PROMPT.md#L212-L214): Rule 3 states: *"不要往 §L 的 walked 栏写字,也不要往 §K 写'walked on <date>'... 不要自行记录'跳过' —— §L 要求有意的跳过必须作为一个决定被写下来,而那是 owner 的决定。"*
  2. Defining future release obligations (e.g. what "Iterate" means and what v1.38 must carry) in a pre-registration box is a material design decision, not a clerical consolidation.
* **Recommended Change:** Delete the auto-commitment fallback under delegation. If the owner is silent, no new box is committed; the pre-existing [§K text](../../../docs/PLAN-STAGE1.md#L526-L554) governs as-is.

---

#### 9. NIT — §A: Citation Omission on Review Prompt Trigger
* **Plan Section:** [§A:83](../../../docs/PLAN-V1.37.md#L83).
* **The Claim:** *"The rating prompt yields for exactly the ride that crosses Kyōto (openedANewOffer). AppModel.swift:2530-2544"*.
* **The Evidence:** While [`Sources/NihongoRideApp/AppModel.swift:2543`](../../../Sources/NihongoRideApp/AppModel.swift#L2543) constructs `openedANewOffer: !hadArrivedBeforeThisRide && hasArrivedAtKyoto`, the actual yield/suppression evaluation happens in [`Sources/StoreReviewKit/ReviewPrompt.swift:169`](../../../Sources/StoreReviewKit/ReviewPrompt.swift#L169) (`guard !moment.openedANewOffer else { return .rideOpenedANewOffer }`).
* **Recommended Change:** Add [`ReviewPrompt.swift:169`](../../../Sources/StoreReviewKit/ReviewPrompt.swift#L169) to the citation list.

---

### What I Would Add

1. **Immediate Multi-SKU Architecture Unblocking in v1.37:**
   Do not defer the architecture refactor ([`RouteStore.swift:69`](../../../Sources/NihongoRideApp/RouteStore.swift#L69) static `productID`, [`Entitlement.swift:172, 222`](../../../Sources/EntitlementKit/Entitlement.swift#L172), [`UnlockOfferLedger.swift:135`](../../../Sources/EntitlementKit/UnlockOfferLedger.swift#L135), and [`scripts/sales_report.py:219`](../../../scripts/sales_report.py#L219) SKU classification) to v1.38. Generalize the entitlement store behind feature flags right now so adding a second SKU is ready the moment Phase 1 concludes.
2. **Japanese UI (E5) Prioritization:**
   53% of all installs come from Japan ([§A:85](../../../docs/PLAN-V1.37.md#L85)), yet the UI defaults to English and has zero Japanese strings ([`AppSettings.swift:92, 230`](../../../Sources/SettingsKit/AppSettings.swift#L92)). Japan has zero App Store ratings. E5 is currently ranked 5th in Phase 2; it should be ranked ahead of any new road or supporter pack.
3. **Explicit Freemium Curriculum Model:**
   Instead of selling background scenery, define the boundary for paid depth: keep N5 and basic Journey mode free as a complete sampler; gate N4–N1 levels and custom text SRS sync behind a one-time lifetime purchase. This directly matches the monetization model of every successful Japanese learning app in the App Store.
