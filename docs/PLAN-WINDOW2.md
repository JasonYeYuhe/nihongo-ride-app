# PLAN-WINDOW2: Window 2's pre-registration — a DRAFT of both variants, measurement mechanics only

> ## ⚠️ DRAFT. This is not the pre-registration, and nothing in it binds yet.
>
> * There are two variants: **E3-path** (treatment v1.39) and **silence-path** (treatment v1.38).
>   **One variant is committed as Window 2's pre-registration, before its treatment release's `--submit`**
>   (`docs/PLAN-V1.37.md:206`, `:384-385`). The one exception is the late box (below), where S is already committed
>   and E is added as its own dated section before v1.39's `--submit`. This commit is a draft of both. It is not that
>   commit, and it does not start any window.
> * Written 2026-10-28 (JST) on branch `docs/p0-5-8`; revised the same day after an adversarial check
>   (`~/Library/Caches/NihongoRide-v137-work/review-p0-5-8.json`).
> * **Agent-authored under the owner's 2026-10-07 delegation** ("你想办法自己做掉 你全权负责 没办法再找我",
>   `docs/measurements/stage1-checkpoints.md:44-46`). It holds **measurement mechanics only**: units, the
>   FX table, the burn-in, the read dates, N₂, the denominator and the P1-12 instrument note
>   (`docs/PLAN-V1.37.md:206`). Where a mechanic needed a choice that the plan does not make, it is labelled
>   *the agent's choice under the 2026-10-07 delegation*. None of it is the owner's decision.
> * **Every branch-consequence cell is blank for the owner**: what ZERO, BELOW-FLOOR and GO-2 mean for the
>   next work, and what an owner box mid-window means. The owner fills them at C-2(e), or in Appendix A-1
>   item 5 on the E3-path (`docs/PLAN-V1.37.md:98`, `:579-580`). PLAN-V1.37 §H holds the agent's *draft*
>   consequences for the owner to read (`docs/PLAN-V1.37.md:365-371`). They are not copied here.
> * **With no answer, the treatment period is reported descriptively against these mechanics, and decides
>   nothing** (`docs/PLAN-V1.37.md:206`, `:370`, `:480`). That is the default on silence.
> * **A blank cell suspends nothing.** The red line, "No existing install loses anything, ever"
>   (`docs/PLAN-V2-PRODUCT.md:387-388`), and the guardrails PLAN-V1.37 §H keeps (a negative review mentioning the
>   purchase, and a grandfathered user reporting lost access, each a stop-and-fix: `docs/PLAN-V1.37.md:372`;
>   `docs/PLAN-STAGE1.md:567-568`) bind by their own texts, whatever this file says. A blank cell here is only what an
>   event means for Window 2's next work.
> * No price is proposed ("An agent invents no prices", `docs/PLAN-V1.34.md:729`). No §K box is written, and
>   nothing goes into `docs/PLAN-STAGE1.md`.

**How the committed version is made from this draft** (on the commit day, before the treatment's `--submit`):
1. Keep one variant (§2 or §3) and delete the other.
2. Fill every `<…>` that §1 and the kept variant mark "filled at commit", from the source named beside it, on
   that day. Nothing is filled from this draft's illustrative values.
3. Leave every `_(owner, …)_` cell exactly as it is, unless the owner has written it. If the owner wrote it,
   paste the owner's words verbatim with their date.
4. Commit it alone, and only then run `--submit`.

**The late box.** If A-1 is written after v1.38's `--submit`, variant S is already committed and its window is open.
v1.39 then moves to 2027-01-05..15 (`docs/PLAN-V1.37.md:385`). On that path:
* variant E is appended as its own dated section, filled at its own commit date (its own FX table, prices and r), and
  committed before v1.39's `--submit`;
* nothing in S's committed text is reworded;
* S's open window is the "owner box mid-window" row of §2. Whether S ends there is that row's blank consequence cell.
  The mechanics only record the box's date, and S's readings up to E's D₀′.

---

## §1 Mechanics common to both variants

### 1.1 Units

* **Report days are Pacific** (`America/Los_Angeles`), as `sales_report.py` cuts them (`scripts/sales_report.py:297`,
  `:1695-1696`). Every row below counts Pacific report days.
* **Rates are per 30 Pacific report days**, the unit `sales_report.py` prints (`scripts/sales_report.py:1755-1756`;
  `docs/PLAN-V1.37.md:322`, `:357`). A rate is a count divided by the data days in its window, times 30.
* **The floor is ¥50 (CNY) per 30 Pacific report days.** The owner's input was "¥50 CNY/month"
  (`docs/PLAN-STAGE1.md:145-146`). PLAN-V1.37 restated it per 30 Pacific report days (`docs/PLAN-V1.37.md:154`,
  `:523`).
* **Money is net developer proceeds.** It is bucketed by the report's `Currency of Proceeds`, never summed raw, and
  converted to CNY only through the FX table in 1.4. Unit counts are printed beside every money figure
  (`docs/PLAN-V1.37.md:357`).

### 1.2 Day 0′, day numbering and the calendar

* **D₀′ is the first Pacific report day on which both platforms are live on the treatment release**
  (`docs/PLAN-V1.37.md:356`): **the firm Pacific release date of the later platform**, a partial day, as
  `FIRM_RELEASE_DATES_PT` counts a release day (v1.36 went live at 15:40–16:00 PDT and its line is that day,
  `scripts/sales_report.py:272-274`). *The agent's choice under the 2026-10-07 delegation.* Direction: D₀′'s
  first-time downloads count in n, and a few of them may predate the release, so n is slightly larger.
  * Both platforms' Pacific release dates are recorded separately when they differ, because "a row in this table may
    describe one platform" (`docs/PLAN-ITERATION.md:689-691`).
  * Source: the store's own release timestamp (iTunes lookup `currentVersionReleaseDate`, read the day it happens),
    the same source `FIRM_RELEASE_DATES_PT` uses (`scripts/sales_report.py:251-255`, `:256-275`).
  * First-time downloads on the earlier platform before D₀′ are outside n, and printed on their own line.
* **Day numbering follows Stage 1:** "day k" is D₀′+k, with D₀′ itself day 0. Stage 1's "day 90" is 2026-09-09 + 90 =
  2026-12-08 and "day 180" is + 180 = 2027-03-08 (`docs/PLAN-STAGE1.md:425-427`). So "≥ 60 days since day 0′"
  (`docs/PLAN-V1.37.md:362`) means a newest report day of D₀′+60 or later.
  * The burn-in D₀′..D₀′+13 is §H's own span, 14 report days (`docs/PLAN-V1.37.md:360`).
  * GO-2's two periods end on D₀′+73 (1.6). That is day 73 in this numbering. §H's "about day 74"
    (`docs/PLAN-V1.37.md:363`) counts the 74 report days D₀′..D₀′+73; it is the same day.
* **JST and PT.** Apple publishes report day D on the Pacific morning of D+1; the tool reads "Pacific today − 1"
  (`scripts/sales_report.py:1695-1696`). Pacific time is UTC−8 (PST) from 02:00 on 2026-11-01 to 02:00 on 2027-03-14,
  and UTC−7 (PDT) outside that. So 07:00 Pacific on D+1 is 00:00 JST on D+2 under PST, and 23:00 JST on D+1 under PDT
  (2027-03-14 07:00 is already PDT). **Plan each reading for JST D+2.** The N = 100 reading of Pacific 10-25 was run on
  JST 10-26, under PDT, and its same-day `review_watch` ran at 14:36Z, 23:36 JST
  (`docs/measurements/stage1-checkpoints.md:204-206`, `:263`). The exact publication time is not measured here.

### 1.3 The denominator

* **The running count n = first-time downloads (`F1` + `1F`) from D₀′ onward, adjusted** (`docs/PLAN-V1.37.md:358`).
  N₂ (1.5) is the target n must reach before the zero row. The adjustment:
  * registered walk installs and registered session-participant installs are subtracted, by the rules of
    `docs/PLAN-STAGE1.md` §K's DECIDED 2026-09-17 box items 1–3 (`:775-787`) and its participant box items 1–5
    (`:875-892`);
  * every walk or participant install is registered **before** any Window 2 reading whose window holds its Pacific
    report day, as Stage 1 requires (`docs/PLAN-STAGE1.md:778-781`).
  * Today's registry is pinned to Stage 1's day 0 (`scripts/sales_report.py:300`, `:700-701`). Where Window 2's
    entries are kept is P1-12(c)'s to build (`docs/PLAN-V1.37.md:243`).
* **What the reports cannot separate, stated now** (`docs/DESIGN-E3-SAMPLER.md:197`, `:593`):
  * the reports do not say whether a first-time download belongs to a new person;
  * a grandfathered account's first install on its other platform can buy E3, and a sampler installed before a later
    gated release can be granted. Whether Apple counts the first as a first-time download is unverified.
  * So n is a count of first-time downloads, not of people who could buy. **Direction:** where it counts installs
    that could not buy, it overstates the exposed denominator, and a zero rules out slightly more than the data
    support.
* **Silence-path only: a ceiling line**, as Stage 1 printed one (`docs/PLAN-STAGE1.md:804-807`): n + L, where L is the
  lifetime first-time downloads before D₀′ (census, read when D₀′ is known). Every existing install can buy the road,
  so this is the most devices that could have been exposed. It is printed beside n, and no row reads it. *The agent's
  choice under the 2026-10-07 delegation*, following Stage 1's practice. The E3-path has no such line, because
  existing installs are grandfathered and cannot buy E3 (`docs/PLAN-V1.37.md:358`).

### 1.4 The FX table

* **Source: the European Central Bank's euro foreign exchange reference rates**, one named public source
  (https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html; daily
  file https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml; full history
  https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.zip). *The agent's choice under the 2026-10-07 delegation*:
  it publishes CNY, JPY and USD in one file, daily, with a public history, so anyone can re-derive the table for any
  date.
* **Which publication.** The newest ECB publication available at the commit's time, with its date written in the table.
  The ECB does not publish on weekends or TARGET holidays, so the date may be a day or more before the commit.
* **Method.** The ECB quotes units of currency C per 1 EUR. The CNY value of 1 unit of C is
  `rate(CNY) / rate(C)`, from that one publication, kept unrounded. Each currency's net proceeds are multiplied by its
  factor, and the CNY-equivalent is rounded to 2 decimals only at the end. CNY's own factor is exactly 1.
* **Fixed for the whole window.** The table is never refreshed mid-window. A currency moving against CNY later changes
  nothing that is read.
* **A proceeds currency the ECB does not publish** has no factor. The 2026-10-27 publication carries 29 currencies, and
  VND, TWD, AED and SAR are not among them. Such proceeds are printed in their own bucket, in their own currency, and
  are **left out of every CNY-equivalent sum**. Each reading names any such bucket. Direction: toward not reaching the
  floor. *The agent's choice under the 2026-10-07 delegation.*
  * **At commit**, list the `Currency of Proceeds` values the cached reports have shown for this app's rows, and mark
    which have no factor: `<filled at commit>`. (No in-app purchase row has ever been reported, `docs/PLAN-V1.37.md:140`,
    so today that list holds no purchase currency.)
  * Against P1-12(b), which fails calibration on "an empty or unknown currency" (`docs/PLAN-V1.37.md:243`): this file
    reads "unknown" as not a currency code at all. If P1-12 is built stricter, so that any code missing from this table
    fails calibration, that is allowed ("Strengthening a control is always allowed", `docs/PLAN-V1.37.md:408`).

**The table** (filled at commit; blank in this draft):

| currency C | ECB rate, C per 1 EUR | CNY per 1 C = rate(CNY) / rate(C) |
|---|---|---|
| CNY | `<filled at commit>` | 1 (exactly) |
| JPY | `<filled at commit>` | `<filled at commit>` |
| USD | `<filled at commit>` | `<filled at commit>` |
| EUR | 1 (by definition) | `<filled at commit>` (= rate(CNY)) |
| every other currency in that publication | `<filled at commit>` | `<filled at commit>` |

ECB publication date: `<filled at commit>` · read at `<JST time>` from the daily file above · file sha256 `<…>`, kept
outside the repo in the release's work dir.

**Illustrative only. These are not the table.** The ECB daily file read 2026-10-28T01:06Z (10:06 JST) carries the
publication of 2026-10-27: CNY 7.4343, JPY 175.97, USD 1.1150 per EUR. By the method above that gives
CNY 0.042248 per JPY (4.2248 per 100 JPY) and CNY 6.6675 per USD. At those values a JPY 128 net sale (the road's
equalised JPY 150 price, `docs/PLAN-V1.37.md:132`) is about ¥5.41, and a USD 0.84 net sale about ¥5.60, against ¥8.42
for a CNY sale. So the share of sales from each storefront moves how many sales the floor needs.

### 1.5 The floor conversion c\* and N₂

* **Net per sale (CNY):** the proceeds of the treatment price's Apple price point in the CHN base territory, by ASC GET
  on the commit day (`/v2/inAppPurchases/<id>/pricePoints?filter[territory]=CHN`, the GET used in
  `docs/PRICING-BRIEF-V137.md:143-144`).
* **c\*(r) = (50 / net per sale) / (30 × r)**, the share of new installs that must buy to reach the floor at r
  installs a report day (`docs/PLAN-V1.37.md:322-330`, `:362`).
* **Two rates, and the larger governs:**
  * r_reg, the registered rate: the N = 200 record's N divided by its cohort days, filled at commit and never updated;
  * r_obs, the observed rate at each reading: n divided by the report days D₀′..newest.
* **N₂ = max(⌈3/c\*(r_reg)⌉, ⌈3/c\*(r_obs)⌉, 200)** new installs, recomputed at each reading from that reading's r_obs.
  §H writes N₂ = max(⌈3/c\*⌉, 200) (`docs/PLAN-V1.37.md:362`); the r_obs term is added so that the rule cannot read a
  zero on fewer installs than ruling out c\* needs.
  * **Why, and the direction.** ⌈3/c\*⌉ grows with r. A fixed r_reg alone would give too small an N₂ if Window 2's
    traffic rose above Stage 1's, which P1-13 and E5 aim at, and a zero would then rule out less than it claims. Taking
    the larger of the two is the conservative direction. It is mechanical: no reader picks a rate. *The agent's choice
    under the 2026-10-07 delegation.*
  * **What it means in days.** ⌈3/c\*(r)⌉ = ⌈1.8 × net × r⌉, so with r_obs that term is met after about 1.8 × net
    report days, whatever the traffic: about 15 days at a ¥8.42 net, about 103 at §F's ¥68-class anchor (arithmetic,
    not a price). The 60-day and 200-install terms then decide the rest.
* c\* uses the CHN net only. Sales from JP or US storefronts net less in CNY (1.4), so the true c\* is higher and
  ⌈3/c\*⌉ lower. Using the CHN net therefore gives the larger N₂. Direction: more installs before a zero is read. For
  other currencies this is checked at commit against the table; any currency that nets more CNY per sale than the CHN
  price point is named there, and the direction claim does not hold for it.

### 1.6 The rows, by offset from D₀′

| row | fires when | what is read | branch read here? |
|---|---|---|---|
| **Burn-in** | D₀′+0 .. D₀′+13 (14 report days) | Reported separately, with `F7` update counts per day. A purchase here is counted and **flagged**, because it may come from the update wave of existing installs (`docs/PLAN-V1.37.md:360`). | no |
| **Record** | the first reading with n ≥ **100** | n, purchases and refunds by SKU, money by currency bucket and in CNY-equivalent, the burn-in split. | **no** (`docs/PLAN-V1.37.md:361`) |
| **Periods** | P1 = D₀′+14 .. D₀′+43; P2 = D₀′+44 .. D₀′+73; Pk = D₀′+14+30(k−1) .. D₀′+43+30(k−1) | Net CNY-equivalent proceeds in each **full** period, in each sum the variant prints. *The agent's choice under the 2026-10-07 delegation*: fixed periods starting after the burn-in, not a sliding 30-day window, so no reader picks a start after seeing the data. Every reading prints whether the GO-2 condition holds so far, descriptively. | no |
| **Zero row** | the first reading with n ≥ **N₂** (1.5) **and** a newest report day of D₀′+60 or later | n and N₂ at that reading. | no |
| **Backstop** | D₀′+180, if the zero row has not been reached | As the zero row, on the **observed** n, as Stage 1 does (`docs/PLAN-STAGE1.md:426`, `:429-430`; `docs/PLAN-V1.37.md:362`). | no |
| **Close** | the later of (the zero row, D₀′+73); or D₀′+180 if the backstop fired | The window's one branch reading. | **yes, once, here** |
| **Refunds** | D₀′+180 | Refund units of the treatment SKU as **absolute counts**, by currency bucket (`docs/PLAN-V1.37.md:364`). | _(owner, C-2(e); A-1 item 5 on the E3-path)_ |

**One read point.** Every branch condition is read once, on the reading whose newest report day is the close, over
D₀′..close. No branch is read at the zero row, at D₀′+73, or anywhere else. *The agent's choice under the 2026-10-07
delegation.* Why: if the zero row came before D₀′+73 (n reaching N₂ by about day 60, about 3.3 installs a day), a zero
read there and a purchase on days 61–73 would make ZERO and BELOW-FLOOR both hold in one window.

**Deviation from §H, stated.** §H says GO-2 "can fire" at about day 74 and reads ZERO "at the zero row" and BELOW-FLOOR
"by the zero row's date" (`docs/PLAN-V1.37.md:362-363`, `:367-368`). Here GO-2 is *reported* as soon as it holds, but is
read as the branch only at the close: 4 days later at ¥10 (close ≈ D₀′+77), up to 30 days later at the ¥68-class anchor
(close ≈ D₀′+103). ZERO and BELOW-FLOOR are read at the close too.

**The branches are read in this order, and the first that holds is the window's branch.** So they are mutually
exclusive by construction, and the last two together cover every case the first two leave, so they are exhaustive:
1. **GO-2:** the floor is met (the variant's sum) in each of two consecutive full periods, both ending on or before the
   close;
2. **BELOW-FLOOR:** not 1, and net purchases of the treatment SKU over D₀′..close ≥ 1;
3. **ZERO:** not 1 or 2 (net purchases ≤ 0), and the pipeline is proven (1.7);
4. **ZERO, pipeline unproven:** not 1 or 2, and the pipeline is not proven.

A negative net count (refunds reported in the window for sales before D₀′) falls in 3 or 4, is printed as the
negative number it is, and prints no bound.

* **Net proceeds in a period** = the proceeds of purchase units reported on that period's days minus the proceeds of
  refund units reported on them, per currency, then converted. Refunds count on the day they are reported, because a
  refund is the same purchase code with negative Units, "arriving up to ~90 days after the sale"
  (`scripts/sales_report.py:438-440`), and a report row is a total with no link to its sale (`:516-518`; the sign
  convention at `:489-507`). A refund reported after the close is read at D₀′+180 and does not change the branch
  reading.
* **The rule of three is used only to falsify on zero.** 3/n, on the observed n at the close (§H writes it 3/N₂), is
  printed only under branch 3 with net purchases exactly 0 **and** a matched known-positive purchase (1.7). It is never
  quoted for a non-zero count, since "1–3 purchases proves existence and estimates nothing" (`docs/PLAN-STAGE1.md:528-530`;
  `docs/PLAN-V1.37.md:362-363`).
* **Refunds: §H's "under the existing ceiling" is left out on purpose** (`docs/PLAN-V1.37.md:364`). That ceiling is a
  Stage 1 rule with consequences attached ("stop selling", `docs/PLAN-STAGE1.md:556-562`). Whether it governs Window 2
  is a consequence, so it sits in the row's blank cell. The count itself is measurement.

### 1.7 When the pipeline counts as proven

A zero is read only against a proven pipeline (`docs/PLAN-V1.37.md:88`, `:368-369`):
* **(a) a matched known-positive purchase**: a `kind=purchase`, `status=matched` registry entry, from Stage 1's walk or a
  later one (`docs/PLAN-STAGE1.md:790-792`); or
* **(b) a real purchase row** of this app's in-app purchase, of either SKU, classified by the tool at any time since
  2026-09-09. An unknown type code fails calibration loudly, so a positive cannot hide (`scripts/sales_report.py:215-229`;
  `docs/PLAN-V1.37.md:88`).
* Under (a) the close may print 3/n. Under (b) alone it states the zero and prints no bound. With neither, the zero
  is **UNINTERPRETABLE**, a measurement statement written here before any reading (`docs/PLAN-V1.37.md:369`).
* The E3-path adds one condition (§3).

### 1.8 Co-interventions and covariates, registered by name

Components are not separable at about 2.6 installs a day. That is said now, not discovered later
(`docs/PLAN-V1.37.md:355`).
* **P1-13, the store change**: descriptions and promotional text, screenshots, the CN search creative, the IAP
  promotional image, and Promoted IAP if it ships (`docs/PLAN-V1.37.md:244`). Each piece's live date is recorded when it
  goes live, and screenshots may stagger to a later version.
* **E5 (P1-15), Japanese UI**, wherever it ships; read by territory, never as a separate test (`docs/PLAN-V1.37.md:269`).
* **Release cadence**, a registered covariate and never a cause. Release days raise first-time downloads (1.18× in the
  N = 100 reading's control, `docs/measurements/stage1-checkpoints.md:225`). Each release adds its firm Pacific date to
  `FIRM_RELEASE_DATES_PT` (`scripts/sales_report.py:251-255`).
* **The `ja` listing's ramp**, already registered for Stage 1 (`docs/PLAN-STAGE1.md:571-580`). Read every row by
  territory.

### 1.9 The instruments, and the P1-12 note

**The primary instrument is `scripts/sales_report.py` with P1-12 merged** (`docs/PLAN-V1.37.md:243`): (a) a SKU column,
the road SKU pinned, an unknown SKU failing calibration, two SKUs never pooled; (b) proceeds bucketed by
`Currency of Proceeds` and converted through 1.4; (c) `--day0` cohorts; (d) the burn-in split.
* The command line is written in on the commit day from the merged tool's `--help`: `<command, filled at commit>`.
* **The tool on `main` today cannot read Window 2's money rows**:
  * it reads `Currency of Proceeds` (`scripts/sales_report.py:407`) and never uses it, and sums `per_unit * u` across
    every currency into one figure (`:489-507`). One JP sale would print as 128 against a CNY floor
    (`docs/PLAN-V1.37.md:150`);
  * it classifies purchases by type code only (`:219`), so two SKUs pool;
  * its cohort is fixed to Stage 1's day 0 (`:300`).
  * So no Window 2 money figure, and no E3-path purchase count, is read from it.
* **Departure, recorded here as PLAN-V1.37 requires** (`docs/PLAN-V1.37.md:243`). A new kind "would be an instrument
  change and waits, like every instrument change, for the known-positive to be confirmed (2026-09-16 box)"
  (`docs/PLAN-STAGE1.md:891-892`), because "a changed instrument would make 'still passes' compare two different
  instruments across the known-positive" (`:740-741`).
  * With a matched walk, P1-12 merges after the confirmation, as written.
  * **Under A′ (no known positive), merging it is a departure from that rule.** PLAN-V1.37 records the agent's reading:
    after the N = 200 record, Stage 1's readings are closed, so no Stage 1 comparison spans the change. What stands in
    for the missing positive control is (1) the byte-for-byte reproduction of the N = 100 and N = 200 readings on the
    new instrument, and (2) any later known positive, confirmed on the new instrument and recorded as re-baselined. The
    synthetic JPY + CNY fixture is a unit test, not a real-row control.
  * The owner can veto the merge at C-2(f) ("P1-12 waits for a known positive"). Silence merges it, labelled
    (`docs/PLAN-V1.37.md:98`, `:243`). If it is vetoed or not merged, Window 2's money rows are not read until it is.
  * Which of these held is written in at commit: `<matched walk / A′ departure / vetoed>`.

**The secondary instrument is `scripts/acquisition_funnel.py`**, for the store co-intervention by territory
(`docs/PLAN-V1.37.md:244`). Its two defects were fixed on `main` in `e884cf6`, and it was re-calibrated live:
**90 = 90** first-time downloads against `sales_report.py`'s census over Pacific 09-21..10-25
(`docs/measurements/v137-funnel-post-day0.md:302-319`).
* What was fixed: each date now comes from the one instance Apple processed last (`latest_per_date`,
  `scripts/acquisition_funnel.py:83`), so a date is no longer counted two or three times (184 first-time downloads
  against a census of 94 for the same dates, 184 = 4 + 2 × 90, `docs/measurements/v137-funnel-post-day0.md:72-80`); and
  `--until` has no default any more (`scripts/acquisition_funnel.py:131`), so a later `--since` no longer gives an
  empty window that exits 0.
* **Options:** `ASC_ANALYTICS_REQUEST=c57c770b-…` (the `ONGOING` request) with `--since <D₀′>` and
  `--until <newest day read>`, GETs only, never re-POSTed.
* **A window the script prints as `EMPTY WINDOW` (exit 4) or `PARTIAL` is not quoted** (`scripts/acquisition_funnel.py:156`,
  `:186`). Only a fully covered window is quoted, as a window total, never per day
  (`docs/measurements/v137-funnel-post-day0.md:129-134`), with its first-time downloads matched to the census for the
  same window at each reading.
* **Apple keeps the daily files for about five weeks**, on a rolling basis: on 2026-10-27 the earliest processing date
  served was 2026-09-22, and on 2026-10-28 the earliest download instance was processed 2026-09-23
  (`docs/measurements/v137-funnel-post-day0.md:14-15`, `:309-311`). So the daily instances are pulled and kept outside
  the repo at least every 28 days from D₀′, or Window 2's first weeks cannot be read by territory. *The agent's choice
  under the 2026-10-07 delegation.*

**`scripts/review_watch.py`** runs the same JST day as every reading, and its output is pasted verbatim
(`docs/measurements/stage1-checkpoints.md:26-29`).

### 1.10 How each reading is recorded

* In a file of its own, created with the committed variant before the first reading:
  `<docs/measurements/window2-readings.md>`.
* Under the seven rules of `docs/measurements/stage1-checkpoints.md:9-29`, adapted only by name: the tool's lines
  verbatim; no bound computed by hand; no branch consequence evaluated in the record; registration confirmed before
  running; what the reading shares data with; append only; `review_watch` the same day.
* **Watched:** every review since D₀′ that mentions a purchase, and any report from a grandfathered user of lost access
  (`docs/PLAN-V1.37.md:372`). Each is recorded when seen. The stop-and-fix each one triggers binds by its own text (top
  box). What it means for Window 2's next work is _(owner, C-2(e); A-1 item 5 on the E3-path)_.

---

## §2 Variant S: the silence path (treatment v1.38)

**When it applies.** The owner writes no E3 box at C-2, so E3 stays on its branch and v1.38 is the treatment
(`docs/PLAN-V1.37.md:98`, `:384`). Committed before v1.38's `--submit` (`docs/PLAN-V1.37.md:226`, `:384`).

* **Treatment:** v1.38's package at the road's price, "Offer v2 + Japanese UI": P1-1 … P1-6 and P1-10 … P1-15 as they
  ship (`docs/PLAN-V1.37.md:222`, `:231-246`). The shipped item list is written in at commit: `<items, filled at commit>`.
* **The treatment SKU:** `com.jasonye.nihongoride.scenery.lifetime` (`docs/PLAN-V1.37.md:131`), the only SKU on sale.
  The floor sum is that SKU's proceeds.
* **Price:** CNY `<filled at commit; today 10.00>` (ASC GET on the commit day). Today's ¥10.00 nets ¥8.42 (ASC GET
  2026-10-27, `docs/PRICING-BRIEF-V137.md:143-155`).
* **D₀′ under GO:** if Stage 1's reading was GO, v1.38's offer-changing items are released no earlier than Pacific
  2026-12-09 unless the owner's C-2 box cuts the repeat-rate run short (`docs/PLAN-V1.37.md:384`). D₀′ is then on or
  after 12-09.
* **c\* and N₂ (filled at commit by 1.5):** r_reg = `<…>`, c\*(r_reg) = `<…>`, ⌈3/c\*(r_reg)⌉ = `<…>`.
  * Illustration at today's inputs, not the commit's: net ¥8.42 and r = 122/47 = 2.596 a day give 50 / 8.42 = 5.94
    sales per 30 days, c\* = 5.94 / 77.9 = 7.63%, ⌈3/c\*⌉ = 40, so **N₂ = 200**.
  * At ¥10, N₂ stays 200 unless r_reg or r_obs rises above about 13.2 a day, because ⌈3/c\*⌉ passes 200 only when
    c\* < 1.5%.

**Read dates.** The rows fire on n and on report days, not on these dates. Projected at r = 2.596 a day, for two
illustrative D₀′ values (v1.38 is submitted about JST 11-30..12-04, `docs/PLAN-V1.37.md:384`; the second is the GO hold):

| row | offset | if D₀′ = Pacific 2026-12-03 | if D₀′ = Pacific 2026-12-09 |
|---|---|---|---|
| burn-in ends | D₀′+13 | 12-16 | 12-22 |
| record, n ≥ 100 | ≈ D₀′+38 | 2027-01-10 | 01-16 |
| day 60 | D₀′+60 | 02-01 | 02-07 |
| P2 ends | D₀′+73 | 02-14 | 02-20 |
| zero row, n ≥ N₂ = 200 | ≈ D₀′+77 | 02-18 | 02-24 |
| **close: the branch reading** | later of the two above | 02-18 | 02-24 |
| backstop and refunds | D₀′+180 | 2027-06-01 | 06-07 |

Each is read on JST D+2 (1.2). For example, the close of Pacific 2027-02-18 is read on JST 2027-02-20.

**Branches,** read once at the close, in this order (1.6). Conditions are measurement. Consequences are the owner's.

| branch | condition (measurement, agent-authored) | consequence for the next work |
|---|---|---|
| GO-2 | Net CNY-equivalent proceeds of the road SKU ≥ ¥50 in each of two consecutive full periods (1.6), both ending on or before the close. Never on a unit count (`docs/PLAN-STAGE1.md:528-530`). | _(owner, C-2(e))_ |
| BELOW-FLOOR | Not GO-2, and net purchases of the road SKU over D₀′..close ≥ 1. | _(owner, C-2(e))_ |
| ZERO | Not GO-2 or BELOW-FLOOR (net purchases ≤ 0), pipeline proven (1.7). 3/n printed only at exactly 0 under 1.7(a). | _(owner, C-2(e))_ |
| ZERO, pipeline unproven | Not GO-2 or BELOW-FLOOR, and neither 1.7(a) nor 1.7(b) holds. The reading says UNINTERPRETABLE and prints no bound. | _(owner, C-2(e))_ |
| owner box mid-window | The owner writes a dated price or E3 box while this window is open (including the late box, top). It is recorded with its date (`docs/PLAN-V1.37.md:371`). | _(owner, C-2(e))_ |

---

## §3 Variant E: the E3 path (treatment v1.39)

**When it applies.** The owner writes Appendix A-1: E3's price and the override (`docs/PLAN-V1.37.md:98`,
`:560-581`). Committed before v1.39's `--submit` (`docs/PLAN-V1.37.md:385`). If A-1 comes after v1.38's `--submit`,
this variant is appended to the committed S as its own dated section (the late box, top).

* **Treatment:** v1.39's E3, a free sampler plus one one-time depth unlock, with every existing install grandfathered
  (`docs/PLAN-V1.37.md:268`), with E5 if it rode v1.38 (`docs/PLAN-V1.37.md:352`; `:269`).
  * Boundary: `<candidate 1 / candidate 2 / the owner's words, from A-1 item 4; filled at commit>`
    (`docs/DESIGN-E3-SAMPLER.md`; `docs/PLAN-V1.37.md:213`).
* **The bridge.** v1.38's period, from its own release to D₀′, is reported descriptively once, at D₀′, in the same units
  and through the same FX table. It has no decision row (`docs/PLAN-V1.37.md:352`).
* **The treatment SKU:** `<E3's product id, filled at commit>`. The road SKU stays on sale and is reported on its own
  rows; the two are never pooled (P1-12(a)).
* **Prices:** E3 CNY `<the owner's figure, from A-1 item 3>`; the road CNY `<unchanged 10.00 / the owner's figure>`.
  Net per sale for each by ASC GET on the commit day. If the road is repriced at the same time, Window 2 confounds the
  two, and that is recorded here (`docs/PLAN-V1.37.md:339`).
* **c\* and N₂ (filled at commit by 1.5, at E3's net):** r_reg = `<…>`, c\*(r_reg) = `<…>`, ⌈3/c\*(r_reg)⌉ = `<…>`.
  No price is assumed here. PLAN-V1.37 §F tabulates the same formula at anchor prices, as arithmetic and not as a
  proposal (`docs/PLAN-V1.37.md:322-330`).
* **Denominator:** new installs only. Existing installs are grandfathered and cannot buy E3 (`docs/PLAN-V1.37.md:358`),
  with the limits in 1.3.
* **The floor sum for GO-2 is the owner's to choose:** `<E3's SKU alone / E3 + the road>` _(owner, C-2(e) or A-1 item 5)_.
  The floor is the owner's app-level input (`docs/PLAN-STAGE1.md:145-146`), and §H names no SKU for GO-2
  (`docs/PLAN-V1.37.md:363`). **Every reading prints both sums**, E3 alone and all SKUs, each by currency and in
  CNY-equivalent. Until the owner chooses, GO-2 is reported against both, descriptively.
* **The pipeline for E3's SKU.** 1.7(b) can be met by a road purchase, which proves that the reports carry this app's
  in-app rows. It does not prove that E3 itself can be bought: a new in-app purchase "has no availability record and is
  silently unbuyable until one is set" (`docs/PLAN-V1.37.md:152`; `docs/DESIGN-E3-SAMPLER.md:418`). So on this path:
  * E3's in-app purchase must be approved with an availability record, read by ASC GET on D₀′ and again at the close;
  * the territories in that record are **read, not prescribed**: they are written in at D₀′ (`<territories, from the
    GET>`), and n, purchases and the zero are counted over those territories only (the census carries `Country Code`,
    `scripts/sales_report.py:403`). A change between the two GETs is printed;
  * without an approved E3 with an availability record, a zero is UNINTERPRETABLE.
  *The agent's reading under the 2026-10-07 delegation.*

**Read dates.** Projected at r = 2.596 a day. PLAN-V1.37 puts D₀′ at about 12-18..22 if the box exists by about 12-07,
and v1.39's submission at 2027-01-05..15 otherwise (`docs/PLAN-V1.37.md:385`, `:391`). The zero row depends on N₂, so it
is shown at N₂ = 268, the value the formula gives at §F's ¥68-class anchor (arithmetic, not a price); with r_obs the
r_obs term is met at about day 103 too (1.5):

| row | offset | if D₀′ = Pacific 2026-12-18 | if D₀′ = Pacific 2026-12-22 |
|---|---|---|---|
| burn-in ends | D₀′+13 | 12-31 | 2027-01-04 |
| record, n ≥ 100 | ≈ D₀′+38 | 2027-01-25 | 01-29 |
| day 60 | D₀′+60 | 02-16 | 02-20 |
| P2 ends | D₀′+73 | 03-01 | 03-05 |
| zero row at N₂ = 268 | ≈ D₀′+103 | 03-31 | 04-04 |
| **close: the branch reading** | the zero row | 03-31 | 04-04 |
| backstop and refunds | D₀′+180 | 06-16 | 06-20 |

These agree with PLAN-V1.37's "late January", "early March" and "early April" (`docs/PLAN-V1.37.md:391`), except that
GO-2 is read at the close, not in early March (1.6). Each is read on JST D+2 (1.2).

**Branches,** read once at the close, in this order (1.6). Conditions are measurement. Consequences are the owner's.

| branch | condition (measurement, agent-authored) | consequence for the next work |
|---|---|---|
| GO-2 | The owner's floor sum (above) ≥ ¥50 CNY-equivalent in each of two consecutive full periods (1.6), both ending on or before the close. Never on a unit count. | _(owner, C-2(e) or A-1 item 5)_ |
| BELOW-FLOOR | Not GO-2, and net purchases of E3's SKU over D₀′..close ≥ 1, in E3's territories. | _(owner, C-2(e) or A-1 item 5)_ |
| ZERO | Not GO-2 or BELOW-FLOOR (net E3 purchases ≤ 0), pipeline proven (1.7, and E3's approval and availability above). 3/n printed only at exactly 0 under 1.7(a). | _(owner, C-2(e) or A-1 item 5)_ |
| ZERO, pipeline unproven | Not GO-2 or BELOW-FLOOR, and the pipeline is not proven as above. The reading says UNINTERPRETABLE and prints no bound. Under A′, if E3 also sells nothing, "nobody wants it" and "the till is broken" stay indistinguishable (`docs/PLAN-V1.37.md:461`). | _(owner, C-2(e) or A-1 item 5)_ |
| owner box mid-window | The owner writes a dated price or SKU box while this window is open. It is recorded with its date. | _(owner, C-2(e) or A-1 item 5)_ |

If the owner chooses "E3 + the road" for the floor sum, GO-2 can hold on road revenue alone. The order in 1.6 still
gives one branch.

---

## §4 What this file does not do

* It writes no consequence. A blank cell is not a default and is not "no consequence". It means the owner has not
  written one, so a reading against it decides nothing about Window 2's next work. It suspends no red line and no
  guardrail (top box).
* It proposes no price, and no illustrative figure in it is the commit's.
* It changes no Stage 1 rule, and no row here reads Stage 1's cohort. Stage 1 closes with the N = 200 record.
* It changes no script. `acquisition_funnel.py` was fixed in its own change (`e884cf6`, 1.9); P1-12 is its own change.

---

## §5 Every number above, re-derived

Read 2026-10-28 (JST). The cache figures come from an offline pass over
`~/Library/Application Support/NihongoRide-Stats/sales/` through `sales_report.py`'s own `our_rows`, `tally` and
`classify_row`, at this commit's `scripts/sales_report.py`, with no network. **The pass read the cache through Pacific
2026-10-26**, the newest cached day. Pacific 10-26 holds 0 first-time downloads, so N through 10-26 is still 122, over
48 days. The figures below are quoted through 10-25, the N = 100 reading's newest day, unless they say otherwise.
Aggregate counts only.

| number | value | source |
|---|---|---|
| cohort since day 0, through Pacific 2026-10-25 | N = 122 (macOS 82 · iOS 40), 47 report days, 0 purchases | the offline pass; equals `docs/measurements/stage1-checkpoints.md:228-235` |
| through Pacific 10-26 | N = 122, 48 report days (10-26: 0 first-time downloads, 2 update units) | the offline pass |
| install rate | 122 / 47 = 2.596 a day; × 30 = 77.9 per 30 report days | the first line |
| lifetime first-time downloads through Pacific 10-25 | 259 (macOS 159 · iOS 100); update units 723 | the offline pass; matches `docs/PLAN-V1.37.md:140` |
| the v1.35 update proxy | 82 = every `F7` unit reported for version 1.35 through Pacific 10-25; 191 = first-time downloads before each platform's 1.35 release day (macOS through 09-28: 112; iOS through 09-29: 79); 82 / 191 = 42.9% | the offline pass; release days `scripts/sales_report.py:270-271`. The "191" was not written down in PLAN-V1.37; this is the split that reproduces it. |
| burn-in exposure | 259 + 2.596 × 39 = 360; 259 + 2.596 × 56 = 404; × 0.43 ≈ 155–174 devices | PLAN-V1.37's ~39–56 days after 10-25 (`docs/PLAN-V1.37.md:360`), i.e. D₀′ near 12-03 and 12-20 |
| net per ¥10 sale | ¥8.42 | ASC GET 2026-10-27 13:49 UTC, `docs/PRICING-BRIEF-V137.md:143-155` |
| JPY / USD equalised nets | JPY 128, USD 0.84 | ASC GET 2026-10-27, `docs/PLAN-V1.37.md:132` |
| ¥10's c\*, ⌈3/c\*⌉, N₂ | 50 / 8.42 = 5.938 sales; / 77.87 = 7.63%; 3 / 0.0763 = 39.3 → 40; N₂ = 200 | arithmetic; agrees with `docs/PLAN-V1.37.md:326` and `docs/PRICING-BRIEF-V137.md:105` |
| ¥10's N₂ stays 200 while | r < 13.2 a day (5.938 / (30 × 0.015)) | arithmetic |
| ⌈3/c\*(r)⌉ in days | 3 / c\* = 3 × 30 r × net / 50 = 1.8 × net × r, so the term is met after 1.8 × net report days: 15.2 at 8.42, 103.1 at 57.26 | arithmetic |
| ¥68-class anchor, for the date table only | net 57.26 (§F's scaled figure; 57.28 by ASC GET): c\* = 1.12%, ⌈3/c\*⌉ = 268 | `docs/PLAN-V1.37.md:329`; `docs/PRICING-BRIEF-V137.md:124-125` |
| days to n = 100, 200, 268 at 2.596 a day | 100 → 38.5 (offset 38); 200 → 77.0 (offset 77); 268 → 103.2 (offset 103) | arithmetic; the offset is the first report day whose cumulative count reaches the target, with D₀′ as offset 0 |
| P2's end | D₀′+73 = day 73 (14 burn-in days + 2 × 30 − 1) | 1.6; the same day as §H's "about day 74", `docs/PLAN-V1.37.md:363` |
| day 60 | D₀′+60, by Stage 1's numbering (2026-09-09 + 90 = 2026-12-08) | `docs/PLAN-STAGE1.md:425-427` |
| projected dates | the two date tables | D₀′ + offset, by calendar arithmetic |
| PST / PDT | PST from 02:00 Sunday 2026-11-01 to 02:00 Sunday 2027-03-14; 07:00 PT on 2026-11-01 = 00:00 JST 11-02, on 2027-03-14 = 23:00 JST 03-14 | `zoneinfo` America/Los_Angeles and Asia/Tokyo, computed 2026-10-28 |
| illustrative FX | CNY 7.4343, JPY 175.97, USD 1.1150 per EUR (ECB, 2026-10-27, 29 currencies, no VND/TWD/AED/SAR); CNY 0.042248 per JPY, 6.6675 per USD | https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml, read 2026-10-28T01:06Z |
| JPY 128 and USD 0.84 in CNY, illustrative | ¥5.41 and ¥5.60 | the two lines above |
| the funnel's double count | 184 against a census of 94 for the same dates; 184 = 4 + 2 × 90 | `docs/measurements/v137-funnel-post-day0.md:72-80` |
| the funnel's calibration after the fix | 90 = 90, Pacific 09-21..10-25, live GET 2026-10-28 | `docs/measurements/v137-funnel-post-day0.md:312-316` |
| Analytics daily retention | earliest processing date 2026-09-22 when read 10-27; earliest download instance processed 2026-09-23 when read 10-28 | `docs/measurements/v137-funnel-post-day0.md:14-15`, `:309-311` |
