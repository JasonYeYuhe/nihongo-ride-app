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

## Still required before any StoreKit is written — owner inputs, per §D

The plan is explicit that an agent must not invent these:

1. **The price**, per territory, written in **CNY** (China is 48% of installs).
2. **The monthly contribution that would make this worth doing.**
3. **The maximum build cost acceptable to find out.**

And the pre-registered kill criteria from §G, which need those numbers first.

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
