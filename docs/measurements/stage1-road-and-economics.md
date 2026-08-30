# Stage 1 — the road, the money, and the two numbers that were wrong

Measured 2026-08-30. Every figure here names the command that produced it. Where a number
contradicts `docs/PLAN-STAGE1.md` Part I or `docs/PLAN-V2-PRODUCT.md`, this file is the later
measurement and Part II of PLAN-STAGE1 carries the consequence.

## 1. The road to Kyōto — corrected for population

**Instrument:** `swift test --filter RoadDataTests`. It rides real `GameSession`s and reads
`session.distanceMeters` back, rather than re-deriving `kana.count × 10` in a second language —
this project has paid three times for a rule written twice.

| | PLAN-STAGE1 Part I | measured |
|---|---|---|
| mean kana of the words met first | 3.71 (mean over all 7,071 entries) | **2.92** |
| new words to 25,000 m | 673 | **856** |
| journey rides to Kyōto, DEFAULT level (N5) | "20–50" | **48**, and only because of reviews |
| journey rides to Kyōto, mixed pool, new words only | — | **72** |
| first ride | — | **exactly 150 m** |
| mean ride to Kyōto | — | **533 m** at N5 with reviews · **350 m** mixed, new-only |

**Why Part I was wrong.** `VocabStore.ordered` sorts by `VocabEntry.difficulty`, and its
`0.6 × length` term deals the short words first. The first twelve words a rider ever sees are
き・て・め・に・ご・え・く・は・せ・みず・あさ・よる — nine of them a single kana. So the
corpus-wide mean describes a population no rider ever meets in that order.

**856 and 864 are not in conflict.** 856 is where the odometer first crosses 25,000 m; the 72nd
ride of twelve is where a *rider* crosses it, because a ride is atomic and nobody dismounts at
word 857. Both are recorded so nobody has to guess which is meant.

`Sources/SceneryKit/RideRoute.swift:46` carried the same error inverted — "a journey ride is
~150 m" is exactly right for the FIRST ride and was used as a steady-state constant to justify the
whole threshold ladder. Corrected, and now pinned by the test above.

## 2. Money — looked up, not derived

**Instrument:** `scripts/asc_api.sh GET "/v2/inAppPurchases/<sibling>/pricePoints?filter[territory]=CHN"`,
decoded. Price-point ids are `base64({"s":<iap id>,"t":<territory>,"p":<global point>})`, so `p`
is global and only `s` is per-IAP — a new product must query its own.

| | |
|---|---|
| CNY 10.00 exists in CHN | **yes**, global price point `10029` |
| net proceeds | **¥8.42** — PLAN-STAGE1 assumed ¥8.50 from a 15% rate |
| equalises to | USD 0.99 · JPY 150 · EUR 0.99 · GBP 0.99, across 174 territories |

**The lesson is small and worth keeping: proceeds are looked up, not computed from a commission
percentage.** ¥10 × 0.85 = ¥8.50 and the real figure is ¥8.42. The difference does not change any
conclusion; the habit of deriving it would eventually change one.

## 3. Traffic, for the pre-registration

**Instrument:** `python3 scripts/sales_report.py --calibrate --json …` (printed `OK`).

| window | downloads | per day | per 30d |
|---|---|---|---|
| trailing 14d | 25 | 1.786 | 53.6 |
| **trailing 28d** | **65** | **2.321** | **69.6** |
| trailing 56d | 99 | 1.768 | 53.0 |
| lifetime | **114** (macOS 62 / iOS 52) | — | — |

The 14/28/56 spread is why the pre-registration quotes a **53–70 band** and uses the 28-day figure
as its point estimate. PLAN-V2-PRODUCT §L's "traffic is rising" is not visible at 14 days.

Rule of three (zero events in n trials ⇒ 95% upper bound ≈ 3/n), at 2.321 installs/day:

| day | new installs | zero purchases rules out |
|---|---|---|
| 15 | 34.8 | ≥ 8.6% |
| 42 | 97.5 | ≥ 3.1% |
| 90 | 208.9 | ≥ 1.4% (≥ 0.9% against the 323-device ceiling) |

## 4. Two documented facts that were stale against the live records

Both were read out of `docs/` by reviewers and both are false of the app as it actually stands.
Recorded because a stale doc is indistinguishable from a current one until somebody checks.

* **`ASC_METADATA.md:60` — "No account, no network".** The LIVE v1.28 description says
  *"Works fully offline. No account, no ads, no tracking, and no analytics of any kind."*
  "No network" is already gone. **"No account" is still there and a purchase makes it false** —
  that correction is a v1.30 metadata blocker.
  Instrument: `asc_api.sh GET /v1/appStoreVersions/3f10fd57-…/appStoreVersionLocalizations`.
* **`ASC_METADATA.md:15` — secondary category "Games — Word".** The live record is
  **primary EDUCATION, secondary REFERENCE**, no Games classification at all. This matters
  because a reviewer flagged mainland China's licence (版号) requirement for *games* offering IAP
  as a possible hard block on the base territory; it does not apply.
  Instrument: `asc_api.sh GET /v1/appInfos/e66ae118-…?include=primaryCategory,secondaryCategory`.

## 5. `AppTransaction` — the open question in Part I, closed

**Instrument:** the shipping SDK's own `.swiftdoc`, plus a runtime probe on macOS under a local
StoreKit configuration.

* Signature: `public static var shared: VerificationResult<AppTransaction> { get async throws }`.
* Its doc comment scopes the cache **per app version**: *"…or make a request to get one from the
  App Store server if one has not been cached yet."*
* **Measured under a simulated offline: it THROWS `networkError(-1009)`.** A rider who
  auto-updated overnight and opens the app on a plane hits a throw on the path meant to protect
  them. `refresh()` is not a fallback — its own doc says it forces an authentication dialog.
* Zero uses across 6,865 sibling `.swift` files, with two positive controls proving the grep fires.

Not used in Stage 1. See PLAN-STAGE1 §I.

## 6. iOS cannot run StoreKit tests on this toolchain; macOS can

**Instrument:** an independent minimal project, so the finding does not depend on this repo.
Xcode 26.6 (17F113), SDK 26.5, Swift 6.3.3, iOS 26.5 simulator runtime.

* A local `.storekit` configuration never reaches the app on iOS under `xcodebuild test` — five
  wirings, two devices, `Product.products(for:)` returns 0 every time.
* `SKTestSession` logs `SKInternalErrorDomain Code=3` for every operation, **and its initialiser
  does not throw** — it returns a live, inert object, so the obvious gate test passes forever.
* The same configuration and code pass **10/10 on macOS**.
* `xcodegen`'s `storeKitConfiguration` is honoured **only** under a scheme's `run:` block. Under
  `test:` or at the scheme's top level it is silently ignored with no diagnostic.

**Recorded as MEASURED-BROKEN on 2026-08-30, not as impossible.** It is a simulator-runtime
failure; re-check on a toolchain update.

## 7. Correction, 2026-08-30 evening — §1 measured a population no default rider is in

The road figures above were first taken on the **mixed** corpus. `AppSettings`'s default
`selectedLevel` is **5** (`Sources/SettingsKit/AppSettings.swift:86`), and `AppModel.startGame`
passes it straight into `GameSession.Config.level` — so a fresh install rides **N5 only**.

Which is this project's rule 5 again — *a rule correct for one population fails silently on
another* — committed inside the instrument written to correct exactly that error in the plan. It
was found by an adversarial review reading the test, not by the test.

Re-measured with the level parameterised:

| | N5 (the default) | mixed pool |
|---|---|---|
| rides to Kyōto, with the review mix | **48** | 48 |
| rides to Kyōto, new words only | **never arrives** | 72 |
| mean ride | 533 m | 350 m (new-only) |

**And the re-measurement surfaced a product fact the first pass could not have seen.** The whole
N5 pool is 646 words ≈ **20.8 km**, so a rider who never leaves the default level **cannot reach
Kyōto on new words at all** — the last 4 km is carried entirely by SRS repetitions. Anything that
changes how often words come back for review therefore moves the road, and the road is what Stage 1
sells the continuation of.

The instrument had a second defect in the same place: `rideTo` returned only the per-ride
distances, so a run that stopped because the **pool ran out** was indistinguishable from one that
stopped because it **arrived** — and on N5 that is what happens. It compared a ride count from an
exhausted pool against a golden taken from an arrival. It now returns `arrived` alongside the
rides, and asserts on it.
