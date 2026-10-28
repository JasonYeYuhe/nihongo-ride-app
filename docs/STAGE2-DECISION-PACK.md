# STAGE2-DECISION-PACK (D3): the Stage 2 fork against §K's branches, a draft for the owner's C-2 card

*Draft, 2026-10-28 (JST). PLAN-V1.37 §C item P0-3 (`docs/PLAN-V1.37.md:204`). Written on branch `docs/p0-3` from `main` at `892ef68`. Every file:line below is at that HEAD and was re-opened before commit. Nothing was built, nothing was bought, and App Store Connect was not called. **This pack decides nothing.** Every decision cell is blank, no price appears, and no branch is recommended. The N = 200 reading has not happened, so its figures are blanks.*

---

## 摘要（给 owner）

* **这是什么。** C-2 卡（N = 200 读数那天，约 11-25..27）要放在桌上的一份草稿。它把 Stage 2 的三条路（PLAN-V2-PRODUCT §E 的 fork）和 §K 的三个分支（GO / STOP / STOP BUILDING）排成一张表，**每个决定格都是空的**，由你填。
* **它和原计划不一样的地方，先说清楚。** PLAN-V1.34 说 D3 要在主持式访谈之后写；访谈从没做过。PLAN-V1.36 说 D3 要等你。这一份是 agent 在没有访谈的情况下写的草稿，只给你在 C-2 时读，**不替你决定任何事**。
* **没走查时（A′）的规则。** PLAN-V1.34 要求 D3 写出"没有已知购买"那个世界的决定规则。本文 §4 把 §K 的原文逐字贴出，标为"agent 在 10-07 委托下的读法"，决定格留给你。
* **本机计数器的偏差：两条路径方向相反，净方向未知。** 都是读代码得出的，没有测量过。代码位置在 §5。
  * **少记：** 付费页只在页面出现那一刻记一次。那时价格还没读到，就记成 `offerUnavailable`；之后价格到了或按了重试，也不补记。单看这一条，它只会把 STOP 推向 STOP BUILDING，不会反过来。
  * **多记：** 这一次记录挂在整个滚动页上，而价格卡片排在 16 段路之后。价格已读到时，页面一打开就记 `offerAppeared`，骑手可能根本没滚到价格那里。这一条把计数推向 STOP。
  * 两条相加的净方向未知。
* **C-2 的六个选项 (a)–(f)** 和 E3 的两个免费/付费边界候选在 §6；day-91 清单在 §7；和这次读数共用数据的其他读数在 §8。
* **没有价格，没有推荐。** N = 200 的数字全部留空。

---

## 0. What this is, and how it departs from the plan that defined it

**The definition.** PLAN-V1.34 D3 defines this file: "the §E fork × §K's branches as a memo with **every decision cell blank**, the measurements each combination needs, the day-91 list … and the readings it shares data with" (`docs/PLAN-V1.34.md:746-749`).

**The departure, said here as P0-3 requires** (`docs/PLAN-V1.37.md:204`):
* PLAN-V1.34 puts D3 *after* the moderated sessions: "Two documents the decision will need, written after the sessions, not code" (`docs/PLAN-V1.34.md:740`). The sessions never ran (`docs/PLAN-V1.36.md:13`). No session was ever registered, and `docs/sessions/` holds only its README (`docs/measurements/stage1-checkpoints.md:190-191`).
* PLAN-V1.36 calls D3 owner-gated: "D3, D4, D5, §E, and session-driven fixes. These are owner-gated" (`docs/PLAN-V1.36.md:253`; also `:13`).
* **So this D3 is a draft written without the sessions, for the owner to read at C-2. It decides nothing.** Where it states a reading under the 2026-10-07 delegation, it says so. Nothing here is the owner's decision, and nothing here is a §K box.

**What "the §E fork" means here.** PLAN-V1.34's own §E is the walk-conditional store-gate item (`docs/PLAN-V1.34.md:766`), which has no fork. The fork is PLAN-V2-PRODUCT §E, "And the fork this plan must not blur" (`docs/PLAN-V2-PRODUCT.md:401-419`). PLAN-V1.37 reads it the same way (`docs/PLAN-V1.37.md:79`).

**Not in this file.** PLAN-V1.34's D3 has a second document, `docs/DESIGN-F1-SRS.md` (`docs/PLAN-V1.34.md:742-745`). It does not exist and P0-3 does not ask for it.

---

## 1. The two axes, as written

### 1.1 §K's branches

The decision fires at "N = 200, or 2027-03-08 (day 180), whichever comes first" (`docs/PLAN-STAGE1.md:426`). On the backstop the bound uses the observed N (`docs/PLAN-STAGE1.md:429-431`). Item 10 makes this schedule govern the decision (`docs/PLAN-STAGE1.md:808-810`).

There are three branches (`docs/PLAN-STAGE1.md:528-554`; quoted in full in §4):
* **GO:** "≥ 1 net purchase at any point" (`:528`).
* **STOP:** zero, and at least one returned counter showing `offerAppeared > 0` in the `kyoto` bucket (`:531-533`).
* **STOP BUILDING:** zero, and no such counter; the zero is recorded as UNINTERPRETABLE (`:550-551`).

There is no ITERATE branch, although the schedule row says "go / iterate / stop" (`docs/PLAN-STAGE1.md:426`; noted at `docs/PLAN-V1.37.md:176`).

What counts as a "returned counter" is narrowed by two boxes:
* counters on walk devices are not returned counters, and such a zero reads as STOP BUILDING / UNINTERPRETABLE, never as STOP (`docs/PLAN-STAGE1.md:782-785`);
* counters on session-participant devices are not either (`docs/PLAN-STAGE1.md:883-884`).

### 1.2 The fork

"Pick one, explicitly, at Stage 2" (`docs/PLAN-V2-PRODUCT.md:407`):
1. **Option 1:** keep the whole app free and sell a Supporter Pack (`docs/PLAN-V2-PRODUCT.md:409-411`).
2. **Option 2:** grandfather existing users, give new users a bounded but complete sampler, and sell the full unlock (`docs/PLAN-V2-PRODUCT.md:412-415`).
3. **Option 3:** keep the generous free tier and build a transformative paid workflow, F1 (`docs/PLAN-V2-PRODUCT.md:416`).

"Choosing none of them and shipping a bit of each is the failure mode" (`docs/PLAN-V2-PRODUCT.md:418-419`).

**How PLAN-V1.37 §E's options map onto the fork:**
* E3 is option 2, by the plan's own label (`docs/PLAN-V1.37.md:268`).
* E6 is option 3, by its own label (`docs/PLAN-V1.37.md:273`).
* E2 (a tip-jar / supporter add-on, `docs/PLAN-V1.37.md:271`), E4 (finite content packs, `:270`) and E1 (another road inside the road SKU, `:272`) carry no fork label in any document read for this pack. *The agent's reading under the 2026-10-07 delegation, labelled as such:* E2 is the nearest item to option 1, but it is not option 1. PLAN-V1.37 defines it as "An add-on only, never instead of E3" (`docs/PLAN-V1.37.md:271`), while option 1 keeps "the whole app free" (`docs/PLAN-V2-PRODUCT.md:409`). E2 beside E3 would be "a bit of each" (`docs/PLAN-V2-PRODUCT.md:418-419`). So row 1 of §2 holds a supporter pack *in place of* E3, and no PLAN-V1.37 item fills it. E4 and E1 are not placed on the fork here.
* With no answer, there is no Phase 2 SKU (`docs/PLAN-V1.37.md:262`).

---

## 2. The table: the fork × §K's branches, every decision cell blank

Each cell gives only what the written rules already say about that combination, with its citation, and then a blank for the owner. A cell's rules are not a recommendation. The "owner" blanks are the decision cells; this pack fills none of them.

| fork option | **GO** (≥ 1 net purchase) | **STOP** (zero, a stranger's counter shows the offer at Kyōto) | **STOP BUILDING** (zero, no such counter; UNINTERPRETABLE) |
|---|---|---|---|
| **0. None of the three** (the default on silence, `docs/PLAN-V1.37.md:262`) | GO's run to day 90 for the repeat rate (`docs/PLAN-STAGE1.md:528-529`); v1.38's offer-changing items released no earlier than Pacific 12-09 unless the owner cuts the run short (`docs/PLAN-V1.37.md:56`). **owner:** `________` | STOP's text prescribes no next release (`docs/PLAN-STAGE1.md:531-533`). v1.38 ships under it (`docs/PLAN-V1.37.md:56`). **owner:** `________` | "The next release's job is instrumentation and placement, not price and not Pro" (`docs/PLAN-STAGE1.md:551-552`). v1.38 ships under it (`docs/PLAN-V1.37.md:56`). **owner:** `________` |
| **1. Supporter Pack, in place of E3** (no PLAN-V1.37 item: E2 is "An add-on only, never instead of E3", `docs/PLAN-V1.37.md:271`) | E2, the nearest item, waits for Window 2's reading (`docs/PLAN-V1.37.md:296`). Any second SKU: the counter is split a release earlier (`docs/PLAN-STAGE1.md:1374-1381`). **owner:** `________` | A second SKU is on PLAN-WINDOW §G's "What must not be built" (`docs/PLAN-WINDOW.md:269`); zero "still means *do not build Pro*" (`docs/PLAN-STAGE1.md:174-176`). PLAN-V2-PRODUCT says patronage "must not be called 'Pro'" (`docs/PLAN-V2-PRODUCT.md:403-405`), and keeps "Nobody tips → … Do not build Pro" (`:236-237`). Whether "do not build Pro" still bars a supporter pack is not written down; the owner reads it. **owner:** `________` | As STOP, plus "not price and not Pro" (`docs/PLAN-STAGE1.md:552`); whether "not Pro" covers patronage is the same open reading (`docs/PLAN-V2-PRODUCT.md:403-405`). **owner:** `________` |
| **2. Sampler + full unlock** (E3) | "Only its price is needed" (`docs/PLAN-V1.37.md:79`). E3 rides v1.39, after v1.38's ledger split (`docs/PLAN-V1.37.md:437`). "An agent invents no prices" (`docs/PLAN-V1.34.md:729`). **owner:** `________` | Needs the owner's override of the written "do not build Pro / no second SKU" rules; Appendix A-1 item 2 drafts it "only if the branch is STOP or STOP BUILDING" (`docs/PLAN-V1.37.md:569-575`). Plus a price. **owner:** `________` | Needs the override of "not price and not Pro" (`docs/PLAN-STAGE1.md:552`) and the same rules, in one dated box (`docs/PLAN-V1.37.md:78`; draft at `:560-580`). Plus a price. **owner:** `________` |
| **3. Paid workflow** (E6, F1) | "E6 is Stage 3" (`docs/PLAN-V1.37.md:296`). Its falsifier is keyed to a session tally (`docs/PLAN-V1.34.md:742-745`), and no session ran (§0). **owner:** `________` | A second SKU, and the row that names F1, now marked "PARTLY SUPERSEDED" (`docs/PLAN-WINDOW.md:269-270`); zero "still means *do not build Pro*" (`docs/PLAN-STAGE1.md:174-176`); plus the same session-tally gap. **owner:** `________` | As STOP, plus "not price and not Pro" (`docs/PLAN-STAGE1.md:552`). **owner:** `________` |

**The backstop row.** If the decision fires at 2027-03-08 instead of at N = 200, the branches are the same and the bound uses the observed N (`docs/PLAN-STAGE1.md:426-431`). The table does not change.

**Whatever the branch, the owner reads it.** "Reading §K's branches as a person when N = 100 and N = 200 fire" is owner-only (`docs/PLAN-V1.34.md:1087`). C-2(a) asks for that reading (`docs/PLAN-V1.37.md:98`).

---

## 3. The measurements each combination needs

### 3.1 By branch

| branch | what has to be measured or read | source |
|---|---|---|
| GO | the repeat rate, to day 90 | `docs/PLAN-STAGE1.md:528-529` |
| GO | refunds at day 180, as absolute counts | `docs/PLAN-STAGE1.md:427, 556-562` |
| any | the day-90 reading split by territory, JP flagged for the `ja` listing | `docs/PLAN-STAGE1.md:577-578` |
| any | `review_watch` the same day; a negative review that names the purchase is a stop-and-fix | `docs/measurements/stage1-checkpoints.md:26-29`; `docs/PLAN-STAGE1.md:567-568` |
| STOP | a returned counter from a stranger, `offerAppeared > 0` in `kyoto`, not from a walk or participant device; §5's two opposite paths apply | `docs/PLAN-STAGE1.md:531-533, 782-785, 883-884` |
| STOP BUILDING | nothing more for Stage 1. The next release's job is instrumentation and placement; in PLAN-V1.37 that is v1.38 as a whole, every item "'instrumentation and placement' or a defect fix" (`:222`), whose instrument items are P1-11 (the ledger v2 and the `offerAppeared` fix) and P1-12 (`sales_report.py` by SKU and currency) (`:242-243`) | `docs/PLAN-STAGE1.md:551-552`; `docs/PLAN-V1.37.md:222, 242-243` |

### 3.2 By fork option

| option | what it needs before a reading means anything | source |
|---|---|---|
| any second SKU | the counter split shipped a release earlier | `docs/PLAN-STAGE1.md:1374-1381`; `docs/PLAN-V1.37.md:437` |
| any treatment | a Window 2 pre-registration committed before its release's `--submit`; the agent commits measurement mechanics only and leaves branch consequences blank | `docs/PLAN-V1.37.md:206, 349-372` |
| 1 (E2) | "Zero units at its window's decision → stop patronage" | `docs/PLAN-V1.37.md:271` |
| 2 (E3) | the install-cohort marker (v1.37), P1-5 and P1-11 (v1.38); the zero row at N₂ = max(⌈3/c\*⌉, 200) **and** ≥ 60 days, with the pipeline proven | `docs/PLAN-V1.37.md:203, 268, 294, 362, 368` |
| 3 (E6) | the session tally ("fewer than 2 of n pasted anything → shelved"), which does not exist | `docs/PLAN-V1.34.md:744`; §0 |

**Under A′ (no walk), Window 2's zeros cannot be read.** A positive proves the pipeline by existing; a zero with no purchase of either SKU ever seen is UNINTERPRETABLE (`docs/PLAN-V1.37.md:88, 369`). If E3 also sells nothing, "nobody wants it" and "the till is broken" stay indistinguishable (`docs/PLAN-V1.37.md:461`).

### 3.3 The N = 200 reading's own figures (blank until the record)

The record is committed with the numbers only, and the branch line is left for the owner (`docs/PLAN-V1.37.md:98`, C-2's silence column; `docs/measurements/stage1-checkpoints.md:16-17`, rule 3).

| figure | value |
|---|---|
| reading date (JST) · newest Pacific report day | `____` · `____` |
| N (macOS · iOS) | `____` (`____` · `____`) |
| purchases: raw gross · refunded · net | `____` · `____` · `____` |
| adjusted purchases: gross · refunded · net | `____` · `____` · `____` |
| registry entries in the window | `____` |
| exit code; every `BOUND WITHHELD:` reason, verbatim | `____` |
| returned counters received (count; any `offerAppeared > 0` at `kyoto` from a stranger) | `____` |
| `review_watch`: since day 0 · flagged | `____` · `____` |
| **branch, read by the owner** | `________` |

---

## 4. A′: the decision rule when there is no known positive

**Why this section exists.** "If the owner records DRAFTS §2 (no known-positive, ever), the bound is withheld for the window's life, N = 100 and N = 200 become records of N only, and D3's decision pack must say what that world's decision rule is — this plan does not" (`docs/PLAN-V1.34.md:1126-1128`). PLAN-V1.37 calls the no-walk world A′ and says it is the likely outcome (`docs/PLAN-V1.37.md:81-86`).

**Where that world stands today.** The N = 100 reading withheld the bound for one reason: "no matched day-0 known-positive purchase" (`docs/measurements/stage1-checkpoints.md:244-245`). The registry has 0 entries (`:212`).

**The rule, stated as the agent's reading under the 2026-10-07 delegation, labelled as such.** In a world with no known positive, the decision rule is §K's existing text, unchanged. No box is added to it. The text, reproduced byte for byte from `docs/PLAN-STAGE1.md:526-554` at `892ef68`:

> **Go / iterate / stop at day 90:**
>
> * **≥ 1 net purchase at any point → GO on H1.** Somebody will pay this developer. Run to day 90
>   anyway for the repeat rate. State the ceiling honestly: 1–3 purchases proves existence and
>   estimates nothing.
> * **Zero, AND at least one returned counter showing `offerAppeared > 0` in the `kyoto` bucket →
>   STOP.** Somebody arrived, **the offer itself rendered with a price in front of them**, nothing
>   was bought. That is the only configuration in which a zero is evidence about willingness to pay.
>
>   > **CORRECTED 2026-08-30, before day 0.** This branch read `settingsRowAppeared > 0` with
>   > `furthestBucket == kyoto`, and that was the error the instrument was built to prevent, written
>   > into the pre-registration itself. `UnlockOfferLedger` says so in as many words: the Settings row
>   > is *"the entrance, not the offer — and the two are a screen apart, so they are counted apart"*,
>   > while `offerAppeared` *"is the event that means somebody was actually in a position to buy"*,
>   > and reading the row as if it meant the offer is *"two different predicates answering one
>   > question — the shape this project has shipped twenty-two times."* The code already recorded the
>   > right event; only this decision rule asked for the wrong one.
>   >
>   > Two further reasons the old form was weaker than it looked. `furthestBucket` is a high-water
>   > mark over the device's whole life, so it could be `kyoto` while the row appeared at 400 m —
>   > the conjunction did not say the two happened together, and the per-bucket form does.
>   > And `shareableSummary` **summed all eight buckets away**, so the quantity this branch asks
>   > about was not printable on the one readout a customer could return; it now prints the kyoto
>   > column on its own line.
> * **Zero, AND no returned counter (or every one showing `offerAppeared == 0` in `kyoto`) → STOP
>   BUILDING, and record the zero as UNINTERPRETABLE.** The next release's job is instrumentation and
>   placement, not price and not Pro. **This branch is the one that must not be quietly dropped:** a
>   pre-registration with no "this taught us nothing" outcome is precisely the failure this project's
>   central rule names, written into the schedule.

**The same §K amends these bullets in later dated boxes.** They are part of the text the owner reads, and are cited here, not reworded:
* What counts as a returned counter: walk devices are not (`docs/PLAN-STAGE1.md:782-785`), and session-participant devices are not (`docs/PLAN-STAGE1.md:883-884`).
* The schedule: item 10 makes the N = 200 / 2027-03-08 schedule govern, and supersedes the older "at day 90" sentences for the decision (`docs/PLAN-STAGE1.md:808-810`). This block's heading says "at day 90".
* The known positive: §K's day-0 paragraph calls the owner's purchase "the money instrument's known-positive" and says "this project does not trust an instrument that has not fired" (`docs/PLAN-STAGE1.md:675-680`). That is the written text on whether a zero can be read without it; see the third bullet below.

**What the text says about A′, read by the agent (2026-10-07 delegation; not the owner's reading):**
* **A stranger's purchase.** GO's condition is "≥ 1 net purchase at any point" (`docs/PLAN-STAGE1.md:528`). It does not mention the known positive. PLAN-V1.34 says that if a stranger buys before the walk, "the tool prints that the zero-purchase bound would not apply anyway, GO on H1 is a person's reading" (`docs/PLAN-V1.34.md:1129-1130`).
* **Zero, and no returned counter.** The third bullet's conditions are met as written: STOP BUILDING, the zero recorded as UNINTERPRETABLE (`docs/PLAN-STAGE1.md:550-551`). PLAN-V1.37 reads it the same way (`docs/PLAN-V1.37.md:86`). PLAN-WINDOW predicted it: "the most likely outcome is UNINTERPRETABLE" (`docs/PLAN-WINDOW.md:347-348`).
* **Zero, and a stranger's counter showing the offer at Kyōto.** The STOP bullet's conditions are met as written (`docs/PLAN-STAGE1.md:531-533`). **The text does not say whether STOP needs the known positive.** The bound needs it (`docs/measurements/stage1-checkpoints.md:244-245`), and the day-0 paragraph says the project "does not trust an instrument that has not fired" (`docs/PLAN-STAGE1.md:679-680`); the branch text itself does not mention it. This pack does not join the two. It is the owner's to read.

| | |
|---|---|
| **The owner's decision rule for A′** (the text above as written, or the owner's words) | `________` |
| **The owner's reading of the branch at N = 200** | `________` |

---

## 5. Stage 1's on-device ledger: one defect under-counts `offerAppeared`, one path can over-count it, and the net direction is unknown

**What the code does at `892ef68`:**
1. The road screen records the offer once, when it appears: `.onAppear { model.recordOfferAppeared() }` (`Sources/NihongoRideApp/RoadView.swift:55-57`). It is the only call site (`grep -rn recordOfferAppeared Sources`).
2. `recordOfferAppeared()` passes `offerLoaded: entitlements.product != nil` (`Sources/NihongoRideApp/AppModel.swift:2621-2628`, the argument at `:2625`).
3. The ledger records `.offerAppeared` only when the call is not suppressed, the device is not entitled, and `offerLoaded` is true. A not-entitled, unsuppressed call with no product records `.offerUnavailable` (`Sources/EntitlementKit/UnlockOfferLedger.swift:217-229`, the choice at `:223-226`).
4. The product is requested once, when `AppModel` creates the store at launch (`Sources/NihongoRideApp/AppModel.swift:605`; `Sources/NihongoRideApp/RouteStore.swift:117, 150`), by `load()` (`RouteStore.swift:164-174`). While that request is in flight the screen shows "Loading price…" (`RoadView.swift:203-205`); if it failed, a Retry button calls `store.load()` again (`RoadView.swift:191-202`, the button at `:199`).
5. Nothing records the offer again when the product arrives, during the same visit, or after a successful Retry. A later visit, with the product loaded, records `offerAppeared` normally.
6. This code has been unchanged since 2026-08-30, before day 0: `git log -S recordOfferAppeared -- Sources` returns only `e74970b` (2026-08-30 18:59 +0900), and the `offerLoaded:` argument at `AppModel.swift:2625` comes from `c30972b` (2026-08-30 17:54 +0900). `RoadView`, `RouteStore` and `EntitlementKit` are on the frozen list, held byte-identical to `fdb2b5f` (`docs/PLAN-V1.37.md:167, 193`). The fix is P1-11, in v1.38, after the N = 200 record (`docs/PLAN-V1.37.md:220, 242`).

So a visit where the price had not loaded yet, or where it loaded only after Retry, is recorded as `offerUnavailable` although the rider may then have seen a price. This is PLAN-V1.37 §A's row (`docs/PLAN-V1.37.md:143`) and review finding G4-9 (`:516`), and it checks out in the code.

**The not-loaded-price defect, on its own, biases toward STOP BUILDING.** STOP needs at least one returned counter with `offerAppeared > 0` in `kyoto` (`docs/PLAN-STAGE1.md:531-533`). STOP BUILDING holds when there is no returned counter, or every one shows `offerAppeared == 0` there (`:550`). This defect can only move a real offer from `offerAppeared` to `offerUnavailable`, never the other way. So it can flip the branch from STOP to STOP BUILDING only if it zeroes the `kyoto` `offerAppeared` of every returned counter, and it can never flip it the other way.

**A second path pushes the other way. Read from the code, not measured.**
* The `.onAppear` that records the offer is attached to the whole screen, the `ScrollView` around `content` (`Sources/NihongoRideApp/RoadView.swift:51-57`).
* The offer card comes after `header`, `tokaido` and `west` (`RoadView.swift:39-43`). Those two cards hold the road's stretch rows: the Tōkaidō's (`:75-77`) and the west's (`:99-101`), sixteen in all (`:14`).
* So with the product loaded, `offerAppeared` is recorded the moment the screen opens, whether or not the rider ever scrolls down to the price.
* §K's STOP text reads it as "the offer itself rendered with a price in front of them" (`docs/PLAN-STAGE1.md:532`). A counter can therefore show `offerAppeared > 0` when the price was never on screen, which pushes toward STOP.
* How often the card is below the fold is not measured; on a large Mac window it may fit on screen. No document in the repo mentions this path (`grep -rn onAppear docs/` finds only the not-loaded-price finding and an unrelated v1.26 timer, 2026-10-28).

**Net direction: unknown.** The two paths push opposite ways and neither is measured. This pack states both and does not choose between them. Whether P1-11's fix should also cover the card's visibility is left to P1-11 (§9).

GO is not touched: its condition is a net purchase (`docs/PLAN-STAGE1.md:528`), which the checkpoint reads from the sales reports, not from the device ledger (`docs/measurements/stage1-checkpoints.md:233-235`). And the ledger expected "under two and plausibly zero" returned counters anyway (`Sources/EntitlementKit/UnlockOfferLedger.swift:20-21`). This repo records none received (searched `docs/`, 2026-10-28).

---

## 6. C-2's options, and E3's two boundary candidates

### 6.1 C-2, the N = 200 card (`docs/PLAN-V1.37.md:98`)

| | the option, as PLAN-V1.37 words it (lightly shortened) | default on silence (from the same row's silence cell, split per option by the agent) | owner |
|---|---|---|---|
| (a) | Read §K's branch as a person, from the record and the same-day `review_watch` (owner-only, `docs/PLAN-V1.34.md:1087`). | The record is committed with numbers only; the branch line is left for the owner. | `________` |
| (b) | E3: a price, plus the override box (Appendix A-1). Under GO, the price only, plus, if wanted, cutting GO's repeat-rate run short. | E3 stays on its branch. No box is written. Under GO, v1.38's offer-changing items are released no earlier than Pacific 12-09. | `________` |
| (c) | The road's price. | Unchanged. No price changes. | `________` |
| (d) | Optional: E3's free/paid boundary. | Candidate 1 (§6.2). | `________` |
| (e) | Window 2's branch consequences: what ZERO, BELOW-FLOOR and GO-2 mean for the next work, in the owner's words. | Window 2's file is committed with measurement mechanics only and its consequence cells blank; v1.38's period is reported descriptively. | `________` |
| (f) | Optional: "P1-12 waits for a known positive". | P1-12 merges with v1.38, labelled as a departure from the 2026-09-16 rule. | `________` |

In every case v1.38 ships, because its contents are legitimate under GO, STOP and STOP BUILDING (`docs/PLAN-V1.37.md:98`, silence column; `:222`). The data for (b) and (c) are in `docs/PRICING-BRIEF-V137.md`, which proposes no price (`docs/PRICING-BRIEF-V137.md:5-8`). Its price points must be re-read on the day C-2 is answered (`:176-177`).

### 6.2 E3's two boundary candidates (`docs/DESIGN-E3-SAMPLER.md:38-45`)

| | **Candidate 1** (the default) | **Candidate 2** (the owner's alternative at C-2(d)) |
|---|---|---|
| free levels | N5, N4 | N5 |
| free words · sentences · dictation · verbs | 1,288 · 1,243 · 1,073 · 306 | 646 · 616 · 518 · 95 |
| paid levels | N3, N2, N1 | N4, N3, N2, N1 |
| paid words · sentences · dictation · verbs | 5,783 · 5,481 · 4,862 · 2,011 | 6,425 · 6,108 · 5,417 · 2,222 |
| free under both | all 233 passages, the learner's own texts, the Tōkaidō, every mode, search, lists, saving, sync, coach, widget, Game Center | same |

* Candidate 1 is the default as **the agent's design choice under the 2026-10-07 delegation**, not the owner's (`docs/DESIGN-E3-SAMPLER.md:47`; `docs/PLAN-V1.37.md:213`). Candidate 2 came from the Flash review (`docs/PLAN-V1.37.md:213, 544`).
* **The choice is made once.** After the first gated release the free set may grow and never shrink (`docs/DESIGN-E3-SAMPLER.md:52, 577`).
* The counts are the design file's, read from the bundled corpus on 2026-10-27 (`docs/DESIGN-E3-SAMPLER.md:3, 25`). P0-2 later withheld 7 dictation sentences, pool 5,935 → 5,928 (`docs/PLAN-V1.37.md:622-625`), so the dictation column above may be off by up to 7 at E3's release. Not re-counted here.

**C-2(d):** `________`

---

## 7. The day-91 list

The items earlier plans held for "day 91" because the window froze them, and where PLAN-V1.37 now puts each one.

| item | held by | where PLAN-V1.37 puts it |
|---|---|---|
| the offer screen at AX5: RoadView's stretch rows, the buy button's "One- / time / purcha / se", the "Already bought it?" card width, the Settings road card, the menu route strip | `docs/PLAN-V1.34.md:747, 1093-1096` | P1-1 (`docs/PLAN-V1.37.md:231`) |
| About's counter text | `docs/PLAN-V1.34.md:747-748, 1095` | P1-11, "About's counter text readable" (`docs/PLAN-V1.37.md:242`) |
| brand contrast on the buy button | `docs/PLAN-V1.34.md:748, 1095` | corrected: the buy button computes at 8.0–9.4:1; the sub-AA text is the boundary sentence and the `Theme.dim` captions (`docs/PLAN-V1.37.md:145`), fixed in P1-1 (`:231`) |
| the About licence badges (4.28:1) and the white on the coral and sky launcher capsules, the rest of the brand-colour list | `docs/PLAN-V1.34.md:305-306, 483-484, 974-975` | **not placed.** No PLAN-V1.37 item names them. |
| the zh Practice store screenshot | `docs/PLAN-V1.34.md:748, 1096` | non-money day-91 item for v1.38 under the cut rule (`docs/PLAN-V1.37.md:256`) |
| the Settings sync-status caption | `docs/PLAN-V1.34.md:748`; `docs/PLAN-V1.36.md:243-245` | same (`docs/PLAN-V1.37.md:256`) |
| About copy | `docs/PLAN-V1.36.md:243-245` | same (`docs/PLAN-V1.37.md:256`) |
| the menu credit line | `docs/PLAN-V1.34.md:1095-1096` | same (`docs/PLAN-V1.37.md:256`) |
| the denied-reminder notice | deferred by name (`docs/PLAN-V1.36.md:241-242`; `docs/PLAN-V1.34.md:1097-1102`), though neither line calls it day-91 | same (`docs/PLAN-V1.37.md:256`) |
| a device-language default | `docs/PLAN-V1.36.md:243-245` | P1-10 (`docs/PLAN-V1.37.md:241`) |
| a Japanese UI | `docs/PLAN-V1.36.md:243-245` | P1-15, E5 (`docs/PLAN-V1.37.md:246`) |
| the CN search-result creative, designed in the window and shipped on day 91 | `docs/PLAN-WINDOW.md:302-306` | P0-10 designs it; P1-13 ships it (`docs/PLAN-V1.37.md:211, 244`) |

**Parked here as a later option, on no card:** the Kyōto-arrival line (`docs/PLAN-V1.37.md:240`). PLAN-V1.37 keeps a modal, badge or post-ride solicitation out (`:435`). What the record already says about it:
* The deferral PLAN-V1.37 cites, "a Stage 2 question" (`docs/PLAN-STAGE1.md:74-76`), was withdrawn before day 0: "The deferral above is withdrawn" (`:80`).
* The arrival-moment entrance already shipped as the menu's route strip, "live only at or past Kyōto … It now marks arrival" (`docs/PLAN-STAGE1.md:92-94`).
* The wording "the road continues west" was rejected as "solicitation wearing a state's clothes" (`docs/PLAN-STAGE1.md:106-107`).

So any further arrival line is a second arrival-moment placement on top of the strip, and a placement change. This pack lists it and does not schedule it.

---

## 8. The readings this pack shares data with

A reading written down first is not thereby blind (`docs/measurements/stage1-checkpoints.md:22-24`, rule 5). The N = 200 reading's cache will contain every report day of:
* the N = 35 record (2026-09-25 JST) and its re-runs (`docs/measurements/stage1-checkpoints.md:33-39`);
* the agent readings of 2026-09-29 (N = 50), 2026-10-03 (N = 59) and 2026-10-07 (N = 68), and the 2026-10-07 investigation's cache-only re-runs (`docs/measurements/stage1-checkpoints.md:249-252`);
* the N = 100 record, read 2026-10-26: N = 122 (macOS 82 · iOS 40), 0 purchases, bound withheld, exit 5 (`docs/measurements/stage1-checkpoints.md:183, 232-235, 244-246`);
* the calibration and release-day controls computed on those days (`docs/measurements/stage1-checkpoints.md:253`);
* PLAN-V1.37 §A's territory split, a read-only parse of the cached daily sales reports (`docs/PLAN-V1.37.md:140`);
* the pricing brief's `sales_report.py --since 2026-09-09 --until 2026-10-25` run of 2026-10-27 (`docs/PRICING-BRIEF-V137.md:90`);
* the post-day-0 funnel, a different instrument (App Analytics) over Pacific 2026-09-20 .. 10-25, whose 94 downloads were matched against the same sales census (`docs/measurements/v137-funnel-post-day0.md:14-18`);
* this pack, which uses only figures already recorded in those files.

The 2026-12-08 interim record, if it comes after N = 200, will share all of the above too (`docs/measurements/stage1-checkpoints.md:5-7`).

---

## 9. Where this pack was unsure, and what it found wrong in PLAN-V1.37

**Unsure:**
* Whether STOP needs the known positive under A′ (§4). The text is silent, and the pack leaves it so.
* Which fork option E2, E4 and E1 belong to (§1.2). Only E3 and E6 are labelled in any document read.
* Whether "do not build Pro" (`PLAN-STAGE1.md:174-176`) or "not price and not Pro" (`:552`) bars a supporter pack (§2, option 1). PLAN-V2-PRODUCT says patronage "must not be called 'Pro'" (`PLAN-V2-PRODUCT.md:403-405`); how that meets the two §K-side rules is not written down.
* E3's dictation counts after P0-2's seven withholdings (§6.2). Not re-counted.
* The net direction of the ledger's bias (§5). Two opposite paths, both read from code, neither measured.

**Found wrong in PLAN-V1.37, against the files at `892ef68`** (none of these changes a rule; each is a citation):
1. P0-3 cites `PLAN-V1.34.md:741` for "written after the moderated sessions" (`docs/PLAN-V1.37.md:204`). Line 741 is blank; the heading is `PLAN-V1.34.md:740`.
2. P0-3's "`PLAN-V1.36.md:13, 253` call D3 owner-gated" holds for `PLAN-V1.36.md:253`. At `PLAN-V1.36.md:13` the sentence is "The sessions never ran, and they are owner-gated", where "they" can be read as the sessions.
3. §0 cites `PLAN-V2-PRODUCT.md:405-410` for "E3 is fork option 2" (`docs/PLAN-V1.37.md:60`). Option 2 is at `PLAN-V2-PRODUCT.md:412-415`; `PLAN-V2-PRODUCT.md:409-411` is option 1.
4. §D cites `PLAN-V1.36.md:241-245` and `PLAN-V1.34.md:1093-1102` for "the denied-reminder notice" as a day-91 item (`docs/PLAN-V1.37.md:256`). Only `PLAN-V1.36.md:243-245` says "day-91 list", and it does not name that notice.
5. §A says "no ledger has ever been returned" and cites `PLAN-STAGE1.md:612-621, 271-275` and `UnlockOfferLedger.swift:16-22` (`docs/PLAN-V1.37.md:136`). Those lines are a rides table, the arrival-rate statement and the ledger's expectation. None records a fact about returned ledgers. The repo records none, so the claim is not contradicted, only uncited.
6. G4-9 says the offer "never re-fires" (`docs/PLAN-V1.37.md:516`); §A's wording, "nothing re-fires when the product arrives or after Retry" (`:143`), is the exact one. "Never" holds within the visit. A later visit with the product loaded does record `offerAppeared` (§5 point 5), so the under-count is per visit, not per device.
7. P1-9b cites `PLAN-STAGE1.md:73-76` (`docs/PLAN-V1.37.md:240`). The Kyōto-arrival sentences are `PLAN-STAGE1.md:74-76`; `PLAN-STAGE1.md:73` is blank.
8. P1-1 and the rest of PLAN-V1.37 do not place the About licence badges or the launcher capsules' brand-colour contrast, which PLAN-V1.34 put on the day-91 list (§7).
9. P1-9b (`docs/PLAN-V1.37.md:240`) parks the Kyōto-arrival line as "a Stage 2 question" from `PLAN-STAGE1.md:73-76`, but the next box withdrew that deferral (`PLAN-STAGE1.md:80`), shipped the arrival-moment entrance as the menu strip (`:92-94`), and rejected "the road continues west" as solicitation (`:106-107`). PLAN-V1.37 does not say so (§7).
10. P1-11's fix fires `offerAppeared` "when the product resolves while RoadView is visible" (`docs/PLAN-V1.37.md:242`). Read from the code, not measured: RoadView being visible is not the offer card being visible, because the card sits below the sixteen stretch rows (§5). As written, the fix closes the under-count and leaves the over-count path.
