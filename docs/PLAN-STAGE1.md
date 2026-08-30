# Stage 1 — the paid entrance, and what it opens

Decided 2026-08-30. Two questions were put to Codex and Gemini 3.7 Flash independently, and to
the owner; this records what was chosen and, where it differs from what was recommended, why.

## The two decisions

**1. No transmitted telemetry. `Data Not Collected` stays.** Both advisors chose this
independently, and neither argued it from privacy — both argued it from statistical power. At
~72 downloads a month, no telemetry can detect a retention change; a before/after series with no
pre-launch baseline and no randomized holdout would be confounded by growth, geography and the
release itself.

**And the measurement now says the same thing, which is better than the argument.** On 2026-08-26
none of Apple's engagement reports existed and I recorded that they should be "planned as
permanently unavailable". Both advisors flagged that as an inference. **They were right and it
was falsified**: on 2026-08-30 `App Sessions Standard` and `App Store Installation and Deletion
Standard` had both materialised. Calibrated against the census, they are still unusable —
**10 installs and 1 deletion over two days, 9.2% of a 109-install census, and a sessions report
whose Counts column sums to zero.** One deletion event cannot answer "did monetization damage
use". The reason is sample size, not absence, so this is worth re-checking as traffic grows and
not worth planning around. `docs/measurements/v2-engagement-reports-calibrated.json`.

> **The consequence, stated as a judgement because that is what it is:** the safety of Stage 1 is
> *designed*, not *observed*. If it harms engagement, the developer will not find out. That is the
> accepted cost, and the design below is what has to carry it.

**2. A small one-time UNLOCK, not a donation.** The owner chose the literal reading of the app's
only review — 「怎么収费找不到付费路口希望有一次性」 asked for a one-time *purchase*, and both
advisors independently pointed out that reading it as "wants to donate" is interpretation. The
plan's §D then binds: **a one-time price may only buy things that are finished.** So something
finished has to exist to be unlocked.

## What gets unlocked: the road past Kyōto

**MEASURED, not invented.** `SceneryKit.RideRoute` defines the Tōkaidō in eight stages —
日本橋 · 川崎 · 箱根 · 富士 · 浜名湖 · 名古屋 · 鈴鹿 · 京都 — and the last one begins at
**25 km of lifetime ride distance**. Past that, `progressWithinStage` returns 1 forever and
`metresToNextStage` returns nil: **the progression ends and nothing replaces it.**

Distance is `kana.count × 10` metres per completed word. Across the 7,071-entry corpus the mean
headword is 3.71 kana, so **673 completed words reach Kyōto** — on the order of 20–50 full rides.
Reachable, and earned. People do arrive there, and there is nothing on the other side.

**So Stage 1 sells the continuation.** A second route, opened by one non-consumable purchase.

Why this shape and not another:

| requirement | how this meets it |
|---|---|
| §D — a one-time price may only buy **finished** things | A route is fixed data: stage names, distances, palettes. **Zero ongoing content labour**, which is the test §D actually applies. |
| The red line — **no existing install loses anything** | The Tōkaidō stays free *and complete*, ending at a real destination. Structurally additive: there is nothing to take away. |
| Gates no learning | The route drives `RideBackgroundView`, the palette and the arrival backdrop, and **nothing else** — no vocabulary, no modes, no review queue. Verified by reading every call site. |
| Cheap enough for Stage 1 | Data plus unlock plumbing. It is not §F1's flagship and is not meant to be. |
| Answers the Stage 1 question | Someone who buys it has completed ~673 words. That is the right person to ask, and a purchase from them is real evidence. |

**And it answers the review literally.** Someone who could not find the payment entrance is given
one, and it buys a thing.

## What this is NOT

* **Not a Pro tier.** Nothing is gated that was not gated before, and no free capability moves.
* **Not content.** Selling more sentences would be selling unfunded future labour (§D), and §F3
  demoted content as an anchor for a reason.
* **Not a subscription.** Nothing recurs.
* **Not measured as safe.** See above.

## Placement, which is a design constraint and not a detail

Codex's discipline, adopted whole: **one row in Settings/About. No modal, no badge, no post-ride
solicitation, no recurring reminder, and deliberately far from the rating prompt** — which
v1.27 already fires after a completed ride, and which must not collide with a purchase request.

The one exception worth arguing later: a rider who has *arrived at Kyōto* is in the one moment
where "the road continues" is information rather than solicitation. That is a Stage 2 question,
after this placement has produced a number.

## The economics, computed before any StoreKit is written (§D)

Owner inputs, 2026-08-30: **price ¥10 CNY one-time · ¥50 CNY/month makes it worth doing ·
50 hours maximum build cost.**

```
monthly = new downloads × paid conversion × net proceeds − content and support cost
```

Traffic is **72 downloads/month**, measured (trailing-28d census). Apple's Small Business
Program rate of 15% is assumed; at 30% every figure below gets ~20% worse.

| price | net/sale | sales needed for ¥50/mo | share of new installs | share of Kyōto arrivers @20% |
|---|---|---|---|---|
| **¥10** | ¥8.50 | **5.9** | **8.2%** | **41%** |
| ¥18 | ¥15.30 | 3.3 | 4.5% | 23% |
| ¥25 | ¥21.25 | 2.4 | 3.3% | 16% |
| ¥30 | ¥25.50 | 2.0 | 2.7% | 14% |

**⚠️ At ¥10 the two owner numbers are inconsistent with each other at today's traffic.** 8.2% of
all installs is at or above the ceiling of free-to-paid conversion for a well-performing app —
and the thing being sold is only *useful* past Kyōto, so the real denominator is arrivers, not
installs. If 20% arrive, 41% of them must buy; if 5% arrive, ¥50/month is **arithmetically
impossible** (163%). Holding ¥10 and reaching the target by traffic alone needs about **300
downloads/month**, roughly 4× today.

**Resolved by changing the yardstick, not the price.** This plan's own architecture says Stage 1
buys **information, not revenue** — it exists to answer *will anyone pay this developer anything
at all* before four times the engineering goes into Pro. A low price maximises the chance of a
non-zero signal, which is the thing Stage 1 is actually short of.

* **Stage 1's kill criterion is any sustained purchasing across the observation window**, not a
  revenue figure. One purchase proves somebody will pay; zero proves nothing (§G), and yet zero
  still means *do not build Pro*, because the larger investment would have no positive evidence.
* **¥50/month is recorded as the Stage 3 floor**, where it belongs.
* **50 hours is comfortable** for this scope — seven sibling apps on this account already ship a
  `<bundle>.pro.lifetime` non-consumable, so this adapts a shape rather than inventing one. The
  scarce resource here is signal, not hours.

**And ¥50/month should be named for what it is:** ¥600/year, about US$84. Against a 50-hour
build that is roughly ¥1.7 per hour in year one. That is not an argument against doing it — it is
the argument for keeping the build small and the yardstick honest.

## What "permanent" covers, named before the SKU exists (§C)

**The purchase buys scenery and routes — every route and every backdrop, now and in future — and
nothing else.**

§C requires this to be named rather than discovered: *"A one-time unlock that implies all future
features is an unbounded promise against finite revenue."* At ¥8.50 net, "everything forever" is
exactly that promise.

Explicitly **outside** it, and to be sold separately if ever built:

* Anything requiring a server — real-time versus play, leaderboards, cloud matches. **These also
  contradict the product's own positioning**: three localised listings and the app's only review
  rest on *fully offline*. A networked mode is not merely out of scope for this SKU, it is a
  different product decision.
* §F1's "bring your own Japanese" — importing custom material.
* Any content pack.

The category is stable, its cost is bounded (route data is finished the day it ships), and its
boundary is stateable to a buyer in one sentence.

## Still required before any StoreKit is written — owner inputs, per §D

~~The plan is explicit that an agent must not invent these.~~ **All three supplied 2026-08-30
and worked through above.** What remains is the §G pre-registration — the minimum cohort, the
observation window, the refund ceiling — which now has the numbers it was waiting on.

## Open, carried

* The entitlement contract (§C) — reinstall, Apple Account change, storefront change, refund,
  revocation, **offline launch**. `AppTransaction.shared` may need a network call when uncached,
  and this app's pitch is offline. **No sibling app on this account uses `AppTransaction`**, so
  there is no in-house precedent. Fail toward "entitled".
* **The house pattern violates the failure rule.** Seven apps here ship
  `<bundle>.pro.lifetime`; Wearform's `refreshEntitlements()` ends `isPro = active`, rebuilt every
  call, so "the entitlement list could not be read" and "never bought" take the same branch. Take
  the shape, not that method.
* The description's "no network" wording — already corrected in v1.28 for CloudKit, and it will
  need revisiting again when a purchase exists.

---

# Part II — what the build found, and the pre-registration

Everything above was decided before any code existed. Everything below was measured while writing
it, on 2026-08-30, and where it contradicts Part I it supersedes it.

## §H The road is twice as long as Part I said, and the error is the familiar one

Part I: *"全语料平均词长 3.71 假名,所以 673 个完成的词到京都,约 20–50 次骑行。"* The arithmetic is
right. **The population is wrong**, and it is this project's most-repeated shape one more time.

New words are not drawn at random. `VocabStore.ordered` sorts by `VocabEntry.difficulty`, whose
`0.6 × length` term deals the **short words first** — so the words a rider actually meets on the
way to Kyōto average **2.92 kana, not 3.71**.

| | Part I | measured |
|---|---|---|
| mean kana of the words ridden first | 3.71 (whole corpus) | **2.92** |
| new words to 25 km | 673 | **856**, inside the 72nd ride of twelve |
| journey rides to Kyōto, DEFAULT level (N5) | "20–50" | **48**, and only because of reviews — see below |
| journey rides to Kyōto, mixed pool, new words only | — | **72** |
| first ride | — | **exactly 150 m** |
| mean ride on the road to Kyōto | — | **533 m** at N5 with reviews · **350 m** mixed, new-only |

Both numbers are kept, because they answer different questions: **856** is where the odometer
first crosses 25,000 m; **72 rides × 12** is where a rider crosses it, since a ride is atomic and
nobody dismounts at word 857.

`RideRoute.swift:46` carried the same error in the other direction — *"a journey ride is ~150 m"*.
That is exactly right **for the first ride**, whose twelve words are き・て・め・に・ご・え・く・は・せ・
みず・あさ・よる, nine of them a single kana. It was then used as a steady-state constant to justify
the whole threshold ladder. Corrected in the code, and `Tests/SceneryKitTests` now pins the road's
shape so the next corpus change reports a new number instead of leaving a paragraph to rot.

**The consequence for §D is worse arithmetic, and it is not hidden.** The buyer is somebody who
rode 48–72 times, not 20–50. Against the measured **2.321 installs/day** and net **¥8.42**:

| arrival rate at Kyōto | arrivers / 30d | share of them who must buy for ¥50/月 |
|---|---|---|
| 30% | 20.9 | 28% |
| 20% | 13.9 | 43% |
| **10%** | 7.0 | **85%** |
| 5% | 3.5 | **170% — impossible** |

**The arrival rate is not measurable and will not become measurable during Stage 1.** The odometer
is device-local and never transmitted; Apple's engagement reports are a 9.2% sample with one
deletion event and a sessions column summing to zero. Every row above is a hypothesis, and the
observation window below is set on that basis rather than on a model that pretends to know which
row is true.

## §I What was decided against Part I, with the measurement that decided it

**`AppTransaction` is NOT used, and §E's grandfathering is deferred.** Part I carried it as an open
item with an unverified offline path. It is now verified and the verdict is worse than "unknown":

* `AppTransaction.shared` is `get async throws`, and the SDK's own doc comment scopes its cache
  **per app version** — "make a request to get one from the App Store server if one has not been
  cached yet". Measured under a simulated offline: **it throws `networkError(-1009)`**. A rider who
  auto-updated overnight and opens the app on a plane hits a throw on the exact path meant to
  protect them. `refresh()` is not a fallback; its own doc says it forces an authentication dialog.
* Under Stage 1's scope the predicate has an **empty extension**: a free rider's outcome does not
  depend on entitlement at all, so grandfathered and not-grandfathered give the same result on
  every input. §E's rule was written for the fork where something free moves behind the paywall.
  This is the other fork, and §E's own text names *"a route"* as its example.
* The one place the branches differ is that grandfathering would hand the SKU **free to every
  pre-paywall install** — which is every Kyōto arriver alive, i.e. exactly the cohort Part I calls
  "the right person to ask". It would zero out the only measurement Stage 1 exists to take.
* Zero of 6,865 sibling `.swift` files use it, with two positive controls proving the grep fires.

What replaces it is a **code-enforced route invariant** rather than a promise: the free road is
frozen field-by-field, and `Fixtures/tokaido-v1.29-sweep.json` — swept from v1.29's own compiled
`RideRoute.swift` at `48de373`, not from the working tree — asserts an unentitled rider gets
identical answers at 1,167 points. `scripts/gen_route_golden.py` refuses to regenerate it from a
ref that already contains the paid road. Deferring costs nothing: `originalAppVersion` reports the
first version the Apple Account downloaded and is readable retroactively, so Stage 3 can still go
the other way with nothing recorded now.

**The offer is one row in Settings, and it opens a screen.** Codex's placement discipline is
adopted whole. The screen is the product page for the thing the row names, not a second
solicitation — and it is what lets the offer be honest to a rider who is still 20 km from the
purchase being any use, which a bare price row cannot be.

**The two roads are presented as two journeys, never as one sixteen-stretch bar.** Structurally the
paid road is appended and a test proves nothing is taken away. That covers what a byte can cover
and not the thing most likely to hurt: before v1.30 the Tōkaidō *was* the road and Kyōto was where
it ended, so one progress bar would convert a finished journey into a half-finished one — nothing
removed, a real loss, and **invisible**, because there is no telemetry and will not be.
**This is a judgement. Nobody has watched a rider react to either layout.**

## §J iOS cannot run the purchase gates. macOS can, and that is where they live

MEASURED on Xcode 26.6 / iOS 26.5 simulator, on an independent minimal project:

* a local `.storekit` configuration **never reaches the app on iOS** under `xcodebuild test` — five
  wirings tried, `Product.products(for:)` returns 0 every time, on two devices;
* `SKTestSession` logs `SKInternalErrorDomain Code=3` for every operation **and its initialiser
  does not throw**, so the obvious gate test passes while the session is completely inert;
* the identical configuration and code pass **10/10 on macOS**.

So the gates are `Tests/NihongoRideMacTests`, and `test00_theStoreIsReachable` is what makes the
rest of that file mean anything — it fails on iOS and passes on macOS, a known negative and a
known positive on this machine today.

**Recorded as MEASURED-BROKEN, not IMPOSSIBLE.** It is a simulator-runtime failure and a toolchain
update could fix it; calling it permanent would be the same inference error the engagement reports
already falsified once. Re-check when Xcode changes.

**Three gates cannot be automated anywhere here and are therefore MANUAL:** no App Store account
signed in, Family Sharing, and a real cross-platform (macOS ↔ iOS) restore. Listing them as tested
because the macOS suite is green would be a lie. They need a walked-through date and device below
before submission.

## §K §G's pre-registration, fixed in advance

Written before the SKU exists. The point is not that these numbers are right; it is that they are
**fixed before the data arrives**, so no outcome can be rationalised afterwards.

**Measured inputs, 2026-08-30, all from `scripts/sales_report.py --calibrate` (OK) and ASC:**

| | |
|---|---|
| installs | **2.321/day** trailing-28d (65/28); band 53–70 per 30d across 14/28/56-day windows |
| lifetime install base | **114** (macOS 62 / iOS 52) |
| net proceeds per ¥10 sale | **¥8.42** — looked up from ASC's price points, **not** derived from a 15% rate |
| CNY 10 equalises to | USD 0.99 · JPY 150 · EUR 0.99 · GBP 0.99, across 174 territories |

**Denominated in installs, not exposures**, deliberately. §D's own economics are stated as a share
of new installs, a device cannot be exposed without installing, and an install-denominated bound
can only *overstate* the traffic — so it is conservative. The exposure question stays where it
honestly belongs: unmeasurable remotely, addressed by the local counter, not by this table.

**Window: 90 days from READY_FOR_SALE on both platforms. Refunds evaluated separately at day 180**,
because refunds land up to ~90 days after a sale and a ceiling read at day 90 is read before the
data exists.

| checkpoint | new installs | zero purchases rules out (rule of three, 95%) | decision attached in advance |
|---|---|---|---|
| **day 15** | 34.8 | per-install conversion **≥ 8.6%** | **Continue, and record it.** §D needs 8.2% at ¥10, so a zero here already falsifies the revenue model. That is a result. **Do not change the price** — a mid-window price change voids this pre-registration and turns the run into an uninterpretable before/after. |
| **day 42** | 97.5 | **≥ 3.1%** | **Continue.** No iteration, because iterating restarts the cohort clock and there is not enough traffic to spend a restart on. |
| **day 90** | 208.9 (+114 base ⇒ ≤ 323 devices ever exposed) | **≥ 1.4%** on new installs · **≥ 0.9%** against the ceiling | **Decide — the three branches below.** |

**Go / iterate / stop at day 90:**

* **≥ 1 net purchase at any point → GO on H1.** Somebody will pay this developer. Run to day 90
  anyway for the repeat rate. State the ceiling honestly: 1–3 purchases proves existence and
  estimates nothing.
* **Zero, AND at least one returned counter showing `settingsRowAppeared > 0` with
  `furthestBucket == kyoto` → STOP.** Somebody arrived, the row appeared, nothing was bought.
  That is the only configuration in which a zero is evidence about willingness to pay.
* **Zero, AND no returned counter (or every one showing `settingsRowAppeared == 0`) → STOP
  BUILDING, and record the zero as UNINTERPRETABLE.** The next release's job is instrumentation and
  placement, not price and not Pro. **This branch is the one that must not be quietly dropped:** a
  pre-registration with no "this taught us nothing" outcome is precisely the failure this project's
  central rule names, written into the schedule.

**Refund ceiling — absolute counts, because below ~20 sales a rate is noise.** At 10 sales and a
true 5% refund rate, P(≥1) = 40%.
* **1 refund → no action.** The modal outcome of a healthy product at this volume.
* **≥ 2 refunds AND ≥ 20% of units → stop selling.** Pull the SKU. **Every existing entitlement
  stays honoured** — pulling a SKU must never revoke, and the code cannot revoke without an
  affirmative revocation signal.
* **≥ 3 refunds at any n ≤ 18 → investigate the product claim, not the price.**

**Guardrails that exist, and the one that does not.**
* **Retention/engagement: nothing behind it**, and this is stated as an accepted cost rather than
  an oversight. If Stage 1 damages engagement, the developer will not find out.
* **Any new store review mentioning the purchase negatively is a stop-and-fix, regardless of
  units.** At one lifetime review, n=1 is a real signal here and it costs nothing to watch.
* **Report the launch spike separately.** The first release carrying the row exposes much of a
  114-device base at once; conflating that with steady state is how a one-off becomes a forecast.

**Day 0, before the SKU goes on sale — non-negotiable, and it is an OWNER action:** make one real
¥10 purchase on the owner's own Apple Account **in production** (sandbox never appears in
`salesReports`), confirm the row appears and `--calibrate` still passes, then refund it. Record the
date here and **exclude it from the cohort**, or it will later look like the signal. This is the
money instrument's known-positive, and this project does not trust an instrument that has not
fired. *An agent cannot do this step and must not try.*

## §L The three manual gates

These cannot be automated on this machine and are therefore **not tested until somebody walks
them**. Recording them as a checklist rather than as prose so that "we tested the purchase flow"
can never mean "the macOS suite was green".

Each needs a date, a device and an outcome written beside it **before v1.30 is submitted**.

| gate | why it cannot be automated | procedure | walked |
|---|---|---|---|
| **No App Store account signed in** | `SKTestSession` cannot simulate a signed-out Apple Account; the closest automatable proxy is `.loadProducts` erroring, which is a different thing and is named as a proxy in the test that does it | Sign out of the App Store on a Mac or device. Launch. Open Settings → The Road. **Expect:** the row is there, the screen opens, the price area says prices are unavailable and offers Retry, Restore is present, and nothing crashes. **Fail if:** the row is missing, or the screen claims the road is unlocked, or the app hangs. | ☐ |
| **Family Sharing** | The SKU ships with Family Sharing **off**, and Apple documents that turning it on can never be undone — so the state to verify is that a family member does NOT inherit it | On a second Apple Account in the same family group, launch and open Settings → The Road. **Expect:** the offer, not the owned state. | ☐ |
| **Cross-platform restore (macOS ↔ iOS)** | One Universal Purchase record covers both platforms on the STORE side; whether the entitlement resolves on the second device is client code and has never been observed | Buy on one platform. On the other, signed into the same Apple Account, launch and open Settings → The Road. **Expect:** owned, without tapping Restore. Then try it from a cold install. **Fail if:** Restore is needed and does not work. | ☐ |

**⚠️ And as of 2026-08-30 the AUTOMATED gates do not run either, so this manual list is the only
purchase coverage that exists.**

`Tests/NihongoRideMacTests` is written, and it skips. `SKTestSession` is **inert for this app on
this machine**: it logs `SKInternalErrorDomain Code=3` for every operation and its initialiser
does not throw, so it hands back a live object that controls nothing. Measured against the
alternatives, in this order, and none of them was the cause: the App Sandbox (turned off for Debug
— the errors persisted), code-signing entitlements (stripped — persisted), the CloudKit isolation.
A minimal, non-App-Store macOS app on this same machine drives the same session fine and passes
10/10, so **the difference is this app, not the tooling** — the remaining untested differences are
the real App Store bundle identifier and the embedded widget extension.

What made this visible is worth more than the gates would have been. The first calibration asked
only *"do products resolve"* — and they do, because the scheme's `storeKitConfiguration` arms the
app's store environment **independently of the session**. So the suite passed while every
simulated refund, network error and Ask-to-Buy in it was doing nothing. The second calibration
makes the session DO something and observes it, and that is what caught it.

The suite now **skips with the reason attached** rather than passing or failing: a green suite that
proves nothing is worse than none, and a permanently-red one teaches people to ignore red. If a
toolchain update fixes the session, every gate starts running again with no edit.

**The one thing that must not happen is weakening that check to make the suite green.**

And restated so the gap is not implied away: **iOS StoreKit behaviour is not observed by any
automated test on this machine either.** The two targets share `Sources/NihongoRideApp`, so the
adapter is the same code — which is an argument, not an observation.

## §M What is done, and what Stage 1 is still waiting on

**Done and proven.**

* The road: eight new stretches, palettes generated from a verified table, contrast 11.1:1 worst
  case against a 7:1 floor.
* The red line: the free road frozen field-by-field and swept against v1.29's own compiled code at
  1,167 points, with a committed negative control and a generator that refuses to read the working
  tree.
* The entitlement rule: pure, exhaustively tested, and unable to express "the store says no".
* The offer: one row, one screen, honest to a rider who has not arrived.
* The counter, with its own limits written on the type.
* The IAP: `com.jasonye.nihongoride.scenery.lifetime`, NON_CONSUMABLE, Family Sharing **off**,
  base territory CHN at ¥10.00 (net ¥8.42), 174 territories auto-equalised, three localisations,
  175 territories available including CHN.

**Blocked, and on what.**

* **Submission is blocked on v1.29 clearing review.** This is the app's FIRST non-consumable, and
  Apple requires the first of each type to be submitted **with a new app version** — so the IAP
  cannot go alone, and there is no editable version while 1.29 sits in `WAITING_FOR_REVIEW`.
* **The IAP is `MISSING_METADATA` until its review screenshot is uploaded.** The screenshot needs
  the built UI; `Screenshot.swift` now renders `road.png` for exactly this.
* **The store description says "No account".** A purchase uses the customer's Apple Account, so
  that becomes false with v1.30 and must be corrected **in the same submission** — it is a
  metadata edit and therefore also blocked until 1.29 clears. (The older "no network" wording is
  already gone; v1.28 fixed it. `docs/ASC_METADATA.md` still shows the pre-v1.28 text and is
  itself stale.)
* **The three manual gates above.**
* **The day-0 known-positive purchase (§K)** — an owner action, in production, refunded after,
  excluded from the cohort.
