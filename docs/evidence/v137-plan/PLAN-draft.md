# PLAN-V1.37: make the paid road worth buying, prove the till rings, then widen what is sold (v1.37 → v1.39)

*Combined plan, 2026-10-27 (JST), day 48 of the pre-registered window (day 0 = Pacific 2026-09-09). It merges Draft A (revenue first) and Draft B (measurement and risk first). The facts come from four read-only lenses: paid surface, rules, evidence and engineering. Nothing was built, nothing in the repo was written, and App Store Connect was read with GETs through `scripts/asc_api.sh` only. Every claim cites a file:line, an ASC GET or a URL. Proposed path: `docs/PLAN-V1.37.md`. Like PLAN-V1.34, it covers three releases, and each release still gets its own dated record when it ships. Gemini 4 Pro and Gemini 3.8 Flash (through agy) review it next. §Q lists the assumptions and open questions for them, and §R will record what they change.*

---

## 摘要（给 owner）

* **现在卖的东西。** 只有一个买断 IAP「西行之路 / 西への道 / The Road West」，价格 ¥10 / ¥150 / $0.99，都是最低价位。买到的是京都之后 8 段路的名字和配色，地标沿用免费路线已有的 4 种剪影。没有新词，没有新模式，没有新美术。
* **结果。** day 0 以来新装 N = 122，购买 0。你的 §K 已知阳性购买还没走，所以工具打印 BOUND WITHHELD，这个 0 现在读不出意思。我们分不清三种情况：没人想买、没人骑到京都、购买链路本身坏了。
* **冲突。** 价格、offer、入口和三个语言的商店元数据都被预注册窗口冻结，冻结到 N = 200（预计日本时间 11-25..27 能读到）或 2027-03-08，以先到者为准。
* **默认做法（A，不用你回复）。** 窗口按原规则跑到 N = 200。这四周把"让付费功能更好"的改动在分支上做完，决定一出就随 v1.38 发出（约 12-02 提交）。
  * 提前结束窗口（B）只快 1.5–3 周，按 ¥10 少赚不到 ¥25，代价是第一阶段唯一的数字永远读不出来。
  * 想选 B 的话说一个字"B"就行。
* **只有你能做、而且最值钱的 75 分钟：§K/§L 走查，建议 11-15 前做完。** 内容是一笔真实购买、退款，加三道检查（未登录、家庭共享、跨设备恢复）。
  * 走了，N = 200 时的 0 就能排除"每装机转化 ≥1.5%"，也就证明 ¥10 甚至 ¥30 都到不了你 ¥50/月的底线（§F）。
  * 不走，以后每一个"改进付费"的结果也都读不出来。
* **价格只由你定。** §F 有同类 app 的价格：中国区买断大多在 ¥66.80–228，最接近的竞品 Rail Typing 买断是 ¥128。我不提议任何价格，你不回答就保持 ¥10。
* **发布节奏。**
  * v1.37：约 11-10 提交，不碰任何付费面。
  * v1.38「Offer v2」：约 12-02 提交。内容包括预览、入口、AX5 缺陷、恢复购买反馈、西路专属地标、商店文案、统计仪表的产品维度，以及新的预注册。
  * v1.39：2027-01 中旬，做 Phase 2 的准备。
  * 第二个 SKU 最早在 Window 2 读数之后。
* **不做的事。** 订阅、广告、服务器、遥测、付费导出、窗口内改价，以及 agent 在任何环境下做购买。

---

## §0 What the owner decides, and what happens with no answer

| | **A: keep the window to N = 200 and build unreleased (default, recommended)** | **B: end the window now with a dated §K box** |
|---|---|---|
| When the money changes reach customers | v1.38, submitted about 2026-12-02 JST if the branch is STOP or STOP BUILDING. Under GO, released no earlier than Pacific 2026-12-09, because GO says "Run to day 90 anyway" (`docs/PLAN-STAGE1.md:526-530`). | About 1.5–3 weeks earlier for the in-app work. The Phase 1 build is about 17 agent-days (§D), so it is not ready much before about 11-20 either way. A price-only ASC change could go live any day, but prices are the owner's (§F). |
| Revenue given up by waiting | About 27–55 new installs see the old offer instead of Offer v2: 1.5–3 weeks at 2.6 installs a day (122 over 47 days, `docs/measurements/stage1-checkpoints.md:228-232`). At ¥8.42 net and an assumed 2–5% conversion that is **about ¥5–23**. | The same amount, gained. |
| What the N = 200 reading tells you | With the walk, a zero at N = 200 prints 3/N ≈ 1.5% per new install (0.96% against the ceiling, 3/314). That rules out the 7.6% the ¥50/month floor needs at ¥10 (`PLAN-STAGE1.md:145-167, 801-806`). Any stranger's purchase means GO. | Nothing. The final record stays N = 122, BOUND WITHHELD (`stage1-checkpoints.md:183-260`). |
| The pre-registration | Kept, together with five releases of registration work. | Voided. It must be recorded as a decision made after the N = 35 and N = 100 readings, which is the "degree of freedom" §K forbids (`PLAN-STAGE1.md:388-392`). The cost is "one paragraph in §K rather than a rebuild" (`docs/PLAN-WINDOW.md:345-351`). |
| Still needed | The walk (§1). | **The walk, still.** Without it, a zero after Offer v2 is just as unreadable. |

**Recommendation: A.**
1. Waiting costs under ¥25 at any assumed conversion up to 5%.
2. Phase 1 needs about three weeks of build and review anyway, so almost nothing waits on the calendar.
3. B gives up the only reading Stage 1 can produce and gains almost nothing in time.

**No answer means A.** A is the status quo: the window ends by its own rule (`PLAN-STAGE1.md:417-431`), and PLAN-V1.33 already defers the offer-screen work "to the first release after §K's decision fires" (`docs/PLAN-V1.33.md:68-75`).

**A without the walk (call it A′) is the worst of both.** N = 200 becomes "a record of N only" (`docs/PLAN-V1.34.md:1126-1128`), and the docs give that world no decision rule beyond the existing zero branch. Appendix A handles it with a box committed before the reading, never after.

---

## §1 The owner's critical path, batched on one card

| # | Owner-only action | When (JST) | Why it is on the critical path |
|---|---|---|---|
| **O-1** | **The walk:** §K's known-positive purchase, the refund, and §L's three gates (signed-out App Store, Family Sharing non-inheritance, cross-platform restore). Per `docs/WALKCARD-STAGE1.md`: about 65–75 min hands-on, plus about 5 min for the refund after the D+1/D+2 confirmation (`WALKCARD-STAGE1.md:13-32, 62-64`). It runs on whichever version is live; `EXPECTED_*` moves to 1.36 on its approval day (`docs/STATE-2026-10-27.md:30-36`). The agent does preflight, baseline, state reads, registry entries and `--confirm-known-positive --no-cache`. | **by 2026-11-15** | See the five reasons after this table. |
| O-2 | Optional: say "B" (§0). Silence means A. | any time before 11-20 | Decides whether v1.37 or v1.38 carries Offer v2. |
| O-3 | Optional: one word on the Appendix A box. Silence means only its restating parts are committed, labelled as the agent's consolidation (§Q-3). | by 11-20 | The box has to land before the N = 200 reading. |
| O-4 | Read §K's branch as a person when N = 200 fires (about 10 min; the agent drafts the record and lays out the branches). | about 11-25..27 | Owner-only (`PLAN-V1.34.md:1086-1087`). |
| O-5 | At the same sitting: (a) the price (§F; default unchanged), and whether it moves in v1.38, which overrides §K's "not price", or waits for Window 2; (b) the Phase 2 fork (§E; default E1); (c) whether the Kyōto-arrival line (P1-9b) ships. | at O-4 | Prices are owner inputs (`PLAN-V1.34.md:728, 1078`; `docs/PLAN-V2-PRODUCT.md:633-640`). The arrival line is a new entrance (`PLAN-STAGE1.md:73-76`). |
| O-6 | One yes/no on §E's signed store-gate harness (simulated `SKTestSession` purchases with no money and no Apple account, run on the walk Mac or a GitHub-hosted runner). | after O-1 | `PLAN-V1.34.md:1082` lists it as owner-only. HANDOFF §8 rule 1 forbids purchases "in any environment", including a local `.storekit` (`docs/HANDOFF-STAGE1-GATES-PROMPT.md:200-208`). |
| O-7 | Approve v1.38's ASC writes: metadata, screenshots, IAP review note, IAP image, promoted IAP, any price schedule. The agent runs `ListAgents`/`SendMessage` first. | at v1.38 submit | `HANDOFF-STAGE1-GATES-PROMPT.md:220`. |
| O-8 | Push the zh section of `site/support.html` (P0-6), and later any site copy that a second SKU makes false. | any time | The site is the owner's to push (`PLAN-V1.34.md:1085`). |
| optional | The D5 `ta_score` `totalPlayerCount` device errand; the moderated sessions (D2, 12–18 h). | after O-1 | These are the only routes to any arrival or "why" evidence (`PLAN-V1.34.md:723-738, 758-762`). They are not on the critical path. |

Why O-1 comes before everything else:
1. **It is the only thing that removes BOUND WITHHELD.** The tool withholds the bound for exactly one reason, the missing matched known-positive purchase (`stage1-checkpoints.md:228-246`).
2. **The till has never been seen to ring.** No production purchase has reached `salesReports`, and sandbox never does (`HANDOFF-STAGE1-GATES-PROMPT.md:200-208`). StoreKit has zero automated coverage on both platforms: all nine `StoreGateTests` skip (`scripts/run_store_gates.sh:136-144`; `docs/measurements/2026-09-17-sktestsession-probe.md:31-54`). Until a purchase is seen, "0 purchases" and "the purchase is broken" print the same line, and so would every improvement this plan ships.
3. **It reveals the macOS IAP report code**, which nobody has ever observed (`scripts/sales_report.py:221-225`).
4. **It protects paying customers.** The entitlement lives only in local UserDefaults (`Sources/EntitlementKit/Entitlement.swift:172`; `AppModel.swift:604-606`). Cross-device ownership therefore depends entirely on StoreKit's `currentEntitlements` (`RouteStore.swift:208-241`), and §L gates 2–3 are unwalked.
5. **It unblocks work.** The purchase-code changes (P1-3, P1-4), §E's harness (P0-9) and the instrument change (P1-12) all wait on it (`PLAN-V1.34.md:766-772, 1116`; `PLAN-STAGE1.md:891-892`). The purchase code has not changed since 751a37a (2026-09-17), so a walk on 1.35 or 1.36 observes the code customers run.

---

## §A The facts this plan starts from

| fact | source |
|---|---|
| One paid thing: non-consumable `com.jasonye.nihongoride.scenery.lifetime` (ASC 6806755720). `APPROVED`, familySharable false, contentHosting false. No promoted purchase, no IAP image, no offer codes. The app is free. | ASC GET 2026-10-27 (`inAppPurchasesV2`, `promotedPurchases`, `offerCodes`, `appPriceSchedule`); `Sources/NihongoRideApp/RouteStore.swift:69` |
| Price: one manual price, CNY 10.00 (net 8.42, base territory CHN). Auto-equalised JPY 150 (net 128) and USD 0.99 (net 0.84). 175 territories. | ASC GET `iapPriceSchedule`, `manualPrices`, `automaticPrices`, `inAppPurchaseAvailability` |
| IAP names: en "The Road West", ja 西への道, zh 西行之路. All approved. | ASC GET `inAppPurchaseLocalizations`; `docs/ASC_METADATA.md:187-189` |
| What it buys: 8 stretches after Kyōto, 大阪 28 km … 長崎 138 km. Each has a name, romaji, threshold, palette and one of the 4 existing landmark kinds. No words, modes or art assets. | `Sources/SceneryKit/RideRoute.swift:207-297`; `RideBackgroundView.swift:184-221` |
| A buyer sees nothing new until the next ride past 28 km, about 6 rides after Kyōto. Non-buyers stay on the 京都 night palette forever. | `AppModel.swift:1725-1730`; `RideRoute.swift:200-203, 323-325, 357-363` |
| Kyōto is at 25,000 m. That takes 48 Journey rides at N5, 33–34 in Sentence or Listen, and 10 or 4 in Practice. Verbs moves the odometer 0 m. The arrival rate is unmeasurable, and no ledger has ever been returned. | `PLAN-STAGE1.md:612-621, 271-275`; `UnlockOfferLedger.swift:16-22` |
| Two entrances: the last Settings card, "The road past Kyōto", at any distance; and the menu route strip, tappable only at 25 km or more, with stop names in English even in the zh UI. | `SettingsView.swift:174-206`; `MenuView.swift:620-631, 661-702` |
| The rating prompt yields for exactly the ride that crosses Kyōto (`openedANewOffer`). | `AppModel.swift:2530-2544` |
| Result: N = 122 (macOS 82 · iOS 40), 0 purchases, 0 refunds, BOUND WITHHELD (exit 5). | `stage1-checkpoints.md:228-246` |
| Since day 0, Japan is 65/122 (53%) and China 29 (24%); before day 0 it was China 42%, Japan 20%. macOS is 67% of new installs. The rate is flat at about 2.6 a day. The JP storefront has 0 ratings. | read-only parse of `~/Library/Application Support/NihongoRide-Stats/sales/*.tsv` (evidence lens); `https://itunes.apple.com/lookup?id=6777469778&country=jp` |
| The purchase path has zero automated coverage. Even when live, `StoreGateTests` call `Product.purchase()` and `AppStore.sync()` directly, not `RouteStore.purchase()` or `restore()`. The StoreKit → `PurchaseAnswer` translation is unobserved. | `Entitlement.swift:37-41`; `Tests/NihongoRideMacTests/StoreGateTests.swift:174-183, 249-261`; `PurchasePlanTests.swift:17-20` |
| Restore is `try? await AppStore.sync()` plus a settle loop, with no notice and no outcome. The buy button has no progress state. A thrown purchase shows the raw `localizedDescription`. | `RouteStore.swift:317-318, 371-393`; `RoadView.swift:189, 250-256, 282-283` |
| Measured AX5 defects, frozen: RoadView stretch rows; the buy button wrapping "One- / time / purcha / se"; the "Already bought it?" width; the Settings road row; the menu strip. `HorizontalTextFitTests` accepts 25 residues, six of them RoadView's. | `docs/PLAN-V1.33.md:69-75`; `Tests/NihongoRideAppTests/HorizontalTextFitTests.swift:263-279` |
| **Correction to PLAN-V1.34 §I:** the 2.70:1 figure is white on solid coral (primary buttons). The buy button is white on sky at 22%, computed at 8.0–9.4:1. The sub-AA text on the offer screen is the 11 pt boundary sentence (2.86–3.01:1) and the `Theme.dim` captions (3.91–4.24:1). All computed from source colours, not rendered pixels. | `RoadView.swift:86, 133, 184-186, 248, 316`; `NihongoRideApp.swift:273-285`; `PLAN-V1.34.md:1095` |
| **The product has two names in the zh UI:** 西の道 (with a Japanese の) in RoadView and Settings, but 西行之路 in the boundary sentence, the IAP and the CN listing. | `RoadView.swift:93, 163, 218, 268` vs `:314`; `SettingsView.swift:192`; https://apps.apple.com/cn/app/id6777469778 |
| The UI defaults to `en` on every device and never reads the locale. There is no Japanese UI. The zh strings are inline `zh ?` ternaries. | `Sources/SettingsKit/AppSettings.swift:15, 92, 230`; `SettingsView.swift:284-288` |
| The store never says what is sold. en/zh say "the one optional in-app purchase", ja says nothing, all three say Tokyo→Kyoto, and no promotional text is set. Screenshots are from the v1.1 era. | ASC GET 1.35 `appStoreVersionLocalizations`; `docs/ASC_METADATA.md:88, 201-216` |
| The IAP review note says "There is no other entry point", which has been false since the v1.30 menu strip. | ASC GET `/v2/inAppPurchases/6806755720`; `PLAN-STAGE1.md:73-95` |
| A second SKU is blocked in code. There is one static productID; one ledger key, where a mismatched productID is quarantined and overwritten; a quarantine key fixed to `defaultsKey + ".unreadable"`; an `UnlockOfferLedger` with no product dimension; and `sales_report.py` classifying purchases by type code only. | `RouteStore.swift:69, 117-120, 180, 365`; `Entitlement.swift:222, 224-242`; `UnlockOfferLedger.swift:52-53, 127, 135`; `sales_report.py:215-229` |
| Economics: the floor is ¥50/month. At ¥8.42 net that is 5.94 sales a month, about 7.6% of about 78 installs a month. §D already calls 8.2% "at or above the ceiling". | `PLAN-STAGE1.md:145-167, 1312-1330` |
| Only two reviews ever: a 2026-07-10 CN review asking for a one-time way to pay, written before the SKU existed, and a 2026-10-09 review praising no ads. | `PLAN-V2-PRODUCT.md:25-29`; `stage1-checkpoints.md:173, 267-283` |

**What the evidence cannot support:** any conversion rate, any count of Kyōto arrivals, any retention figure, or any claim that a different price or offer would convert at 2.6 installs a day.

---

## §B The conflict, and the facts that shape the plan more than the freeze does

**The freeze.**
* Constraint 1 freezes the offer, price and placement ("Voids the pre-registration").
* Constraint 4 freezes en-US, zh-Hans and ja store metadata (`PLAN-WINDOW.md:115-126`).
* §G forbids a second SKU until the counter is split, "never in the same release" (`PLAN-WINDOW.md:265-275`).
* v1.36 kept `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`, `RouteStore`, `EntitlementKit`, `Theme`, `ScaledFont` and the `.storekit` file byte-identical to `fdb2b5f` (`docs/PLAN-V1.36.md:22-26`).

**What is open:** modes, review, stats, widgets, UI, accessibility and content (`PLAN-WINDOW.md:128-129`), plus documents, and code built and held on branches.

**When the decision row fires.** It fires at "N = 200, or 2027-03-08, whichever comes first" (`PLAN-STAGE1.md:417-431`).
* 122/47 = 2.596 installs a day. 78 more are needed, which takes 30.05 days.
* The first Pacific report day with N ≥ 200 is about 11-23..25, readable about 11-25..27 JST.
* Cross-checks: (122−36)/32 = 2.69 a day gives 11-24; (122−68)/20 = 2.70 a day gives 11-23.
* This is a projection, not a commitment. Each registered walk install delays it by about 0.4 days. It lands before the 2026-12-08 interim record, which carries no decision.

**Four facts that shape the plan:**
1. **§K's branches are GO, STOP and STOP BUILDING / UNINTERPRETABLE. There is no ITERATE**, although the schedule table and the tool say "go / iterate / stop" (`PLAN-STAGE1.md:426, 526-554`).
   * STOP needs a returned counter from a stranger who reached Kyōto, and the ledger expects "under two and plausibly zero" of those (`UnlockOfferLedger.swift:20-21`).
   * So the most likely branch is STOP BUILDING, whose prescription is "instrumentation and placement, not price and not Pro".
   * Phase 1 below is built to that prescription, so it is legitimate under every branch. Under GO it waits for 12-09.
2. **¥10 scenery cannot reach the floor at today's traffic however well it is presented**, because it needs 7.6% of all installs. Phase 1 is necessary, since it makes the paid thing visible, legible and reliable, but it is not sufficient. Reaching ¥50/month needs a different good at a different price (§E, §F) or about 4× the traffic (`PLAN-STAGE1.md:166-167`). The plan says so rather than implying otherwise.
3. **Distribution is the binding term** (`PLAN-STAGE1.md:1320-1325`). Revenue = traffic × conversion × net. The store work (P1-13) moves the traffic term, and it is frozen until the decision.
4. **Every priced comparable sells learning content, levels, lines, modes or ad removal, met early. None sells scenery alone** (§F). This is an inference from list prices only.

---

## §C Phase 0: now until the decision fires (inside the window)

**Rules for this phase:**
* Anything that ships passes `PLAN-WINDOW` §A's two-clause test: it changes neither what a device is offered nor which devices arrive (`PLAN-WINDOW.md:22-29`).
* The frozen list stays byte-identical to `fdb2b5f`.
* Money work is built in private clones on a `release/v1.38` branch and **not merged to `main`** until the N = 200 record and the owner's branch reading are committed.
* `sales_report.py` does not change until the N = 200 record is written.
* No release ships in the quiet period: from the day after v1.37 is submitted until the N = 200 record. This keeps release-day bumps (1.18×) out of the decision reading, following the v1.36 hold precedent (`PLAN-V1.36.md:798-815`).

| id | what | why | size (agent-days) | verify / registered |
|---|---|---|---|---|
| **P0-1** | **v1.36 approval-day chores** (`STATE-2026-10-27.md:30-36`): `FIRM_RELEASE_DATES_PT` and its test pin; `stage1_walk.py` `EXPECTED_*` → 1.36 / 61 / 62 with fixtures; walk card and DRAFTS; cadence row; STATE and memory; `review_watch`. Then the agent half of O-1. | The walk must observe the binary customers run (`WALKCARD-STAGE1.md` §1). | 0.25 + 0.5 | `stage1_walk.py preflight` exit 0; `test_sales_report.py` green; `--confirm-known-positive` exit 0 with no `WARNING` before the registry entry (on a `WARNING`, stop and show the owner). |
| **P0-2** | **v1.37, the open-surface release:** `n2-b277` 六十キロ and the 12 out-of-table number and counter sentences, each corrected by ear and upheld 2 of 2; the 点 row's tolerances; the CI corpus check on cancelled pushes; a removed word's `accessibilityValue` (`STATE-2026-10-27.md:67-73`). Nothing on the frozen list. | It fixes taught errors and keeps the cadence, a registered covariate (`PLAN-ITERATION.md` §G). | 2 · 1.5 · 0.5 | §J V1–V4, V6–V8. `road.png`, `road-iap-review.png` and `menu.png` byte-identical. A §K constraint-3 box before `--submit` (direction neutral, cadence line), in the shape of the 2026-10-26 box (`PLAN-STAGE1.md:1034-1060`). |
| **P0-3** | **`docs/STAGE2-DECISION-PACK.md` (D3)**, as specified and never written: the §E fork × §K's branches with every decision cell blank (`grep -c DECIDED` = 0); the day-91 list; the readings it shares data with; this plan's §D as the default next release; the open choices O-5(a–c) and P1-8's two variants. | `PLAN-V1.34.md:740-749`; `PLAN-V1.36.md:13, 253`. The N = 200 reading needs it on the table. | 1.5 | An adversarial lens checks every cited line. The cells stay blank. |
| **P0-4** | **Pricing brief:** §F's tables with every URL, CNY/JPY/USD, and the floor arithmetic. No price is proposed. | O-5(a) needs data, and an agent invents no prices (`PLAN-V1.34.md:1078`). | 0.5 | Each figure re-read from its public page on the day it is filed. |
| **P0-5** | **Window 2 pre-registration draft** (§H shape), committed before v1.38's `--submit`. | One treatment per window, fixed in advance (`PLAN-V2-PRODUCT.md:550-555`). | 0.5 | — |
| **P0-6** | **zh section of `site/support.html`**, drafted in `site/` for the owner to push (O-8). | "the one half a paying Chinese customer would actually hit" (`PLAN-V2-PRODUCT.md:356-366`). It touches neither clause. | 0.25 | The live page is curled after the owner pushes. |
| **P0-7** | **Post-day-0 funnel, read-only:** `scripts/acquisition_funnel.py` with `ASC_ANALYTICS_REQUEST=c57c770b-faac-4b80-9bb7-354ed6c66f92`, split by territory and platform. Inputs: App Store Discovery and Engagement daily for 09-21..10-25; Installation and Deletion daily for 09-21..10-08; the monthly App Sessions instance. Each report is used only if a calibration shows it usable. Aggregate counts only, in `docs/measurements/v137-funnel-post-day0.md`. | The ja listing is a registered co-intervention (`PLAN-STAGE1.md:571-580`). Japan is 53% of installs with 0 ratings, and who they are decides E5. The engagement reports were unusable on 2026-08-30 (`PLAN-STAGE1.md:14-22`); the base is about 2.4× larger now, so re-test rather than assume. | 0.5 | The script's own calibration. Every figure quoted with its report instance and processing date. See §Q-6 on the presigned URLs. |
| **P0-8** | **Appendix A box**, committed before the N = 200 reading (O-3). | `PLAN-V1.34.md:1126-1128`. Writing it after the reading is the degree of freedom §K forbids. | 0.25 | Nothing above it is reworded. |
| **P0-9** | **After O-1 and O-6 only: §E, the purchase path's first automated observation** (`PLAN-V1.34.md:766-787`). It signs the macOS test host with `get-task-allow`, runs the nine gates *executed* with one mutated red, adds the Octane-config `trap` in `run_store_gates.sh`, and gets `stage1_walk.py preflight` to exit 0. Plus a 0.5-day iOS re-probe on Xcode 27. The preferred runner is a separate workflow on the free macos-26 GitHub runner, which isolates the Octane config from the walk Mac (`docs/measurements/2026-09-17-sktestsession-probe.md:45-51, 97-101`; `.github/workflows/gates.yml:47`; https://docs.github.com/en/billing/concepts/product-billing/github-actions). The walk Mac is the fallback. | There is zero automated coverage on both platforms. The harness is test infrastructure: it does not change the binary and touches no frozen source, so it lands on `main` when green. | 1 + 0.5 CI + 0.5 iOS | **Falsifier:** if hosted runners keep `SKTestSession` inert, record it in the probe doc and fall back. Unmeasured: whether the real bundle id goes live with `get-task-allow` at all. |
| **P0-10** | **Store creative, designed and not uploaded:** the CN search-result creative (icon, title, subtitle, first two screenshots), plus en/zh/ja screenshots that show the road, one paid stretch labelled as paid, and the offer. Filed under `docs/store/drafts/`, with a dated GET of the three locales as the baseline. | "designed during the window and shipped on day 91" (`PLAN-WINDOW.md:302-306`). Nothing on the store shows what is sold. | 2 (optional) | — until P1-13 ships. |
| **P0-11** | **Phase 1, built on branches and held:** P1-1, P1-2, P1-6, P1-7, P1-8, P1-9, P1-10, P1-11 and P1-13's copy. **Branch only until O-1 is recorded:** P1-3 and P1-4. **Starts only after the N = 200 record:** P1-12. | Already dated "the first release after §K's decision fires" (`PLAN-V1.33.md:68-75`). Built now, nothing waits on engineering when the row fires. | counted in §D | Each branch passes §J before it is called done, and is rebased after v1.37 ships. |

**Deliberately held even though it arguably passes the two-clause test:** the buyer-only scenery work (P1-7). There are zero buyers and no preview, so shipping it early cannot move a purchase. It would only invite an argument over constraint 1. It ships with P1-6, so the preview shows it from day one.

**Phase 0 total:** about 6 agent-days plus v1.37 (4), with P0-9 (2) after the walk and P0-10 (2) optional. The Phase 1 branch work runs in parallel.

---

## §D Phase 1: at the decision (v1.38, "Offer v2")

**What it is.** One registered package, read as a package: at about 2.6 installs a day, testing the parts one by one costs about 3 months each. It follows §K's STOP BUILDING prescription (instrumentation and placement) at today's price, unless the owner overrides it in O-5(a).

**Preconditions:**
* the N = 200 record is committed and O-4 is done;
* the Window 2 pre-registration is committed before `--submit`;
* for P1-3 and P1-4, O-1 is recorded;
* for P1-12, the N = 200 record is written.

| id | what | why (evidence) | size | verify | measured |
|---|---|---|---|---|---|
| **P1-1** | **The offer screen's measured defects.** The six RoadView text-fit residues and the buy button at AX5, fixed the house way (stack vertically at accessibility sizes, or a `FlowLayout`; never a raised ceiling). The "Already bought it?" width: test first the hypothesis that `card()` applies `.panel()` before `.frame(maxWidth: .infinity)` (`RoadView.swift:341-350`; `NihongoRideApp.swift:290-297`). The Settings road row at AX5. The menu strip's stop names localised in zh. The boundary sentence and dim captions raised to ≥ 4.5:1. | `PLAN-V1.33.md:69-75`; §A contrast row. A large-text rider meets a broken buy button. | 2.0 + 0.5 AX5 pass | `HorizontalTextFitTests.accepted` **25 → 19**, only ever lowered. Contrast **measured on rendered pixels**. V2 with intended differences named in advance; V3; V4. | Window 2 package |
| **P1-2** | **One name for the product:** 西行之路 in zh everywhere, matching the IAP and the CN listing. "The Road West" in en. Pinned by `PurchasePromiseTests`. | §A: 西の道 vs 西行之路. | 0.25 | The test pins both names; mutating one string goes red. | package |
| **P1-3** | **Purchase and restore feedback** *(needs O-1)*. A pure `restorePlan`, table-tested like `purchasePlan`, with three outcomes: "Restored", "Nothing to restore on this Apple Account", "Couldn't reach the App Store". A progress or disabled state on Buy and Restore. Thrown errors shown as a localised sentence. The ledger records the restore outcome. | `RouteStore.swift:371-374`; `RoadView.swift:189, 282-283`. A buyer whose restore fails sees nothing, and a negative purchase review is §K's only stop-and-fix guardrail (`PLAN-STAGE1.md:567-568`). | 1.0 | Plan table tests. V5 once P0-9 is live. Optional 5-minute owner check on the refunded walk account: Restore must show "nothing to restore". | new event `restoreFinished(found/none/error)` |
| **P1-4** | **A seam for StoreKit result → `PurchaseAnswer`** *(needs O-1)*, with tests (`.pending` must never read as `.userCancelled`), plus `StoreGateTests` that drive `RouteStore.purchase()` and `restore()` themselves. | `PurchasePlanTests.swift:17-20`; `StoreGateTests.swift:174-183, 249-261`; deferred "until the walk" (`PLAN-V1.34.md:1116`). | 0.5 | Swap pending and cancel → red. | — |
| **P1-5** | *(reserved: §E's harness is P0-9; it is test infrastructure and lands before v1.38)* | | | **v1.38 `--submit` requires P0-9 green if P1-3 or P1-4 ship.** | |
| **P1-6** | **Show what is sold.** The west card's eight locked rows (`RoadView.swift:92-102`) become rendered thumbnails: `RideBackgroundView` at a fixed progress, one per stretch, each with a VoiceOver label. The copy names the goods concretely ("eight cities from Ōsaka to Nagasaki, 113 km past Kyōto"); it mentions landmarks only if P1-7 ships. The boundary sentence stays. | Nothing previews the paid scenery (`Screenshot.swift:307-317` is a developer capture). | 1.5 | Each preview matches the entitled ride render pixel for pixel at the same progress, so the preview is the product. `PurchasePromiseTests` and `PaidRouteRowTests` change in the same commit as the copy. The free Tōkaidō frozen sweep stays green (`PLAN-STAGE1.md:1169-1171`). | new event `previewAppeared` per bucket |
| **P1-7** | **The paid road gets its own content:** 3–4 west-specific landmark kinds drawn in code (e.g. a strait bridge, a harbour, a pagoda), tinted by the palettes' existing contrast rules. **No memorial sites** (not the A-Bomb Dome). The Tōkaidō's four kinds are untouched. `westStages`' names, romaji and `startMetres` stay byte-identical and are pinned by a test ("These thresholds are what somebody PAID for", `RideRoute.swift:204-206`). *First to cut.* | 8 palettes on 4 reused silhouettes is thin value (`RideRoute.swift:44-52`). This is the cheapest way to make what is already sold worth more, which is the owner's literal request. | 2.0 | Contact sheet of all 16 stretches, en/zh, every intended difference named; a native-eye check of each landmark; the frozen-road sweep. | package |
| **P1-8** | **Immediate payoff on purchase.** Today a buyer at 25.0–28.0 km sees nothing until Ōsaka. Choose one variant in the D3 pack: a one-time "departure" backdrop on the next ride, or a westbound variant of the Kyōto stretch for owners. No distance moves. *Second to cut.* | `AppModel.swift:1725-1730`; `RideRoute.swift:323-325`; "the difference between a purchase and a refund" (`RoadView.swift:164-166`). | 1.0 | A ride test that crosses the purchase; V3. | refunds over Window 2 |
| **P1-9** | **Placement: the menu strip opens the Road screen at every distance**, not only at 25 km or more (`MenuView.swift:661-695`). Before Kyōto it shows progress, the preview and the distance-aware blurb that already exists (`RoadView.swift:259-270`). No price, badge or modal on the strip. | It is §K's prescribed job after an uninterpretable zero. Today the only non-Settings entrance is 48 rides away. The four placement clauses stay asserted (`PLAN-STAGE1.md:113-116`). | 1.0 | `PaidRouteRowTests` updated with its clauses kept; placement suite (V4); the rating yield re-tested with its paired control (`PLAN-STAGE1.md:134-141`). | `menuRouteEntranceAppeared` now counts from 0 km, a registered change of meaning |
| **P1-9b** | **Optional, owner's choice at O-5(c):** one line on the results screen of the ride that crosses Kyōto, once per device, with a button to the Road screen. No modal, no badge. | `PLAN-STAGE1.md:73-76` calls arrival "the one moment where 'the road continues' is information rather than solicitation … a Stage 2 question". Draft B rejected any post-ride solicitation, so this is the owner's call. | 0.5 | A test that the arrival line and the rating prompt never co-occur in one run, checked on the time axis as well as the screen axis. | new ledger event |
| **P1-10** | **The UI language for fresh installs follows the device:** a first preferred language of `zh-Hans*` → `zh`, everything else `en`. Existing installs keep their saved choice. `zh-Hant` stays `en` as a recorded choice, because the zh UI is Simplified. | `AppSettings.swift:15, 92, 230`. China was 42–48% of installs before day 0 and met an English offer. | 0.5 | Tests for a fresh vs an existing setting; V2 in zh. | split by territory |
| **P1-11** | **The instrument for any second offer.** `UnlockOfferLedger` format v2 with a product dimension: decode v1 by padding, never truncate; existing counts migrate under the road's id. A quarantine key per ledger key. About's counter text made readable in both languages. **Ships here so that no second SKU ever shares its release** (`PLAN-STAGE1.md:1374-1381`). | §A second-SKU blockers; `Entitlement.swift:222, 236-238`; `PLAN-V1.33.md:76-77`. | 1.5 | v1→v2 decode tests including a short array; a truncating decode mutated → red; `shareableSummary`'s kyoto line pinned. | the ledger itself |
| **P1-12** | **`sales_report.py` learns the SKU** *(starts only after the N = 200 record)*. A SKU column; the road SKU pinned; an unknown SKU fails calibration; `--day0` / cohort support for Window 2. | `sales_report.py:215-229, 431-447`. An instrument change waits for the known positive (`PLAN-STAGE1.md:891-892`) and for the reading, so the instrument that decides Stage 1 is the one it was registered with. | 1.5 | Reproduces the N = 100 and N = 200 readings byte for byte; `--confirm-known-positive` still matches the walk's purchase; two SKUs never pool. | the instrument |
| **P1-13** | **The store says what is sold.** en/zh/ja descriptions and promotional text name the road west (Kyōto→Nagasaki, one-time), with the ja copy reviewed by a native. P0-10's screenshots and CN creative. An IAP promotional image. A promoted IAP on **iOS only**: `PurchaseIntent` needs macOS 14.4+ and the macOS target is 14.0 (`project.yml:137, 276`; https://developer.apple.com/documentation/storekit/purchaseintent). Mac support is to be verified (§Q-8). | ASC GET 1.35 localizations; `ASC_METADATA.md:201-216`; `PLAN-WINDOW.md:302-306`. It is also the only lever on traffic. | 3.0 | Byte-exact ASC read-back of every PATCH; the copy checked sentence by sentence against the code (V7). **Cut rule:** screenshots may follow in the next version; the binary does not wait. | a registered co-intervention; `acquisition_funnel.py` by territory |
| **P1-14** | **The IAP review note made true** (both entrances, plus P1-9's change); the app-level review notes name the new placement. Read first whether editing an approved IAP's note triggers re-review. | ASC GET reviewNote; `MenuView.swift:661-695`. | 0.1 | read-back | — |

**Totals:**
* **Build: about 16.9 agent-days.** That is P1-1…P1-14 summed, with P1-9b included and P0-9 counted in Phase 0. About 12 of those days can be built on branches before the decision.
* Verify and review: 3. Release: 0.5.

**Cut rule.** Anything not green with its tests by 11-30 moves whole to v1.39, in this order: P1-7, then P1-8, then P1-13's screenshots, then P1-9b. P1-1, P1-2, P1-11 and P1-12 never slip, because they are the defects and the instrument. P1-3 and P1-4 ship only with a recorded walk and a green P0-9: "purchase code changed mid-window without a walk observing it; the walk first" (`PLAN-V1.34.md:1116`).

**Non-money day-91 items** ride v1.38 only if they fit under the cut rule; otherwise they go to v1.39. They are the Settings sync caption, the denied-reminder notice, About copy, the menu credit line and the zh Practice screenshot (`PLAN-V1.36.md:241-245`; `PLAN-V1.34.md:1093-1102`).

---

## §E Phase 2: new revenue (v1.39 onward): options, with what each needs

Pick one. "Choosing none of them and shipping a bit of each is the failure mode" (`PLAN-V2-PRODUCT.md:407-419`). The D3 pack holds the blank cells, and the owner picks at most one primary option at O-5(b).

| | option | evidence | agent-days | risk / App Review / privacy | falsifier (pre-registered before code) |
|---|---|---|---|---|---|
| **E1** | **A second road inside the existing SKU, advertised as part of it** (default) | §N values a road at ¥0 as a separate good, but it raises value per ¥ (`PLAN-STAGE1.md` §N). "A gift keeps its option value" (`PLAN-STAGE1.md:1196-1198`; `RoadView.swift:309-315`). | about 3 per road, plus generalising `RideRoute.stages(westOpen:)` (`RideRoute.swift:323-324`; `AppModel.swift:1725`) | Low. Thresholds are permanent once shipped; only finished roads are promised; the boundary promise must not widen. The IAP description edit in 3 locales probably rides a version's review (verify). | It is not separable from Phase 1 at 2.6 a day; it is a value bet, not an experiment. Do it only if Window 2 shows ≥ 1 purchase, or as the default when nothing else is chosen. |
| **E2** | **Supporter Pack** (a second non-consumable that gates nothing), fork option 1 | The only willingness-to-pay statement asked for a one-time way to pay (`PLAN-V2-PRODUCT.md:25-29`). Patronage comparables: Typing Land $4.99, renshuu's supporter tiers. | 3–5: generalise `RouteStore`; a per-SKU defaults key; P1-11 and P1-12 already shipped; update `PrivacyClaimTests`, `PurchasePromiseTests`, `PaidRouteRowTests`, `OneBranchRuleTests` and `stage1_walk.py`'s constants | The new IAP needs an availability record or it is silently unbuyable (`ASC_METADATA.md:194-195`). Submitted via `POST /v1/inAppPurchaseSubmissions`; 3 localisations and a review screenshot; the Family Sharing choice is irreversible. "The one optional in-app purchase" becomes false in `site/privacy.html:31, 69`, `site/support.html:43` and the en-US description (owner pushes). §N says no second SKU pays for itself (`PLAN-STAGE1.md:1314-1326`). | Zero supporter units at Window 2's decision, with the known positive, stops patronage (`PLAN-V2-PRODUCT.md:547`). |
| **E3** | **A complete free sampler for new installs plus one non-consumable that unlocks depth; existing installs grandfathered** (fork option 2) | Every priced comparable gates learning content met early (§F). It is the only option whose arithmetic reaches the floor at today's traffic: about 1.1% of installs at a ¥68-class tier vs 7.6% at ¥10. | 10–15, design first | **High.** A grandfathering bug takes something from an existing user, which breaches the red line. `AppTransaction.originalAppVersion` is `CFBundleShortVersionString` on macOS but `CFBundleVersion` on iOS, and "1.0" in sandbox (https://developer.apple.com/documentation/storekit/apptransaction/originalappversion), so it needs two predicates. `AppTransaction` was decided against because it throws offline (`PLAN-STAGE1.md:279-283`); unreadable must mean entitled (`PLAN-V2-PRODUCT.md:384-397`). It also shrinks the free funnel while traffic is the binding term. | Pre-register an N where 3/N is below the floor rate (about 273 installs, about 3.5 months). **It needs an owner override** of "zero still means do not build Pro" (`PLAN-STAGE1.md:174-176`; `PLAN-V2-PRODUCT.md:231-236`) if the decision lands on a zero, recorded in a dated box. Earliest v1.40. |
| **E4** | **Finite content packs** (e.g. per level) | Kanji Study sells levels at $9.99–14.99 and ¥1,500–4,000 (https://apps.apple.com/us/app/kanji-study-learn-japanese/id1078107994). "Discrete finite packs, priced individually" is the only honest form (`PLAN-V2-PRODUCT.md:306-310`). | 5–10 per pack, plus the reading-review pipeline | Medium. Content quality is this project's hardest-won property. The boundary sentence currently excludes "content packs" from the road SKU (`RoadView.swift:316`), so this is a separate SKU (E2's engineering). | Zero sales over the registered cohort means do not build a second pack. |
| **E5** | **Japanese UI** (a conversion enabler, not a SKU) | 53% of new installs are from Japan and meet an English UI and offer. | 6–10 (the inline ternaries, plus a native review) | Medium. The audience is unknown: natives practising romaji, or learners living in Japan. | Gate it on P0-7, then pre-register the JP-share and JP-conversion delta, split by territory. |
| **E6** | **F1 paid workflow** (pasted Japanese with SRS and sync) | Fork option 3; the bounded half shipped free (`PLAN-WINDOW.md:277-300`). | 80–120 h (`PLAN-STAGE1.md:1371`); `DESIGN-F1-SRS.md` first | Medium; it changes ride distance. | "Fewer than 2 of n pasted anything → shelved" (`PLAN-V1.34.md:742-745`). Needs the sessions. Stage 3. |

**Recommended sequence.** v1.38 ships P1-11, so v1.39 can carry E1 (the default) or prepare E2 behind a constant. A second SKU goes live no earlier than the release after P1-11 *and* after Window 2's decision. E3 is the owner's strategic fork, decided at the N = 200 reading with the D3 pack. If chosen, it is designed and proven offline during Window 2 and ships no earlier than v1.40.

---

## §F Pricing: the owner's decision, with data

**No price is proposed. An agent invents no prices** (`PLAN-V1.34.md:1078`; `PLAN-V2-PRODUCT.md:633-640`).

**Comparables** (list prices only, not revenue; public App Store pages, read 2026-10-27):

| app | storefront | what is paid for | price | URL |
|---|---|---|---|---|
| Rail Typing – 打字学日语 (typing along real lines, Kyoto included: the closest concept, launched Oct 5) | CN | all lines, one line free | ¥12/mo · ¥68/yr · **¥128 lifetime** | https://apps.apple.com/cn/app/id6817686826 |
| 日语打字通 | CN | VIP | ¥6.80–16.80 passes · **¥66.80 permanent** | https://apps.apple.com/cn/app/id6783668620 |
| TypeAll-打字菌 | CN | full | ¥12/mo · ¥38/yr · **¥68 lifetime** | https://apps.apple.com/cn/app/id6767579225 |
| MARU日语五十音特训 | CN | ad removal + modes | **¥148 permanent** | https://apps.apple.com/cn/app/id1208009110 |
| MOJi辞書 | CN | membership | ¥12/mo – ¥58/yr · ¥228 permanent | https://apps.apple.com/cn/app/id1021094295 |
| Kana – type japanese | US | full | $0.99/wk · $9.99/yr · $19.99–24.99 lifetime | https://apps.apple.com/us/app/kana-type-japanese/id6744024458 |
| Kanji Study | US / JP | per level | $9.99–14.99, all $29.99 · JP ¥1,500–4,000 | https://apps.apple.com/us/app/kanji-study-learn-japanese/id1078107994 |
| Typing Land | US | donation-style unlock | $4.99 | https://apps.apple.com/us/app/typing-land/id1568264476 |
| AnkiMobile | US/JP/CN | paid upfront | $24.99 / ¥4,000 / CN ¥168 | https://itunes.apple.com/lookup?id=373493387&country=cn |
| さくらやタイピング練習LITE | JP | ad removal | ¥900/mo | https://apps.apple.com/jp/app/id1545885771 |

Free kana apps with no IAP at all also exist, e.g. Kana – Hiragana and Katakana and MOJiKana (https://apps.apple.com/us/app/kana-hiragana-and-katakana/id1454200955; https://apps.apple.com/cn/app/id6447672905).

**Arithmetic, not a recommendation.**
* Net is scaled from the measured ¥10 → ¥8.42. The exact figure, and whether each anchor is an Apple CNY price point, comes from an ASC GET at decision time.
* Installs are about 77.9 a month.
* The last column assumes demand does not rise with price, so a matched-zero bound at ¥10 also caps conversion at any higher price for the *same* good and placement.

| CNY | anchor | net ≈ | sales/month for ¥50 | share of installs | ruled out by a matched N = 200 zero (< 1.5%)? |
|---|---|---|---|---|---|
| 10 | today | 8.42 | 5.94 | **7.6%** | yes |
| 18 | — | 15.16 | 3.30 | 4.2% | yes |
| 30 | §D's row (`PLAN-STAGE1.md:160`) | 25.26 | 1.98 | 2.5% | yes |
| 68 | TypeAll lifetime / 日语打字通 ¥66.80 | 57.26 | 0.87 | 1.1% | no |
| 128 | Rail Typing lifetime | 107.78 | 0.46 | 0.6% | no |

**What the data says and does not say.**
* Every comparable charges for *learning*, not scenery.
* ¥10 for a cosmetic reached after about 48 rides sits below every comparable's price structure.
* Nothing here shows a higher price on the *same* good would convert at 2.6 installs a day.
* The inference, offered only as an inference: a price well above ¥10 is honest only with a thicker package (P1-6/P1-7 at least, E3/E4 at most).

**O-5(a)'s choices** (default: no change):
* **Price stays for v1.38.** This follows §K's "not price". Window 2 isolates placement plus value, and the price question goes to Window 3, about 2–3 months later.
* **Price moves in v1.38.** This overrides the branch and is recorded in a dated box before `--submit`. It reaches the floor question faster, but Window 2 then confounds price with placement.
* **Road stays at ¥10, E3 priced separately.**

**Mechanics.**
* No binary is needed: the offer shows `product.displayPrice` (`RoadView.swift:179`).
* It is an ASC write to the CHN base-territory manual price, scheduled to take effect the day v1.38 goes live so the treatment starts on one day (https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases/).
* Update the hard-coded "CNY 10.00" in `scripts/submit_1_30.py:202`, `xcode/NihongoRide.storekit:8` and the review notes.

---

## §H Measurement: the Window 2 pre-registration (shape; filled in by P0-5)

* **Revenue metric:** net proceeds per Pacific month from `sales_report.py`, against the ¥50/month floor (`PLAN-STAGE1.md:145-150`).
* **Secondary metrics:** net purchases per 100 new installs, split by territory and platform; refunds as absolute counts under the existing ceiling.
* **Treatment:** v1.38's package, by name. Its components will not be separable at 2.6 a day, and that is said now, not discovered later.
* **Day 0′:** the first Pacific day both platforms are live on 1.38, with per-platform dates if they differ (`PLAN-ITERATION.md:689-691`).
* **Rows:**
  * a record at N₂ = 100;
  * the decision at **N₂ = ⌈3 / c\*⌉ or day 90, whichever comes first**, where c\* is the floor conversion at the price in force (so at ¥10, c\* = 7.6% and N₂ = 40; at ¥68, about 273). A zero at that N is exactly the bound that rules out reaching the floor;
  * refunds read at day 180.
* **Branches:**
  * **GO-2:** net purchases on a floor pace. The Phase 2 option chosen in D3 opens.
  * **BELOW-FLOOR:** ≥ 1 purchase, below pace. Only options that raise net per sale (price or package) qualify, and there is no more scenery-only work.
  * **ZERO:** scenery cannot carry revenue at this traffic. Read the funnel first (P1-13 has shipped), and the next change is *what* is sold, not how it is shown. No Phase 2 SKU without an owner decision.
* **Instrument:**
  * O-1's known positive carries over;
  * P1-12 is re-validated by re-classifying the matched day;
  * the launch spike to the existing base is reported separately (`PLAN-STAGE1.md:569-570`);
  * walk and participant installs are subtracted as in §K;
  * reads are split by territory (the ja and listing co-interventions).
* **No-known-positive world:** if O-1 never happened, Window 2's zeros are uninterpretable too, and the box says so before any reading.
* **Guardrails kept:** any negative review mentioning the purchase is a stop-and-fix (`PLAN-STAGE1.md:567-568`); the refund-ceiling rules carry over.

---

## §I Release cadence: the first three releases

| release | target submit (JST) | window | contents | agent-days (build · verify+review · release) | registered as |
|---|---|---|---|---|---|
| v1.36 | submitted 10-27 | Window 1 | as recorded; approval-day chores (P0-1) | — · — · 0.25 | the 2026-10-26 box |
| **v1.37** | **11-09..13**, only after 1.36 is live on both platforms. If it is not submitted by 11-14, hold it until the N = 200 record. | Window 1 | P0-2 only; the frozen list byte-identical to `fdb2b5f` | 2 · 1.5 · 0.5 | §K constraint-3 box before `--submit` |
| quiet period | v1.37 submit → N = 200 record | Window 1 | No release. Phase 1 branches finish; P0-9 lands after O-1 and O-6. | — | — |
| **v1.38 "Offer v2"** | **about 12-02** under STOP or STOP BUILDING; **released no earlier than Pacific 12-09** under GO | Window 2 opens | §D | 16.9 (about 12 pre-built) · 3 · 0.5 | Window 2 pre-registration committed first; a §K box records Window 1's close |
| **v1.39** | **about 2027-01-12..15**, after Window 2's first record | Window 2 | items cut from v1.38; non-money leftovers; Phase 2 *preparation* that changes no offer (e.g. the `RouteStore` generalisation behind a constant); E1 if the owner chose it and Window 2's box names v1.39 as its iteration point | 3–5 · 1.5–2 · 0.5 | Window 2 box |
| v1.40+ | after Window 2's decision row | — | the one Phase 2 option chosen | per §E | Window 3 pre-registration |

Release days raise first downloads (1.18× to 1.58× in the two controls). Cadence is a registered covariate, never claimed as a cause (`PLAN-ITERATION.md` §G).

Interleaved:
* O-1 by 11-15;
* P0-9 the day after the walk is confirmed and O-6 is given;
* the N = 200 reading about 11-25..27;
* P1-12 straight after that record;
* the 2026-12-08 interim record, with no decision attached.

---

## §J Verification standard (PLAN-V1.34 §G kept, `PLAN-V1.34.md:1020-1070`, plus the purchase path)

* **V1.** `run_all_gates.sh` green at floor 10 (9 headless). `HorizontalTextFitTests.accepted` is only ever lowered.
* **V2.** Headless renders, en + zh, three runs, compared pixel by pixel. Intended differences are named per screen before reading.
  * In v1.37, `road.png`, `road-iap-review.png` and `menu.png` are identical, checked by a frozen-surface lens.
  * In v1.38 they and Settings are intended differences and are listed. The Tōkaidō scenery renders stay identical.
* **V3.** AX5 simulator pass, default and AX5, en/zh, on the existing `NihongoRide-VisualPass` (402 pt) and `NihongoRide-Placement` devices plus the iPad mini, for every changed screen before and after. Contrast is measured on rendered pixels. The harness stays outside the repo.
* **V4.** `run_ios_placement_tests.sh` whenever UI changes, and before merging any UI-test change (SwiftPM gates do not compile UI tests).
* **V5.** Store gates.
  * Exit 3 is tolerated until P0-9. After it: exit 0 with nine executed and a red mutation per gate family.
  * Any `RouteStore` or `EntitlementKit` diff gets a purchase-adapter lens with independent refuters.
  * "Strengthening a control is always allowed; loosening one for a green never is" (`HANDOFF-STAGE1-GATES-PROMPT.md:216`).
* **V6.** Pre-submission review:
  * one lens per file group, plus a tests lens that mutates;
  * independent refuters for every non-NOTE finding;
  * two rounds, with a third if round 2 finds a SERIOUS;
  * reviewers read the diff and do not build (`~/.claude/CLAUDE.md`, Build roots rule 2);
  * the two Gemini reviews through agy run on this plan and on each release diff.
* **V7.** `launch_gate.sh`; curl the live privacy and support pages; byte-exact ASC read-back of every PATCH; What's New checked sentence by sentence against the code. Copy pins (`PurchasePromiseTests`, `PaidRouteRowTests`, `OneBranchRuleTests`, `PrivacyClaimTests`) change in the same commit as the copy they pin.
* **V8.** Every fix is proven by reverting it and seeing its test go red (`HANDOFF-STAGE1-GATES-PROMPT.md:258`).
* **Build discipline.**
  * Private clones under `~/Library/Caches/NihongoRide-v137-work/<name>`, one build root per concurrently building checkout, with `COMPILER_INDEX_STORE_ENABLE=NO`.
  * Read-only lenses do not build.
  * `git status` before every build, because of the iCloud `* 2.swift` duplicates (`STATE-2026-10-27.md:54-57`).
  * Agents never share the live tree.
* **Public repo.** Aggregate counts only: no device names, no account identifiers. Walk screenshots and owner-device readouts stay outside the repo (`PLAN-V1.34.md:733-734`).

---

## §K Deliberately NOT done, and why

* **Changing the offer, price, placement or en/zh/ja metadata before the decision row**, unless the owner chooses B. Constraints 1 and 4 (`PLAN-WINDOW.md:115-126`).
* **Any purchase by an agent in any environment, and any Apple-account action.** This includes `SKTestSession` on a CI runner before O-6 (`HANDOFF-STAGE1-GATES-PROMPT.md:200-210`).
* **Changing `sales_report.py` before the N = 200 record.** That would be an instrument changed right before its decision reading.
* **A second SKU in the same release as the ledger split** (`PLAN-STAGE1.md:1374-1381`).
* **A Kyōto-arrival modal, badge or post-ride solicitation.** P1-9b's single informational line is the owner's choice, nothing more (`PLAN-STAGE1.md:70-76, 118-132`).
* **Moving any threshold, shortening the free road, or gating anything an existing install has.** Thresholds are permanent and buyers paid for the west ones (`RideRoute.swift:204-206`). The red line is enforced by grandfathering only (`PLAN-V2-PRODUCT.md:369-395`).
* **A subscription.**
  * There is no demonstrated retention (`PLAN-V2-PRODUCT.md:323-327`).
  * `EntitlementRecord` has no expiry, so a lapsed subscription would read as entitled forever (`Entitlement.swift:123-127, 149-156`; `RouteStore.swift:233-240`).
  * `IAY` is expected-absent in `sales_report.py:226-229`.
  * Guideline 3.1.2 needs Terms of Use, and `site/` has none.
  * Reopen only on measured retention plus a valued content cadence.
* **Ads, accounts, anything server-backed, transmitted telemetry, charging for export, zh-Hant or ko listings** (`PLAN-WINDOW.md:265-275`). Data Not Collected stays.
* **Off-store promotion during a window.** It changes which devices arrive more than metadata does (`PLAN-WINDOW.md:42-48`).
* **Paid upfront.** It removes the trial on a 2.6-a-day funnel with no ratings in its largest territory (`PLAN-V2-PRODUCT.md:314-322`). Model it only after P0-7.
* **Selling audio on the system voice.** 964 sentences are withheld because the voice reads them wrong (`PLAN-STAGE1.md:1369`).
* **Turning on Family Sharing for this SKU.** It is irreversible, and §L gate 2 tests that it stays off (`HANDOFF-STAGE1-GATES-PROMPT.md:218`).
* **Offer codes, temporary sales, Product Page Optimization.** At 2.6 installs a day none of them reaches a readable result, and each would muddy Window 2.
* **A Japanese UI in Phase 1.** It is gated on P0-7 (E5).
* **TestFlight for anyone, or development builds on walk devices, before §L is recorded** (`PLAN-V1.34.md:733-736`).
* **Any agent-chosen price** (§F).

---

## §M What would make this plan wrong

* **A stranger buys before N = 200.** That is GO on H1, read by a person. v1.38 is released no earlier than Pacific 12-09. P1-3, P1-4 and P0-9 rise in priority because a real customer now depends on restore. The Phase 2 fork reads GO's side (`PLAN-V2-PRODUCT.md:231-240`).
* **The walk finds the till broken:** no `salesReports` row, no cross-device restore, or a family member who inherits the purchase. Stop-and-fix overrides everything here, and v1.37 or the next release becomes a purchase-path fix.
* **The owner never walks.** N = 200 is a record of N only, P1-3 and P1-4 are cut, and Window 2 inherits an instrument nobody has seen fire, so its zeros are uninterpretable too. The plan's revenue measurement then means nothing all the way down.
* **Traffic stalls or rises.** N = 200 slides toward the 2027-03-08 backstop, or arrives earlier, and the quiet period moves with it. If N < 200 at the 12-08 interim, A vs B is worth asking once more.
* **P0-7 shows the JP installers are natives practising romaji.** Then E5 and a different framing outrank E1–E3, and the scenery SKU's audience is the minority.
* **Hosted runners keep `SKTestSession` inert.** P0-9 falls back to the walk Mac with the trap, or the honest exit-3 state stays and is recorded.
* **P1-7's landmarks cannot be drawn recognisably in code within 2 days.** Cut them, and P1-6's copy drops its landmark clause rather than over-promising.
* **A negative store review mentions the purchase.** Stop-and-fix (`PLAN-STAGE1.md:567-568`).
* **The 1.5% bound is misread as a statement about Offer v2.** It bounds the Stage 1 treatment only, and Window 2 measures the new one.

---

## §Q Assumptions and open questions (for the Gemini reviewers and the owner)

**Assumptions the plan rests on. Each is a place to attack.**
1. **The projection.** N = 200 lands on Pacific report days about 11-23..25 at about 2.6 installs a day. It is extrapolated from 47 days of a flat series (`stage1-checkpoints.md:228-232`), not guaranteed.
2. **Revenue foregone under A is under ¥25.** This assumes 2–5% conversion of the *improved* offer and a 1.5–3 week difference in ship date. If Offer v2 converted far higher, B's cost rises, but nothing in the evidence supports a higher rate.
3. **The agent may commit Appendix A's restating parts under the owner's delegation, labelled as such.** These are the items that only repeat existing §K text: the window ends by its own rule; with no known positive the reading is a record of N only; a zero with no returned counter is STOP BUILDING. Items that *add* meaning wait for the owner's word: what "iterate" means, and what the next release must carry. *Reviewer question:* is even the restating box a "redefinition" that belongs to the owner?
4. **Buyer-only scenery changes (P1-7) touch "the offer".** The plan treats them conservatively and holds them to v1.38. The docs do not decide this.
5. **The "ruled out" column in §F assumes demand does not rise with price** for the same good and placement. It is invalid for a thicker package.
6. **P0-7 is read-only and allowed.** `acquisition_funnel.py` fetches Apple's presigned report URLs, which `scripts/asc_api.sh` does not cover. The task's GET-only rule was written for `asc_api.sh`. Confirm it extends to this documented script.
7. **P0-9 on a GitHub-hosted runner removes the Octane-config reason §E waited on.** Whether a hosted runner's storekitagent serves `SKTestSession`, and whether the real bundle id goes live with `get-task-allow`, are unmeasured.
8. **Promoted IAP is iOS-only here.** The deployment-target arithmetic (macOS 14.0 < 14.4) is from `project.yml`. Whether the Mac App Store shows promoted IAPs at all was not re-verified.
9. **Editing an approved IAP's description or review note, or changing its price, may or may not need App Review.** Not established. P1-14 reads first.
10. **Effort figures** are agent estimates summed item by item, not measured. Phase 1's 16.9 days assumes the branch work starts about 11-01.

**Open questions:**
1. *(owner)* Will O-1 be walked by 11-15? Everything measurable downstream depends on it.
2. *(owner)* A or B? Silence means A.
3. *(owner, at N = 200)* The price; the Phase 2 fork (default E1); whether P1-9b's arrival line ships.
4. *(owner)* Allow §E's simulated purchases (O-6), departing from HANDOFF §8 rule 1's "any environment"?
5. *(owner)* §K and the tool say "go / iterate / stop", but the branch text has no ITERATE. Should the Appendix A box define it as "the held list, at today's price"?
6. *(owner)* If the decision lands on a zero, does the owner want to override "zero still means do not build Pro" for E3 (`PLAN-STAGE1.md:174-176`)? Only a dated box can do that.
7. *(reviewers)* Is Window 2's decision row at N₂ = ⌈3/c\*⌉ statistically sound? At ¥10 it fires at N₂ = 40, which is short; should there be a floor (e.g. max(⌈3/c\*⌉, 100))?
8. *(reviewers)* Should the quiet period also hold P0-9? It is test infrastructure and changes no binary.
9. *(engineering, unverified)* Is the "Already bought it?" width caused by `.panel()` before `.frame(maxWidth:)`? This needs a simulator check in a private clone after the freeze lifts.
10. *(engineering)* Is the iOS simulator still inert for a local `.storekit` on Xcode 27? It has not been re-run since Xcode 26.6.
11. *(evidence)* Who installs from the JP storefront? Answered in part by P0-7, and fully only by sessions or reviews.
12. *(positioning)* Rail Typing (CN, journey-themed, ¥128 lifetime, launched Oct 5) is a direct new competitor in the territory that produced the only purchase request. Should P1-13's zh copy and the CN creative position against it?

---

## §R What the reviews changed

*Pending. Filled in after the agy reviews (Gemini 4 Pro, Gemini 3.8 Flash) in the house style: every finding is verified against the cited line before it is accepted, rejected findings are kept with their reason, and the record says what the reviews did not check.*

---

## Appendix A: the dated §K box drafts (exactly one is committed, before the N = 200 reading)

**If A (the default):**

> ### 📌 REGISTERED <date> (JST), BEFORE the N = 200 reading: what happens when the decision row fires
>
> Written under the owner's decision of <date> ("A"), or, with no answer by 2026-11-20, as the agent's consolidation
> of existing text under the owner's delegation, labelled as such. **Nothing above is reworded. No threshold, branch,
> denominator or exclusion moves.**
>
> 1. The window ends by its own rule: the first `--checkpoint` reading whose adjusted N ≥ 200, or 2027-03-08,
>    whichever comes first. The 2026-12-08 interim record is unchanged and carries no decision.
> 2. The branch is read by the owner, as a person, from that reading and the same-day `review_watch`.
> 3. If no matched known-positive purchase exists at that reading, the reading is a record of N only. No bound is quoted
>    anywhere, nothing is concluded about willingness to pay, and a zero with no returned counter is read under the
>    existing branch as STOP BUILDING / UNINTERPRETABLE.
> 4. *(owner's word required; omitted if committed under delegation)* Whatever the branch, the first release submitted
>    after the reading carries the held list (PLAN-V1.37 §D): offer presentation, placement and instrumentation. Under
>    STOP or STOP BUILDING that release adds no SKU and changes no price unless the owner overrides "not price" in a
>    separate dated box. Under GO it is released no earlier than Pacific 2026-12-09 ("Run to day 90 anyway").
> 5. *(owner's word required; omitted if committed under delegation)* "Iterate", named in the schedule table and never
>    defined in the branches, means exactly item 4.
> 6. Before that release's `--submit`, a Window 2 pre-registration is committed (PLAN-V1.37 §H).

**If B:**

> ### 📌 ENDED EARLY <date> (JST) by the owner's decision, after the N = 35 and N = 100 readings had been read
>
> This is a decision made after seeing data, recorded as such (§K forbids deciding "after seeing a checkpoint"). The
> final Stage 1 record is the N = 100 reading of 2026-10-26: N = 122, 0 purchases, BOUND WITHHELD, for the one reason
> that no matched known-positive purchase exists. No bound is quoted, and the zero is UNINTERPRETABLE. Nothing above is
> reworded. Window 2 begins with the first release that changes the offer, under a pre-registration committed before
> its `--submit`.