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
| window | 2026-06-06 (1.0 READY_FOR_SALE) → 2026-08-24 · 80 days, **80 of 80 reports materialised** |

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
| `F7` | **update, on ALL devices** including iPhone and iPad | 293 units; **2.08x on release days vs 1.19x for downloads** |
| `3F` / `F3` | redownload | 4 units in the app's whole life |

`F7` appearing on iPhone contradicts the intuition that `F`-prefixed codes are Mac-only, which
is why the classification is proven **behaviourally** — updates must be release-locked and
downloads must not be — rather than read off Apple's code table.

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
| 28-day windows, oldest → newest | **11 → 31 → 67** |
| trailing-28d run rate | **72 / 30 days** |
| lifetime average run rate | 41 / 30 days |
| **China share of all downloads** | **52 / 109 = 48%** (35 of the last 67) |
| next territories | JP 15 · US 9 · VN 5 · AU 4 · IN 3 · HK 3 · TW 2 |
| written reviews, all time | **1** (`meta.paging.total`, confirmed) |
| storefront locales configured | **2** — `en-US`, `zh-Hans`, on both platforms |
| Analytics report requests ever made | **0**, until 2026-08-26 |

## What this corrects in PLAN-V2-PRODUCT.md

1. **§A "one review is a measurement of near-zero traffic" was an inference, and the traffic
   was measurable all along.** The direction survives — 109 lifetime installs is a tiny base —
   but the plan's working figure of "40 monthly downloads" describes the *lifetime average*,
   not the present. **Traffic more than doubled over the last two 28-day windows (31 → 67)**,
   and the plan contains no awareness of a trend because nobody pulled the series.
2. **Shipping frequently is already acting as distribution.** The growth coincides with seven
   releases in fourteen days. This is correlation over one app with no control, so it is a
   hypothesis, not a finding — but it is a Stage 0 lever the plan does not list, and it is free.
3. **§C "the keyword list is English-only" is false.** `zh-Hans` keywords ship on both
   platforms and have since before this plan. What is true is the *other* half: only two
   locales exist, so Japan (**#2 territory, 15 downloads, no `ja` listing**), Taiwan and Korea
   are genuinely untouched.
4. **§C's entitlement question "do macOS and iOS share one app record" is answered: yes.** One
   record, one SKU (`nihongoride-mac-2026`), and Apple stamps **every unit** `iOS and macOS`.
5. **§A's China signal is much stronger than one review.** The plan justified writing CNY and
   localising the paywall from a single review (n=1). The census says **48% of all installs are
   China** (n=109). That recommendation survives re-measurement and gets stronger.
6. **§I's "the description becomes untrue" risk is confirmed verbatim.** The live listing reads
   `Fully offline. No account, no network, no tracking, no ads.` / `完全离线。无账号、不联网、无追踪、无广告。`

## The arithmetic §G needs, with real numbers

§G fixes the falsification threshold at 100 genuine exposures (zero purchases below that rules
out nothing useful). Against the measured base:

* **The active installed base is at most 109 devices** — lifetime downloads, before any
  deletion. This is a census ceiling, not an estimate.
* So **100 genuine tip-jar exposures is ~92% of every device that has ever installed the app.**
  Reaching it at all depends on the update population, and it is a **one-shot**: it is exactly
  the "launch spike with no clean exposure denominator" §G warns against conflating with
  steady-state.
* A *clean* steady-state cohort of 100 new installs takes **~42 days at the trailing rate**,
  and ~73 days at the lifetime rate.

**The active-device count is still not measured.** Sales and Trends cannot produce it; the
Analytics reports can, and they were requested on 2026-08-26 (`ONE_TIME_SNAPSHOT`
`4c53fdae-17db-4666-a557-cceeb6795e85`, `ONGOING` `c57c770b-faac-4b80-9bb7-354ed6c66f92`).
When they materialise, **calibrate them against this census before believing them** — their
download figure divided by 109 is the sampling rate, and it is the only thing that says how
much weight the retention and session numbers can carry.
