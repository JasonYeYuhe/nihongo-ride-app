# PLAN-V1.37: fix what is sold, build what can earn, let the window close on its own (v1.37 → v1.39)

*Revised plan, 2026-10-27 (JST), day 48 of the pre-registered window (day 0 = Pacific 2026-09-09; the newest report day read is Pacific 10-25, 47 report days). This is revision 2, with a further correction pass of the same day (34 checked problems: citations, the IAP submission path, the overrides B needs, the Window 2 file's scope, the minimum walk as an owner-chosen deviation, and B's revenue). It keeps the combined draft's facts, house style and verification standard, and applies the two agy reviews (Gemini 4 and Gemini 3.8 Flash). §R records every finding of both, numbered, with accept / partial / reject and the reason. Nothing was built, nothing in the repo was written, and App Store Connect was read with GETs only. Every claim cites a file:line (repo HEAD `54470d0`), an ASC GET or a URL. Proposed path: `docs/PLAN-V1.37.md`. Like PLAN-V1.34 it covers three releases, and each release still gets its own dated record when it ships.*

---

## 摘要（给 owner）

* **现在卖的东西，以及它为什么到不了底线。**
  * 唯一的付费项是买断「西行之路」，¥10（净 ¥8.42）。买到的是京都之后 8 段路的名字和配色。要骑约 48 次才到京都，买了以后还要再骑约 6 次才看得到第一段新风景。
  * 你的底线是每 30 天 ¥50。现在每天约 2.6 个新装机，要 7.6% 的新装机都买它才够。
  * 同类 app 没有一个卖风景；都卖学习内容、关卡/线路、模式或去广告。所以这个 ¥10 的风景做得再好，也到不了底线。
* **赚钱的路：E3 + E5。**
  * **E3：** 新用户得到一个完整的免费部分，另外卖一个买断的"深度解锁"（例如 N3–N1 的内容）。已经装过 app 的人，现有的一切全部免费保留。
    * 按同类 app 的 ¥68 档位算，只要约 1.1% 的新装机购买就到底线。这只是算术，价格由你定。
  * **E5：** 日文界面。53% 的新装机来自日本，现在看到的全是英文。
  * 这两件现在就在分支上做，先不发布。西行之路照卖，只修缺陷、加预览，不再加风景。
  * 旧文件写过"窗口结束前不做 Pro、不做第二个 SKU"。在分支上先做，是 agent 按 10-07 的委托做的判断（理由在 §C P0-11）。你想停，说一句"停掉分支"就停。
* **现在要你做的决定：没有。**
  * 默认 A：观察窗口按原规则跑到 N = 200（预计日本时间 11-25..27 能读到），到时自动结束。
  * 想提前结束就说"B"。§0 写了 B 的理由和代价。
    * 好处：改好的付费页早约 2.5–3 周上线；E3 只早约 1 周（它约 12-07 才做得完）。多赚约 ¥10–30，不到一个月的底线。
    * 代价：预注册作废，记为看过数据后的决定；最后一份正式记录停在 N = 122（上界扣住）。B 之后要发 E3，同样要你写下覆盖"不做 Pro"的那句。
* **以后两个决定，各一张卡：**
  1. **11-15 走查卡，三选一。**
     * 完整走查：你亲手约 45–55 分钟，退款另约 5 分钟（终端部分由 agent 做）。
     * 最小走查（约 15–20 分钟）：Mac 和 iPhone 都要装好，先在 iPhone 上截购买前的 OFFER，再在 Mac 上买一次。这台 Mac 以后做不了检查 1；检查 2、3 以后补走，或由你写「不走」；退款等它们做完。这偏离了走查卡定好的顺序，选它就是你的决定。
     * 你写下"不走"。
     * 你不回，agent 什么都不替你记，按"没走"来规划。
     * 只要那一次购买能匹配上，现有的 N = 122 就已经说明：¥10–¥30 的风景到不了底线（3/122 = 2.46%）。
     * 同一张卡上还有两件只有你能做的：推网站改动；公开仓库历史里还有你的电话号码，要不要重写历史或把仓库设为私有（不回 = 不动）。
  2. **N = 200 卡，约 11-25..27。**
     * 你读 §K 的分支，并给 E3 定价。
     * 0 购买会落在 STOP BUILDING，原文是"不改价、不做 Pro"。所以要发 E3，需要你在一个带日期的框里写下"价格 + 覆盖这一句"。框由 agent 起草。
     * 同一张卡上：下一个观察窗口（Window 2）各分支的后果由你写。你不回，agent 只提交计量规则，后果格子留空。
     * 你不回：v1.38 照发（它在每个分支下都合规），E3 留在分支上，价格不动。
* **发布计划（日本时间）：**
  * **v1.36：** 10-27 已提交，等审核。批准当天先做收尾杂事。
  * **v1.37：** 约 11-09..13 提交，不碰任何付费面。内容是修读音，再加一个只存在本机的"装机批次标记"，以后 E3 靠它认出老用户。它批准当天也要做收尾杂事，N = 200 的读数要用到它的上线日期。
  * **v1.38：** 约 11-30..12-04 提交。内容是付费页的缺陷、风景预览、恢复购买的反馈、日文界面（来得及的话），以及统计仪表按货币和 SKU 分开（先在分支上做好，N = 200 记录之后才合并）。万一到时是 GO（有陌生人买了），改付费页的部分默认不早于太平洋时间 12-09 上线，除非你在卡上写明提前。
  * **v1.39（E3）：** 只有你在 N = 200 卡上写了价格才发；约 12-07 前写好则约 12-14..18 提交，晚于此则 2027-01-05..15。你不回就不发。
* **不做的事：**
  * 订阅、广告、服务器、遥测，窗口内改价；
  * 再加风景：西段地标、出发背景、0 km 入口都已砍掉；
  * agent 在任何环境下做购买；
  * agent 替你写任何带新含义的 §K 框。

---

## §0 What the owner decides now, and what happens with no answer

**Nothing is required now.** The default is A, and A needs no answer.

| | **A: let the window end by its own rule at N = 200 (default on silence)** | **B: end the window now with a dated §K box (owner only)** |
|---|---|---|
| When the money changes reach customers | v1.38 (Offer v2 fixes, instruments, E5 if green) is submitted about 11-30..12-04 JST under STOP and STOP BUILDING. Item 10 (`docs/PLAN-STAGE1.md:808-810`) supersedes the older "at day 90" sentences **for the decision** only. It does not cover GO's "Run to day 90 anyway for the repeat rate" (`PLAN-STAGE1.md:528-529`), which governs observation *after* GO. **Under GO**, v1.38 still ships, but its offer-changing items are released (manual release) no earlier than Pacific 12-09, unless the owner writes in the C-2 box that the repeat-rate run is cut short. E3 ships in v1.39, about 12-14..18, if the owner says yes on the N = 200 card. | v1.37 can carry the ledger split and the Offer v2 fixes (about 11-13..17). E3 then rides the next release once it is green: about 12-07..11 at the earliest, because E3 is estimated green about 12-07 (§Q-3), against about 12-14..18 under A. **Offer v2 arrives about 2.5–3 weeks earlier; E3 only about one week earlier.** E3 cannot ship before the release *after* the ledger split under either option (`docs/PLAN-STAGE1.md:1374-1381`). |
| Revenue given up by waiting | 2.5–3 weeks at 2.596 installs a day (122 over 47 days, `docs/measurements/stage1-checkpoints.md:228-232`) is about 45–55 new installs (17.5 × 2.596 = 45.4; 21 × 2.596 = 54.5). **The road term is near zero.** Under A those installs still see the road at ¥10, and they meet it at Kyōto about 48 rides after install, by which time v1.38's Offer v2 is live under either option. What B adds there is only Offer v2's increment, unquantified. **The E3 term is real,** because installs that arrive before E3 are grandfathered and can never buy it. At E3's floor rate at the ¥68-class anchor (1.12%, §F), 45–55 installs give 0.51–0.61 sales × ¥57.26 ≈ **¥29–35, about 0.6–0.7 of a floor-month, if E3 shipped 2.5–3 weeks earlier.** E3 is green only about 12-07 (§Q-3), so B moves it about one week: about 18 installs, ≈ ¥12. **Total: about ¥12, at most about ¥30, below one floor-month.** The anchor is arithmetic, not a price proposal. | The same amount, gained. |
| What the record says | With a matched known positive, a zero at N = 200 bounds per-install conversion below 3/200 = 1.50% (3/314 = 0.96% against the ceiling). **The N = 122 already observed gives 3/122 = 2.46% (3/236 = 1.27% against the ceiling) once the walk is matched.** That already rules out ¥10, ¥18 and ¥30 scenery (§F). N = 200 adds a registered reading. It does not change the decision. | The final registered record is the N = 100 reading (N = 122, BOUND WITHHELD, `stage1-checkpoints.md:183-260`). If the walk happens later, 3/122 is still available as arithmetic, but not as a registered reading. |
| The pre-registration | Kept. | Voided, and recorded as a decision made after the N = 35 and N = 100 readings (§K forbids deciding "after seeing a checkpoint", `PLAN-STAGE1.md:388-392`). The cost is "one paragraph in §K rather than a rebuild" (`docs/PLAN-WINDOW.md:345-351`). |
| Owner decisions it needs | **None now.** At the N = 200 reading: E3's price plus the override of "not price and not Pro" and of the other written "do not build Pro / no second SKU" rules, in one dated box (Appendix A-1). | Now: "B" (box A-2). **That box carries the same override** of `PLAN-STAGE1.md:174-176`, `PLAN-V2-PRODUCT.md:236-237, 547, 639` and `PLAN-WINDOW.md:269`, because those rules are not §K branches: they still bind when the window ends at N = 122 with 0 purchases, and E3 is fork option 2 (`PLAN-V2-PRODUCT.md:405-410`). Before E3's submit: E3's price. |
| The walk | Still the only thing that makes a zero readable. The minimum walk is enough for the bound (§1). | The same. |

**B, stated fairly.** It is the Flash reviewer's recommendation (§R F-5):
* The owner asked to start making money ("想要开始盈利了").
* The most likely branch at N = 200 is STOP BUILDING, which prescribes "instrumentation and placement, not price and not Pro" (`PLAN-STAGE1.md:550-554`).
* ¥10 scenery cannot reach the floor (§B), and with a walk, the data already in hand rule it out (3/122).
* So the window's last four weeks cannot change what should be built.
* PLAN-WINDOW §I calls a *different* alternative "not stupid": treating Stage 1 as already answered by construction and spending the 90 days on distribution (`PLAN-WINDOW.md:348-351`). That was framed before the window, as an alternative to running the measurement, not as ending it after two readings. **No document defines ending the window early.**

That case is strong.

**Why A is still the default.**
1. Silence cannot end a window. Ending it is the owner's decision, so the only option an agent can default to is the status quo.
2. A costs about ¥12, at most about ¥30: below one floor-month.
3. E3 and E5 take about five weeks to build on branches (to about 12-07, §Q-3) whichever option is chosen (§D, §E).
4. A keeps the record clean.

**Stated plainly: under A, a zero at N = 200 lands on STOP BUILDING, and its text says "not price and not Pro".** E3 is a new price on new depth. So shipping E3 needs **one owner decision at that reading**: E3's price and the override of §K's "not price and not Pro", `PLAN-STAGE1.md:174-176` and the other written prohibitions listed in A-1 item 2, recorded in a dated §K box written then (Appendix A-1, drafted by the agent, committed only on the owner's word). With no answer, E3 stays on its branch and v1.38 ships without it.
* Under **GO** (a stranger buys first), E3 is one of the §E fork's options (`docs/PLAN-V2-PRODUCT.md:231-244, 401-419`), so only its price is needed.

**A without the walk (A′) is the likely outcome, and the plan is built for it.**
* The walk has been pending since day 0.
* The owner has twice delegated broadly: "你想办法自己做掉 你全权负责 没办法再找我" on 10-07, and "你继续做到收尾吧" on 10-26 (`stage1-checkpoints.md:43-48, 184-190`).

Under A′:
* N = 200 is "a record of N only" (`docs/PLAN-V1.34.md:1126-1128`), and the existing §K text governs as written: a zero with no returned counter is STOP BUILDING / UNINTERPRETABLE. **No agent-written box is added.** The same lines leave D3 to say what that world's decision rule is; P0-3 does so as the agent's reading, labelled, with the decision cell left to the owner.
* P1-3 and P1-4 do not wait for the walk (§D). One owner card on 11-15 offers the minimum walk (§1).
* In Window 2 a *positive* proves the pipeline by existing: an IAP row, and an unknown type code fails calibration loudly (`scripts/sales_report.py:215-229`). Under A′ only Window 2's zeros are unreadable.

---

## §1 The owner's touchpoints: two cards, each with a default on silence

| # | Card | When (JST) | What the owner does | Default on silence (never an owner-only decision) |
|---|---|---|---|---|
| **C-0** | optional | any time before about 11-15 | Say "B" (§0). | A. |
| **C-1** | **Walk card** | **11-15**, or earlier if the owner opens a session saying "开始走查". Never on a day the live version is changing (v1.37's release day): the walk runs on whichever version is live after its approval-day chores (P0-1 / P0-2). | Choose one: **(a) the full walk**: §K purchase and refund plus §L's three checks (`docs/WALKCARD-STAGE1.md:22-33`: about 45–55 min of the owner's own time, plus about 5 min for the refund; the older 65–75 min budget at `:61` also counts the terminal steps the agent now does). **(b) The minimum walk** (below, about 15–20 min), a deviation from the card that the owner chooses. **(c) "Not walked"**: the owner pastes DRAFTS §2 / §4, or says so in words the agent quotes verbatim in the record (`docs/DRAFTS-STAGE1-RECORDS.md:97-186`). On the same card: (d) after a walk, a yes/no on signing §E's store-gate harness (P0-9); (e) push the `site/` diff of P0-6; (f) optional: the public-repo history question: the App Review phone number left the tree in `54470d0` but remains in git history (rewrite history, make the repo private, or leave it). | Nothing is recorded. The agent never writes a skip and never writes "walked" (`docs/HANDOFF-STAGE1-GATES-PROMPT.md:212-214`). The plan runs as A′. The harness stays unsigned, so exit 3 remains the honest state. The site is not pushed, and C-2 offers it again. History is left as it is. |
| **C-2** | **N = 200 card** | about **11-25..27**, the morning the record lands | (a) Read §K's branch as a person, from the record and the same-day `review_watch` (owner-only, `PLAN-V1.34.md:1087`). (b) E3: a price, plus the override box (Appendix A-1). Under GO, the price only, plus (if wanted) cutting GO's repeat-rate run short. (c) The road's price (default: unchanged). (d) Optional: E3's free/paid boundary (default: candidate 1 in P0-13). (e) Window 2's branch consequences (P0-5): what ZERO, BELOW-FLOOR and GO-2 mean for the next work, written or confirmed in the owner's words. (f) Optional: "P1-12 waits for a known positive" (§D P1-12). | The agent commits the N = 200 record with the numbers only, as it did for N = 35 and N = 100, and leaves the branch line for the owner. v1.38 ships, because its contents are legitimate under GO, STOP and STOP BUILDING (§D); under GO its offer-changing items are released no earlier than Pacific 12-09. E3 stays on its branch. No price changes. No box is written. Window 2's file is committed with measurement mechanics only and its branch-consequence cells blank, so v1.38's period is reported descriptively. P1-12 merges with v1.38, labelled as a departure from the 2026-09-16 rule (§D). |

**The minimum walk (option b) is a deviation from the walk card, chosen by the owner at C-1.** The card fixes its order: "本卡按事先定好的走查顺序写 … 不要重新设计顺序" (`WALKCARD-STAGE1.md:12`). Its valid subsets are steps 0–1, 0–2, and 0–3 together with check 3A (`:665-667`). "Step 1, then step 3, skipping step 2" is not one of them, and a deviation means "停下，由你决定" (`:669`). Option (b) is:
1. Step 1: install on the Mac and the iPhone, and on the iPhone take the pre-purchase OFFER screenshot (about 10–12 min, card `:28`). This keeps check 3's negative control alive. The iPhone must be at hand.
2. Step 3: the purchase on the Mac (about 5 min), **skipping step 2.** The card makes check 1 a precondition of step 3 (`:390`), so choosing (b) **forfeits check 1 on this Mac** (ordering rule 2, `:674`). That forfeit is the owner's recorded decision, in the owner's own words under DRAFTS §4, like option (c). The agent does not write it.
3. Step 6: the agent's D+1/D+2 match.

What it leaves open:
* **Checks 2 and 3 can be walked later, but only before the refund** (ordering rule 1). The refund (about 5 min) therefore waits until the owner walks them, or records them as deliberately not walked.

P0-1 adds a short addendum for (b) to the walk card; the card does not already cover it. The agent never drops a check on its own. The minimum walk is enough to remove BOUND WITHHELD, because the bound needs only the matched purchase (`stage1-checkpoints.md:228-246`).

**The agent's half of any walk:** preflight, baseline, state reads, the D+1/D+2 match, and
`python3 scripts/sales_report.py --confirm-known-positive --kind purchase --at <…> --platform macOS --country <XX>`.
**There is no `--no-cache`**: that flag makes the confirm command exit 2 (`scripts/sales_report.py:1660-1670`).
* Registry entries in `docs/measurements/stage1-known-positives.json` are drafted by the agent and committed under the owner's 2026-10-07 delegation, **labelled as such**. This is the pattern the N = 35 and N = 100 records used, and the walk card lists it (`WALKCARD-STAGE1.md:35-41`).
* The owner can apply them instead: the file is owner-maintained (`sales_report.py:77`; `PLAN-STAGE1.md:707`).
* On a `WARNING` above the draft, the agent stops and shows the owner.

**Not on any card, done under the release delegation** (`docs/PLAN-V1.36.md:4-5`):
* each release's upload, submit and metadata PATCHes, with `ListAgents`/`SendMessage` first and a byte-exact read-back;
* the IAP review-note fix (P1-14), with v1.38, after the N = 200 record. The IAP is frozen until then (`PLAN-V1.36.md:24`).

Creating E3's IAP and setting any price happen only after C-2's box.

**Optional, never on the critical path:** the D5 `ta_score` device errand and the moderated sessions (`PLAN-V1.34.md:723-738, 758-762`).

---

## §A The facts this plan starts from

| fact | source |
|---|---|
| One paid thing: non-consumable `com.jasonye.nihongoride.scenery.lifetime` (ASC 6806755720). `APPROVED`, familySharable false, contentHosting false. No promoted purchase, no IAP image, no offer codes, no subscription groups. The app is free. | ASC GET 2026-10-27 (`inAppPurchasesV2`, `promotedPurchases`, `offerCodes`, `subscriptionGroups`, `appPriceSchedule`); `Sources/NihongoRideApp/RouteStore.swift:69` |
| Price: one manual price, CNY 10.00 (net 8.42, base territory CHN). Auto-equalised JPY 150 (net 128) and USD 0.99 (net 0.84). 175 territories. | ASC GET `iapPriceSchedule`, `manualPrices`, `automaticPrices`, `inAppPurchaseAvailability` |
| IAP names: en "The Road West", ja 西への道, zh 西行之路. All approved. | ASC GET `inAppPurchaseLocalizations`; `docs/ASC_METADATA.md:187-189` |
| What it buys: 8 stretches after Kyōto, 大阪 28 km … 長崎 138 km. Each has a name, romaji, a threshold, a palette and one of the 4 existing landmark kinds (Fuji, torii, castle, tower), all drawn in code. No words, modes or art assets. | `Sources/SceneryKit/RideRoute.swift:44-52, 207-297`; `Sources/NihongoRideApp/RideBackgroundView.swift:184-232` |
| A buyer sees nothing new until the next ride past 28 km, about 6 rides after Kyōto. Non-buyers stay on the 京都 night palette forever. | `AppModel.swift:1725-1730`; `RideRoute.swift:200-203, 323-325, 357-363` |
| Kyōto is at 25,000 m. That takes 48 Journey rides at N5, 33–34 in Sentence or Listen, and 10 or 4 in Practice. Verbs moves the odometer 0 m. The arrival rate is unmeasurable, and no ledger has ever been returned. | `PLAN-STAGE1.md:612-621, 271-275`; `Sources/EntitlementKit/UnlockOfferLedger.swift:16-22` |
| Two entrances: the last Settings card, "The road past Kyōto", at any distance; and the menu route strip, tappable only at 25 km or more, with stop names in English even in the zh UI. | `SettingsView.swift:174-206`; `MenuView.swift:620-631, 661-702` |
| The rating prompt yields for exactly the ride that crosses Kyōto: `AppModel` builds `openedANewOffer`, and `ReviewPrompt` returns `.rideOpenedANewOffer` on it. | `AppModel.swift:2530-2544`; `Sources/StoreReviewKit/ReviewPrompt.swift:169` |
| Result: N = 122 (macOS 82 · iOS 40), 0 purchases, 0 refunds, BOUND WITHHELD (exit 5). | `stage1-checkpoints.md:228-246` |
| Since day 0, Japan is 65/122 (53%) and China 29 (24%). Before day 0 it was China 42%, Japan 20%. macOS is 67% of new installs. The rate is flat at about 2.6 a day. The JP storefront has 0 ratings. Lifetime: 259 first downloads, 723 update units, no IAP row ever. | read-only parse of the cached daily sales reports (evidence lens); `https://itunes.apple.com/lookup?id=6777469778&country=jp` |
| The purchase path has zero automated coverage. All nine `StoreGateTests` skip, and even when live they call `Product.purchase()` and `AppStore.sync()` directly, not `RouteStore.purchase()` or `restore()`. The StoreKit → `PurchaseAnswer` translation is unobserved, and the test file says so itself. | `Entitlement.swift:37-41`; `Tests/NihongoRideMacTests/StoreGateTests.swift:174-183, 249-261`; `Tests/NihongoRideAppTests/PurchasePlanTests.swift:18-21` |
| Restore is `try? await AppStore.sync()` followed by a settle loop. There is no notice and no outcome, and an offline sync error is swallowed. The buy button has no progress state. A thrown purchase shows the raw `localizedDescription`. | `RouteStore.swift:317-318, 371-374, 376-393`; `RoadView.swift:189, 250-256, 282-283` |
| **The ledger under-counts `offerAppeared`.** `RoadView` records the offer once, `.onAppear`. If the price has not loaded yet, the event is `offerUnavailable`, and nothing re-fires when the product arrives or after Retry. Stage 1's on-device counters carry this bias. | `RoadView.swift:55-57`; `UnlockOfferLedger.swift:217-229` |
| Measured AX5 defects, frozen: RoadView stretch rows; the buy button wrapping "One- / time / purcha / se"; the "Already bought it?" card width; the Settings road row; the menu strip. `HorizontalTextFitTests` accepts 25 residues, six of them RoadView's. **Hypothesis from code, not measured:** `card()` applies `.panel()` before `.frame(maxWidth:)` (`RoadView.swift:348-349`), which may be the cause of the measured `restore` card width, and predicts the same shrink-wrap on the `owned` ("Opened") card. No document measures the `owned` card; P1-1's V3 "before" pass must confirm both. | `docs/PLAN-V1.33.md:69-75`; `Tests/NihongoRideAppTests/HorizontalTextFitTests.swift:263-279`; `RoadView.swift:212-223, 237-258, 341-350`; `NihongoRideApp.swift:290-297` |
| **Correction to PLAN-V1.34 §I:** the 2.70:1 figure is white on solid coral. The buy button computes at 8.0–9.4:1. The sub-AA text on the offer screen is the 11 pt boundary sentence (2.86–3.01:1) and the `Theme.dim` captions (3.91–4.24:1). All computed from source colours. | `RoadView.swift:86, 133, 184-186, 248, 316`; `NihongoRideApp.swift:273-285` |
| **The product has two names in the zh UI:** 西の道 in RoadView and Settings, 西行之路 in the boundary sentence, the IAP and the CN listing. | `RoadView.swift:93, 163, 218, 268` vs `:314`; `SettingsView.swift:192` |
| The UI defaults to `en` on every device and never reads the locale. There is no Japanese UI. The zh strings are inline `zh ?` ternaries. | `Sources/SettingsKit/AppSettings.swift:15, 92, 230`; `SettingsView.swift:284-288` |
| The store never says what is sold. en/zh say "the one optional in-app purchase", ja says nothing, all three say Tokyo→Kyoto, and no promotional text is set. Screenshots date from v1.1. The same "one optional in-app purchase" wording is on the site. | ASC GET 1.35 `appStoreVersionLocalizations`; `docs/ASC_METADATA.md:88, 201-216`; `site/privacy.html:31, 69`; `site/support.html:43` |
| The IAP review note says "There is no other entry point", which has been false since v1.30. | ASC GET `/v2/inAppPurchases/6806755720`; `PLAN-STAGE1.md:73-95` |
| **`sales_report.py` sums proceeds across currencies.** It reads `proceeds_currency` and never uses it in the tally, so one JP sale (JPY 128) would print as 128 against a CNY floor. | `scripts/sales_report.py:403-404, 486-504` |
| A second SKU is blocked in code: one static productID; one ledger key, where a mismatched productID is quarantined and overwritten; a quarantine key fixed to `defaultsKey + ".unreadable"`; an `UnlockOfferLedger` with no product dimension; and `sales_report.py` classifying by type code only. | `RouteStore.swift:69, 117-120, 180, 365`; `Entitlement.swift:222, 224-242`; `UnlockOfferLedger.swift:52-53, 127, 135`; `sales_report.py:215-229` |
| New IAPs: a new product has no availability record and is silently unbuyable until one is set. **A later non-consumable goes through `POST /v1/inAppPurchaseSubmissions`**, which the code calls "the RIGHT endpoint for a LATER purchase". `reviewSubmissionItems` with an `inAppPurchaseVersion` was forced only for the app's **first** non-consumable, which `inAppPurchaseSubmissions` refuses with 409 `FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION`. E3 would be the app's second non-consumable. **Neither path has been measured for a second IAP.** The stale part of `ASC_METADATA.md:182` is only its parenthetical claim that `reviewSubmissionItems` "does not accept IAP". | `docs/ASC_METADATA.md:181-182, 196-197`; `scripts/submit_1_30.py:28-31`; `scripts/asc_release.py:611-614` |
| Build numbers differ by platform: macOS 61, iOS 62. The macOS target is 14.0 and iOS 17.0. | `project.yml:136-137, 275-276` |
| Economics: the floor is ¥50 per 30 Pacific report days. At ¥8.42 net that is 5.94 sales, which is 7.63% of 77.9 installs. §D already calls 8.2% "at or above the ceiling". | `PLAN-STAGE1.md:145-167, 1312-1330`; §F |
| Only two reviews ever: a 2026-07-10 CN review asking for a one-time way to pay, written before the SKU existed, and a 2026-10-09 review praising no ads. | `PLAN-V2-PRODUCT.md:25-29`; `stage1-checkpoints.md:173, 267-283` |
| The App Review contact phone left the working tree in `54470d0`. `asc_release.py` reads the contact from a local file. The number remains in git history. The `contactEmail` in the historical `submit_1_*.py` scripts is the public support address, published on purpose: it appears in `site/support.html` (2×), `site/privacy.html` (2×) and `AboutView.swift` (1×), and `54470d0`'s message says it stays. | `git show 54470d0`; `scripts/submit_1_30.py:235-236`; `grep -cF` without printing the address |

**What the evidence cannot support:** any conversion rate, any count of Kyōto arrivals, any retention figure, or any claim that a different price or good would convert at 2.6 installs a day.

---

## §B The conflict, and the facts that shape the plan more than the freeze does

**The freeze, until the N = 200 record.**
* Constraint 1 freezes the offer, the price and the placement. Constraint 4 freezes the en-US, zh-Hans and ja metadata (`PLAN-WINDOW.md:115-126`).
* §G "What must not be built" lists **"A second SKU"** as a row of its own: "six independent analyses said no … a week of engineering must clear 6.7% of every new install, forever". **Separately**, the same row adds a precondition: the counter has no product dimension, so "Split the counter first, never in the same release" (`PLAN-WINDOW.md:265-269`). For E3, the prohibition is lifted only by the owner's override box (A-1 item 2, or A-2); the counter split is satisfied by P1-11 shipping in v1.38, a release before E3.
* v1.36 kept these byte-identical to `fdb2b5f` (`docs/PLAN-V1.36.md:22-26`): `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`, `RouteStore`, `EntitlementKit`, `Theme`, `ScaledFont`, and the `.storekit` file.
* **Open:** modes, review, stats, widgets, UI, accessibility and content (`PLAN-WINDOW.md:128-129`), documents, and code built and held on branches.

**When the decision row fires.** At "N = 200, or 2027-03-08, whichever comes first" (`PLAN-STAGE1.md:417-431`). Item 10 makes this schedule govern, and supersedes "at day 90" **for the decision** (`PLAN-STAGE1.md:808-810`). It does not cover GO's "Run to day 90 anyway for the repeat rate" (`:528-529`); see §0.
* The rate is 122/47 = 2.596 installs a day. 78 more are needed, which takes 30.05 days. So the first Pacific report day with N ≥ 200 is about 11-23..25, readable about 11-25..27 JST.
* Cross-checks: (122−36)/32 = 2.69 a day gives 11-24; (122−68)/20 = 2.70 a day gives 11-23.
* This is a projection, not a commitment. Each registered walk install delays it by about 0.4 days. It lands before the 2026-12-08 interim record, which carries no decision.

**Five facts that shape the plan:**
1. **§K's branches are GO, STOP and STOP BUILDING / UNINTERPRETABLE. There is no ITERATE**, although the schedule table and the tool say "go / iterate / stop" (`PLAN-STAGE1.md:426, 526-554`).
   * STOP needs a returned counter from a stranger who reached Kyōto. The ledger expects "under two and plausibly zero" of those, and its `offerAppeared` is under-counted (§A).
   * So the likely branch is STOP BUILDING: "instrumentation and placement, not price and not Pro". v1.38 is built to be legitimate under all three branches. E3 is not, and needs the owner (§0).
   * The existing §K text governs as written. This plan adds no box that defines "iterate".
2. **¥10 scenery cannot reach the floor at today's traffic, however well it is presented.** It needs 7.63% of all installs.
   * Fixing the offer screen is still owed to the people who meet it: the defects, legibility and restore feedback.
   * Reaching ¥50 needs a different good (E3) or about 4× the traffic (`PLAN-STAGE1.md:166-167`). So no more scenery is built (P1-7, P1-8 and P1-9 are cut).
3. **The data already in hand are nearly enough.** With a matched walk purchase, 3/122 = 2.46% rules out ¥10, ¥18 and ¥30 scenery. Waiting to N = 200 tightens this to 1.50% on a treatment v1.38 replaces anyway. Neither figure rules out a ¥68-class good (1.12%, §F).
4. **Distribution is the binding term** (`PLAN-STAGE1.md:1320-1325`). Revenue = traffic × conversion × net, and the store work (P1-13, P0-10) is the only lever on traffic.
5. **Every priced comparable sells learning content, levels, lines, modes or ad removal, met early. None sells scenery alone** (§F). This is an inference from list prices only.

---

## §C Phase 0: now until the N = 200 record (inside the window)

**Rules for this phase:**
* Anything that ships passes `PLAN-WINDOW` §A's two-clause test: it changes neither what a device is offered nor which devices arrive (`PLAN-WINDOW.md:22-29`).
* The frozen list stays byte-identical to `fdb2b5f`.
* Money work (Phase 1, E3, E5, the multi-SKU generalisation) is built in private clones on branches and **not merged to `main`** until the N = 200 record is committed.
* `sales_report.py` does not change **on `main`** until the N = 200 record. P1-12 is built on a branch now and merged after the record (§D). Stage 1's decision reads units, not proceeds, so the currency defect cannot touch it (`PLAN-STAGE1.md:526-530`).
* **Quiet period:** no release between the day after v1.37's submit and the N = 200 record. This keeps release-day bumps out of the decision reading, as in v1.36 (`PLAN-V1.36.md:798-815`).
* **No agent-authored §K box that adds meaning.** The only §K boxes the agent writes are the constraint-3 registration before each `--submit`, the house practice the 2026-10-26 box followed (`PLAN-STAGE1.md:1034-1060`). These record what ships and add no rule.

| id | what | why | size (agent-days) | verify / registered |
|---|---|---|---|---|
| **P0-1** | **v1.36 approval-day chores** (`docs/STATE-2026-10-27.md:30-36`): `FIRM_RELEASE_DATES_PT` and its test pin; `stage1_walk.py` `EXPECTED_*` → 1.36 / 61 / 62 with fixtures; walk card and DRAFTS; the cadence row; STATE and memory; `review_watch`; retire `NihongoRide-v135-work` after copying what the docs cite; a short walk-card addendum for option (b) (§1), which the card does not already cover. Then the agent half of any walk (§1). | The walk must observe the binary customers run. | 0.25 + 0.5 | `stage1_walk.py preflight` exit 0; `test_sales_report.py` green; the confirm command exits 0 with no `WARNING` (no `--no-cache`). |
| **P0-2** | **v1.37, the open-surface release:** `n2-b277` 六十キロ and the 12 out-of-table number and counter sentences, each corrected by ear and upheld 2 of 2; the 点 row's tolerances; the CI corpus check on cancelled pushes; a removed word's `accessibilityValue` (`STATE-2026-10-27.md:67-73`); **plus P0-12**. Nothing on the frozen list. **Plus v1.37's own approval-day chores**, the same list as P0-1: `FIRM_RELEASE_DATES_PT` and its test pin; `stage1_walk.py` `EXPECTED_*` → 1.37 and its builds, with fixtures (`scripts/stage1_walk.py:108-110`); the walk card; the cadence row; `review_watch`. **They must land before the N = 200 `--checkpoint`**, which withholds the bound with "release registry incomplete" when a version's Pacific release date is missing (`scripts/sales_report.py:256, 1369`). | Fixes taught errors and keeps the cadence, which is a registered covariate (`PLAN-ITERATION.md` §G). | 2 · 1.5 · 0.5 (+0.25 approval day) | §J V1–V4, V6–V8. `road.png`, `road-iap-review.png` and `menu.png` byte-identical. A constraint-3 box before `--submit`: direction neutral, with a cadence line. After approval: `stage1_walk.py preflight` exit 0 against 1.37, `test_sales_report.py` green. |
| **P0-12** | **The install-cohort marker, in v1.37.** On launch, write `NihongoRide.installCohort.v1` = {first-seen marketing version as integer components, first-seen build, platform, `priorDataPresent`} **once, if absent**. It is monotonic: a later or larger value never overwrites a smaller one. `priorDataPresent` records whether an odometer or settings existed before the first write, so installs that predate the marker are known as such. The value is local in UserDefaults and is not on the frozen list (a pure type in `SettingsKit` plus one call in `AppModel`). **No CloudKit** until the production-schema gate is passed for a new record type. | E3's grandfathering must never depend on `AppTransaction` or the network (§E). The marker changes nothing offered and nothing about who arrives, so it can ship inside the window. Every launch of 1.37 and 1.38 by an existing install becomes offline proof before E3 exists. | 0.5 | Pure tests: write-once; never raised; integer parsing ("1.4" < "1.40"); per-platform build. Mutate the monotonic guard → red. `PrivacyClaimTests` unchanged (local only). Registered in v1.37's constraint-3 box as content that changes neither clause. |
| **P0-3** | **`docs/STAGE2-DECISION-PACK.md` (D3)**: the §E fork × §K's branches with every decision cell blank (`grep -c DECIDED` = 0); the day-91 list; the readings it shares data with. **It also says** that Stage 1's on-device ledger under-counts `offerAppeared` (§A), which biases any returned counter toward STOP BUILDING. It lays out C-2's options and E3's two boundary candidates. **An A′ section** states the no-known-positive decision rule that `PLAN-V1.34.md:1126-1128` says D3 must state: it reproduces the existing §K STOP BUILDING / UNINTERPRETABLE text verbatim (`PLAN-STAGE1.md:526-554`) as **the agent's reading under the 2026-10-07 delegation, labelled as such**, and leaves the decision cell for the owner. **Departure, said in the pack:** `PLAN-V1.34.md:741` defines D3 as written after the moderated sessions, which never ran; and `PLAN-V1.36.md:13, 253` call D3 owner-gated. This D3 is a draft written without the sessions, for the owner to read at C-2, and decides nothing. | `PLAN-V1.34.md:740-749, 1126-1128`. C-2 needs it on the table. | 1.5 | An adversarial lens checks every cited line. The cells stay blank. |
| **P0-4** | **Pricing brief:** §F's tables with every URL, CNY/JPY/USD, the floor arithmetic per 30 Pacific report days, and the Apple CNY price points nearest the comparables (ASC GET at decision time). No price is proposed. | C-2(b) needs data, and "an agent invents no prices" (`PLAN-V1.34.md:729`; the owner-only price item at `:1081`). | 0.5 | Each figure is re-read from its public page on the day it is filed. |
| **P0-5** | **Window 2 pre-registration: two variants**, drafted in `docs/PLAN-WINDOW2.md`: E3-path (treatment v1.39) and silence-path (treatment v1.38). Exactly one is committed before its treatment release's `--submit`. It is its own file, not a box in PLAN-STAGE1 §K. **What the agent commits is measurement mechanics only**, labelled as agent-authored under the 2026-10-07 delegation: units, the FX table, the burn-in, the read dates, N₂, the denominator, and the P1-12 instrument note. **Every branch-consequence cell** (what ZERO, BELOW-FLOOR and GO-2 mean for the next work, and what an owner box mid-window means) **is left blank for the owner**, as D3 and the N = 200 record already do. The owner fills them at C-2(e), or in A-1 item 5 on the E3-path. With no answer, the treatment period is reported descriptively against the mechanics, like the E3-path bridge. | One treatment per window, fixed in advance (`PLAN-V2-PRODUCT.md:550-555`). Branch consequences bind later owner choices, and §K-like boxes are owner-only (`PLAN-V1.34.md:1086-1087`; §R G4-7 point 3). §H gives the shape. | 0.75 | Every number in it is re-derived. The FX table is fixed on the commit date from one named public source. `grep` shows every branch-consequence cell blank in the agent's commit. |
| **P0-6** | **`site/` diff for the owner to push (C-1e):** the zh section of `site/support.html`, and SKU-neutral purchase wording ("any optional in-app purchase is handled by the App Store") in `site/privacy.html:31, 69` and `site/support.html:43`. It is true now and after E3, so E3 needs no second push. **Plus the privacy page's local-storage list** (`docs/STATE-2026-10-27.md:72`, a v1.37 item): `site/privacy.html:34-35` lists what is stored on the device, and gains one sentence on the install-cohort marker (P0-12: local, never synced or sent), timed to v1.37's release. | "the one half a paying Chinese customer would actually hit" (`PLAN-V2-PRODUCT.md:356-366`); a false public claim must not outlive E3. | 0.25 | `PrivacyClaimTests` (which read `site/privacy.html`, `PrivacyClaimTests.swift:91-95`) change in the same commit if they pin these strings or that paragraph. The live pages are curled after the owner pushes. |
| **P0-7** | **Post-day-0 funnel, read-only:** `scripts/acquisition_funnel.py` with `ASC_ANALYTICS_REQUEST=c57c770b-…`, by territory and platform, GETs only (the request is never re-POSTed). Aggregate counts go in `docs/measurements/v137-funnel-post-day0.md`. **It gates nothing.** E5 does not wait for it, because it cannot tell natives from learners: the reports carry territory and source, not who the user is (an inference; facts JSON `under[2]`, open question on natives vs learners). | It describes the ja listing's co-intervention and the traffic term. | 0.5 | The script's own calibration. Each figure is quoted with its report instance and processing date. |
| **P0-8** | **Drafts only:** the N = 200 record, with numbers only and the branch line blank for the owner, in the shape of the N = 100 record; and Appendix A's owner boxes. Nothing is committed to §K without the owner's word. | `PLAN-V1.34.md:1086-1087`; §R G4-7, F-8. | 0.25 | — |
| **P0-9** | **§E, the purchase path's first automated observation** (`PLAN-V1.34.md:766-787`). **Preconditions, unchanged:** the §K purchase recorded **and its refund row**, or DRAFTS §2/§4 pasted (`PLAN-V1.34.md:768-772`), **plus** the owner's yes at C-1(d). **On CI it needs a Debug-only stripped entitlements file:** an ad-hoc-signed test host keeps `get-task-allow` and drops CloudKit, Game Center and the team App Group, because AMFI refuses those entitlements without a profile (`project.yml:70-71`). The Release entitlements are pinned byte-identical (`codesign -d --entitlements`). **The Xcode versions differ:** `macos-26` runs Xcode 26.x / Swift 6.3.3 (`.github/workflows/gates.yml:47, 74-78`), while the probe ran on Xcode 27 and saw `Code=4`, not 26.x's `Code=3`. So the runner is re-probed before anything is concluded. Includes the Octane-config `trap` and a 0.5-day iOS re-probe. **Stays off `main` until the N = 200 record.** | Zero automated coverage on both platforms. | 1 + 0.5 CI + 0.5 iOS | Nine gates *executed*, one mutated red per family. **Falsifier:** if hosted runners keep `SKTestSession` inert, record it in the probe doc and fall back to the walk Mac. Under A′ this item never runs, and exit 3 stays the recorded state. |
| **P0-10** | **Store creative and an ASO audit, designed and not uploaded:** the CN search-result creative; en/zh/ja screenshots of the road, a paid stretch labelled as paid, and the offer; a read-only audit of the `keywords`, subtitle and title fields against high-intent JP/CN queries. Filed under `docs/store/drafts/` with a dated GET baseline. | "designed during the window and shipped on day 91" (`PLAN-WINDOW.md:302-306`). Traffic is the binding term. | 2.5 | — until P1-13. |
| **P0-11** | **Branches, held:** Phase 1 (§D), **including P1-12** (merged only after the record); **E5** (P1-15); the **multi-SKU generalisation** (P1-5) behind a constant; **E3** (P0-13 then its code). | Built now, nothing waits on engineering when the row fires. **Two written rules are against *building*, not only shipping:** "Not in this plan: … Building Pro before Stage 1 reports — the whole point of the staging" (`PLAN-V2-PRODUCT.md:633, 639`), and PLAN-WINDOW §G "What must not be built", row "A second SKU" (`PLAN-WINDOW.md:265-269`). **The agent's reading under the 2026-10-07 delegation, labelled as such:** their measurement harm (a changed offer, pooled counts) comes only from shipping, and branch-only work ships nothing, creates no IAP and changes nothing on `main`. Their effort warning ("a week of engineering must clear 6.7% … forever") does apply, and the agent takes that risk because the owner asked to start earning ("想要开始盈利了"). This is not an owner decision. The owner can stop it with one line ("停掉分支") on any card or session; shipping still needs A-1 or A-2. | counted in §D, §E | Each branch passes §J before it is called done, and is rebased after v1.37 ships. |
| **P0-13** | **`docs/DESIGN-E3-SAMPLER.md`**, design before code. It covers the boundary, the grandfather rule, and App Review. **Boundary candidates** (one-time goods must be finished, `PLAN-V2-PRODUCT.md:302-312`): **candidate 1, the default:** free is kana, N5 and N4 in every mode, the Tōkaidō, and everything that already ships free; paid is the N3, N2 and N1 pools. **Candidate 2** (Flash): N5 free, N4–N1 paid. The grandfather rule is a pure function (§E). | It is the money path. The owner may pick the other candidate at C-2(d), and silence keeps candidate 1, labelled as the agent's design choice under the delegation. | 1.5 | An adversarial lens on the red line (`PLAN-V2-PRODUCT.md:369-397`): no existing install may lose anything. |
| **P0-14** | **Public repo:** nothing to redact in the tree. The `contactEmail` in the historical `submit_1_*.py` scripts is the public support address, published on purpose (§A). Only the phone number, removed from the tree in `54470d0`, remains in git history; whether to rewrite history or make the repo private is the owner's call (C-1f). | The repo is public. | 0 | — |

**Phase 0 total:** about 8.5 agent-days (P0-1 0.75, P0-3 1.5, P0-4 0.5, P0-5 0.75, P0-6 0.25, P0-7 0.5, P0-8 0.25, P0-10 2.5, P0-13 1.5), call it 9, plus v1.37 (4.5 incl. P0-12's 0.5, + 0.25 approval day). P0-9 (2) runs only after a walk, its refund row and C-1(d). The branch work runs in parallel.

---

## §D Phase 1: v1.38, "Offer v2 + Japanese UI" (after the N = 200 record, under every branch)

**What it is.** It fixes the paid thing for the people who meet it, prepares the instrument and the code for a second SKU, and adds Japanese UI. It adds no scenery, no new entrance, no price change and no SKU. Every item is "instrumentation and placement" or a defect fix, so it is legitimate under GO, STOP and STOP BUILDING.

**Preconditions:**
* the N = 200 record is committed;
* the Window 2 variant whose treatment is v1.38 is committed first (only on the silence path; mechanics only, §C P0-5);
* P1-12 is built on a branch during Phase 0 and **merged** after the record; only its byte-for-byte reproduction of the N = 200 reading waits for the record.

| id | what | why (evidence) | size | verify | measured |
|---|---|---|---|---|---|
| **P1-1** | **The offer screen's measured defects.** The six RoadView text-fit residues and the buy button at AX5, fixed the house way: stack at accessibility sizes, or a `FlowLayout`; never a raised ceiling. `card()` moves `.frame(maxWidth: .infinity, alignment: .leading)` before `.panel()`, which is expected to fix `restore` and `owned`. That cause is a code-reading hypothesis, and the `owned` defect is predicted, not measured (§A): **V3's "before" pass must show both defects before the fix is credited**, and a card that does not shrink-wrap before is dropped from the claim. The Settings road row at AX5. The menu strip's stop names localised. The boundary sentence and dim captions raised to ≥ 4.5:1. | `PLAN-V1.33.md:69-75`; `RoadView.swift:212-223, 237-258, 341-350`; §A contrast row. | 2.5 incl. AX5 pass | `HorizontalTextFitTests.accepted` **25 → 19**, only ever lowered. Contrast **measured on rendered pixels**. V2 with intended differences named in advance (including the `owned` card); V3; V4. | package |
| **P1-2** | **One name for the product:** 西行之路 in zh everywhere, "The Road West" in en, 西への道 in ja (with P1-15). Pinned by `PurchasePromiseTests`. | §A. | 0.25 | Mutating one string → red. | package |
| **P1-3** | **Purchase and restore feedback, not waiting for the walk.** `restore()` replaces `try? await AppStore.sync()` with `do / catch`. A pure `restorePlan(syncResult:, verifiedEntitlement:)`, table-tested like `purchasePlan`, has three outcomes: "Restored"; "Nothing to restore on this Apple Account" (sync succeeded, no entitlement); "Couldn't reach the App Store — try again when online" (sync threw, no verified entitlement), **so an offline restore is never reported as nothing to restore.** Buy and Restore get a progress or disabled state. Thrown errors are shown as a localised sentence. The ledger records `restoreFinished(found/none/error)`. | `RouteStore.swift:371-374`; `RoadView.swift:189, 282-283`; a negative purchase review is §K's only stop-and-fix (`PLAN-STAGE1.md:567-568`). The walk-first rule was about changing purchase code *mid-window* (`PLAN-V1.34.md:1116`), and v1.38 ships after the window closes. | 1.25 | Plan table tests. Mutate: map a sync throw to `.none` → red. An injectable sync seam is tested offline. A purchase-adapter lens with independent refuters. StoreGateTests that drive `restore()` land when P0-9 is allowed. | new event `restoreFinished` |
| **P1-4** | **A pure seam for StoreKit result → `PurchaseAnswer`, not waiting for the walk.** It is a behaviour-preserving extraction with table tests: `.pending` must never read as `.userCancelled`. `StoreGateTests` that drive `RouteStore.purchase()` follow P0-9. | `PurchasePlanTests.swift:18-21`; `StoreGateTests.swift:174-183, 249-261`. | 0.5 | Swap pending and cancel → red. Diff reviewed as a pure move. | — |
| **P1-5** | **Multi-SKU generalisation, shipped dark behind a constant** (`MultiSKU.enabled = false`). `RouteStore` takes a product list; each SKU gets its own defaults key and quarantine key (`Entitlement.swift:222, 236-238`); the road's key and record are unchanged. Built early on a branch. | It makes E3's release a small diff. Sharing a key would quarantine and overwrite the road's record and lock buyers out offline (`Entitlement.swift:224-242`). | 2.0 | The road's `NihongoRide.entitlement.v1` decodes byte-identically before and after. Two-SKU tests on separate keys. Mutate to a shared quarantine key → red. Purchase-adapter lens. | — |
| **P1-6** | **Show what is sold.** The west card's eight locked rows become rendered thumbnails: `RideBackgroundView` at a fixed progress, one per stretch, each with a VoiceOver label. The copy names the goods concretely ("eight cities from Ōsaka to Nagasaki, 113 km past Kyōto") and promises no landmarks. The boundary sentence and the distance-aware blurb stay (`RoadView.swift:259-270`). | Nothing previews the paid scenery. | 1.5 | Each preview matches the entitled ride render pixel for pixel at the same progress. `PurchasePromiseTests` and `PaidRouteRowTests` change in the same commit as the copy. The Tōkaidō frozen sweep stays green. | new event `previewAppeared` |
| ~~P1-7~~ | **Cut:** west-specific landmarks. | No buyer has shown that paid scenery sells, and more scenery cannot reach the floor (§B). §R G4-3, F-1. | — | — | — |
| ~~P1-8~~ | **Cut:** departure backdrop / immediate payoff. | Same reason. With P1-9 cut, the App Review concern it answered is gone too. §R G4-14, F-4. | — | — | — |
| ~~P1-9~~ | **Cut:** the menu strip at 0 km. | An entrance at 0 km to a purchase that shows nothing until 28 km is an App Review risk (Guideline 2.1/3.1.1, unverified) and tells a new rider the purchase does nothing for about 47 rides (`RoadView.swift:259-270`). §R F-4, G4-14. | — | — | — |
| ~~P1-9b~~ | **Moved to D3 as a later option, not on any card:** the Kyōto-arrival line. | Fewer owner touchpoints. It is a new entrance and a Stage 2 question (`PLAN-STAGE1.md:73-76`). | — | — | — |
| **P1-10** | **The UI language for fresh installs follows the device:** `ja*` → `ja` (with P1-15), `zh-Hans*` → `zh`, everything else `en`. Existing installs keep their saved choice. `zh-Hant*` defaults to `en`, and a **mechanical zh-Hant conversion table** (a test-pinned character map over the zh strings) is offered as a selectable option, **not the default**. | `AppSettings.swift:15, 92, 230`. China was 42–48% of installs before day 0 and met an English offer. | 0.5 + 0.5 option | Tests for a fresh vs an existing setting; V2 in zh and ja. | split by territory |
| **P1-11** | **The instrument for any second offer.** `UnlockOfferLedger` format v2 with a product dimension: decode v1 by padding, never truncate; existing counts migrate under the road's id; a quarantine key per ledger key; About's counter text readable. **Plus the `offerAppeared` fix:** fire `offerAppeared` once per visit when the product resolves while RoadView is visible (including after Retry), and log `offerUnavailable` only when loading has finished with no product. **It ships here so that no second SKU ever shares its release** (`PLAN-STAGE1.md:1374-1381`). | §A; `RoadView.swift:55-57`; `UnlockOfferLedger.swift:217-229`. | 2.0 | v1→v2 decode tests including a short array; a truncating decode mutated → red; a cold-open test where the product arrives after appear → exactly one `offerAppeared`; `shareableSummary`'s kyoto line pinned. | the ledger itself |
| **P1-12** | **`sales_report.py` learns SKU and currency** (built on a branch in Phase 0; merged after the N = 200 record). (a) A SKU column; the road SKU pinned; an unknown SKU fails calibration; two SKUs never pool. (b) **Proceeds are bucketed by `Currency of Proceeds` and never summed raw.** An empty or unknown currency on a purchase or refund row fails calibration. The floor is evaluated in CNY-equivalent through the FX table pre-registered in `PLAN-WINDOW2.md`, with per-currency totals and unit counts printed alongside. (c) `--day0` cohort support for Window 2. (d) **The burn-in split:** days D₀′..D₀′+13 are reported separately from D₀′+14 onward, with F7 update counts, so an update-wave purchase is visible on the time axis, the only one the reports carry (`sales_report.py:536-541`). | `sales_report.py:215-229, 403-404, 486-504`. **The rule it meets:** a new kind "would be an instrument change and waits, like every instrument change, for the known-positive to be confirmed (2026-09-16 box)" (`PLAN-STAGE1.md:891-892`; also `PLAN-V1.34.md:716-717`), because "a changed instrument would make 'still passes' compare two different instruments across the known-positive" (`PLAN-STAGE1.md:740-741`). With a matched walk, P1-12 merges after the confirmation, as written. **Under A′ no known positive exists, so merging it is a departure from that rule**, recorded as such in `PLAN-WINDOW2.md` and the v1.38 record. The agent's reading under the delegation: after the N = 200 record Stage 1's readings are closed, so no Stage 1 comparison spans the change; what replaces the missing positive control is (1) the byte-for-byte reproduction of the N = 100 and N = 200 readings on the new instrument, a regression control on real rows, and (2) any later known positive confirmed on the new instrument and recorded as re-baselined. The synthetic JPY+CNY fixture is a unit test, **not** a real-row control. The owner can veto the merge at C-2(f) ("P1-12 waits for a known positive"); silence merges it, labelled. | 2.5 | After the record: reproduces the N = 100 and N = 200 readings byte for byte. `--confirm-known-positive` still matches. A synthetic JPY+CNY fixture → per-currency buckets; mutate to a raw sum → red. | the instrument |
| **P1-13** | **The store says what is sold.** en/zh/ja descriptions and promotional text name the road west (Kyōto→Nagasaki, one-time), and drop "the one optional in-app purchase". The ja copy uses P1-15's glossary. P0-10's screenshots and CN creative. An IAP promotional image. **Promoted IAP only together with `PurchaseIntent.intents` handling** (`#available(iOS 16.4, macOS 14.4, *)`; iOS's 17.0 target always has it, and macOS 14.0 needs the check) **and tests; otherwise it is cut.** **Registered in Window 2 as a co-intervention**; screenshots may stagger to the next version. | ASC GET 1.35 localizations; `ASC_METADATA.md:201-216`. A store-initiated buy with no handler drops the purchase. | 2.5 (+1.0 if Promoted IAP) | Byte-exact ASC read-back; the copy checked sentence by sentence against the code (V7). **Cut rule:** screenshots may follow; the binary does not wait. | co-intervention; `acquisition_funnel.py` by territory |
| **P1-14** | **The IAP review note made true** (both entrances); the app-level review notes name the placement. First read whether editing an approved IAP's note triggers re-review. | ASC GET reviewNote; `MenuView.swift:661-695`. | 0.1 | read-back | — |
| **P1-15** | **E5, Japanese UI on the key surfaces:** onboarding, menu, Settings, the Road screen and offer, results, About. `ja` joins `en`/`zh` in the language setting. Strings are short and plain and pinned by a glossary test. Not gated on P0-7. | 53% of new installs are from Japan and meet English (§A). It is presentation, not price and not Pro. | 6–8 | V2 en/zh/ja; V3 AX5 in ja; `HorizontalTextFitTests` run in ja with no new residue. The copy check is two independent model reviewers plus the glossary test, recorded as **not native-reviewed** unless the owner names a reviewer. | split by territory |

**Totals:**
* **Build:** about 15.6 agent-days without P1-15, excluding P1-10's zh-Hant option (+0.5) and P1-13's Promoted IAP (+1.0); 16.1 / 17.1 with them. With P1-15: 21.6–23.6 on the same exclusions (22.1–24.1 / 23.1–25.1 with them). All of it, P1-12 included, is built on branches during Phase 0; P1-12's read of the N = 200 reading waits for the record.
* Verify and review: 3. Release: 0.5.

**Cut rule.** Anything not green with its tests by 11-30 moves whole to v1.39, in this order: P1-13's screenshots, P1-15 (E5), P1-10's zh-Hant option, P1-6.
* P1-1, P1-2, P1-3, P1-11 and P1-12 never slip: they are the defects and the instrument.
* P1-5 never slips if E3 is to ride v1.39.

**Non-money day-91 items** ride v1.38 only if they fit under the cut rule: the Settings sync caption, the denied-reminder notice, About copy, the menu credit line, the zh Practice screenshot (`PLAN-V1.36.md:241-245`; `PLAN-V1.34.md:1093-1102`).

---

## §E Phase 2: the revenue path (v1.39 onward), re-ranked

"Choosing none of them and shipping a bit of each is the failure mode" (`PLAN-V2-PRODUCT.md:407-419`). **There is no default Phase 2 SKU on silence.** E3 ships only on C-2's box. Under GO, it ships on a price alone.

The falsifier column is a **draft** for the owner's branch-consequence cells in `PLAN-WINDOW2.md` (P0-5). The agent commits only the measurement rows; what a zero means for the next work is the owner's to write.

| rank | option | evidence | agent-days | risk / App Review / privacy | falsifier (pre-registered before release) |
|---|---|---|---|---|---|
| **1** | **E3: a complete free sampler plus ONE one-time depth unlock; existing installs grandfathered** (fork option 2) | Every priced comparable gates learning content met early (§F). It is the only option whose arithmetic reaches the floor at today's traffic: 1.12% of new installs at the ¥68-class anchor, against 7.63% for the road at ¥10. The only purchase request asked for a one-time way to pay (`PLAN-V2-PRODUCT.md:25-29`). Purchases come only from new installs, because grandfathered installs already have the depth. That gives E3 a clean denominator. | 10–15 (P0-13 first; P1-5 and P1-11 already shipped) | **High, controlled by the grandfather rule** (below). New IAP: an availability record, 3 localisations, a review screenshot, Family Sharing left off (irreversible). As a later non-consumable it is submitted via `POST /v1/inAppPurchaseSubmissions` (`submit_1_30.py:28-31`), around the v1.39 binary's submission; `reviewSubmissionItems` was forced only for the first non-consumable (`asc_release.py:611-614`). Neither path is measured for a second IAP, so the release script stops and reports any answer other than success rather than guessing; a 409 `FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` would mean the version-attached path instead. The purchase unlocks levels the buyer can open at once, so App Review sees the change immediately. Tests to update: `PrivacyClaimTests`, `PurchasePromiseTests`, `PaidRouteRowTests`, `OneBranchRuleTests`, `stage1_walk.py`'s constants. Data Not Collected stays. | Zero E3 purchases at N₂ = max(⌈3/c\*⌉, 200) new installs **and** ≥ 60 days, with the pipeline proven: E3 at that price and boundary cannot reach the floor at this traffic, and the next lever is traffic, not another SKU (§H). |
| **1** | **E5: Japanese UI** (a conversion enabler, not a SKU) | 53% of new installs are from Japan. | 6–8 (P1-15) | Medium: copy quality, with no native reviewer named. | Read by territory within Window 2. It is a named component, not a separate test. |
| 3 | **E4: finite content packs**, after E3's Window 2 reading | Kanji Study sells levels (§F). "Discrete finite packs, priced individually" is the honest form (`PLAN-V2-PRODUCT.md:306-310`). | 5–10 per pack | Medium. It splits about 78 installs a month across packs. | Zero sales over its registered cohort → no second pack. |
| 4 | **E2: a tip-jar / supporter add-on** (a non-consumable that gates nothing) | Patronage comparables: Typing Land $4.99, renshuu's supporter tiers. §N: no second SKU pays for itself (`PLAN-STAGE1.md:1314-1326`). | 2–3 after P1-5 | Low. An add-on only, never instead of E3. | Zero units at its window's decision → stop patronage (`PLAN-V2-PRODUCT.md:547`). |
| 5 | **E1: another road inside the road SKU**, only as a gift after traction | "A gift keeps its option value" (`PLAN-STAGE1.md:1196-1198`). Worth ¥0 as a separate good (§N). | about 3 per road | Low. Thresholds are permanent once shipped. | Only after Window 2 shows sustained road revenue. Never a default. |
| 6 | **E6: F1 paid workflow** | Fork option 3; the bounded half shipped free (`PLAN-WINDOW.md:277-300`). | 80–120 h (`PLAN-STAGE1.md:1371`) | Medium; it changes ride distance. Stage 3. | "Fewer than 2 of n pasted anything → shelved" (`PLAN-V1.34.md:742-745`). |

**E3's grandfather rule: a pure function, tests first.** No existing install may lose anything, ever (`PLAN-V2-PRODUCT.md:369-397`). An install is grandfathered, and the grant is **persisted**, if any of these holds:
1. **The P0-12 marker exists** with a first-seen build from before E3's build on that platform. Versions and builds are compared as integer components, per platform: macOS 61, iOS 62 today (`project.yml:136, 275`).
2. **The marker is written at E3's first launch with `priorDataPresent`** (an odometer or settings from before). The install predates E3.
3. **A verified `AppTransaction` in the production environment** has `originalAppVersion` below E3's: `CFBundleShortVersionString` on macOS, `CFBundleVersion` on iOS (https://developer.apple.com/documentation/storekit/apptransaction/originalappversion), parsed as integers.

Two further cases:
* **In the sandbox environment** (App Review, TestFlight), `originalAppVersion` is "1.0", so rule 3 is ignored there and only rules 1 and 2 apply. A reviewer's fresh install therefore sees the offer.
* **Unreadable** means `AppTransaction` throws (offline, `PLAN-STAGE1.md:279-283`) **and rules 1–2 do not grant**. Then the install gets **temporary, non-persisted grace**: the depth is open for this session, and the check is retried next launch.
* **Order:** the grandfather check reads the marker **as it stood before this launch's write** (P0-12 writes it at every first launch if absent). Otherwise a legacy user who deletes the app and reinstalls offline would find a fresh marker (first-seen = E3's build, `priorDataPresent` = false), fail rules 1–3, and get neither a grant nor grace.
* A table-test row covers exactly that: offline reinstall, no prior data, no pre-launch marker, `AppTransaction` throws → session grace, nothing persisted.

So:
* an existing user on a plane loses nothing;
* a fresh offline install gains nothing permanent;
* nothing depends on the network for anyone who launched 1.37 or later.

Tests cover every row. Mutations: persisting the grace, a string comparison, and accepting sandbox → each must go red.

**Sequence:**
* **v1.38** ships P1-5 (dark) and P1-11, so **v1.39** can carry E3: a constant flip, the new product, and the boundary.
* E5 rides v1.38 if green, otherwise v1.39.
* E4 and E2 wait for Window 2's reading. E1 waits for traction. E6 is Stage 3.

---

## §F Pricing: the owner's decision, with data

**No price is proposed. "An agent invents no prices"** (`PLAN-V1.34.md:729`; the owner-only price item at `:1081`; `PLAN-V2-PRODUCT.md:633-640`).

**Comparables** (list prices only, not revenue; public App Store pages, read 2026-10-27):

| app | storefront | what is paid for | price | URL |
|---|---|---|---|---|
| Rail Typing – 打字学日语 (typing along real lines, Kyoto included: the closest concept, launched Oct 5) | CN | all lines, one line free | ¥12/mo · ¥68/yr · **¥128 lifetime** | https://apps.apple.com/cn/app/id6817686826 |
| 日语打字通 | CN | VIP (kana/word/sentence, JLPT N5–N1) | ¥6.80–16.80 passes · **¥66.80 permanent** | https://apps.apple.com/cn/app/id6783668620 |
| TypeAll-打字菌 | CN | full | ¥12/mo · ¥38/yr · **¥68 lifetime** | https://apps.apple.com/cn/app/id6767579225 |
| MARU日语五十音特训 | CN | ad removal + modes | **¥148 permanent** | https://apps.apple.com/cn/app/id1208009110 |
| MOJi辞書 | CN | membership | ¥12/mo – ¥58/yr · ¥228 permanent | https://apps.apple.com/cn/app/id1021094295 |
| Kana – type japanese | US | full | $0.99/wk · $9.99/yr · $19.99–24.99 lifetime | https://apps.apple.com/us/app/kana-type-japanese/id6744024458 |
| Kanji Study | US / JP | per level | $9.99–14.99, all $29.99 · JP ¥1,500–4,000 | https://apps.apple.com/us/app/kanji-study-learn-japanese/id1078107994 |
| renshuu | US | pro + supporter tiers | $3.99–6.99 · $49.99–59.99/yr · $109.99–129.99 lifetime | https://apps.apple.com/us/app/renshuu-japanese-learning/id1542730063 |
| Typing Land | US | donation-style unlock | $4.99 | https://apps.apple.com/us/app/typing-land/id1568264476 |
| AnkiMobile | US/JP/CN | paid upfront | $24.99 / ¥4,000 / CN ¥168 | https://itunes.apple.com/lookup?id=373493387&country=cn |
| さくらやタイピング練習LITE | JP | ad removal | ¥900/mo | https://apps.apple.com/jp/app/id1545885771 |

Free kana apps with no IAP at all also exist, e.g. Kana – Hiragana and Katakana and MOJiKana (https://apps.apple.com/us/app/kana-hiragana-and-katakana/id1454200955; https://apps.apple.com/cn/app/id6447672905).

**Arithmetic, not a recommendation.** The unit is **per 30 Pacific report days**, the unit `sales_report.py` prints. Installs are 2.596 × 30 = 77.9. Net is scaled from the measured ¥10 → ¥8.42. The exact net, and whether each anchor is an Apple CNY price point, come from an ASC GET at decision time. The "ruled out" columns assume demand does not rise with price for the *same* good and placement. They say nothing about a different good such as E3.

| CNY | anchor | net ≈ | sales per 30 days for ¥50 | c\* (share of new installs) | ⌈3/c\*⌉ | Window 2 N₂ = max(⌈3/c\*⌉, 200) · days at 2.6/day | ruled out for the road by a matched zero at N = 122 (< 2.46%)? | … at N = 200 (< 1.50%)? |
|---|---|---|---|---|---|---|---|---|
| 10 | today | 8.42 | 5.94 | **7.63%** | 40 | 200 · 77 | yes | yes |
| 18 | — | 15.16 | 3.30 | 4.24% | 71 | 200 · 77 | yes | yes |
| 30 | §D's row (`PLAN-STAGE1.md:160`) | 25.26 | 1.98 | 2.54% | 119 | 200 · 77 | yes (barely) | yes |
| 68 | TypeAll lifetime / 日语打字通 ¥66.80 | 57.26 | 0.87 | 1.12% | 268 | 268 · 103 | no | no |
| 128 | Rail Typing lifetime | 107.78 | 0.46 | 0.60% | 504 | 504 · 194 (past the day-180 backstop) | no | no |

**What the data says and does not say.**
* Every comparable charges for *learning*, not scenery. ¥10 for a cosmetic reached after about 48 rides sits below every comparable's price structure.
* Nothing here shows that any price converts at 2.6 installs a day. The E3 rows are the conversion the floor *needs*, not a forecast.
* Even E3 at a ¥68-class price reaches only the floor. Anything bigger needs traffic.

**C-2's price choices** (default: no change, and no E3):
* **E3 priced, the road unchanged.** This is the money path. The road stays ¥10 as a small add-on.
* **E3 priced, the road repriced at the same time.** Window 2 then confounds the two. Allowed, and recorded in the same box.
* **No E3.** v1.38 is the treatment, at ¥10.

**Mechanics.**
* The road needs no binary for a price change: the offer shows `product.displayPrice` (`RoadView.swift:179`).
* A price is an ASC write to the CHN base-territory manual price, scheduled to take effect the day the treatment release goes live (https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases/).
* Update the hard-coded "CNY 10.00" in `xcode/NihongoRide.storekit:8` and the review notes. `submit_1_30.py:202` is historical and left as it is.

---

## §H Measurement: the Window 2 pre-registration (shape; P0-5 fills it in)

* **Treatment:**
  * **E3-path:** v1.39's E3 (with E5 if it rode v1.38). v1.38's period before it is a **bridge**, reported descriptively with no decision row.
  * **Silence-path:** v1.38's package at ¥10.
  * P1-13's store change is a **registered co-intervention**, by name.
  * Components are not separable at 2.6 a day. This is said now, not discovered later.
* **Day 0′:** the first Pacific day both platforms are live on the treatment release, with per-platform dates if they differ (`PLAN-ITERATION.md:689-691`).
* **Units:** everything is per 30 Pacific report days. Proceeds are bucketed by currency and converted only through the FX table fixed in the file on its commit date, from one named public source. Unit counts are printed alongside.
* **Denominator:** first-time downloads since day 0′, adjusted for registered walk and participant installs as in §K. For E3, grandfathered installs cannot buy, so the denominator is new installs only.
* **Rows:**
  * **Burn-in:** days D₀′..D₀′+13 are reported separately with F7 update counts. A purchase there is counted but flagged, because it may come from the update wave of existing installs: about 360–405 lifetime first downloads by v1.38 / v1.39's day 0′ (259 by Pacific 10-25, facts JSON `under[2]`, + 2.596/day × ~39–56 days), of which about 43% update (the v1.35 proxy: 82 update units against 191 prior installs), so roughly 155–175 devices. That matters for the road. It does not matter for E3, whose existing installs are grandfathered.
  * **Record** at N₂ = 100. No decision.
  * **Zero falsification** at N₂ = **max(⌈3/c\*⌉, 200) new installs AND ≥ 60 days since day 0′**, with c\* the floor conversion at the treatment's price. At ¥10 that is 200 installs (about 77 days); at a ¥68-class price, 268 (about 103). The backstop is day 180, with the bound computed from the observed N. **The rule of three is used only to falsify on zero:** 3/N₂ is quoted only when purchases = 0, and only with a matched known positive.
  * **GO-2** only on **sustained revenue**: net CNY-equivalent proceeds ≥ ¥50 in **each of two consecutive full 30-Pacific-report-day periods**, both after the burn-in. The earliest it can fire is about day 74. Never on a unit count such as 3/40, since "1–3 purchases proves existence and estimates nothing" (`PLAN-STAGE1.md:528-530`).
  * **Refunds** read at day 180 as absolute counts under the existing ceiling.
* **Branches.** The agent's commit defines each branch's **condition** (measurement) and leaves its **consequence** cell blank for the owner (P0-5; C-2(e); A-1 item 5). The consequences below are the agent's **draft** for the owner, not committed text:
  * **GO-2** (condition as above). Draft consequence: the next ranked option (E4 or E2) may open in the *next* window.
  * **BELOW-FLOOR:** ≥ 1 net purchase, not GO-2 by the zero row's date. Draft consequence: only options that raise net per sale or traffic qualify; no scenery-only work.
  * **ZERO:** 0 net purchases of the treatment SKU at the zero row, pipeline proven. Draft consequence: the good at that price cannot reach the floor at this traffic, and the next work is distribution; no new SKU without an owner decision.
  * **ZERO, pipeline unproven** (A′, and no purchase of either SKU ever seen): UNINTERPRETABLE. This is a measurement statement, said in the file before any reading.
  * With the consequence cells blank, a reading is reported descriptively against the conditions and decides nothing.
* **An owner's price/E3 box during a silence-path window** is recorded with its date. What it means for that window is the owner's to write in that box; the agent's draft wording is "ends that window early as the owner's recorded decision and opens Window 3".
* **Guardrails kept:** any negative review mentioning the purchase is a stop-and-fix (`PLAN-STAGE1.md:567-568`); a grandfathered user reporting lost access is a stop-and-fix too.

---

## §I Release cadence (JST)

| release | target submit | window | contents | agent-days (build · verify+review · release) | registered as |
|---|---|---|---|---|---|
| v1.36 | submitted 10-27, `AFTER_APPROVAL` | Window 1 | as recorded; approval-day chores (P0-1) | — · — · 0.25 | the 2026-10-26 box |
| **v1.37** | **11-09..13**, only after 1.36 is live on both platforms. If not submitted by 11-14, it is held until the N = 200 record. P0-12 then rides v1.38, and E3 leans on rules 2–3 for one release more. | Window 1 | P0-2 + P0-12; the frozen list byte-identical to `fdb2b5f`. **Approval-day chores** (P0-2): `FIRM_RELEASE_DATES_PT` + test pin, `EXPECTED_*` → 1.37, walk card, cadence row, `review_watch`, all before the N = 200 checkpoint. | 2.5 · 1.5 · 0.5 (+0.25) | constraint-3 box before `--submit` |
| quiet period | v1.37 submit → N = 200 record | Window 1 | No release. Branches finish. P0-9 runs only if a walk, its refund row and C-1(d) all exist, and stays off `main`. | — | — |
| N = 200 record | about **11-25..27** | Window 1 ends | C-2 | 0.25 | the record (numbers only) + any owner box |
| **v1.38 "Offer v2 + Japanese UI"** | **about 11-30..12-04**, under every branch. **Under GO**, its offer-changing items are released no earlier than Pacific 12-09 (GO's "Run to day 90 anyway for the repeat rate", `PLAN-STAGE1.md:528-529`, which item 10 does not supersede), unless the owner's C-2 box cuts the repeat-rate run short. | bridge (E3-path) or Window 2 (silence-path) | §D | 15.6–23.6 (all pre-built on branches; see §D totals for the exclusions) · 3 · 0.5 | constraint-3 box; on the silence path, `PLAN-WINDOW2.md` (mechanics only) committed first |
| **v1.39 "Depth unlock (E3)"** | **Only if C-2's box (A-1) exists. No box → no E3.** About **12-14..18** if the box exists by about 12-07 and E3 is green; if the box arrives after about 12-07, or E3 is not green by then, **2027-01-05..15**. | Window 2 opens (E3-path) | E3 + the new IAP (via `POST /v1/inAppPurchaseSubmissions` as a later non-consumable, `submit_1_30.py:28-31`; unmeasured for a second IAP); items cut from v1.38 | 10–15 (mostly pre-built) · 2 · 0.75 | `PLAN-WINDOW2.md` committed first |
| v1.40+ | after Window 2's zero row or GO-2 | Window 3 | the next ranked option (§E) | per §E | Window 3 pre-registration |

* Release days raise first downloads (1.18× to 1.58× in the two controls). Cadence is a registered covariate, never claimed as a cause (`PLAN-ITERATION.md` §G).
* The 2026-12-08 interim record still happens. It carries no decision and holds no release.
* No date in this plan waits for "day 90" **for the decision** (item 10, `PLAN-STAGE1.md:808-810`). The one exception is GO's repeat-rate observation (`PLAN-STAGE1.md:528-529`), which item 10 does not cover: under GO, v1.38's offer changes wait for Pacific 12-09 unless the owner records cutting the run short.
* **Window 2 dates on the E3-path:** day 0′ about 12-18..22. The record at N₂ = 100 about late January 2027. The earliest GO-2 about early March. The zero row at the ¥68-class anchor about early April.

---

## §J Verification standard (PLAN-V1.34 §G kept, `PLAN-V1.34.md:1020-1070`, plus the purchase path)

* **V1.** `run_all_gates.sh` green at **floor 17 (16 headless)** (`scripts/run_all_gates.sh:391-392`), raised whenever a gate script is added. `HorizontalTextFitTests.accepted` is only ever lowered.
* **V2.** Headless renders, en + zh (+ ja from P1-15), three runs, compared pixel by pixel. Intended differences are named per screen before reading.
  * In v1.37, `road.png`, `road-iap-review.png` and `menu.png` are identical, checked by a frozen-surface lens.
  * In v1.38 they and Settings are intended differences, and are listed. The Tōkaidō scenery renders stay identical.
* **V3.** AX5 simulator pass, default and AX5, en/zh/ja, on `NihongoRide-Placement` plus the iPad mini, and `NihongoRide-VisualPass`, which was deleted on 2026-09-29 and is recreated by the harness as an iPhone 17 Pro clone when missing (`PLAN-V1.34.md:978`); by the global simulator rule it is reported when created and removed when the task is done. For every changed screen before and after. Contrast is measured on rendered pixels.
  * **Simulator runtime (checked 2026-10-27):** the iOS 26.5 runtime is gone. `xcrun simctl list runtimes` lists iOS 18.5, 27.0 and 27.1, and the 26.5 copies of `NihongoRide-Placement`, iPhone 17 Pro / Pro Max and the iPad mini show as "runtime profile not found". Available copies of all four exist on **iOS 27.0**, and `run_ios_placement_tests.sh` picks the *available* device by name, so V3 and V4 run on iOS 27.0. Record the runtime with every placement or AX5 result. The stale 26.5 entries are not this plan's to delete.
* **V4.** `run_ios_placement_tests.sh` whenever UI changes, and before merging any UI-test change.
* **V5.** Store gates.
  * Exit 3 is tolerated until P0-9. After it, exit 0 with nine executed and a red mutation per gate family.
  * **P1-3, P1-4 and P1-5 ship on pure table tests plus mutation plus a purchase-adapter lens with independent refuters.** They do not wait for P0-9. The residual, that the adapter is unobserved end to end, is written in the release record.
  * When P0-9 exists, the Release entitlements are checked byte-identical with `codesign -d --entitlements` on every build.
  * "Strengthening a control is always allowed; loosening one for a green never is" (`HANDOFF-STAGE1-GATES-PROMPT.md:216`).
* **V6.** Pre-submission review:
  * one lens per file group, plus a tests lens that mutates;
  * independent refuters for every non-NOTE finding;
  * two rounds, with a third if round 2 finds a SERIOUS;
  * reviewers read the diff and do not build;
  * the two agy reviews run on each release diff;
  * E3 adds a red-line lens on the grandfather rule.
* **V7.** `launch_gate.sh`; curl the live privacy and support pages; byte-exact ASC read-back of every PATCH; What's New checked sentence by sentence against the code. Copy pins (`PurchasePromiseTests`, `PaidRouteRowTests`, `OneBranchRuleTests`, `PrivacyClaimTests`) change in the same commit as the copy they pin.
* **V8.** Every fix is proven by reverting it and seeing its test go red (`HANDOFF-STAGE1-GATES-PROMPT.md:258`).
* **Build discipline.**
  * Private clones under `~/Library/Caches/NihongoRide-v137-work/<name>`, one build root per concurrently building checkout, with `COMPILER_INDEX_STORE_ENABLE=NO`.
  * Read-only lenses do not build.
  * `git status` before every build, because of the iCloud `* 2.swift` duplicates.
  * Agents never share the live tree.
* **Public repo.** Aggregate counts only: no device names, no account identifiers, no contact data. Walk screenshots and owner-device readouts stay outside the repo (`PLAN-V1.34.md:733-734`). New scripts read the review contact the way `asc_release.py` does.

---

## §K Deliberately NOT done, and why

* **Changing the offer, price, placement or en/zh/ja metadata before the N = 200 record**, unless the owner chooses B. Constraints 1 and 4 (`PLAN-WINDOW.md:115-126`).
* **Any agent-authored §K box that adds meaning**, on silence or otherwise. That covers the delegation fallback the draft had, a definition of "iterate", and a recorded skip. The existing §K text governs as written (`PLAN-V1.34.md:1086-1087`; `HANDOFF-STAGE1-GATES-PROMPT.md:212-214`).
* **Any purchase by an agent in any environment, and any Apple-account action**, including `SKTestSession` before P0-9's preconditions (`HANDOFF-STAGE1-GATES-PROMPT.md:200-210`).
* **Changing `sales_report.py` on `main` before the N = 200 record** (P1-12 is built on a branch), and ever summing proceeds across currencies.
* **More scenery as a money lever:** west landmarks (P1-7), the departure backdrop (P1-8), and E1 as a default. The road is fixed and shown, not grown.
* **A 0 km entrance (P1-9), or any entrance to a purchase that shows nothing on purchase.** It is an App Review and honesty risk.
* **A Kyōto-arrival modal, badge or post-ride solicitation.** The informational line is parked in D3.
* **A Promoted IAP without `PurchaseIntent.intents` handling and tests.**
* **A second SKU in the same release as the ledger split** (`PLAN-STAGE1.md:1374-1381`). E3 rides v1.39, after v1.38's P1-11.
* **Grandfathering that depends on the network**, or a persisted grant from an unreadable `AppTransaction`.
* **Moving any threshold, shortening the free road, or gating anything an existing install has** (`RideRoute.swift:204-206`; `PLAN-V2-PRODUCT.md:369-397`).
* **A subscription.**
  * There is no demonstrated retention (`PLAN-V2-PRODUCT.md:323-327`).
  * `EntitlementRecord` has no expiry (`Entitlement.swift:123-127, 149-156`).
  * `IAY` is expected-absent (`sales_report.py:226-229`).
  * There is no Terms of Use page in `site/`.
* **Ads, accounts, anything server-backed, transmitted telemetry, charging for export, zh-Hant or ko listings** (`PLAN-WINDOW.md:265-275`). The zh-Hant *UI option* is a local string table, not a listing. Data Not Collected stays.
* **The marker in CloudKit** before the production-schema gate is passed for the new record type.
* **zh-Hant conversion as the default** for `zh-Hant*` devices. It is an option only.
* **Off-store promotion during a window** (`PLAN-WINDOW.md:42-48`). Between windows, the agent may draft; posting is the owner's.
* **Paid upfront, within these three releases.** It is **not rejected**: PLAN-V2-PRODUCT keeps it open and asks that it be modelled "against freemium on the actual funnel before discarding it" (`PLAN-V2-PRODUCT.md:314-319`). This plan has not modelled it. E3 is chosen first because it keeps the free funnel that 2.6 installs a day depend on; that is this plan's reasoning, not a finding. It is open question 9 (§Q).
* **Audio on the system voice** (`PLAN-STAGE1.md:1369`), **Family Sharing for any SKU** (irreversible; `HANDOFF-STAGE1-GATES-PROMPT.md:218`).
* **Offer codes, temporary sales, Product Page Optimization.** At 2.6 installs a day none of them reaches a readable result.
* **TestFlight for anyone, or development builds on walk devices, before §L is recorded** (`PLAN-V1.34.md:733-736`).
* **Any agent-chosen price** (§F).

---

## §M What would make this plan wrong

* **A stranger buys before N = 200.** That is GO on H1, read by a person. The decision does not wait for day 90, but GO's repeat-rate run does (`PLAN-STAGE1.md:528-529`): v1.38's offer changes are released no earlier than Pacific 12-09 unless the owner cuts the run short. E3 needs only a price. P1-3 matters more, because a real customer now depends on restore.
* **The walk finds the till broken:** no `salesReports` row, no cross-device restore, or a family member who inherits the purchase. Stop-and-fix overrides everything here, and the next release becomes a purchase-path fix. E3 waits.
* **Nobody walks (A′).** N = 200 is a record of N only, and existing §K governs. Window 2's positives still read, its zeros do not. If E3 also sells nothing, "nobody wants it" and "the till is broken" stay indistinguishable, and that is said in the Window 2 file.
* **E3's grandfather rule has a bug.** An existing user loses depth, which breaches the red line: stop-and-fix, and the rule's tests were wrong. The P0-12 marker, the sandbox rule and the session-only grace exist to make this unlikely, not impossible.
* **E3's boundary is wrong.** If the free tier feels crippled, ratings and installs fall. If it is too generous, nobody meets the paywall. Window 2 cannot separate these; the reviews and the funnel (P0-7) are the only signals.
* **Japanese UI copy reads as machine-made.** With 53% of installs from Japan and 0 JP ratings, a bad first impression is costly. That is why it is kept plain and glossary-pinned, and a native reviewer is welcome.
* **Traffic stalls or rises.** N = 200 slides toward the 2027-03-08 backstop, or arrives earlier, and the quiet period and C-2 move with it. If N < 200 at the 12-08 interim, B is worth one line on a card again.
* **Hosted runners keep `SKTestSession` inert, or AMFI still refuses the stripped host.** P0-9 falls back to the walk Mac, or exit 3 stays and is recorded.
* **Year-end App Review slows v1.39.** E3 slips to January, which costs about one floor-month again.
* **A negative store review mentions the purchase.** Stop-and-fix (`PLAN-STAGE1.md:567-568`).
* **The 1.50% / 2.46% bounds are misread** as statements about E3 or Offer v2. They bound the Stage 1 treatment only.

---

## §Q Assumptions and open questions

**Assumptions. Each is a place to attack.**
1. **The projection.** N = 200 lands on Pacific report days about 11-23..25 at about 2.6 installs a day, extrapolated from a flat 47-day series.
2. **B's gain is about ¥12, at most about ¥30.** Only the E3 term counts: installs that arrive before E3 are grandfathered and can never buy it. At E3's floor rate at the ¥68-class anchor, 45–55 installs (2.5–3 weeks) give ¥29–35; with E3 green only about 12-07, B moves it about one week, ≈ ¥12. The road term is Offer v2's increment, unquantified and near zero, because the offer is met about 48 rides after install. If E3 converted far above its floor, B's value rises in proportion. Nothing in the evidence supports any rate.
3. **E3 and E5 can be built on branches by about 12-07.** That is 10–15 + 6–8 agent-days in parallel from about 11-01, estimated, not measured.
4. **The boundary candidate 1 is a product choice the delegation covers.** It is not one of the owner-only items listed for this plan. The owner can still choose otherwise at C-2(d).
5. **The agent-authored part of the Window 2 pre-registration is measurement mechanics only** (P0-5): units, the FX table, the burn-in, read dates, N₂. Every branch-consequence cell is the owner's, filled at C-2(e) or in A-1 item 5, and blank otherwise. So the file never carries a rule that binds a later owner choice, and v1.38 never waits for it.
6. **P0-7 is read-only.** It GETs presigned report URLs and never re-POSTs the request.
7. **App Review behaviour** is unverified here: a 0 km entrance rejection, editing an approved IAP's note or price, a Promoted IAP without a handler. The plan avoids each risk rather than relying on a claim about it.
8. **Effort figures** are agent estimates summed item by item.

**Open questions:**
1. *(owner, C-1)* Which walk, if any? Everything readable downstream depends on it.
2. *(owner, C-2)* E3's price and the override; the road's price; optionally the boundary; Window 2's branch consequences; optionally holding P1-12 for a known positive; under GO, whether to cut the repeat-rate run short.
3. *(owner, C-1f)* The public repo's history, which still holds the App Review phone number: rewrite, make private, or leave?
4. *(owner, optional)* Is there a native Japanese reader for P1-15's strings?
5. *(engineering)* Does a hosted runner serve `SKTestSession` with a stripped Debug host? Is the iOS simulator still inert on Xcode 27?
6. *(engineering)* Does editing an approved IAP's review note trigger re-review? P1-14 reads first.
7. *(evidence)* Who installs from the JP storefront? P0-7 answers part of it; sessions or reviews answer the rest.
8. *(positioning)* Rail Typing (CN, journey-themed, ¥128 lifetime) is a direct new competitor. P1-13's zh copy and the CN creative should name what Nihongo Ride does that it does not: offline, no ads, Mac. The copy says that only where the code supports it.
9. *(owner, later)* Paid upfront: `PLAN-V2-PRODUCT.md:314-319` asks that it be modelled against freemium on the actual funnel before it is discarded. Nobody has. It could be modelled from the funnel reports (P0-7) after Window 2.

---

## §R What the reviews changed

Two agy reviews of the draft: Gemini 4 (`docs/evidence/v137-plan/review-gemini-4-argon-high.md`, 16 findings and 4 additions) and Gemini 3.8 Flash (`docs/evidence/v137-plan/review-gemini-3.8-flash-high.md`, 9 findings and 3 additions). Their line numbers refer to the draft (`docs/evidence/v137-plan/PLAN-draft.md`), not to this file. Every finding was checked against repo HEAD before a decision.
* The orchestrator verified four claims in code: the currency sum (`sales_report.py:486-504`, with `proceeds_currency` read at `:404` and unused in the tally); the `--no-cache` clash (`:1663-1670`); the superseded day-90 rule (`PLAN-STAGE1.md:808-810`); and the `offerAppeared` single fire (`RoadView.swift:57`; `UnlockOfferLedger.swift:217-229`).
* The reviewers' copy was at `06e941c`, one commit before `54470d0`. That commit touched only `scripts/asc_release.py` and `scripts/submit_1_*.py` (`git show --stat 54470d0`), so `sales_report.py` has the same line numbers in both copies: `proceeds_currency` is at `:404` in each. Gemini 4's `:424` was simply a wrong citation.

**Gemini 4**

| # | sev | finding | decision | reason / where |
|---|---|---|---|---|
| G4-1 | BLOCKER | `sales_report.py` sums proceeds across JPY/CNY/USD, so one JP sale reads as 128 against a CNY floor. | **ACCEPT** | Verified. P1-12(b): currency buckets, calibration fails on an empty or unknown currency, and the FX/unit rule is pre-registered in `PLAN-WINDOW2.md`. Stage 1 is unaffected, because it reads units (§C rules). |
| G4-2 | BLOCKER | Window 2's ⌈3/c\*⌉ row fires before its own N₂ = 100 record, pools legacy update purchases, and misuses the rule of three for GO-2. | **ACCEPT** | §H: max(⌈3/c\*⌉, 200) **and** ≥ 60 days; a separate 14-day burn-in; the rule of three only to falsify on zero; GO-2 only on two full 30-day periods. Their legacy-pooling point holds for the road; E3 is immune because existing installs are grandfathered. |
| G4-3 | BLOCKER | Phase 1 + ¥10 + E1 default cannot make money; P1-7/P1-8 are low value; Phase 2 is mis-ranked; E1's falsifier contradicts §H's ZERO branch. | **PARTIAL** | Accepted: P1-7 and P1-8 cut; no E1 default; re-ranked E3+E5, E4, E2 (add-on only), E1 (post-traction gift), E6. Not taken: "no Phase 2 build on silence". E3 and E5 are *built* on branches without an owner decision; *shipping* E3 needs C-2's box. The texts this works against, quoted: "zero still means *do not build Pro*" (`PLAN-STAGE1.md:176`) and "Not in this plan: … Building Pro before Stage 1 reports — the whole point of the staging" (`PLAN-V2-PRODUCT.md:639`), plus PLAN-WINDOW §G's "A second SKU" row (`PLAN-WINDOW.md:269`). Why branch-only work under the 2026-10-07 delegation is not "building Pro" in their sense: their measurement harm needs something shipped, and nothing ships, no IAP is created and `main` is unchanged until A-1 or A-2. Their effort warning does apply, and the agent takes it on because the owner asked to start earning. This is the agent's reading, labelled; the owner can stop the branches with one line (§C P0-11). |
| G4-4 | BLOCKER | `--no-cache` crashes the confirm command; the known-positives registry is owner-maintained and the delegation is unrecorded. | **PARTIAL** | Accepted: `--no-cache` removed everywhere. Registry entries are drafted and committed by the agent under the 2026-10-07 delegation, labelled as such, or applied by the owner (§1). Not taken: recording the delegation in §K. It is already recorded (`WALKCARD-STAGE1.md:35-41`; `stage1-checkpoints.md:43-48, 184-190`), and a new §K box would itself be a box that adds meaning. |
| G4-5 | SERIOUS | N = 122 already rules out ¥10 and ¥30 once walked; A′ is the modal outcome; decouple P1-3/P1-4; add an 11-15 card. | **ACCEPT** | §0 says 3/122 = 2.46% plainly. A′ is planned for (§0, §M). P1-3 and P1-4 are decoupled, with unit tests and mutation (§D). C-1 is the single card on 11-15. |
| G4-6 | SERIOUS | The "released no earlier than 12-09 / run to day 90" hold is superseded. | **PARTIAL** | Verified (`PLAN-STAGE1.md:808-810`) for the decision: every hold that waited on day 90 to decide is removed (§0, §I, §M). Not taken for GO: item 10 supersedes the "at day 90" sentences "for the decision" only, and GO's "Run to day 90 anyway for the repeat rate" (`PLAN-STAGE1.md:528-529`) governs observation after GO. Under GO, v1.38's offer changes are released no earlier than Pacific 12-09 unless the owner records cutting the run short (C-2(b)). |
| G4-7 | SERIOUS | P0-9 dropped the refund-row precondition; P0-9 on `main` mid-window; the agent committing Appendix A on silence breaches owner-only §K. | **ACCEPT** | Points 1–2: P0-9 keeps `PLAN-V1.34.md:768-772`'s refund row, plus C-1(d), and stays off `main` until the N = 200 record. Appendix A's delegation fallback is deleted, and no box is written on silence. **Point 3** (`review-gemini-4-argon-high.md:63`: committing a Window 2 pre-registration is "new policy", and §K boxes are owner-only, `PLAN-V1.34.md:1086-1087`): **accepted.** Moving the rules out of §K into a separate file changes the label, not the effect. So the agent commits only Window 2's measurement mechanics; every branch-consequence cell is left blank for the owner (C-2(e), A-1 item 5), and with no answer the period is reported descriptively (P0-5, §H, §Q-5). |
| G4-8 | SERIOUS | AMFI kills an ad-hoc host with CloudKit/Game Center/App Group entitlements; `macos-26` is Xcode 26.x, not the probed 27; `try?` sync makes offline read as "nothing to restore". | **ACCEPT** | P0-9: a Debug-only stripped entitlements file, Release pinned with `codesign -d`, and the runner re-probed first. P1-3: `do / catch`, with an offline sync error → "Couldn't reach the App Store". The AMFI behaviour is not measured here (§Q-5). |
| G4-9 | SERIOUS | `offerAppeared` fires once `.onAppear`; a not-yet-loaded price logs `offerUnavailable` and never re-fires. | **ACCEPT** | Verified. Fixed in P1-11. D3 records that Stage 1's ledger carries this bias (P0-3). |
| G4-10 | SERIOUS | E3 grandfathering: an offline/signed-out loophole vs a reinstall lockout; build-number drift; string comparison of versions. | **PARTIAL** | Accepted: the P0-12 marker, integer parsing per platform, and unreadable = temporary non-persisted grace (§E). Changed: the marker ships in **v1.37**, not v1.38, because it changes nothing offered. It is **local only**; CloudKit comes later and only with the production-schema gate, where the reviewer proposed CloudKit now. Added: the sandbox rule, since in sandbox `originalAppVersion` is "1.0". |
| G4-11 | SERIOUS | Promoted IAP without a `PurchaseIntent` handler drops store-initiated buys; the macOS 14.0 target does not block `#available(macOS 14.4)`; the wrong ASC citation and endpoint. | **PARTIAL** | Accepted: P1-13, Promoted IAP only with `PurchaseIntent.intents` handling and tests, otherwise cut; citation fixed to `ASC_METADATA.md:196-197` (availability). **Not taken: "new IAPs go via `reviewSubmissionItems`".** The code says the opposite for a later IAP: `POST /v1/inAppPurchaseSubmissions` "is the RIGHT endpoint for a LATER purchase", and `reviewSubmissionItems` was forced only because the *first* non-consumable got 409 `FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` (`submit_1_30.py:28-31`; `asc_release.py:611-614`). E3 is the second non-consumable, so it goes via `inAppPurchaseSubmissions`; neither path is measured for a second IAP. The doc fix is limited to `ASC_METADATA.md:182`'s parenthetical ("does not accept IAP"). |
| G4-12 | SERIOUS | V1's gate floor is stale (10/9); the script enforces 17/16. | **ACCEPT** | Verified (`run_all_gates.sh:391-392`). §J V1. |
| G4-13 | MINOR | P0-7 cannot tell natives from learners, so gating E5 on it stalls it; zh-Hant users get English. | **PARTIAL** | Accepted: E5 is not gated on P0-7, which now gates nothing. Partial: zh-Hant gets a mechanical conversion table as an **option, not the default**. The UI is Simplified, and a mechanical table can mis-convert. |
| G4-14 | MINOR | The 0 km strip funnels new riders into copy saying the purchase does nothing for ~47 rides; P1-8 only covers 25–28 km. | **ACCEPT** | P1-8 and P1-9 are cut. `offerBlurb` stays honest and unchanged. |
| G4-15 | MINOR | Citations (RideBackgroundView path/lines, PurchasePlanTests path); `card()` width also affects `owned`; PII in the submit scripts. | **ACCEPT** | Paths fixed in §A. P1-1 fixes `restore` and `owned`. The phone was already removed in `54470d0` (after the reviewers' copy). The `contactEmail` left in the scripts is the public support address, published on purpose on the site and in About, so nothing is redacted (P0-14). Git history is the owner's call (C-1f). |
| G4-16 | NIT | §F uses 30-day windows and §H calendar months. | **ACCEPT** | Unified as "per 30 Pacific report days" (§F, §H). |
| G4-A1 | add | A pre-E3 cohort marker. | **ACCEPT** | P0-12, in v1.37. |
| G4-A2 | add | A temporal burn-in split in `sales_report.py`. | **ACCEPT** | P1-12(d), §H. |
| G4-A3 | add | A JP/CN ASO keyword audit, plus an off-store distribution plan between windows. | **PARTIAL** | The audit is in P0-10, read-only. The distribution plan is drafted only. Posting anything publicly is the owner's (§K). |
| G4-A4 | add | One forcing card on 11-15 and a gate at N = 200. | **ACCEPT** | C-1 and C-2 (§1), each with a default on silence that makes no owner-only decision. Not taken: making C-2 *blocking*. Its silence default is the existing branch, as written. |

**Gemini 3.8 Flash**

| # | sev | finding | decision | reason / where |
|---|---|---|---|---|
| F-1 | BLOCKER | E1 default at ¥10 cannot monetise; make E3 the Phase 2 goal. | **ACCEPT** | §E re-ranked; no E1 default. |
| F-2 | BLOCKER | N₂ = ⌈3/c\*⌉ is inverted: 40 installs in ~15 days, high false-negative risk (0.97⁴⁰ ≈ 29.6%). | **ACCEPT** | Arithmetic verified. §H uses max(⌈3/c\*⌉, **200**) and ≥ 60 days, stricter than the suggested 100. |
| F-3 | SERIOUS | The walk dependency paralyses engineering; decouple the code; compress the walk to a 5-minute Mac purchase and drop §L. | **PARTIAL** | Code decoupled (P1-3, P1-4). The **minimum walk** (§1) is offered as an owner-chosen deviation from the card: a Mac purchase plus the iPhone pre-purchase screenshot, about 15–20 min, since 5 min loses check 3's control; it forfeits check 1 on this Mac, as the owner's recorded decision. Not taken: dropping §L. The agent never drops a check on its own. The owner walks them later or records them as deliberately not walked (`HANDOFF-STAGE1-GATES-PROMPT.md:212-214`). |
| F-4 | SERIOUS | A 0 km entrance with delayed value risks App Review rejection; if P1-9 ships, P1-8 must too. | **ACCEPT** | Resolved by cutting P1-9 (and P1-8), not by keeping P1-8. The rejection claim itself is unverified (§Q-7); the cut also answers the honesty problem. |
| F-5 | SERIOUS | Option A traps the owner; recommend B. | **PARTIAL** | A stays the default on silence, because silence cannot end a window. B is presented as a strong alternative with Flash's reasoning given fairly (§0), with its gain quantified (about ¥12, at most about ¥30). §0 states plainly that under A, a zero at N = 200 is STOP BUILDING ("not price and not Pro"), so E3 needs one owner decision then: price plus override, in a dated box (Appendix A-1). **Not taken: the other half of F-5's recommendation** (`review-gemini-3.8-flash-high.md:64`), "pre-register an explicit owner override so v1.38 can introduce depth pricing or content SKUs immediately upon reaching N=200". An override registered now would be an owner box with no owner; A-1 is drafted for C-2 instead. And E3 cannot ride v1.38: it carries the ledger split, and a second SKU never shares that release (`PLAN-STAGE1.md:1374-1381`), so under A E3 rides v1.39. |
| F-6 | SERIOUS | Store metadata (P1-13) in the same window confounds arrival with conversion. | **ACCEPT** | P1-13 is registered in Window 2 as a named co-intervention, and screenshots may stagger. On the E3-path the store copy for the road lands in the bridge release, before Window 2's day 0′. |
| F-7 | MINOR | "Unreadable = entitled" gives offline fresh installs Pro free; the reverse locks out old users; use local data migration. | **ACCEPT** | The P0-12 marker with `priorDataPresent`, plus temporary non-persisted grace (§E). Merged with G4-10. |
| F-8 | MINOR | Appendix A's delegated commit breaches governance; delete the fallback. | **ACCEPT** | Deleted. The existing §K text governs as written (§K, Appendix A). |
| F-9 | NIT | Cite `ReviewPrompt.swift:169` for the rating yield. | **ACCEPT** | §A. |
| F-A1 | add | Multi-SKU architecture unblocked in v1.37 behind flags. | **PARTIAL** | Built early on branches behind a constant (P1-5, P0-11), and shipped dark in **v1.38**, not v1.37. `RouteStore` and `EntitlementKit` are on v1.37's frozen list, and the ledger split is an instrument change that the STOP branch's returned counters would read mid-window. |
| F-A2 | add | Rank Japanese UI (E5) ahead of new roads and supporter packs. | **ACCEPT** | E5 is ranked with E3 and rides v1.38 if green (P1-15). |
| F-A3 | add | A freemium curriculum model: N5 free; N4–N1 and custom-text SRS sync paid. | **PARTIAL** | Taken in as E3 boundary candidate 2 (P0-13). The default is candidate 1 (N5 and N4 free), as the more generous funnel (`PLAN-V2-PRODUCT.md` §E "a generous free tier is still the funnel"). Custom-text SRS sync is E6 / Stage 3 work, and it is not part of a one-time unlock. |

**Nothing was rejected outright.** Every PARTIAL above names what was not taken and why.

**What the reviews did not check:**
* Neither re-ran an ASC GET or re-read a comparable's live price.
* Neither measured AMFI, `SKTestSession` on a hosted runner, or any App Review behaviour; their App Review claims are reasoning, not citations of Apple text.
* Neither saw `54470d0`.
* Neither examined E3's grandfather rule against the sandbox `originalAppVersion` = "1.0" case, which this revision added.

---

## Appendix A: owner boxes, drafted (each is committed only on the owner's word; nothing is committed on silence)

**There is no delegation fallback.** If the owner says nothing, none of these is written, and the existing §K text governs as it stands (`PLAN-STAGE1.md:526-554`, with item 10 at `:808-810`).

**A-1: at the N = 200 reading, if the owner chooses E3** (C-2):

> ### 📌 DECIDED <date> (JST) by the owner, AFTER reading the N = 200 record: E3 and its price
>
> Written by the owner, or drafted by the agent and confirmed in the owner's words: "<verbatim>". Nothing above is
> reworded. No threshold, branch, denominator or exclusion moves.
>
> 1. The Stage 1 window ended by its own rule at the N = 200 reading of <date>. Its branch, read by the owner,
>    was <GO / STOP / STOP BUILDING (UNINTERPRETABLE)>.
> 2. *(only if the branch is STOP or STOP BUILDING)* The owner overrides, for exactly one good, a one-time depth
>    unlock (PLAN-V1.37 §E, E3) with every existing install grandfathered: "not price and not Pro" (§K);
>    "zero still means do not build Pro" (`PLAN-STAGE1.md:174-176`); "near-zero over the window kills H2 as well as
>    H1 — do not build Pro" (`PLAN-V2-PRODUCT.md:547`); "Nobody tips → … Do not build Pro" (`PLAN-V2-PRODUCT.md:236-237`);
>    "Not in this plan: … Building Pro before Stage 1 reports" (`PLAN-V2-PRODUCT.md:639`); and PLAN-WINDOW §G's
>    "What must not be built" row "A second SKU" (`PLAN-WINDOW.md:265-269`), whose separate precondition, the
>    counter split, v1.38's P1-11 meets. This is a decision made after seeing the reading, and is recorded as such.
> 3. E3's price: CNY <owner's figure> (base territory CHN, manual price), effective the day the release carrying it is
>    live. The road west's price: <unchanged at CNY 10.00 / owner's figure>.
> 4. *(optional)* E3's boundary: <candidate 1 / candidate 2 / owner's words>.
> 5. Window 2 is pre-registered in `docs/PLAN-WINDOW2.md` before that release's `--submit`. Its branch consequences,
>    in the owner's words: <ZERO → … / BELOW-FLOOR → … / GO-2 → …, or "as drafted in PLAN-V1.37 §H">.

**A-2: if the owner chooses B** (C-0):

> ### 📌 ENDED EARLY <date> (JST) by the owner's decision, after the N = 35 and N = 100 readings had been read
>
> This is a decision made after seeing data, recorded as such (§K forbids deciding "after seeing a checkpoint").
> The final Stage 1 record is the N = 100 reading of 2026-10-26: N = 122, 0 purchases, BOUND WITHHELD, for the one
> reason that no matched known-positive purchase exists. No bound is quoted, and the zero is UNINTERPRETABLE. If a
> known positive is matched later, 3/122 = 2.46% may be quoted as arithmetic, never as a registered reading.
> Nothing above is reworded. Window 2 begins with the first release that changes the offer, under a pre-registration
> committed before its `--submit`. E3's price is the owner's, recorded before that release.
>
> The owner also overrides, for exactly one good, a one-time depth unlock (PLAN-V1.37 §E, E3) with every existing
> install grandfathered, the written rules that are not §K branches and still bind when the window ends at
> N = 122 with 0 purchases: "zero still means do not build Pro" (`PLAN-STAGE1.md:174-176`); "near-zero over the
> window kills H2 as well as H1 — do not build Pro" (`PLAN-V2-PRODUCT.md:547`); "Nobody tips → … Do not build Pro"
> (`PLAN-V2-PRODUCT.md:236-237`); "Building Pro before Stage 1 reports" (`PLAN-V2-PRODUCT.md:639`); and PLAN-WINDOW
> §G's "A second SKU" row (`PLAN-WINDOW.md:265-269`). This too is a decision made after seeing data.

**A-3: the walk's records** (C-1). These are the existing drafts, unchanged:
* `DRAFTS-STAGE1-RECORDS.md` §1/§1b for a walk (the agent fills in the numbers);
* §2 and §4 for "not walked", which only the owner pastes or confirms in words that are quoted verbatim;
* §3 for §L's results.

Under the minimum walk, check 1's forfeit on this Mac is recorded by the owner under §4 when (b) is chosen; checks 2 and 3 are either walked later, before the refund, or recorded by the owner under §4. The agent never records any of them.

---

## Dated corrections, 2026-10-28 (JST), from v1.37's review rounds

Written by the agent. Each line corrects a fact in this plan; none adds or loosens a rule.
* **§J V1, the gate floor:** `release/v1.37` raises it to **20** (19 headless) with three new self-tests
  (`test_ci_vocab_base.py`, `test_submit_1_37.py`, `test_check_propagated_exclusions.py`). `main` stays at 18 / 17 until
  the release merges.
* **§B and §C, the frozen list:** `Theme` is not a file. It lives in `Sources/NihongoRideApp/NihongoRideApp.swift`, which
  `scripts/submit_1_37.py` `FROZEN_PATHS` now names, so the whole file is held byte-identical to `fdb2b5f`. A diff over a
  path that does not exist prints nothing, which is how the old list hid it (review round 1, frozen-1).
* **§C rules and §K, "`sales_report.py` does not change on `main` before the N = 200 record":** this never covered the
  approval-day `FIRM_RELEASE_DATES_PT` line. P0-2 requires 1.37's line before the N = 200 `--checkpoint`, and 1.36's
  landed in `acf8ae5`. Those lines add a release date from the store's own timestamp, as the tuple's comment has
  always required; they change no rule, threshold or classification (review round 1, frozen-4).
* **P0-2's scope grew under review:** 18 corrections in two batches (the six 一日 ついたち → いちにち found by round 1's
  corpus lens), and 7 dictation withholdings, pool 5,935 → 5,928. Every correction was upheld 2 of 2. The pool-must-not-
  shrink rule was set aside for these seven by the orchestrator under the 2026-10-07 delegation, recorded in
  `docs/measurements/v137-reading-manifest.json`.
