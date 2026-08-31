# v1.30 — Stage 1 goes on sale

**The release that opens the observation window.** Everything about *what* is sold, *why* that
shape, and *what will be concluded from the result* is in `PLAN-STAGE1.md`, which was written
before this build existed and is not restated here. This file records only what the release run
itself did and found — the numbers, the decisions taken at submission time, and the two things
that were measured rather than assumed.

**Submitted 2026-08-31, macOS build 54 / iOS build 55, marketing 1.30 — both platforms and the
in-app purchase all `WAITING_FOR_REVIEW`, verified by querying ASC after the fact rather than by
reading the responses to our own calls.**

| | id | state read back from Apple |
|---|---|---|
| macOS 1.30 | `12936de2-27c5-4049-860b-10ad6f30a404` | `WAITING_FOR_REVIEW`, build 54 VALID |
| iOS 1.30 | `b0804989-4791-4b6d-af11-65edce327f8d` | `WAITING_FOR_REVIEW`, build 55 VALID |
| `…scenery.lifetime` | `6806755720` (version `1e3a1b2d…`) | `WAITING_FOR_REVIEW`, riding the macOS submission |

Bumped with `scripts/check_versions.py --bump 1.30`, which locates every field by its enclosing
target — never a chained string replace, which is how v1.25 gave both platforms build 48. The
uploaded archives were each re-checked against `project.yml` (`--archive`), and `launch_gate.sh`
passed on **the macOS app from the archive that was actually uploaded**, with the Mac signed into
iCloud — 16 s, the crash v1.4 died of arriving in under 2. The console-lock sampler recorded
**0 of 95 samples locked** during the macOS export.

Baseline re-verified on the untouched tree *before* anything changed, so a later failure could
be attributed: `swift test` **632 green** · `scripts/run_ios_placement_tests.sh` **7/7** ·
`scripts/run_store_gates.sh` **exit 3, nine skipped, NO COVERAGE** — reported honestly, exactly
as §L says it must be. That third one is not a passing gate and is not written down as one.

## §A The description line that stops being true, corrected per locale rather than translated

This is the release's one metadata change, and the interesting part is that **the three locales
did not need the same edit, and treating them as one sentence in three languages would have made
the listing worse.**

Checked against the live text on 2026-08-31, one locale at a time:

| locale | the live sentence | after v1.30 | outcome |
|---|---|---|---|
| en-US | `No account` | an in-app purchase uses an Apple Account, so the unqualified claim can be read as "nothing here needs an account" | **corrected** |
| zh-Hans | 「无账号」 | same unqualified reading | **corrected** |
| **ja** | `アカウント登録は不要` | says **registration** is not required, which stays true: a buyer uses an Apple Account they already have and registers nothing with the developer | **left alone** |

Editing `ja` for symmetry would have replaced a sentence that was already unambiguous with one
that needed a qualifier — **loosening it while looking like tidying** — and it would have put
un-reviewed Japanese into the one listing on this app that had a native review. A Japanese reader
is not left short: the App Store renders the purchase's own Japanese name and description on the
same product page.

The correction that was made states the fact rather than narrowing the claim, because a narrowed
claim still leaves the reader to infer:

> • Works fully offline. No sign-up and no account with the developer, no ads, no tracking, and
> no analytics of any kind. **The one optional in-app purchase is handled by the App Store,
> through your own Apple Account.**

### And this exact line has gone stale once before, which is the part worth keeping

Until v1.28 it read `No account, no network, no tracking, no ads` — and `iCloudSyncEnabled`
defaults to **true**, so the app reached the network by default while the product page said it
did not. The sentence was true when written and was falsified by a capability added afterwards,
and nobody went back to re-read it. `PLAN-STAGE1` expected this line to become false when the
IAP shipped; **it had already been false for releases.**

> **The rule, which is worth more than either correction: every capability that touches the
> network or an account requires this paragraph to be re-read before it ships.** It is the most
> stale-prone and least re-read paragraph on the product page, and it has now been caught twice
> by somebody happening to look — which is not a method. Recorded in `STATE`.

### The edit is surgical, and that is load-bearing

`submit_1_30.py` does not ship the description as a constant. Shipping 1,773 characters from this
repo would silently revert anything changed in App Store Connect since the last release — and
this listing is not maintained only from here: a separate session owns product/ASO, and the `ja`
locale was written and natively reviewed outside any submit script.

So `DESCRIPTION_EDITS` names, per locale, the exact sentence it expects to find and the exact
sentence it leaves behind, and **a locale where the old sentence is not present exactly once is a
FAILURE, not a skip.** "Already corrected" and "somebody rewrote the paragraph" must not print
the same thing. Four cases were exercised against the live text before anything was PATCHed:
the edit applies · already-corrected writes nothing and does not fail · a rewritten paragraph
fails · the sentence appearing twice fails. The applying case also asserts the reverse
substitution reproduces the original byte for byte, which is what proves nothing else moved.

## §B How the first in-app purchase actually gets submitted, and the wrong turn on the way

The IAP rides **the version's own review submission**, as a `reviewSubmissionItems` whose
relationship is **`inAppPurchaseVersion`** pointing at an `inAppPurchaseVersions` object
(`GET /v2/inAppPurchases/{id}/versions`) — not at the purchase.

That is three steps from where this release started, and the steps are worth recording because
**the mistake was in the reasoning, not in the API.**

**1. The first probe asked the wrong names and the absence was believed.**
`fields[reviewSubmissionItems]` rejects `inAppPurchase` and `inAppPurchaseV2` while accepting
`appStoreVersion`, `appEvent`, `appCustomProductPageVersion` and both experiment types, so the
probe demonstrably fires — and I concluded the resource does not take purchases at all. The
instrument was fine. **The candidate list was two names long, and the right name was a third one
that describes a different object.** A positive control on the create endpoint settles the
question the field list could not: `appStoreVersion` answers with a STATE error where a nonsense
name answers `RELATIONSHIP.UNKNOWN`, so the endpoint does distinguish the two cases — which means
an `UNKNOWN` for two guesses was never evidence about a third.

**2. `inAppPurchaseSubmissions` exists, is create-only, and is the wrong endpoint here.**
`GET /v1/inAppPurchaseSubmissions` answers 403 *"Allowed operation is: CREATE"* against a control
path that 404s, so the resource is real — it is how a **later** purchase is submitted on its own.
For an app's first non-consumable it returns 409:

> `STATE_ERROR.FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` — *"The first Non-Consumable
> In-App Purchase for this app must be submitted for review at the same time that you submit an
> app version."*

**Both readings of "at the same time" were tried and both were wrong**: with the versions already
`WAITING_FOR_REVIEW`, and with an open submission holding the version item but not yet sent. The
sentence does not mean *around the same moment*; it means *in the same submission*.

**And the error carried its own diagnosis the whole time.** The first failure printed only
*"please check associated errors"*, which reads like a dead end; the machine-readable
`meta.associatedErrors` in the same response body held the exact code. It was found by dumping the
error object rather than the message — a reminder that an ASC error's `detail` is a summary and
its `meta` is the evidence.

**3. One purchase cannot be an item in two submissions.** Adding it to the second platform
returns `STATE_ERROR.ENTITY_STATE_INVALID`. That is right rather than a limitation: under
Universal Purchase the SKU is app-level, so it is reviewed once and is then live on both. macOS's
submission carries it; iOS's carries its version alone.

### The defect this release found in its own submit script, which cost the two submissions

`do_submit` said, in a comment, that the purchase "is submitted only if every attach succeeded" —
and then the loop that submitted the versions never looked at whether it had. So when the purchase
failed, **both platforms went to Apple anyway, carrying release notes describing a purchase nobody
could make.** Both submissions were cancelled (`PATCH reviewSubmissions {canceled: true}`; the
versions come back as `DEVELOPER_REJECTED`, which is submittable) and rebuilt correctly.

A guard in prose and no guard look identical from outside. The rule now lives in the control flow
— nothing is submitted unless the purchase is staged or already in review — and in
`scripts/test_submit_gate.py`, which drives `do_submit` against a stateful fake App Store Connect.
**It has a paired control that must fire**: the mutation half asserts zero submissions go out when
the purchase cannot be staged, and that assertion would pass just as well on a `do_submit` that
submits nothing at all, so the control half runs the identical fake with one variable changed and
requires exactly two submissions and no failures. Removing the gate from a copy of the script
makes the test red with the exact message this afternoon produced.

**What was NOT harmed, and it is worth saying because it is the reason this was recoverable:** the
metadata phase had already read every field back byte for byte, so the cancel/rebuild cycle
replayed only submission containers. No copy was rewritten, and no build was rebuilt.

## §C What the copy quotes, and why none of it is typed

`release_numbers.py` gained the shape of the two roads, parsed out of the shipped
`RideRoute.swift`: `freeRouteStretches` 8 · `freeRouteEndKm` 25 · `paidRouteStretches` 8 ·
`paidRouteFirst` Ōsaka · `paidRouteLast` Nagasaki · `paidRouteStops` the eight names. The What's
New and the review notes quote those rather than integers somebody typed beside them — the same
rule that exists because two live listings said 183 passages for months after the corpus reached
233.

**The parse asserts its own population before anything reads off it**: both roads present, both
non-empty, ids contiguous from 0. Proven to fire — renaming `startMetres` to `startMeters` in the
route (the shape a refactor takes) makes it exit with *"parsed no tokaido stretches"* instead of
quoting a plausible zero. A regex that silently matches nothing is this repo's oldest defect, and
it would have reached App Review inside a sentence.

`BASELINE_REF` was advanced to the v1.29 release commit, so every corpus delta in this release
reads **0**, which is true: v1.30 touches no vocabulary file. Leaving the baseline behind is how a
one-release delta silently becomes a two-release total.

## §D What the release notes say, and the dimension that makes that legitimate

The five-clause placement discipline — no modal, no badge, no post-ride solicitation, no
recurring reminder, far from the rating prompt — **constrains in-app surfaces.** Release notes are
shown by the App Store, once per update, outside the app; no clause reaches them. Naming the
dimension is the point: `STATE` now records that a prose clause whose dimension nobody wrote down
always costs something, and the only variable is which form.

What does carry over is the standard the menu strip was held to — report the state, do not sell
it. So the notes say a second journey exists and that one optional one-time purchase opens it,
and they carry no price, no urgency and no call to act. They also say, first among the bullets
that matter, that **the Tōkaidō stays free and complete and this version takes nothing away from
anyone** — which is the red line stated to the people it protects.

## §E Still owner-only, and still not done

Unchanged from `PLAN-STAGE1` §K/§L, restated because a release is exactly when these get assumed:

* **The three manual gates** — no App Store account signed in · Family Sharing does not inherit ·
  macOS↔iOS cross-platform restore. Each needs a date, a device and an outcome written into §L's
  table. **The automated gates do not run either** (`SKTestSession` is inert for this app on this
  machine), so this manual list is the only purchase coverage that exists. A green `swift test`
  says nothing about StoreKit.
* **The day-0 known positive** — one real ¥10 purchase on the owner's own Apple Account in
  production, confirm `sales_report.py --calibrate` still passes, refund, then exclude it from the
  cohort and record the date. An agent cannot do this and must not try.
* **The 90 days start at `READY_FOR_SALE`, not at submission.** Changing the price or the offer
  mid-window voids the pre-registration.
