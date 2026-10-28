# docs/store/drafts: store creative and ASO, designed and not uploaded (PLAN-V1.37 P0-10)

* **Designed during the observation window.** Nothing in this directory is live, and nothing was
  uploaded, PATCHed or changed in App Store Connect. ASC was read with GETs only
  (`scripts/asc_api.sh GET`).
* **When it ships.** PLAN-WINDOW said "designed during the window and shipped on day 91"
  (`docs/PLAN-WINDOW.md:302-306`). Under PLAN-V1.37 it ships **with P1-13** in v1.38, after the
  N = 200 record, as a registered Window 2 co-intervention; screenshots may stagger to a later version
  (`docs/PLAN-V1.37.md:244`). On the E3-path the road copy lands in the bridge release
  (`docs/PLAN-V1.37.md:538`).
* **Baseline date: 2026-10-28, 01:04–01:14 UTC (10:04–10:14 JST)**, against the live 1.36 on macOS and
  iOS.
* No price is proposed anywhere here. No decision cell is filled.

| file | what |
|---|---|
| `asc-baseline-2026-10-28.json` | The dated GET baseline: name and subtitle (appInfoLocalizations), description, keywords and promotional text for both platforms (appStoreVersionLocalizations), the screenshot and preview sets, and the IAP's localizations. Endpoints, lengths and SHA-256s included. No contact fields. |
| `ASO-AUDIT.md` | Read-only audit of title, subtitle and keywords against JP and CN learner queries; candidate values for P1-13; every claim checked against the code. |
| `SCREENSHOTS.md` | en / zh / ja shot lists (the road, a paid stretch labelled as paid, the offer), the CN search-result creative, as a spec with captions in three languages. |
| `serp-2026-10-28.json` | The App Store web search reads behind the audit (35 queries, public data, with a known-positive control). |

Raw GET responses, the search-page parser and its outputs are kept outside the repo, in
`~/Library/Caches/NihongoRide-v137-work/evidence-p0-10/`.

## Findings for the owner (nothing here was worked around silently)

1. **"Shipping moves 75% of impressions" is stale** (`docs/PLAN-WINDOW.md:306`, which P0-10's "why"
   cites). 75% was CN's share over 06-06..08-24 (`docs/measurements/v2-acquisition-funnel.md:72`). Over
   09-20..10-25 CN is 2,651 of 7,345 impressions (36%) and JP 3,049 (42%)
   (`docs/measurements/v137-funnel-post-day0.md:167-168`). JP's first impression, mostly on the Mac,
   now matters as much as CN's search row.
2. **"First two screenshots"** (`docs/PLAN-WINDOW.md:305`; `v2-acquisition-funnel.md:129, 133`):
   Apple says the first one to three, by orientation (`https://developer.apple.com/app-store/product-page/`,
   read today). The live iPhone set is portrait, so the CN creative is designed as three frames.
3. **PLAN-V1.37 §Q item 8 names "Mac" as something Rail Typing does not do** (`docs/PLAN-V1.37.md:493`).
   Its CN listing, read today (`https://apps.apple.com/cn/app/id6817686826`), says it runs on Apple-silicon
   Macs ("需要 macOS 15.0 或更高版本以及装有 Apple M1 或更高版本芯片的 Mac"). Its listing does not
   mention ads either way, and it has online play (对战), so "offline" and "no ads" are this app's own
   facts, not a measured contrast. Its prices, read today: 永久定期券 ¥128, 年卡 ¥68, 月卡 ¥12.
   Guideline 2.3.7 also bars a subtitle from referencing other apps.
4. **ja has no screenshot set at all**, and JP is shown the English set (`SCREENSHOTS.md` §1). P1-13's
   "screenshots" for ja is therefore a new set, not an update, and is part of the co-intervention.
5. **The CN storefront lists Simplified Chinese and English (U.K.)**, not English (U.S.)
   (`ASO-AUDIT.md` §3). An `en-GB` locale would add a second CN keyword field; PLAN-V1.37 §K is silent on
   it. Owner decision, not drafted as a default.
6. **The "offer" frame cannot show the price.** Guideline 2.3.7 says screenshots "should not include
   prices". P0-10's "the offer" is designed cut above the buy row.
7. **Not PLAN-V1.37, but found:** the live `ja` keyword `かな入力` aims at kana-keyboard input, which the
   app does not have (`ASO-AUDIT.md` §5.3); `docs/ASC_METADATA.md:205-215` records a screenshot order
   that differs from the live one; Apple's two pages disagree on whether keywords are 100 bytes or 100
   characters, and the live ja field (151 bytes) settles it as characters for that field.
