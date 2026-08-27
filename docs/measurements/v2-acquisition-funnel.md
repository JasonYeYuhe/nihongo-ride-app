# The acquisition funnel — what the App Store shows, and what it converts

Measured 2026-08-27, over 2026-06-06 … 08-24 (the same window as the Stage 0 census).
Regenerate: `python3 scripts/acquisition_funnel.py --json docs/measurements/v2-acquisition-funnel.json`.

`sales_report.py` answers *how many installs*. This answers *out of how many people who saw it*,
which is the distinction PLAN-V2-PRODUCT §G is built on: **"nobody sees this app" and "people see
it and do not install it" have opposite fixes.**

## ⚠️ First, a warning this project carried turned out to be false here

`~/Documents/credits.md` records that the Analytics API counts only users who opted into sharing
and **"can show 0 while the real number is not 0"**. `v2-stage0-baseline.md` repeated it, and it
is the stated reason the census was taken from Sales and Trends instead.

**For the download report in the `analyticsReportRequests` API, that is measured false.**

| | Analytics | Sales and Trends census |
|---|---|---|
| first-time downloads | **109** | **109** |
| macOS / iOS | **60 / 49** | **60 / 49** |
| territories in disagreement | **0 of 20** | — |

The raw totals differ (111 vs 109) for one reason only: Analytics had one extra day of coverage
(2026-08-25). Aligned to the same window they agree exactly, territory by territory.

So the download half of Analytics is **census-grade and needs no scaling**. Two things do NOT
follow, and neither is asserted here:

* **The impression and page-view numbers are NOT calibrated.** There is no second instrument for
  them. They are Apple's own count, and are used as such.
* **The warning is not withdrawn generally.** It may still hold for the older App Analytics
  dashboard, and it plausibly explains the *engagement* reports below, which is where an
  opted-in sample is actually required.

## ⚠️ Second: 8 reports of 156 arrived, and the split is the finding

Requested 2026-08-26, checked ~28 hours later:

| arrived | did not |
|---|---|
| App Downloads (Standard + Detailed) | App Sessions |
| App Store Discovery and Engagement (Standard + Detailed) | App Store Installation and Deletion |
| App Store Web Preview Engagement | App Crashes |
| App Install Performance · Platform App Installs | **App Opt In** · retention |

**Every report that arrived is acquisition-side; every one that did not needs a sample of users
who opted into sharing.** If this were latency they would have arrived together. It is not proof
— only waiting longer can prove it — but plan for **§G's engagement guardrails being permanently
unavailable at this traffic level**, and rebuild that section on the census plus local counters.

## The funnel

| | |
|---|---|
| impressions | **14,292** |
| product page views | 627 |
| taps | 281 |
| **first-time downloads** | **109** |
| **impression → download** | **0.76%** |
| from **App Store search** | **101 of 109 — 93%** (App referrer 6, browse 2) |

**Page views are not a funnel stage.** 45 of 109 downloads (41%) carry Page Type `No page` —
installed straight from search results without ever opening the product page. Page-view-to-download
therefore exceeds 100% in some territories (Australia: 4 downloads, 3 page views) and **must never
be quoted as a conversion rate**. The honest denominator is impressions.

## Where the impressions go, and where they convert

| territory | impressions | share of impressions | downloads | impression → download | listing |
|---|---|---|---|---|---|
| **CN** | 10,700 | **75%** | 52 | **0.49%** | zh-Hans |
| **JP** | 1,196 | 8% | 15 | **1.25%** | **en only** |
| US | 707 | 5% | 9 | 1.27% | en-US |
| VN | 243 | 2% | 5 | 2.06% | en only |
| IN | 132 | 1% | 3 | 2.27% | en only |
| AU | 73 | <1% | 4 | 5.48% | en only |
| HK | 51 | <1% | 3 | 5.88% | en only |

No industry benchmark is quoted here, because an unsourced "typical conversion is N%" is exactly
the kind of number this project refuses. The comparison that IS available is internal, and it is
sharp enough: **conversion across territories spans 0.49% to 5.88%, and the worst of them is the
one holding three quarters of the impressions.**

## What this changes

1. **"A paywall built in an empty room" needs one qualifier.** The room is not empty of
   *footfall* — the app was surfaced 14,292 times. It is empty of *conversion*: 0.76% of those
   who saw it installed it, and of those who installed it, one has ever left a review. Stage 0
   stays first; its emphasis moves from "be visible" toward "convert the visibility that already
   exists".
2. **The `ja` listing case is stronger than the one the plan made, and it is a different case.**
   The plan proposed `ja` because Japan is the #2 territory. The funnel says Japan **already
   converts at 2.5× China's rate with an English-only listing** — so a Japanese listing is not
   fixing a conversion problem there. It is an **impressions** play: Japanese keywords buy
   Japanese search surface, and JP's conversion rate is the evidence that the impressions it buys
   would convert well. That is a better argument, and it predicts a different number to watch
   (JP impressions, not JP conversion).
3. **China is the anomaly worth a release of its own.** 75% of impressions, 48% of downloads, the
   lowest conversion of any significant territory — despite being the only non-English localised
   listing. Two explanations fit and the data here cannot separate them: the zh keywords match
   broad, low-intent queries, or the zh product page (subtitle, screenshots) does not convince.
   **They have different fixes**, and distinguishing them is the next measurement, not the next
   guess.
4. **93% of installs come from search.** Whatever is done, it is done to search: keywords, title,
   subtitle, and the first two screenshots — which are what 41% of installers see instead of the
   product page.
