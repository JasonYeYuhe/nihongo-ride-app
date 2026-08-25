# Stage 0 baseline — the traffic number the product plan assumed

Taken 2026-08-26, before anything ships. `docs/PLAN-V2-PRODUCT.md` §C requires a baseline
recorded *before* any change, because "without a baseline the first month's figure is
uninterpretable". This is that baseline, and taking it corrected four things the plan asserted.

Regenerate with `scripts/sales_report.py --calibrate --json docs/measurements/v2-stage0-baseline.json`.
**Do not quote a number from a run that did not print `OK — the instrument responds to
known-positive events`** (the script exits 4 in that case).

## The instrument, and why it is not the obvious one

| | |
|---|---|
| source | **Sales and Trends** (`/v1/salesReports`), the census |
| NOT | the Analytics API, which counts only users who opted into "Share With App Developers" and **can report zero while real downloads exist** |
| vendor number | `94126306`, from `~/Documents/credits.md` |
| window | 2026-06-06 (1.0 READY_FOR_SALE) → 2026-08-24 · 80 days, **80 of 80 reports returned data** — no day came back `pending` or `nosales`. That rules out gaps in *retrieval*; it says nothing about Apple's own upstream pipeline, which is not observable from here |

Apple returns 404 both for "no transactions" and "report not built yet". The script parses the
error detail and prints them as different lines, because a pipeline that is merely LATE
otherwise reads as a census zero.

### The product-type codes were derived, not copied

A sibling project (`Wearform/scripts/sales-report.py`) solves this exact problem and its
whitelist is `{1,1F,1T,1E,1EP,1EU}` for downloads. **Run unchanged against Nihongo Ride it
reports 49 downloads where the census says 109, with macOS silently 0.** This app is a
Universal Purchase app and Apple reports it with codes that whitelist does not contain:

| code | meaning | proof it means that |
|---|---|---|
| `F1` | first download, Desktop | 60 units; not release-locked |
| `1F` | first download, iPhone/iPad | 49 units; not release-locked |
| `F7` | **update, on ALL devices** including iPhone and iPad | 293 units — Desktop 138, **iPhone 106, iPad 49**; release-locked at **+4.77σ** |
| `3F` / `F3` | redownload | 4 units in the app's whole life |

`F7` appearing on iPhone contradicts the intuition that `F`-prefixed codes are Mac-only, which
is why the classification is proven **behaviourally** — updates must be release-locked and
downloads must not be — rather than read off Apple's code table. No `7`, `7F` or `7T` row exists
anywhere in this app's data, so `F7` is not merely *an* update code, it is the *only* one.

**Stated as ratios (2.08x / 1.19x) this was a number that sounds like evidence.** Restated as a
Poisson test against the null of equal rates, over August:

| | release days | other days | expected under null | observed | |
|---|---|---|---|---|---|
| updates `F7` | 91 in 6d | 131 in 18d | 55.5 (σ 7.45) | 91 | **+4.77σ — decisively release-locked** |
| downloads `F1`+`1F` | 17 in 6d | 43 in 18d | 15.0 (σ 3.87) | 17 | **+0.52σ — indistinguishable from not release-locked** |

The download figure is evidence *because* it is consistent with the null, not because 1.19 is a
number greater than 1.

### The calibration is proven to fail

Two mutations, both exit 4:

* **drop `F1`** — reproduces the sibling script's exact defect. Total falls 109 → 49, macOS to
  0, and the guard fires: *58 row(s) carry a code this classifier does not know: F1*.
* **call `F7` a download and claim `7F` is the update code** — total inflates to 402 and two
  guards fire: `7F` never occurs (a whitelist member that never occurs is an unverified claim),
  and updates stop being elevated on release days.

IAP codes are listed in `EXPECTED_ABSENT` with the reason *impossible until Stage 1 ships
StoreKit*. The first run that sees one fails until it is reclassified, so an IAP unit can never
land silently in "unclassified".

## What was measured

| | |
|---|---|
| **first-time downloads, lifetime** | **109** — macOS 60 · iOS 49 |
| updates | 293 · redownloads 4 |
| `Supported Platforms` on every row | **`iOS and macOS`** — Universal Purchase, already |
| 28-day windows, oldest → newest | **11 → 31 → 67** — the oldest is not comparable; normalised below |
| trailing-28d run rate | **72 / 30 days** |
| lifetime average run rate | 41 / 30 days |
| **China share of all downloads** | **52 / 109 = 48%** (35 of the last 67) |
| next territories | JP 15 · US 9 · VN 5 · AU 4 · IN 3 · HK 3 · TW 2 |
| written reviews, all time | **1** (`meta.paging.total`, confirmed) |
| storefront locales configured | **2** — `en-US`, `zh-Hans`, on both platforms |
| Analytics report requests ever made | **0**, until 2026-08-26 |

## What this corrects in PLAN-V2-PRODUCT.md

1. **§A "one review is a measurement of near-zero traffic" was an inference, and the traffic
   was measurable all along.** The direction survives, and **the conclusion Stage 0 rests on is
   unchanged: 2.4 downloads a day is still economically near-zero, and monetising it first
   would still be building a paywall in an empty room.** What is corrected is narrower — the
   plan's working figure of "40 monthly downloads" is the *lifetime average*, the present rate
   is ~72/30d, and the plan carries no awareness of a trend because nobody pulled the series.
   **This is a reason to state Stage 0's premise accurately, not a reason to shorten Stage 0.**

   The first window is not comparable: the app did not exist for 4 of its 28 days and had no
   downloads for 6 more. Normalised to days the app existed:

   | window | days | downloads | per day |
   |---|---|---|---|
   | 2026-06-06 … 06-29 | 24 | 11 | 0.46 |
   | 2026-06-30 … 07-27 | 28 | 31 | 1.11 |
   | 2026-07-28 … 08-24 | 28 | 67 | 2.39 |

   Growth is parallel on both platforms — macOS 8 → 18 → 34, iOS 3 → 13 → 33 — so neither
   store is carrying the other and no platform is flat.

2. **The cause of the growth is NOT established, and four explanations remain unexcluded.**
   Seven releases in fourteen days coincide with it, and that is the tempting reading; it is
   also the one with a perverse incentive attached (cut micro-releases to "distribute"), so it
   is recorded here as one candidate among four rather than as a lever. The others: App Store
   keyword indexing ramps over a new app's first weeks, so window 1 is partly an unindexed
   baseline; the single 5-star review landed 2026-07-10 in window 2, and a visible star rating
   raises impression-to-tap; and 35 of window 3's 67 installs are China, where one Xiaohongshu
   / V2EX / Zhihu mention produces a bump of about this size and then decays. **Acquisition
   source is what separates these, it lives in the Analytics reports, and it is not yet
   available.** Until it is, no cause may be asserted.
3. **§C "the keyword list is English-only" is false.** `zh-Hans` keywords ship on both
   platforms and have since before this plan. What is true is the *other* half: only two
   locales exist, so Japan (**#2 territory, 15 downloads, no `ja` listing**), Taiwan and Korea
   are genuinely untouched.
4. **§C's entitlement question "do macOS and iOS share one app record" is answered: yes.** One
   record, one SKU (`nihongoride-mac-2026`), and Apple stamps **every unit** `iOS and macOS`.
   **This settles the App Store side and not the runtime side.** A shared record makes a single
   non-consumable purchasable on both platforms; whether the *entitlement* then resolves on the
   second device still depends on client code and is a Stage 1 test case, not a settled fact.
5. **§A's China signal is much stronger than one review — for reach, and only for reach.** The
   plan justified writing CNY and localising the paywall from a single review (n=1). The census
   says **48% of all installs are China** (n=109), which settles that the audience is there and
   that Simplified-Chinese merchandising and CNY pricing are right. **It measures nothing about
   willingness to pay.** Going from n=1 to n=52 strengthens the evidence for *reach*, not for
   *intent*, and conflating those is the same move §A was corrected for.
6. **§I's "the description becomes untrue" risk is confirmed verbatim.** The live listing reads
   `Fully offline. No account, no network, no tracking, no ads.` / `完全离线。无账号、不联网、无追踪、无广告。`

## The arithmetic §G needs, with real numbers

§G fixes the falsification threshold at 100 genuine exposures (zero purchases below that rules
out nothing useful). Against the measured base:

* **The active installed base is at most 109 devices** — lifetime downloads, before any
  deletion. This is a census ceiling, not an estimate.
* **109 is also a ceiling on device-installs, not on people.** One person installing on a Mac
  and an iPhone is two units (`F1` + `1F`), so the number of distinct humans is *lower* than
  109 — the ceiling binds harder than it first reads.
* **The step that turns installs into exposures is unmeasured, and that is the whole
  difficulty.** An earlier draft of this file said "100 exposures ≈ 92% of every device that
  ever installed", which is only true if every install sees the tip jar exactly once. A tip jar
  in Settings is seen by a small fraction of users; one on the results screen is seen by
  approximately every active user, repeatedly. **The multiplier between 109 installs and 100
  exposures therefore spans more than an order of magnitude, and no honest number for it exists
  before it is instrumented.**
* So what the 109 ceiling licenses is a **bound, not a schedule**: *at most* 109 devices can
  ever be exposed for the first time, whatever the placement. It does not license "100
  exposures in 42 days" — that figure was 100 *new installs*, which is a different quantity and
  is the one thing here that is genuinely on a ~42-day clock at the trailing rate.
* **This is the argument for §G's local exposure counter, and it is stronger than §G made it.**
  Without a counter the exposure denominator is not merely unknown, it is unknowable, and every
  conversion figure computed against installs instead of exposures is wrong by the placement
  multiplier. **Placement must therefore be chosen and recorded before the counter is useful.**
* One consequence §G should carry: because the installed base is ~109 and the first release
  carrying a tip jar exposes much of it at once, the first weeks are structurally a **one-shot**
  — exactly the "launch spike with no clean exposure denominator" §G warns against reading as
  steady state.

**The active-device count is still not measured.** Sales and Trends cannot produce it; the
Analytics reports can, and they were requested on 2026-08-26 (`ONE_TIME_SNAPSHOT`
`4c53fdae-17db-4666-a557-cceeb6795e85`, `ONGOING` `c57c770b-faac-4b80-9bb7-354ed6c66f92`).
When they materialise, **calibrate them against this census before believing them** — their
download figure divided by 109 is the sampling rate, and it is the only thing that says how
much weight the retention and session numbers can carry.

## What was learned by checking prerequisites nobody had checked

* **The Paid Applications Agreement is ACTIVE**, so Stage 1 is not hard-blocked. Not asserted —
  five apps on this team hold IAPs in `APPROVED` state (Wearform, Stride, ColorArchive,
  Tetsuzukit, and RoastMate with four consumable credit packs), and an IAP cannot reach
  `APPROVED` without an active agreement. This was the one thing that could have added 1–3
  weeks of tax and banking latency to Stage 1, and it is already paid for.
* **"There is no monetization code" is true of this repo and false of this developer.** Seven
  apps on the account ship a `<bundle>.pro.lifetime` non-consumable behind one subscription
  group. Stage 1's build cost should be modelled against *adapting a pattern that has shipped
  seven times*, not against writing StoreKit from zero — which matters, because §D requires a
  stated maximum build cost before a model can be called correct.
* **But the house pattern implements exactly the failure rule §C forbids.** Wearform's
  `StoreManager.refreshEntitlements()` ends `isPro = active`, where `active` is rebuilt from
  `Transaction.currentEntitlements` on every call. Nothing persists a previously verified
  entitlement, so "the entitlement list could not be read" and "this user never bought
  anything" take the same branch. §C's rule is *never revoke on failure what was previously
  verified*. **Copy the pattern for its shape and not for this method.**
* **No sibling uses `AppTransaction` at all.** So §E's grandfathering mechanism is new work for
  this developer, and the offline behaviour the handoff flags as a design gate is genuinely
  unverified — there is no shipped precedent to read it off.

## The review this record went through

Gemini 3.7 Flash, one of the three reviewers of the plan itself, was asked to attack this
record. Recorded in the house style, because two of its most confident findings were wrong and
the pattern is the useful part.

**Right, and it is the correction that mattered most.** *"100 exposures ≈ 92% of every device
that ever installed"* is an order-of-magnitude error, because downloads are not exposures. The
fix is above. Its own replacement figure — "typical exposure rates are 5–20%, so you need ~667
users" — was **not adopted**, because that number is exactly the kind this project refuses:
plausible, unsourced, and presented as if measured. The honest statement is a bound plus the
observation that the multiplier is unknowable before instrumentation.

**Right about rigour, and checking it strengthened the thing it attacked.** It called the
2.08x / 1.19x separation "noise-mining". Recomputed as a Poisson test the update effect is
+4.77σ and the download effect +0.52σ, so the classification stands and the *presentation* was
the defect — ratios were being offered where a significance test was needed.

**Right, and operationally load-bearing.** `SKStoreReviewController` and the ASO metadata are
not two separable next steps: new locales, a reworded description and a new binary all attach
to the same App Store version record, so they ship as one v1.27 payload or not at all. It also
noted Apple's limit of three review prompts per 365 days, which makes the trigger milestone a
design decision rather than a detail.

**Right to ask, and the answer was already yes.** The Paid Applications Agreement check above
exists because it asked for it. It was the only prerequisite capable of hard-blocking Stage 1,
and nobody had looked.

**Confidently wrong, and the data was already in the file.** It marked as DECISIVE that
`F7`-on-iOS was an unverified deduction confusing `Supported Platforms` with `Device`, and
warned that Mac updates might be masking zero iOS updates. The `Device` column reads `iPhone`
on 106 units and `iPad` on 49, and no `7`/`7F`/`7T` row exists anywhere. The reverse of its
concern is true: 155 of 293 updates are on iOS devices.

**Confidently wrong in its arithmetic, right in its instinct.** It marked as DECISIVE that
"window 3 is 24 days, not 28". Window 3 is the newest and has all 28 days with reports; the
short window is the *oldest*, because the app did not exist for four of its days. The instinct
— that unequal windows were being compared — was correct, and the normalisation above exists
because of it.

**Guarding against a reading this file invited.** It warned at DECISIVE that treating "traffic
doubled" as licence to deprioritise Stage 0 would be the most expensive available error. No
such deprioritisation was proposed, but the wording permitted it, and correction #1 was
rewritten so it cannot be read that way.

**The pattern, which is the same one the plan itself kept producing.** Both of Gemini's wrong
findings were confident claims about data it had been given and had not checked, and its one
unusable proposal was an unsourced industry average offered as a correction to an unsourced
estimate. Same failure the plan was corrected for three times: **a claim that sounds measured
and is not.** Two of its right findings were of the opposite kind — *"you did not check X"* —
and those were the valuable ones.
