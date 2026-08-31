# The 90 days — what may be built while Stage 1 is being measured

Written 2026-08-31, the day v1.30 went to review; **rewritten the same day after two external
reviews killed its central proposal.** What that proposal was, and how it died, is kept in §C
rather than deleted, because the reason it died is the most useful thing in this file.

`PLAN-STAGE1.md` decided what is sold and what will be concluded. `PLAN-V1.30.md` records how it
shipped. This file answers the only question those two leave open: **what is legitimate to build
between now and day 90.**

---

## §A The question is not "what next", it is "what will not destroy the measurement"

Stage 1 cost a release and buys exactly one number. The pre-registration in `PLAN-STAGE1` §K fixes
in advance what each outcome means, and the whole value of fixing it in advance is lost the moment
something moves that the pre-registration did not anticipate. **The most expensive mistake
available in the next 90 days is not building the wrong feature. It is building a right feature
that makes the number uninterpretable**, because the number cannot be re-taken: there is one
cohort, and restarting the clock costs 90 more days at ~2.3 installs a day.

Every candidate gets one test, in two clauses, because the pre-registration has two sides:

> **Does it change what a device is offered? Does it change which devices arrive?**

The first protects the treatment, the second the denominator. Touching neither is free. Touching
either is not forbidden — it is **registerable**, and the difference between a covariate and a
degree of freedom is entirely whether it was written down before it shipped. §K already carries
one that was not: the `ja` listing, registered three days late.

---

## §B The tension, stated rather than dodged — and it is real

`PLAN-STAGE1` §N concluded from six independent analyses that **the binding constraint is
distribution, not the catalogue** — 14,292 impressions converting at 0.76%, 93% of installs from
search. That is the highest-value work available to this project by a wide margin.

**And it is exactly the work clause two forbids.** Keywords, title, subtitle, screenshots and new
locales all change which devices arrive.

One reviewer proposed off-store acquisition (Reddit, Hacker News, YouTube, 小红书) as a third
option that "perfectly preserves the ASO baseline". **That is wrong and it is worth saying why,
because the error is attractive:** off-store traffic does not touch App Store *metadata*, but
clause two is not about metadata — it is about which devices arrive. Off-store promotion dumps
installs of a different intent distribution into CN/US/JP, the strata that carry the measurement.
It is *more* contaminating than a metadata change, not less, because it moves both the volume and
the composition of the existing strata.

**So there is no free distribution work, and this plan stops looking for some.** The dilemma is
genuine. What follows accepts it: the window is spent on diagnosis and on debt, and distribution
is *prepared* rather than shipped.

---

## §C The proposal this plan was built on, and the two-line check that killed it

**WITHDRAWN.** The first draft's central move was: ship a `zh-Hant` or `ko` storefront listing,
because Taiwan (2 lifetime installs) and Korea (0) have no baseline, so a new locale there creates
a *new stratum* rather than shifting an existing one — buildable inside the window provided the
exclusion from the day-90 read is declared in advance.

Both reviewers rejected it, independently, and the decisive objection is one neither the draft nor
its author checked:

```
Sources/SettingsKit/AppSettings.swift:129
    private static let validLanguages: Set<String> = ["en", "zh"]
Sources/SettingsKit/AppSettings.swift:211
    if !Self.validLanguages.contains(s.languageCode) { s.languageCode = "en" }
```

**The app's interface is English or Simplified Chinese. There is no third option, and any other
code is silently reset to English.** The corpus carries `exEN` and `exZH` glosses and nothing
else. So a Korean listing would send Korean readers to an English/Simplified-Chinese app, and a
Traditional-Chinese listing would send Taiwanese readers to Simplified copy — *for a product whose
entire subject is the precision of written language.* The predictable result is an uninstall, and
the less likely but much more expensive one is **the single negative review that §K names as its
only stop-and-fix guardrail**, arriving inside the measurement window, caused by this plan.

A second, smaller hole confirms the shape: **Hong Kong is already a Traditional-Chinese-reading
stratum with a baseline** — 51 impressions, 3 downloads, 5.88%, on the English listing
(`v2-acquisition-funnel.md`). The draft's territory table listed TW and KR and did not think of
HK, so even the bookkeeping was incomplete.

> **The lesson is not "check the binary before writing a localisation plan", though it is that
> too.** It is that this file asserted *"a new locale in a zero-baseline territory creates a new
> stratum"* — a claim about **store mechanics** — and never asked the prior question of whether
> the **product** could serve those readers at all. STATE's new preamble names the family exactly:
> a sound argument, correctly reasoned, aimed at a scope that was never checked. The store
> argument is fine. It was answering a question that could not arise.

**What would make this reopen:** localising the UI and the glosses, which is a real project and is
not window work. Recorded so the next person meets it as a prerequisite rather than rediscovering
it as an objection.

---

> ### CORRECTED 2026-08-31, hours after writing, on the owner's push-back — this file conflated two unrelated things
>
> The owner's response to the draft was *"I'd rather build more features."* **They are right, and
> the error is structural rather than a difference of taste.**
>
> This plan organised the window around *protecting the measurement*, and then listed only
> maintenance as permitted — coverage, corpus fixes, accessibility. That silently treats "build"
> and "measure" as competing for the same 90 days. **They do not compete at all.** The measurement
> is a purchase count pulled from App Store Connect by `sales_report.py`. It costs **zero
> engineering**, it runs whether anybody writes code or not, and no feature work makes it arrive
> later or noisier.
>
> **And free feature work passes both clauses of this file's own test.** A new practice mode does
> not change what a device is offered — the paid thing is still the road west — and it does not
> change which devices arrive. §A had the right test; §D applied it only to a drawer of chores.
>
> **The genuine constraints on feature work are four, and they are much narrower than this file
> implied:**
>
> 1. **Do not touch the offer, the price, or the placement.** Voids the pre-registration.
> 2. **Anything shipped free is permanently free**, by the red line — no installed user may lose
>    anything. So the window is the period in which the Stage 3 catalogue gets given away. This is
>    the one constraint that actually shapes *which* feature, and it is a decision rather than a
>    rule; see §K.
> 3. **A feature that substantially changes how far people ride changes exposure-per-install**,
>    which is the denominator §K deliberately does not measure. Second-order and tolerable —
>    **register it, do not avoid it.**
> 4. **Do not change store metadata for `en-US` / `zh-Hans` / `ja`.** Unchanged; that one really
>    is about which devices arrive.
>
> Everything else — modes, review scheduling, stats, widgets, UI, accessibility, content — is
> open. §D below stays correct about *what the debt is* and is wrong about it being the whole list.

> **The backlog moved out of this file on 2026-08-31.** The owner chose fast iteration, and a
> constraint document that also carries the work list makes the work list read like a set of
> concessions. **`docs/PLAN-ITERATION.md` is the backlog**; this file is why the constraints are
> as few as they are. §D below is kept because it is still an accurate inventory of the *debt* —
> it was never an accurate inventory of what may be built.

## §D What is free, re-ranked after review

Free = invisible to both clauses of §A's test. **The first draft ranked these by what was
interesting; both reviewers reordered them by what is at risk, and they were right.**

**1. Automated coverage for the purchase, on iOS.** `run_store_gates.sh` exits 3 with nine tests
skipped — `SKTestSession` is inert for this app on this machine — and **iOS StoreKit is observed
by no automated test at all.** The two targets share `Sources/NihongoRideApp`, so "the adapter is
the same code" is an argument, not an observation, and `PLAN-STAGE1` §J says so in those words.
The thing now carrying money has the least coverage in the repository. Re-check on every toolchain
change; the failure is a simulator runtime bug, not a law. **Ranked fourth in the first draft; it
belongs first.**

**2. Read `ta_score`'s `totalPlayerCount` — cheap, but not "one call".** §N refuted a Game Center
leaderboard as an instrument and then named the free step nobody took: `ta_score` has shipped since
v1.3 and its player count has never been read. If it returns 3, a class of future proposals closes
for almost nothing. **The first draft called it "the cheapest item in the repository" and that was
wrong** — `GKAccessPoint`/`GKLeaderboard` need an authenticated Apple Account on a real device, so
this is a physical-device errand plus throwaway debug code, not a script. Still cheap. Not free.
And it must not change what any user sees: the access point is *already* active on the Settings
screen that carries the offer row (§N), so the constraint is to read the count without touching
that.

**3. Corpus items with a known shape.** `n5-kazoku` reads 四人 as よんにん where standard Japanese
lexicalises よにん — correcting it releases no sentence (Kyoko says ひと either way), so it belongs
to a reading-gate release rather than its own. The 112 uninspected residue. Small, well-understood,
and invisible to the measurement.

**4. Accessibility (§E, carried since v1.26) and ordinary defects.** v1.30's Mac short-window fix
came out of this drawer and was a real bug nobody had reported.

**5. NOT the 522 undecided dictation sentences.** The first draft ranked these second. `PLAN-V1.29`
closed that door **with a measurement**: 1b's silence is a prosody limit rather than a coverage
gap, Sudachi had already proposed the hypothesis for 518 of 523, testing the missing five released
exactly one sentence, and `AVSpeechSynthesisMarker` phoneme marks are empty for every Japanese
voice. Both reviewers called this an unbounded research sink against a closed door. **Demoted to:
if a new instrument appears, revisit. Do not go looking during the window.**

---

## §E The one thing the first draft omitted entirely, and it is the most valuable item here

**Moderated sessions with 10–15 recruited users.** This is not a new idea — it is
`PLAN-V2-PRODUCT` §H, which already says to *"recruit 10–15 target users across proficiency,
territory and platform. Watch a session. Then force a choice between concrete packages at concrete
prices"*, and calls it *"the only instrument that can answer a question ASC structurally
cannot."* The first draft scheduled 90 days of waiting and never mentioned it.

**Why it is the most valuable thing available, stated against §K's own structure.** §K's day-90
decision has three branches, and their probabilities are not close to equal:

| branch | fires when | honest probability |
|---|---|---|
| **GO** | ≥ 1 purchase | plausible, and the only clean outcome |
| **STOP, with evidence** | zero purchases **and** a voluntarily returned counter showing `offerAppeared > 0` in the `kyoto` bucket | **very low.** `UnlockOfferLedger`'s own doc comment puts expected returned ledgers over 90 days at *"under two and plausibly zero"* — and this branch needs one from a *non-buyer who reached Kyoto*, a strictly rarer thing |
| **UNINTERPRETABLE** | zero purchases and no such counter | **almost everything else** |

> **⚠️ And this table is misleading as written, corrected the same day.** It gives the branch
> probabilities *conditional on zero sales* without ever saying how likely zero sales is — which
> makes UNINTERPRETABLE look near-certain when it is not. Over ≤ 323 devices ever exposed, the GO
> branch fires with probability **80% at a true conversion of 0.5%**, 96% at 1%, and still 48% at
> 0.2%. It only collapses below ~0.3%. **The measurement is in materially better shape than the
> paragraph below suggests**, and presenting a conditional probability as if it were an
> unconditional one is this repo's own favourite error wearing statistics.

So conditional on zero sales, the pre-registered outcome is *already* known today, and §K says as
much: it exists precisely so that "this taught us nothing" is a permitted result rather than a
rationalisation. **That is intellectually honest and it is still a bad position to be in**, and
moderated sessions are the one instrument that changes it — they do not depend on a stranger
volunteering a debug string, and they answer *why* rather than *whether*.

Against §A's two clauses: recruited users install the app, so clause two is touched. **Register
them now** — recruit outside the App Store where possible, record how many installs the recruitment
produced and in which territories, and exclude them from the day-90 read the way TW/KR were going
to be excluded. That is bookkeeping this file can do correctly, unlike §C, because the users are
counted individually.

---

## §F The checkpoints, corrected — and one of the corrections is inside the pre-registration

**§K's day-15 row was arithmetically false and has been corrected before day 0.** It said a zero at
day 15 *"already falsifies the revenue model"* against §D's 8.2%. Rule of three at n = 34.8 bounds
conversion at **3/34.8 = 8.62%**, so 8.2% is *not* excluded — the refuting number sat in the
adjacent cell of the same row. Exact binomial: P(0 | p = 0.082, n = 35) = **5.01%**, which does not
clear 0.05 either. **The first checkpoint that can falsify 8.2% is day 42** (bound 3/97.5 = 3.08%).
The thresholds are unchanged; only the claim about what a day-15 zero *means*. See §K's correction
box.

**Both reviewers also rejected the calendar-day projection, and they are right.** The table's
~35 / ~98 / ~209 comes from 2.321 installs/day held flat, while the measured series is
**0.46 → 1.11 → 2.39 per day across three 28-day windows** — roughly doubling each month — with the
`ja` ramp still in flight. A flat anchor on a non-stationary series makes every row wrong in the
same direction.

> **The fix is to denominate the checkpoints by cumulative new installs rather than by date**:
> read at **N = 35**, **N = 100**, **N = 200**, whenever they arrive. The rule-of-three bounds are
> functions of N alone, so this makes the pre-registration *more* exact rather than changing it,
> and it removes a growth assumption the plan had no business making. **This is proposed here and
> is not yet adopted** — it changes the shape of §K's table and therefore needs the owner's
> decision, and it must be decided **before day 0**, which is the only moment amending a
> pre-registration is free.

**And a smaller one neither reviewer stated cleanly.** One reviewer claimed §K blindly attributes
purchases to the new cohort when the 114-device base can buy too. **That is wrong at day 90** — §K's
day-90 row carries both denominators explicitly (*"208.9 (+114 base ⇒ ≤ 323 devices ever exposed)"*,
*"≥ 1.4% on new installs · ≥ 0.9% against the ceiling"*). **It is right at day 15 and day 42**,
whose rows carry only the new-install denominator, and where the base is proportionally largest —
at day 15 the base is over three times the new cohort. Those two rows should carry the ceiling too.
*(The same reviewer's proposed remedy — read `AppTransaction.originalAppVersion` — is unavailable:
§I decided against `AppTransaction` because it throws `networkError(-1009)` offline, and no sibling
app uses it.)*

| checkpoint | expected installs (flat anchor, **known to be low**) | zero purchases rules out | decision |
|---|---|---|---|
| **day 0** | — | — | Owner buys one ¥10 in production, confirms `--calibrate`, refunds, records the date, **excludes it**. **Owner only.** |
| **N = 35** (~day 15) | 34.8 | ≥ 8.6% | Record. **Falsifies nothing.** Do not change the price. |
| **N = 100** (~day 42) | 97.5 | ≥ 3.1% | Record. First checkpoint that can falsify §D's 8.2%. **No iteration.** |
| **N = 200** (~day 90) | 208.9 (≤ 323 exposed) | ≥ 1.4% new · ≥ 0.9% ceiling | Decide on §K's three branches. **Split by territory**; JP flagged for the `ja` ramp. |
| **day 180** | — | — | Refund ceiling — refunds land up to ~90 days after a sale. |

---

## §G What must not be built

| | why |
|---|---|
| **A second SKU** | §N: six independent analyses said no, and the arithmetic is re-derivable — a week of engineering must clear 6.7% of every new install, forever. **And `UnlockOfferLedger.counts` has no product dimension**, so a second offer silently pools its counts with the road's. Split the counter first, **never in the same release**. |
| **Pro, or §F1 "bring your own Japanese"** | Stage 3. No tokenizer on the device; `VocabStore.loadBundled` reads a `static let shared`; 80–120 h estimated. Stage 2 cannot happen before day 90. |
| **A `zh-Hant` or `ko` storefront listing** | §C. The binary cannot serve those readers. |
| **Anything server-backed** | The failure rule, and the fully-offline positioning three localised listings and the app's only review rest on. |
| **Any transmitted telemetry** | `Data Not Collected` stays. Local never-transmitted counters remain fine — the distinction is collection, not counting. |
| **Charging for data export** | Plain CSV export is free, permanently. |
| **Changing the price, the offer, or the placement** | Voids the pre-registration. The only row here where the cost is not "wasted effort" but "the previous release was wasted". |

**Prepared but not shipped:** CN search-result creative. `v2-acquisition-funnel.md` establishes the
gap is at the search row (impression → product page, 4.01% vs 6.19%, z = +3.55) and **not** at the
product page (z = +1.70, not significant on eight Japanese page-installs). Icon, title, subtitle
and first-two-screenshot variants can be *designed* during the window and shipped on day 91.
Designing costs nothing measurable; shipping moves 75% of impressions.

---

## §H Owner-only, one with an expiry already running

* **§L's three manual purchase gates** — no App Store account signed in · Family Sharing does not
  inherit · macOS↔iOS cross-platform restore. §L required these *before* v1.30 was submitted; they
  were not walked, and §L carries a box saying so. **While the version is in review a failed gate
  costs a cancel and a resubmit — minutes, measured. After `READY_FOR_SALE` it costs a whole new
  version with live customers meeting a broken purchase.** Two of the three need only a Mac and an
  iPhone.
* **§K's day-0 known-positive purchase.** An agent cannot do it and must not try.
* **Whether to adopt §F's install-denominated checkpoints.** Free to decide now, not later.

---

## §I What would make this plan wrong

* **If v1.30 is rejected.** Everything assumes it ships; a rejection moves day 0 and may move the
  copy.
* **If `ta_score` returns a usable `totalPlayerCount`.** §N's refutation rests partly on achievable
  n; a surprising number reopens a measurement §H calls impossible.
* **If traffic keeps doubling.** §F already treats the flat anchor as known-low. If the third-month
  rate holds, day 90 arrives with materially more installs and the bounds tighten faster.
* **If the engagement reports become usable.** Called permanently unavailable on 2026-08-26,
  falsified four days later. At 9.2% coverage they cannot carry a guardrail; at 40% they could, and
  Stage 1's safety would stop being purely designed.
* **The largest remaining assumption, named:** that spending the window on debt and diagnosis
  beats spending it on distribution and accepting a contaminated read. This plan chooses the
  measurement. **That choice is only correct if the measurement is worth having** — and §E's own
  table says the most likely outcome is UNINTERPRETABLE. A defensible opposite plan exists: treat
  Stage 1 as already-answered-by-construction, spend 90 days on distribution, and read whatever
  arrives as a bonus. It is not chosen here, but it is not stupid, and if the owner prefers it the
  cost is one paragraph in §K rather than a rebuild.

---

## §J What the two reviews changed, kept in the house style

Gemini 3.1 Pro and Gemini 3.7 Flash, independently, 2026-08-31, both with the repo readable.
**Every finding below was verified against the repo before being accepted, and two were rejected.**

**Decisive, and it killed the plan's central proposal.** Both found that the app's UI is
`["en", "zh"]` only, so `zh-Hant`/`ko` listings would deliver readers to a language the binary
cannot show. Flash cited `AppSettings.swift:129` exactly. Verified.

**Decisive, and it is an error inside the pre-registration.** Flash computed that a day-15 zero
does *not* falsify §D's 8.2% — 3/34.8 = 8.62%, and the exact binomial is 5.01%. `PLAN-STAGE1` §K
said it did, in a cell adjacent to the number that refutes it. Corrected before day 0.

**Right, and it was a whole missing section.** Flash noted the plan omits `PLAN-V2-PRODUCT` §H's
moderated sessions — the only instrument that addresses the near-certain UNINTERPRETABLE branch.
§E exists because of this.

**Both, independently, on the growth projection.** A flat 2.321/day anchor against a measured
0.46 → 1.11 → 2.39 series. Both proposed denominating by installs instead of dates.

**Both, independently, on the ranking.** iOS StoreKit coverage up; the 522 dictation sentences out.

**Right, and it made the first draft's own claim sharper.** Both found Hong Kong — an existing
Traditional-Chinese-reading stratum the draft's table omitted.

**Rejected, and checked before rejecting.** Pro called it the biggest blind spot that §K would
"blindly attribute" a base-user's purchase to the new cohort. §K's day-90 row carries both
denominators explicitly. The claim is false at day 90 — and true at day 15 and day 42, which is
narrower, more actionable, and was obscured by the overstatement. Pro's proposed remedy
(`AppTransaction.originalAppVersion`) is unavailable for reasons §I already recorded.

**Rejected.** Pro offered off-store acquisition as a third option that "perfectly preserves the ASO
baseline". It preserves the metadata and not the baseline; clause two is about which devices
arrive. See §B.

**The pattern, worth naming because it is this repo's own.** The two rejected findings were both
*asserted* — a claim about what §K does, and a claim about what off-store traffic preserves —
neither checked against the file it described. The six accepted findings all *cited a line*. That
is the same split this project keeps finding in its own work, arriving from outside it.
