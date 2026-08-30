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
