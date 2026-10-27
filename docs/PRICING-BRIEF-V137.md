# Pricing brief for C-2(b) (PLAN-V1.37 P0-4)

Filed 2026-10-27 (JST). Read-only. Written by an agent for the owner's C-2 decision.

**No price is proposed, ranked or recommended here.** "An agent invents no prices"
(`docs/PLAN-V1.34.md:729`; the owner-only price item at `:1081`). Nothing below is a decision, and no
decision cell is filled. Every price in this file is a list price on a public page. None of it is
revenue, and none of it says what converts.

What this file holds:
1. §F's comparables, each re-read today, with CNY / JPY / USD where a storefront shows them.
2. The floor arithmetic per 30 Pacific report days, re-derived from the repo's own numbers, and a check
   of every row of `docs/PLAN-V1.37.md` §F's table.
3. The Apple CNY price points at and next to each comparable, with proceeds, from an ASC GET today.
4. What was not re-read, and where this file was unsure.

---

## 1. Comparables, re-read 2026-10-27

**How each was read.**
* Every apps.apple.com page was read with WebFetch, then fetched raw with `curl` and parsed. The
  storefront embeds its "App内购买 / アプリ内購入 / In-App Purchases" list as `textPair` items, so the
  prices below are the page's own strings, not a model's summary. Fetch times 2026-10-27
  13:49–13:51 UTC.
* Each app was also fetched in the CN, JP and US storefronts (`https://apps.apple.com/<cc>/app/id<id>`).
  A 404 means the app is not sold in that storefront.
* AnkiMobile is a paid app, so its price is the app price from
  `https://itunes.apple.com/lookup?id=373493387&country=<cc>`, as §F did.
* The extracted rows are kept outside the repo at
  `~/Library/Caches/NihongoRide-v137-work/evidence-p0-4-p0-7/storefront-iap-rows-2026-10-27.txt`.

**Result: every price in §F's table (`docs/PLAN-V1.37.md:308-318`) was re-read today and is unchanged.**
Three descriptions are sharpened in §1.2; no price differs.

### 1.1 The table, with three currencies

The §F storefront's prices come first. The other two currencies are the same app in the JP or US
storefront, added because the brief asks for them. A storefront page lists at most about ten IAP rows,
so a long price list may be cut short (MOJi辞書 and renshuu show exactly ten).

| app | §F storefront | what is paid for | CNY (CN storefront) | JPY (JP storefront) | USD (US storefront) | vs §F |
|---|---|---|---|---|---|---|
| Rail Typing – 打字学日语 | CN | all lines ("全线定期券") | ¥12 month · ¥68 year · **¥128 lifetime** | ¥300 month · ¥1,500 year · ¥3,000 lifetime | $1.99 month · $9.99 year · $19.99 lifetime | same |
| 日语打字通 | CN | VIP | ¥6.80 3-month · ¥9.80 6-month · ¥16.80 1-year · **¥66.80 permanent** | not sold (404) | not sold (404) | same |
| TypeAll-打字菌 | CN | membership | ¥12 month · ¥38 year · **¥68 lifetime** | ¥300 month · ¥800 year · ¥1,500 lifetime | $1.99 month · $4.99 year · $9.99 lifetime | same |
| MARU日语五十音特训 | CN | paid upgrade (ads, modes) | **¥148 permanent** | ¥3,000 | $19.99 | same |
| MOJi辞書 | CN | membership | ¥12 month · ¥48 half-year · ¥58 year · ¥228 permanent; also ¥15 "1个月", coins ¥8–28, a widget skin ¥8 | ¥300 month · ¥1,300 year · ¥4,800 lifetime | $1.99 month · $7.99 year · $39.99 lifetime | same |
| Kana – type japanese | US | full | ¥8 week · ¥68 year · ¥148 / ¥168 lifetime | ¥150 week · ¥1,500 year · ¥3,000 / ¥4,000 lifetime | **$0.99 week · $9.99 year · $19.99 / $24.99 lifetime** | same |
| Kanji Study | US / JP | per level | ¥68–98 per level · ¥88 all | **¥1,500–2,500 per level · ¥4,000 all** | **$9.99–14.99 per level · $29.99 all** | same |
| renshuu | US | pro + supporter tiers | ¥45 subscription · ¥328 year · ¥798 lifetime; Kao Club ¥38–328 | ¥450–800 · ¥8,000–10,000 year · ¥18,000–22,000 lifetime | **$3.99–6.99 · $49.99–59.99 year · $109.99–129.99 lifetime**; Kao Club $5 / $15 | same |
| Typing Land | US | donation unlock ("Typing Sword") | not sold (404) | ¥800 | **$4.99** | same |
| AnkiMobile | US / JP / CN | paid upfront | **¥168** | **¥4,000** | **$24.99** | same (lookup API) |
| さくらやタイピング練習LITE | JP | ad removal, monthly | not sold (404) | **¥900** | not sold (404) | same |

Bold marks the figures §F quoted. "same" means each bold figure matches §F's string today.

**Nihongo Ride's own IAP, on the same pages today:** 西行之路 ¥10.00 (CN), 西への道 ¥150 (JP), The Road
West $0.99 (US). This matches `docs/PLAN-V1.37.md:132`.

**The free kana apps §F names** (`docs/PLAN-V1.37.md:320`): Kana – Hiragana and Katakana (id1454200955)
and MOJiKana (id6447672905) are free in all three storefronts, and their pages list no in-app
purchases today.

### 1.2 Three descriptions, sharpened (prices unchanged)

* **Rail Typing, "all lines, one line free".** The CN description says the Yamanote line is free for
  good, one more "今日一线" (line of the day) opens free each day, and every mode is free. The pass
  ("全线定期券") unlocks every line, including lines and cities added later. Monthly, yearly (with a free
  trial on the first subscription) and one-time purchase are all offered. Kyoto is among the listed
  lines. Its version history starts at 1.0 on 2026-10-05 (`<time datetime="2026-10-05">`), and 1.2.0
  was "4天前" (four days before today). §F's "launched Oct 5" is the 1.0 date in the version history.
* **さくらや, "¥900/mo".** The storefront list shows "LITE版有料プラン ¥900" with no period. The monthly
  term comes from the description, which calls it a 月額 auto-renewing subscription renewed every month.
* **MOJi辞書.** §F's "¥12/mo – ¥58/yr · ¥228 permanent" is right. The page also lists a ¥48 half-year,
  a ¥15 "1个月", MO coins and a widget skin.

---

## 2. The floor arithmetic, re-derived

### 2.1 The inputs, each from the repo

| input | value | source |
|---|---|---|
| the floor | ¥50 CNY a month | owner input 2026-08-30, `docs/PLAN-STAGE1.md:145-146` |
| the unit used here | per 30 Pacific report days | `docs/PLAN-V1.37.md:322`; the unit `sales_report.py` prints (`scripts/sales_report.py:1755-1756`) |
| new installs | N = 122 over 47 Pacific report days (2026-09-09 .. 10-25) | the N = 100 record, `docs/measurements/stage1-checkpoints.md:228, 232` |
| installs a day | 122 / 47 = **2.5957** | derived |
| installs per 30 days | 2.5957 × 30 = **77.87** | derived. `sales_report.py --since 2026-09-09 --until 2026-10-25`, run today, prints "per-30-days rate over the window: 77.9 downloads" |
| net ratio | ¥10 → ¥8.42, so **0.842** | `docs/PLAN-V1.37.md:132`; re-read today in §3 (CNY 10.00 → proceeds 8.42) |
| zero bound | 3 / N (rule of three): 3/122 = **2.459%**, 3/200 = **1.500%** | `docs/PLAN-V1.37.md:183` |

Formulas, per 30 days:
* sales needed = 50 / net
* c\* = sales needed / 77.87
* ⌈3/c\*⌉, then N₂ = max(⌈3/c\*⌉, 200), then days = N₂ / 2.6

### 2.2 Every row of §F's table, checked (`docs/PLAN-V1.37.md:324-330`)

Unrounded values first. "Net (ASC)" is the actual proceeds of that Apple price point, read in §3.

| CNY | net scaled (×0.842) | net (ASC today) | sales / 30 d | c\* | 3/c\* → ⌈⌉ | N₂ | days at 2.6 (at 2.596) | > 2.46%? | > 1.50%? | §F row |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 8.420 | 8.42 | 5.938 | 7.626% | 39.34 → 40 | 200 | 76.9 (77.0) | yes | yes | **correct** |
| 18 | 15.156 | 15.16 | 3.299 | 4.237% | 70.81 → 71 | 200 | 76.9 (77.0) | yes | yes | **correct** |
| 30 | 25.260 | 25.27 | 1.979 | 2.542% | 118.02 → 119 | 200 | 76.9 (77.0) | yes (by 0.08 pt) | yes | **correct** |
| 68 | 57.256 | 57.28 | 0.873 | 1.121% | 267.52 → 268 | 268 | 103.1 (103.2) | no | no | **correct** |
| 128 | 107.776 | 107.83 | 0.464 | 0.596% | 503.57 → 504 | 504 | 193.8 (194.2) | no | no | **correct** |

**No arithmetic error was found in §F's table.** Every printed cell matches at the precision printed.

The supporting figures elsewhere in the plan also check:
* `docs/PLAN-V1.37.md:154`: 50 / 8.42 = 5.94 sales, and 5.94 / 77.9 = 7.63%.
* `docs/PLAN-V1.37.md:171`: 122/47 = 2.596 a day; 78 more installs take 78 / 2.596 = 30.05 days.
* `docs/PLAN-V1.37.md:172`: (122−36)/32 = 2.69 and (122−68)/20 = 2.70. (The 36 and 68 inputs were not
  re-checked here.)
* `docs/PLAN-V1.37.md:183`: 3/122 = 2.46% and 3/200 = 1.50%.
* `docs/PLAN-V1.37.md:362`: "200 installs (about 77 days)" and "268 (about 103)" match.

### 2.3 Three small things the table does not say

None of these changes a printed cell.
1. **The net column is scaled, and the real proceeds differ slightly.** At ¥30, ¥68 and ¥128 the ASC
   proceeds are ¥25.27, ¥57.28 and ¥107.83. §F prints ¥25.26, ¥57.26 and ¥107.78. The largest gap is
   ¥0.05, and no c\*, ⌈3/c\*⌉ or day count moves. §F's line 322 already says the exact net comes from
   an ASC GET at decision time.
2. **A month is not 30 days.** The owner's floor is "¥50 CNY/month" (`docs/PLAN-STAGE1.md:145-146`).
   §F uses 30 Pacific report days. A mean calendar month is 30.44 days, which gives 79.0 installs and
   c\* = 7.52% at ¥10 instead of 7.63%. So 30 days is the stricter of the two, by about 1.4%. This is a
   unit choice, labelled as such in §F, not an error.
3. **Rounding of days.** 504 / 2.596 = 194.2, so the ¥128 row is "194" if rounded and "195" if rounded
   up. Either way it is past the day-180 backstop, as §F says.

`docs/PLAN-STAGE1.md:155-161`'s older §D table (net ¥8.50 at a 15% assumption, 72 downloads a month)
gives 8.2% at ¥10. §F's 7.63% is the same question with the measured net and today's traffic. Both are
in the repo; neither is wrong for its inputs.

---

## 3. Apple CNY price points at and next to each comparable

**Source:** ASC GET `/v2/inAppPurchases/6806755720/pricePoints?filter[territory]=CHN&limit=200&include=territory`,
via `scripts/asc_api.sh GET`, 2026-10-27 13:49 UTC. Four pages, following `links.next`.
`meta.paging.total` = 646, and 646 distinct points were collected, all territory CHN. The range runs
from 0.00 to 2,999.00. Raw pages are kept outside the repo at
`~/Library/Caches/NihongoRide-v137-work/evidence-p0-4-p0-7/asc-pricepoints-CHN-2026-10-27/`.

**Every CNY comparable price is an exact Apple price point.** So is each of §F's arithmetic anchors.

| CNY point | proceeds | proceeds / price | comparable(s) at this point | point below → proceeds | point above → proceeds |
|---|---|---|---|---|---|
| 6.80 | 5.73 | 84.26% | 日语打字通 3-month VIP | 6.50 → 5.48 | 7.00 → 5.90 |
| 9.80 | 8.26 | 84.29% | 日语打字通 6-month VIP | 9.50 → 8.00 | 9.90 → 8.34 |
| 10.00 | 8.42 | 84.20% | Nihongo Ride today; §F anchor | 9.90 → 8.34 | 10.80 → 9.10 |
| 12.00 | 10.11 | 84.25% | Rail Typing month · TypeAll month · MOJi month | 11.80 → 9.94 | 12.80 → 10.78 |
| 15.00 | 12.64 | 84.27% | MOJi "1个月" | 14.80 → 12.47 | 15.80 → 13.31 |
| 16.80 | 14.15 | 84.23% | 日语打字通 1-year VIP | 16.00 → 13.48 | 17.00 → 14.32 |
| 18.00 | 15.16 | 84.22% | §F anchor | 17.80 → 15.00 | 18.80 → 15.84 |
| 30.00 | 25.27 | 84.23% | §F anchor (`docs/PLAN-STAGE1.md:160`) | 29.90 → 25.19 | 30.80 → 25.95 |
| 38.00 | 32.01 | 84.24% | TypeAll year | 37.80 → 31.84 | 38.80 → 32.69 |
| 48.00 | 40.44 | 84.25% | MOJi half-year | 47.80 → 40.27 | 48.80 → 41.11 |
| 58.00 | 48.86 | 84.24% | MOJi year | 57.80 → 48.69 | 58.80 → 49.53 |
| 66.80 | 56.27 | 84.24% | 日语打字通 permanent | 66.00 → 55.60 | 67.00 → 56.44 |
| 68.00 | 57.28 | 84.24% | TypeAll lifetime · Rail Typing year; §F anchor | 67.80 → 57.12 | 68.80 → 57.96 |
| 128.00 | 107.83 | 84.24% | Rail Typing lifetime; §F anchor | 127.00 → 106.99 | 129.00 → 108.67 |
| 148.00 | 124.68 | 84.24% | MARU permanent | 147.00 → 123.84 | 149.00 → 125.52 |
| 168.00 | 141.53 | 84.24% | AnkiMobile (paid app, CN) | 167.00 → 140.68 | 169.00 → 142.37 |
| 228.00 | 192.07 | 84.24% | MOJi permanent | 223.00 → 187.86 | 229.00 → 192.91 |

Read with care:
* The order is by price. It is not a ranking.
* These are the price points of the **existing** non-consumable (6806755720). A new SKU (E3) has its own
  price-point list, which must be read by its own GET once it exists.
* The proceeds are this developer's proceeds at today's terms. They are not the comparables' proceeds.
* **These must be re-read at decision time.** Apple changes price points and proceeds with tax and
  currency updates, and today's GET says nothing about the day C-2 is answered.

---

## 4. What this file could not re-read, and where it was unsure

* **Nothing here is revenue or conversion.** List prices show how comparables are structured. They do
  not show what any of them sells.
* **"What is paid for"** was re-read only for the three items in §1.2, plus the page headings. The other
  rows keep §F's descriptions.
* **Storefront lists can be cut short.** A page shows about ten IAP rows. The "Kao Club" rows in renshuu,
  and MOJi's coin and skin rows, show the lists are mixed, not only the headline tiers.
* **Same app, different price ladders by storefront.** TypeAll's ¥68 lifetime sits next to $9.99 and
  ¥1,500; Rail Typing's ¥128 next to $19.99 and ¥3,000. These are the developers' own per-storefront
  choices or Apple's equalisation; the pages do not say which.
* **The rule-of-three columns** depend on a matched known-positive purchase, which does not exist yet
  (`docs/measurements/stage1-checkpoints.md:244-246`). They say what a zero *would* rule out, not what
  has been ruled out.
* **PLAN-V1.37 §F was found arithmetically correct.** The three notes in §2.3 are precision and unit
  remarks, not errors.
