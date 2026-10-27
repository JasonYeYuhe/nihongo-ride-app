# The acquisition funnel after day 0 (PLAN-V1.37 P0-7)

Read 2026-10-27 (JST). Read-only. **It gates nothing** (`docs/PLAN-V1.37.md:208`).
Aggregate counts only.

**Instrument:** `scripts/acquisition_funnel.py` with the existing `ONGOING` request
`ASC_ANALYTICS_REQUEST=c57c770b-faac-4b80-9bb7-354ed6c66f92`. GETs only. No analytics request was
created or re-POSTed. The script contains no POST (`grep -n POST` finds only the comment at
`scripts/acquisition_funnel.py:52`).

**Short version.**
* The command in the brief returns an empty window, and the script, given an end date, double-counts.
  Neither result can be used. §1 shows both runs verbatim.
* Apple keeps this request's daily files only from processing date 2026-09-22. So "since day 0" cannot
  be read. The earliest complete window is **Pacific-labelled 2026-09-20 .. 10-25 (36 of the 47 days)**.
* Read once per date (§2), that window has **7,345 impressions, 288 page views and 94 first-time
  downloads**. The 94 matches the Sales and Trends census exactly: 94, macOS 64 and iOS 30, and the
  same counts in every territory the census prints.

---

## 1. What the script printed, verbatim

### 1.1 The command as briefed: an empty window

`ASC_ANALYTICS_REQUEST=c57c770b-… python3 scripts/acquisition_funnel.py --since 2026-09-09`, run
2026-10-27T13:51:20Z:

```
window 2026-09-09 .. 2026-08-24
  impressions 0 · page views 0 · taps 0 · first-time downloads 0
  impression -> download  0.00%   <- the honest rate
  0 of 0 downloads (0%) never opened the product page, so page-view-to-download is not a conversion rate
  source: 

  terr     impr     pv   dl  impr->dl
exit=0
```

**These zeros are not a measurement.** `--until` defaults to `2026-08-24`
(`scripts/acquisition_funnel.py:102`), so the window ends before it starts. Every row is filtered out
(`:115`), and the script exits 0 with clean-looking zeros.

### 1.2 With an explicit end date: every download counted twice

`… --since 2026-09-09 --until 2026-10-25`, run 2026-10-27T13:59:42Z:

```
window 2026-09-09 .. 2026-10-25
  impressions 21466 · page views 826 · taps 686 · first-time downloads 184
  impression -> download  0.86%   <- the honest rate
  103 of 184 downloads (56%) never opened the product page, so page-view-to-download is not a conversion rate
  source: App Store search=167 (91%) · App Store browse=12 (7%) · App referrer=3 (2%) · Web referrer=2 (1%)

  terr     impr     pv   dl  impr->dl
  JP       8861    399  105     1.18%
  CN       7769    181   34     0.44%
  US       2221     92   14     0.63%
  VN        507     34    9     1.78%
  IN        175      3    0     0.00%
  ID        165     18    2     1.21%
  AE        155      0    2     1.29%
  CO        125      3    2     1.60%
  AU        124     15    2     1.61%
  TW        107      9    0     0.00%
  TR        102      6    0     0.00%
  PH         96      9    2     2.08%
exit=0
```

**These figures are inflated and must not be quoted.**
* 184 first-time downloads, against a census of 122 for the whole window and 94 for the part these
  files cover (§3).
* **The cause.** `report_rows` concatenates the rows of every `DAILY` instance
  (`scripts/acquisition_funnel.py:83-95`). For this `ONGOING` request, each daily instance covers
  more than one date:
  * a download instance carries the last **2** dates;
  * an engagement instance carries the last **3**.
* So each date is summed 2 or 3 times. Check: 184 = 4 + 2 × 90. 2026-09-20's 4 downloads appear in
  one instance, and the other 90 appear in two.
* Restated download rows were identical on all 35 dates that appear in two instances. So this is double counting, not
  revision.
* The script's own docstring calibration (109 = 109, `scripts/acquisition_funnel.py:16-19`) was measured
  on the `ONE_TIME_SNAPSHOT` request (`:52-54`). That calibration does not carry over to `ONGOING`.
* **The script prints no calibration line.** The calibration in §3 was done for this file against
  `sales_report.py`.

The script was not changed. Its two defects are reported for the owner (see "PLAN-V1.37 findings" at
the end).

---

## 2. How the figures below were read

* **Same GETs, same code.** A helper calls the script's own `token()` and `get()` and lists the request,
  its reports, their instances and their segments. It is GET-only and outside the repo, at
  `~/Library/Caches/NihongoRide-v137-work/evidence-p0-4-p0-7/funnel_inspect.py`, with its raw pull
  (`funnel_raw.json.gz`) and aggregation (`funnel_agg.py`).
* **The request**, GET `/v1/analyticsReportRequests/c57c770b-…` on 2026-10-27: `accessType ONGOING`,
  `stoppedDueToInactivity false`. It has 156 reports.
* **The reports:**
  * App Store Discovery and Engagement Standard, report `r14-c57c770b-faac-4b80-9bb7-354ed6c66f92`:
    35 `DAILY` instances (processing dates 2026-09-22 .. 10-26), 5 `WEEKLY` and 1 `MONTHLY`.
  * App Downloads Standard, report `r3-c57c770b-faac-4b80-9bb7-354ed6c66f92`: 36 `DAILY` instances
    (processing dates 2026-09-22 .. 10-27).
  * No instance list was paged: `meta.paging.total` equals what was returned.
* **One instance per date.** For each `Date`, only the rows of the instance with the **latest processing
  date** that carries that date are used. Appendix A lists the instance used for each date.
* **The window** is 2026-09-20 .. 2026-10-25, 36 dates. Both reports cover every date in it, and
  2026-10-25 is the newest Pacific day of the N = 100 record (`stage1-checkpoints.md:228`).
* **Platform** is the report's `Device` column. `Desktop` is the Mac, and iPhone plus iPad is iOS. §3
  shows this mapping reproduces the census split exactly.

---

## 3. Calibration against the Sales and Trends census

`python3 scripts/sales_report.py --since 2026-09-20 --until 2026-10-25`, run 2026-10-27, with report
states `data=36`:

| | Analytics, one instance per date | census |
|---|---|---|
| first-time downloads | **94** | **94** |
| macOS / iOS | **64 / 30** (Desktop 64; iPhone 18 + iPad 12) | **64 / 30** |
| JP · CN · US · VN | 53 · 18 · 7 · 5 | 53 · 18 · 7 · 5 |
| TH · HK · MM · CO · LA · AE · AU · ID | 2 · 2 · 1 · 1 · 1 · 1 · 1 · 1 | 2 · 2 · 1 · 1 · 1 · 1 · 1 · 1 |
| 13th territory | PH 1 | not printed: the census prints its top 12 (`scripts/sales_report.py:1757-1758`); 94 − 93 = 1 |

**The window totals agree exactly. The days do not.**
* Only 14 of 36 dates have the same count in both (`sales_report.py --daily`). The absolute daily
  differences sum to 26, and they cancel over the window.
* So the Analytics `Date` is not the Pacific report day, at least at the edges.
* Quote these figures **only as window totals**, never per day, and never splice them onto a census
  window that starts or ends on a different day.

**Impressions and page views have no second instrument.** They are Apple's own count and are not
calibrated, as `docs/measurements/v2-acquisition-funnel.md` already says. They are the `Counts` column,
as the script uses (`scripts/acquisition_funnel.py:122`), not `Unique Counts`.

**Not final.** Engagement impressions were revised between restatements on 25 of the 35 dates restated, by +1 to +4
impressions a day (largest on 2026-10-08: 188 → 192). The last two dates (10-24, 10-25) have been
restated fewer times than the rest. Download rows did not change between restatements.

---

## 4. The funnel, 2026-09-20 .. 2026-10-25 (36 dates)

### 4.1 Totals

| | count |
|---|---|
| impressions | **7,345** (App Store search 6,963 · browse 382) |
| page views | **288** |
| taps | 236 |
| first-time downloads | **94** |
| impression → first-time download | **1.28%** |
| downloads with Page Type "No page" (installed from the results list) | 52 of 94 (55%) |
| downloads by source | App Store search 85 (90%) · browse 6 · app referrer 2 · web referrer 1 |

Page views are not a stage of this funnel. Over half the downloads never opened the product page, so
page-view-to-download is not a rate (`scripts/acquisition_funnel.py:33-38`).

### 4.2 By territory

| territory | impressions | page views | first-time downloads | impr → dl |
|---|---|---|---|---|
| JP | 3,049 | 139 | 53 | 1.74% |
| CN | 2,651 | 65 | 18 | 0.68% |
| US | 750 | 31 | 7 | 0.93% |
| VN | 178 | 12 | 5 | 2.81% |
| 56 other territories | 717 | 41 | 11 (in 9 of them) | 1.53% |
| **total** | **7,345** | **288** | **94** | **1.28%** |

Japan is 56% of first-time downloads in this window and China 19%. The census over the full
day-0 window says 53% and 24% (`docs/PLAN-V1.37.md:140`).

### 4.3 By platform

| platform | impressions | page views | first-time downloads | impr → dl |
|---|---|---|---|---|
| macOS (Desktop) | 4,453 | 148 | 64 | 1.44% |
| iPhone | 1,481 | 102 | 18 | 1.22% |
| iPad | 1,411 | 38 | 12 | 0.85% |

### 4.4 Territory by platform

| territory | macOS impr · pv · dl | iPhone impr · pv · dl | iPad impr · pv · dl |
|---|---|---|---|
| JP | 1,918 · 101 · **48** | 484 · 23 · 2 | 647 · 15 · 3 |
| CN | 1,480 · 17 · 2 | 478 · 31 · **9** | 693 · 17 · **7** |
| US | 592 · 5 · 4 | 141 · 25 · 2 | 17 · 1 · 1 |
| VN | 139 · 11 · 4 | 31 · 1 · 1 | 8 · 0 · 0 |
| other | 324 · 14 · 6 | 347 · 22 · 4 | 46 · 5 · 1 |

Read as counts. Most cells are single digits, so the rates within them mean little.
* Japan's downloads are 48 of 53 on the Mac.
* China's are 16 of 18 on iPhone or iPad. China shows 1,480 Mac impressions and 2 Mac downloads.

### 4.5 Before 2026-09-20: what is left

* **No daily data.** Apple no longer serves daily instances for 2026-09-09 .. 09-19 under this request.
  Those 11 Pacific days hold 28 of the census's 122 first-time downloads (122 − 94).
* **Downloads:** the download report has no weekly or monthly instances.
* **Engagement:** two coarser instances overlap the gap. They are not split by territory here, and they
  are not calibrated.

| granularity | instance (processing date · id prefix) | period starting | impressions · page views · taps |
|---|---|---|---|
| MONTHLY | 2026-10-05 · `1f5e6e55` | 2026-09-01 | 7,207 · 226 · 196 |
| WEEKLY | 2026-09-25 · `94063055` | 2026-09-14 | 1,384 · 50 · 38 |
| WEEKLY | 2026-10-02 · `7f893b8d` | 2026-09-21 | 1,511 · 55 · 61 |
| WEEKLY | 2026-10-09 · `f2ebeb96` | 2026-09-28 | 1,843 · 45 · 35 |
| WEEKLY | 2026-10-16 · `6fa0f806` | 2026-10-05 | 1,407 · 61 · 48 |
| WEEKLY | 2026-10-23 · `84cc4013` | 2026-10-12 | 1,289 · 61 · 38 |

As a check, the daily impressions for 2026-09-21 .. 09-27 sum to 1,510, against the weekly instance's
1,511.

---

## 5. What this cannot tell

* **Natives from learners.** The reports carry territory, device, source and page type. Nothing says
  who the user is or what language they read. A JP-storefront install may be a Japanese native, a
  learner living in Japan, or anyone with a JP Apple ID. This is the open question in
  `docs/PLAN-V1.37.md:208`. These data do not close it, and E5 does not wait for them.
* **Anything about purchase or use.** Impressions and downloads only. No sessions, retention or
  deletion figures were read here.
* **Day 0 .. 09-19**, at daily or territory resolution (§4.5).
* **Cause.** It describes the traffic term and the ja listing's co-intervention
  (`docs/PLAN-STAGE1.md:571-580`). It cannot separate the listing's effect from anything else that
  changed in the window.

---

## PLAN-V1.37 findings (for the owner; nothing here was worked around silently)

1. **P0-7's verify column says "The script's own calibration"** (`docs/PLAN-V1.37.md:208`). The script
   prints none. Its calibration is a docstring record from the `ONE_TIME_SNAPSHOT` request. This file
   did the calibration in §3 instead.
2. **With the `ONGOING` request, `acquisition_funnel.py` double- or triple-counts** (§1.2). Any figure
   produced from it with `c57c770b-…` before today is inflated by about 2× (downloads) and 3×
   (impressions). No such figure was found in the repo (`git grep c57c770b` finds only plan and
   baseline references).
3. **The default `--until 2026-08-24`** turns any later `--since` into an empty window that exits 0
   (§1.1).
4. **"Since day 0" is not obtainable** from this request any more (§4.5). P0-7's wording assumes it is.

---

## Appendix A: the instance used for each date

Processing date · instance id prefix (the first 8 characters). The full ids come back from
GET `/v1/analyticsReports/<report>/instances`.

| Date | Discovery and Engagement (`r14-…`) | Downloads (`r3-…`) |
|---|---|---|
| 2026-09-20 | 2026-09-23 · `cbfc1db2` | 2026-09-22 · `9200fa32` |
| 2026-09-21 | 2026-09-24 · `79606fad` | 2026-09-23 · `71ac8bc1` |
| 2026-09-22 | 2026-09-25 · `a824e659` | 2026-09-24 · `19dca93c` |
| 2026-09-23 | 2026-09-26 · `ee0e5d6e` | 2026-09-25 · `71dd5027` |
| 2026-09-24 | 2026-09-27 · `50b7b8f9` | 2026-09-26 · `79b94909` |
| 2026-09-25 | 2026-09-28 · `6beca141` | 2026-09-27 · `86769e7e` |
| 2026-09-26 | 2026-09-29 · `d0ecadf4` | 2026-09-28 · `333ed4df` |
| 2026-09-27 | 2026-09-30 · `af598638` | 2026-09-29 · `ea8d57a2` |
| 2026-09-28 | 2026-10-01 · `d17e68d3` | 2026-09-30 · `f64436aa` |
| 2026-09-29 | 2026-10-02 · `5a2db321` | 2026-10-01 · `515eeca4` |
| 2026-09-30 | 2026-10-03 · `96e936af` | 2026-10-02 · `86961af9` |
| 2026-10-01 | 2026-10-04 · `b2a53fb9` | 2026-10-03 · `4f5347e7` |
| 2026-10-02 | 2026-10-05 · `748975ad` | 2026-10-04 · `39e91e46` |
| 2026-10-03 | 2026-10-06 · `3bce6c0e` | 2026-10-05 · `52d39a5f` |
| 2026-10-04 | 2026-10-07 · `abc79708` | 2026-10-06 · `cb9cb9f2` |
| 2026-10-05 | 2026-10-08 · `127747d2` | 2026-10-07 · `55a685e3` |
| 2026-10-06 | 2026-10-09 · `d47af6f0` | 2026-10-08 · `e944ad16` |
| 2026-10-07 | 2026-10-10 · `842a835f` | 2026-10-09 · `7ffdb2ec` |
| 2026-10-08 | 2026-10-11 · `bf5504ba` | 2026-10-10 · `4df24f46` |
| 2026-10-09 | 2026-10-12 · `ce22bb14` | 2026-10-11 · `57e9618b` |
| 2026-10-10 | 2026-10-13 · `5c87bc32` | 2026-10-12 · `b260bc3c` |
| 2026-10-11 | 2026-10-14 · `70ef533f` | 2026-10-13 · `60b9b094` |
| 2026-10-12 | 2026-10-15 · `4912a010` | 2026-10-14 · `b6af4814` |
| 2026-10-13 | 2026-10-16 · `4dc2f973` | 2026-10-15 · `eeba8462` |
| 2026-10-14 | 2026-10-17 · `7d3d0b33` | 2026-10-16 · `acd913c2` |
| 2026-10-15 | 2026-10-18 · `029796f7` | 2026-10-17 · `5599bb7e` |
| 2026-10-16 | 2026-10-19 · `368f3dfb` | 2026-10-18 · `72b9949c` |
| 2026-10-17 | 2026-10-20 · `3a6f1b38` | 2026-10-19 · `1915f463` |
| 2026-10-18 | 2026-10-21 · `39fa040f` | 2026-10-20 · `2629fc7b` |
| 2026-10-19 | 2026-10-22 · `021e4756` | 2026-10-21 · `032fbd2e` |
| 2026-10-20 | 2026-10-23 · `9459b7da` | 2026-10-22 · `6a718a28` |
| 2026-10-21 | 2026-10-24 · `400669f1` | 2026-10-23 · `6dfb7953` |
| 2026-10-22 | 2026-10-25 · `3c69f05e` | 2026-10-24 · `06d8bab8` |
| 2026-10-23 | 2026-10-26 · `b4e3a3dc` | 2026-10-25 · `cd1856d6` |
| 2026-10-24 | 2026-10-26 · `b4e3a3dc` | 2026-10-26 · `e25a284b` |
| 2026-10-25 | 2026-10-26 · `b4e3a3dc` | 2026-10-27 · `e4fd911c` |

Kept outside the repo, in `~/Library/Caches/NihongoRide-v137-work/evidence-p0-4-p0-7/`: both script runs
(`funnel-as-briefed.txt` md5 `a59a560795348b0e9c6665c4c46ea821`; `funnel-until.txt` md5
`a3162837ea51cf08d528a5e784bac2ad`), the deduplicated aggregate (`funnel-dedup-2026-09-20..10-25.txt`
md5 `c1546f6098c8eed924038b7b51d49b4f`), and the census runs.
