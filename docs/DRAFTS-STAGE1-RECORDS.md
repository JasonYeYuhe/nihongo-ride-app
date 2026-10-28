# 草稿:Stage 1 的 §K / §L 记录文本

> ## ⚠️ DRAFT —— 这里的任何内容都没有被记录。
>
> 这是给你挑的草稿,不是记录。选哪一份、改成什么、放到哪里、放不放,都由你决定。
> 本文件的存在不代表任何检查已经做过或决定不做;`docs/PLAN-STAGE1.md` §L 表里的 ☐ 一个都没动,§K 也没有任何记录。
>
> 写于 2026-09-16(JST),对应走查卡 `docs/WALKCARD-STAGE1.md`。

**怎么读这份草稿**

* `<尖括号>` 是必须替换的空位。每一份都给了"做了"和"决定不做"两种变体;三道检查可以各自选不同变体,所以 §L 部分是按检查分段的。
* 粘贴块用**英文**写,因为它们要放进英文的 `docs/PLAN-STAGE1.md`。说明文字用中文。
* 粘贴块里用弯引号 “…” 括起来的,都是逐字引用 `docs/PLAN-STAGE1.md` 的原文。其余引号是普通引号。
* 你决定后,放进去的那一刻的日期写在记录里 —— 那是记录的日期,不是本草稿的日期。

---

## 1. §K day-0 记录 —— 变体 A:做了

建议位置(你决定):`docs/PLAN-STAGE1.md` §K day-0 段落之后、2026-09-16 新增的框之后,新起一个框。
晚了这件事必须写明:day 0 是 2026-09-09,段落要求 “before the SKU goes on sale”,这个条件**没有满足**。

```markdown
> ### Day 0 known-positive — made <YYYY-MM-DD>, recorded <YYYY-MM-DD>
>
> **Late, and recorded as late.** Day 0 was 2026-09-09. The paragraph above asks for this purchase
> “Day 0, before the SKU goes on sale”; the SKU was on sale from day 0, so that condition was
> **not met**. This purchase was made <N> days after day 0.
>
> | | |
> |---|---|
> | purchase, local time | `<YYYY-MM-DDTHH:MM:SS+09:00>` (JST) |
> | Pacific report day | `<YYYY-MM-DD>` |
> | platform · device · build | macOS · <Mac model>, macOS <version> · App Store 1.36 (61) |
> | storefront · country code | <storefront> · `<XX>` — price shown on the button: `<price string, verbatim>` |
> | units | 1 |
> | matched product type code | `<code exactly as printed by the confirm command>` |
> | confirm | `python3 scripts/sales_report.py --confirm-known-positive --kind purchase --at <YYYY-MM-DDTHH:MM:SS+09:00> --platform macOS --country <XX>` → **exit 0** · transcript `<k-08-confirm-purchase.txt>` sha256 `<…>` |
> | full-window calibration | `python3 scripts/sales_report.py --calibrate` → **exit 0** · transcript `<k-09-calibrate.txt>` sha256 `<…>` |
> | refund requested | `<YYYY-MM-DD>` |
> | refund row | Pacific report day `<YYYY-MM-DD>` · `--confirm-known-positive --kind refund …` → exit `<code>` · transcript `<r-03-confirm-refund.txt>` sha256 `<…>` — or: `<not yet seen as of YYYY-MM-DD>` |
> | registry | `<purchase entry id>`, `<refund entry id>` in `docs/measurements/stage1-known-positives.json` |
>
> Matched rows, as printed by the confirm command:
>
> ```
> <paste the matched-row lines of the transcript here>
> ```
>
> **Excluded from the cohort** by the registry: `kind=purchase` and `kind=refund` entries are always
> subtracted from the purchase numerator (gross / refunded / net / purchase territory), never by more
> than the report cell holds.
> Evidence (screenshots, the Apple receipt with the order ID) is kept outside git; the files and
> their sha256 are in `<manifest file name>`.
```

变体 A 只适用于确认命令**退出 0**、全窗口校准**退出 0** 的情况。如果不是,用下面的 A2。

---

## 1b. §K day-0 记录 —— 变体 A2:买了,但没有确认上(确认命令退出 4 或 7)

已知阳性本身就是一次**可以得到阴性结果**的测试。§K 说买了就要 “Record the date here”,所以这种结果也要记,而且不能套用变体 A。
要知道的事实:如果购买行的产品类型代码不在 `PURCHASE` 里,`validate_registry` 不接受一个 `matched` 条目,`--checkpoint` 会一直扣住上界,
直到分类器被改 —— 改分类器是仪器变更,由你决定,不是记录的一部分。**确认命令打印 `NOT A MATCH` 的情况也一样**(例如 Mac 购买以 `IA1` 上报,
而 `PURCHASE` 把 `IA1` 映射到 iOS):平台写 macOS、代码写 `IA1` 的 `matched` 条目同样会被拒绝(`'IA1' is not a purchase code for 'macOS'`);
条目只能保持 `awaiting-report`、代码留 null,要改的是 `PURCHASE` 的平台映射,同样是你决定的仪器变更。**不要**为了能记录而把平台改写成 iOS。

```markdown
> ### Day 0 known-positive — purchase made <YYYY-MM-DD>, NOT confirmed as of <YYYY-MM-DD>
>
> **Late, and recorded as late.** Day 0 was 2026-09-09. The paragraph above asks for this purchase
> “Day 0, before the SKU goes on sale”; that condition was **not met**. The purchase was made <N>
> days after day 0.
>
> **The known-positive did not come back positive.** A real production purchase was made
> (`<YYYY-MM-DDTHH:MM:SS+09:00>`, Pacific report day `<YYYY-MM-DD>`, macOS, `<XX>`, price shown
> `<price string, verbatim>`), and
> `python3 scripts/sales_report.py --confirm-known-positive --kind purchase --at <…> --platform macOS --country <XX>`
> exited **<4 | 7>** on `<YYYY-MM-DD>` (transcript `<k-08-confirm-purchase.txt>` sha256 `<…>`).
>
> What it printed for D-1..D+1, verbatim:
>
> ```
> <the purchase-class and UNCLASSIFIED lines, and any other-platform notice, as printed>
> ```
>
> **Consequence.** No `matched` registry entry exists, so `--checkpoint` keeps withholding the bound.
> The instrument has not been shown to report this purchase; a later zero is still not a result.
> Next step, decided by the owner: <e.g. investigate the product type code / wait and re-run / other>.
> Refund: <not requested — or requested YYYY-MM-DD, with the reason it was requested before a match>.
```

---

## 2. §K day-0 —— 变体 B:决定不做

这是一个**决定**,不是空着。结果用 §K 自己的话写。

```markdown
> ### Day 0 known-positive — deliberately not walked, decided <YYYY-MM-DD> by the owner
>
> **This is a decision, not a gap.** The owner decided not to make the purchase the paragraph above
> describes. Reason: <the owner's reason>.
>
> **The precondition this abandons, as the paragraph states it:** “Day 0, before the SKU goes on sale
> — non-negotiable, and it is an OWNER action”. It was already not met when this was decided (day 0
> was 2026-09-09 and the SKU was on sale from then), and by this decision it never will be.
>
> **What that costs, in §K's own words.** The purchase is “the money instrument's known-positive,
> and this project does not trust an instrument that has not fired.” And: “§K's own day-0 row is the
> thing that makes a later zero interpretable, and it has not been walked.”
>
> Accordingly `python3 scripts/sales_report.py --checkpoint` keeps withholding the zero-purchase
> bound — it prints `BOUND WITHHELD:` with its reasons, among them that no `kind=purchase` entry has
> `status=matched`, and exits 5 — at N = 35, N = 100, N = 200, 2026-12-08 and 2027-03-08 alike.
> N and the counts are still printed and recorded; only the bound is withheld.
>
> If this decision is reversed later, the reversal and its date are added to this box; nothing
> above is reworded.
```

---

## 3. §L ⚠️ 框的更新 —— 变体 A:做了,附结果

⚠️ 框原文要求:“When the gates are walked, fill the table's `walked` column and say so here.”
框里原有的每一行都不能改(“a gate that gets quietly reworded after it is crossed stops being a gate”),所以下面是**追加**在框末尾的新行。
三道检查可以只取其中几行。

```markdown
>
> **Walked late — recorded <YYYY-MM-DD>.** The precondition above was not met; walking the gates
> after the fact does not change that, and this paragraph does not claim otherwise.
>
> | gate | date (local, with offset) | device · build | outcome |
> |---|---|---|---|
> | No App Store account signed in | `<YYYY-MM-DDTHH:MM+09:00>` | <Mac model>, macOS <version>, App Store 1.36 (61); signed out via <path used> | <outcome>. Price area after ≥ 10 s, verbatim: `<…>`. <If it differs from Expect:> Expect reads “the price area says prices are unavailable and offers Retry”; observed `<…>`; owner's judgement: <…>. |
> | Family Sharing | `<…>` | family member's own <device>, <OS version>, App Store 1.36 (<build>) | <offer shown / owned shown>, after launch and after one relaunch. Positive control added by the walk card (not by this table) — Purchase Sharing visible on that device: <yes / no / not checked>. <Any Expect mismatch, verbatim.> |
> | Cross-platform restore (macOS ↔ iOS) | `<…>` | purchase on the Mac; iPhone <model>, iOS <version>, App Store 1.36 (62) | Direction walked: macOS → iOS only. Pre-purchase offer screenshot: `<file>`. Relaunch: <owned / not owned>; waited 2 min: <no / yes>; Restore tapped: <no / yes → result>. Cold install (delete + reinstall): <owned / not owned>; waited 2 min: <…>; Restore tapped: <…>. <Any Expect / Fail-if mismatch, verbatim.> |
>
> Evidence is kept outside git: `<manifest file name>` (sha256 per file).
```

**表格行怎么填**(本分支给 §L 表加了 `date | device | outcome` 三列;前三列不动,`walked` 列的标记由你选):

```markdown
| **No App Store account signed in** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <Mac model, macOS version, 1.36 (61)> | <one-line outcome> |
| **Family Sharing** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <family device, OS version, 1.36 (build)> | <one-line outcome> |
| **Cross-platform restore (macOS ↔ iOS)** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <Mac → iPhone model, iOS version, 1.36 (62)> | <one-line outcome> |
```

---

## 4. §L —— 变体 B:决定不做(逐道)

框原文:“If they are deliberately not walked, **say that here too** — an unanswered gate and a gate somebody decided to skip must not look alike”。
下面每一条都是你的决定,各有自己的理由空位;只取你决定不做的那几条。

```markdown
>
> **Deliberately not walked — decided <YYYY-MM-DD> by the owner.** This box asks for exactly this:
> “If they are deliberately not walked, **say that here too**”.
>
> * **No App Store account signed in** — deliberately not walked. Reason: <reason>.
> * **Family Sharing** — deliberately not walked. Reason: <reason>.
> * **Cross-platform restore (macOS ↔ iOS)** — deliberately not walked. Reason: <reason>.
>
> The precondition this leaves violated, as the sentence above states it: “Each needs a date, a
> device and an outcome written beside it **before v1.30 is submitted**.”
>
> The asymmetry this box describes has resolved to its second row. macOS 1.36 (build 61) and iOS
> 1.36 (build 62) are `READY_FOR_SALE` (ASC, 2026-10-27), so if one of these paths is broken the cost
> is the row “after `READY_FOR_SALE`”: “a whole new version, and until it clears, live customers
> meet a broken purchase.”
```

**表格行怎么填(决定不做的那几道)** —— 否则决定不做的行和没人回答的行看起来一模一样,而 §L 的框要求两者 “must not look alike”:

```markdown
| **<gate>** | <unchanged> | <unchanged> | <your mark> | <decision date YYYY-MM-DD> | — | deliberately not walked — see the box above |
```

---

## 5. 登记表条目 JSON 草稿

放进 `docs/measurements/stage1-known-positives.json` 的 `"entries"`(没有任何工具会写这个文件,只有你)。
字段按约定:`kind` 取 `purchase` / `refund` / `first_download` / `redownload`;`country_code` 是报表里的**两位**码;
`units` 是正整数(退款也写 1);`status` 在报表出来前是 `awaiting-report`,匹配上后改成 `matched` 并填 `matched_product_type`;
`evidence` 用 `python3 scripts/stage1_walk.py manifest "$EV"` 的输出填。`notes` 里**不要**写订单号或 Apple ID。

**报表行是汇总。** 下载类条目只能说"这一天、这个平台、这个国家的某个单位很可能是这次安装",无法确定地归属。
你的 Mac / iPhone 安装在报表里是首次下载还是重新下载,取决于那个账号的下载历史,这里没有记录 —— 报表出来后按实际代码选 `kind`。

```json
[
  {
    "id": "<YYYY-MM-DD>-mac-purchase",
    "kind": "purchase",
    "report_day_pt": "<YYYY-MM-DD>",
    "platform": "macOS",
    "country_code": "<XX>",
    "units": 1,
    "status": "awaiting-report",
    "matched_product_type": null,
    "local_timestamp": "<YYYY-MM-DDTHH:MM:SS+09:00>",
    "walk_step": "PLAN-STAGE1 §K day-0 known-positive; also §L cross-platform restore's purchase (walk card step 3)",
    "evidence": [
      {"file": "k-01-offer-price.png", "sha256": "<sha256>"},
      {"file": "k-03-road-opened.png", "sha256": "<sha256>"},
      {"file": "k-05-mac-state.txt", "sha256": "<sha256>"},
      {"file": "k-06-apple-receipt.eml", "sha256": "<sha256>"},
      {"file": "k-07-purchase-time.txt", "sha256": "<sha256>"},
      {"file": "k-08-confirm-purchase.txt", "sha256": "<sha256>"}
    ],
    "notes": "<price string shown, verbatim; storefront>"
  },
  {
    "id": "<YYYY-MM-DD>-mac-refund",
    "kind": "refund",
    "report_day_pt": "<YYYY-MM-DD>",
    "platform": "macOS",
    "country_code": "<XX>",
    "units": 1,
    "status": "awaiting-report",
    "matched_product_type": null,
    "local_timestamp": "<refund approval time, YYYY-MM-DDTHH:MM:SS+09:00>",
    "walk_step": "refund of <YYYY-MM-DD>-mac-purchase (walk card step 7)",
    "evidence": [
      {"file": "r-01-refund-request.png", "sha256": "<sha256>"},
      {"file": "r-02-refund-decision.eml", "sha256": "<sha256>"},
      {"file": "r-03-confirm-refund.txt", "sha256": "<sha256>"}
    ],
    "notes": "<refund requested YYYY-MM-DD; Apple's decision>"
  },
  {
    "id": "<YYYY-MM-DD>-mac-install",
    "kind": "first_download",
    "report_day_pt": "<YYYY-MM-DD>",
    "platform": "macOS",
    "country_code": "<XX>",
    "units": 1,
    "status": "awaiting-report",
    "matched_product_type": null,
    "local_timestamp": "<YYYY-MM-DDTHH:MM:SS+09:00>",
    "walk_step": "walk card step 1: App Store install on the owner's Mac",
    "evidence": [
      {"file": "s1-01-mac-preflight.txt", "sha256": "<sha256>"}
    ],
    "notes": "<use kind redownload instead if the report day shows F3 rather than F1 for this platform/country>"
  },
  {
    "id": "<YYYY-MM-DD>-family-install",
    "kind": "first_download",
    "report_day_pt": "<YYYY-MM-DD>",
    "platform": "<iOS | macOS>",
    "country_code": "<XX>",
    "units": 1,
    "status": "awaiting-report",
    "matched_product_type": null,
    "local_timestamp": "<YYYY-MM-DDTHH:MM:SS+09:00>",
    "walk_step": "walk card step 5: §L Family Sharing, family member's own device and account",
    "evidence": [
      {"file": "g2-02-settings-row.png", "sha256": "<sha256>"}
    ],
    "notes": "<family account label only, no personal data>"
  },
  {
    "id": "<YYYY-MM-DD>-iphone-cold-reinstall",
    "kind": "redownload",
    "report_day_pt": "<YYYY-MM-DD>",
    "platform": "iOS",
    "country_code": "<XX>",
    "units": 1,
    "status": "awaiting-report",
    "matched_product_type": null,
    "local_timestamp": "<YYYY-MM-DDTHH:MM:SS+09:00>",
    "walk_step": "walk card step 4B: §L cross-platform restore, cold install on the iPhone",
    "evidence": [
      {"file": "g3-12-ios-state.txt", "sha256": "<sha256>"}
    ],
    "notes": "<use kind first_download instead if the report day shows 1F; the step-1 iPhone install gets its own entry the same way>"
  }
]
```

**决定要先于读数,并写明日期。** `exclude_walk_first_downloads_from_N` 会改变 N。§K 在分母重新计价那件事上写下的原则是
“What is NOT available any more is deciding it after seeing a checkpoint”,改动要 “the change and its timestamp go in this box”。
而登记表里一旦有 `first_download` 条目、这个决定还是 null,`--checkpoint` 就会把两种 N 都打印出来;反过来,安装**没登记**时工具看不见它们,
会照常打印上界。所以截止点是**任何一次窗口里包含 walk 安装报表日的 `--checkpoint` 之前**,最稳的是走查之前。把下面这段(日期是做决定的那一刻)记进 §K:

```markdown
> **Decided <YYYY-MM-DDTHH:MM+09:00>, before any `--checkpoint` reading that held a walk install:**
> walk-caused first-time downloads are <subtracted from | kept in> N
> (`decisions.exclude_walk_first_downloads_from_N` = <true | false> in `docs/measurements/stage1-known-positives.json`).
> Reason: <reason>.
```

**2026-09-17:上面这段决定已记进 §K,成为 “DECIDED 2026-09-17” 框的第 1 条(true:走查造成的安装登记为 `first_download` 后从 N 里减掉),由代理在你的授权下做出,早于任何走查和任何含走查数据的读数。**

两个决定字段(`"decisions"`)也只由你填:`exclude_walk_first_downloads_from_N` 为 null 且窗口里存在 `first_download` 条目时,
`--checkpoint` 不减、打印未决条目数,并扣住上界;`exclude_owner_refund_from_refund_ceiling` 只记录和回显,这一轮没有工具评估 day-180 退款上限。
(2026-09-17:两个字段都已按框第 1、6 条在登记表里设为 `true`,由代理在你的授权下写入;`entries` 仍是空的。上面说的 null 行为因此不会再出现,除非有人把它改回 null。)

---

## 6. 给你的问题 —— 没有替你决定

**2026-09-17 已决定:** 这些问题在 2026-09-17 由代理在你的授权下(“好的 你继续全部做掉吧 你全权负责”)做了决定,见 `docs/PLAN-STAGE1.md` §K 的 “DECIDED 2026-09-17” 框;标题里的"没有替你决定"是 2026-09-16 写下时的状态,问题原文一字未删,每条后面的 `→ decided:` 是对应框条目的一行摘要,两者不一致时以框为准。

§K 没有写清的地方。每条只写"不同回答会怎样改变读数",**不给建议**。编号后括号里是审计文件里的原编号。
记号:`g` = 真实售出单位,`r` = 真实退款,`k` = 走查造成的安装。

1. **(Q3.4)你自己设备上的计数器算不算 “returned counter”?** §K 的 STOP 分支没说是谁的计数器。
   算:排除后零购买 + 你的设备在 kyoto 桶里 `offerAppeared > 0` → STOP(走查本身会产生 `offerAppeared`;它落不落在 kyoto 桶,取决于那台设备的累计里程是否 ≥ 25 km,未核实)。不算 → STOP BUILDING / UNINTERPRETABLE。
   **这是清单里影响最大的一条,它直接翻转分支。** 退款之后你算不算「non-buyer」(`docs/PLAN-WINDOW.md` 的用语,不是 PLAN-STAGE1 的)也没写。
   → decided: 框第 2 条 —— 走查设备(你的、家人的)上的计数器**不算** “returned counters”;零购买且 kyoto 桶里的 `offerAppeared` 只来自走查设备时,读作 STOP BUILDING / UNINTERPRETABLE,永远不读作 STOP。
2. **(Q3.2)走查造成的安装要不要从 N 里减掉?**(登记表 `exclude_walk_first_downloads_from_N`;**时机见 §5:要在看到含 walk 安装的读数之前定**)k 在 0 到 4 之间,前提是它们真是首次下载。
   不减:真实安装的上界是 3/(N−k),N = 35 时 k=0 为 8.6%、k=2 为 9.1%、k=4 为 9.7%;N = 100 时 3.00% → 3.06%。
   没有哪条规则只因 k 翻转;变的是检查点什么时候触发、打印的上界是多少。决定为 null **且登记表里有 `first_download` 条目**时 `--checkpoint` 扣住上界;没登记的安装工具看不见,不会因此扣住。
   → decided: 框第 1 条 —— 走查造成的安装不算 cohort:登记为 `first_download` 后从 N 里减掉(`decisions.exclude_walk_first_downloads_from_N = true`,已写进登记表);由此产生的义务是每一次走查安装都要在任何窗口包含其太平洋报表日的 `--checkpoint` 之前登记。
3. **(Q3.3)家人的安装算不算 cohort?** 算:N 和那个 storefront 的下载数 +1(两台设备 +2),它的计数器也可能成为 “returned counter”
   (但 0 米时 `offerAppeared` 落在 nihonbashi 桶,除非那个账号骑过 25 km,否则触发不了 STOP)。不算:这些数不动,它的计数器忽略。
   → decided: 框第 1、2 条 —— 家人的安装是走查安装,不算 cohort(登记为 `first_download` 后从 N 里减掉);家人设备上的计数器也不算 “returned counters”。
4. **(Q3.5)退款把净额抵消,算不算 “exclude it from the cohort”?** (i) 算:从购买行到退款行之间(最长约 90 天)net = 1,GO 会因你那一单触发,
   “at any point” 甚至可以读成 GO 已经永久触发。(ii) 不算,必须显式排除:GO 永远不会因你那一单触发。
   事实说明,不是建议:按本轮约定,`--checkpoint` 实现的是 (ii) —— `purchase` 和 `refund` 条目总是从购买分子里减掉(最多减到报表那一格实际持有的数量);选 (i) 意味着要改这个实现。
   → decided: 框第 3 条 —— (ii):显式排除,不靠净额抵消;你的购买和退款通过登记表减掉,GO 永远不会因你那一单触发,不管退款行到没到。
5. **(Q3.6)Apple 拒绝退款怎么办?** §K 没有规则。按 (i),GO 永久成立;按 (ii),登记的购买照样被减掉,只是永远没有退款行可匹配。
   → decided: 框第 4 条 —— 拒绝退款不改变排除:如实记录拒绝,购买照样被排除。
6. **(Q3.7)已知阳性要不要等到退款行也出现才算完成?** 要:day 0 要等负数行出现才算完,可能几周。
   不要:day 180 的退款数为零时,那个零来自一条从未触发过的代码路径 —— 和购买为零是同一个问题。
   事实说明,不是建议:`--checkpoint` 现在的实现是"不要" —— 购买条目一旦 `matched` 就可能打印上界,不等退款行;选"要"意味着要改这个实现。
   → decided: 框第 5 条 —— 不等退款行:`--confirm-known-positive --kind purchase` 退出 0(行匹配上、全窗口 `--calibrate` 通过)即购买路径的已知阳性完成;退款行是退款路径自己的已知阳性,看到时另记,在那之前 day-180 的任何退款数都标明来自一条从未触发过的路径。
7. **(Q3.1)你的退款要不要从 day-180 退款上限里排除?**(登记表 `exclude_owner_refund_from_refund_ceiling`,只记录不应用)
   r = 1 时:购买和退款都算 → g ≤ 9 就触发停售;都排除 → “no action”;退款算但你那单不进分母 → g ≤ 10 触发。
   r = 2 且 g ≤ 18 时:都算 → 3 次退款 → 调查产品主张;排除 → 2 次,只有 g ≤ 10 才停售。另外 “units” 是毛还是净、“n ≤ 18” 的 n 是什么,都没定义。
   → decided: 框第 6 条 —— 你的退款不是客户退款:它和你那一单都从 day-180 退款上限里排除(`decisions.exclude_owner_refund_from_refund_ceiling = true`,已写进登记表,仍然只记录不应用);上限里 “units” 指客户的毛售出单位,“n ≤ 18” 的 n 是同一个数。
8. **(Q3.8)day 0 和登记表用哪个日历?** 报表是太平洋日;JST 16:00 前的购买落在前一个太平洋日。登记表同时记 `report_day_pt` 和带时区的本地时间。
   §K 的 “DAY 0 = 2026-09-09” 是日本时间的观察日;按太平洋时间,macOS 1.31 的上架是 09-07 或 09-08(release-days 核对,未能定案),
   `--since 2026-09-09` 不含太平洋 09-08。今天的缓存里 09-08 没有 F1/1F 行,所以按 09-08 还是 09-09 算 N 一样;09-07 这里没有核对。
   → decided: 框第 7 条 —— 报表日一律用太平洋日,cohort 从太平洋报表日 2026-09-09 起;太平洋 09-08 有 0 个首次下载、09-07 有 1 个(缓存,2026-09-17 读),保留 09-09 就把那 1 个留在外面,方向:N 更小。
9. **(Q3.9)打印的阈值还是 3/N?** §K 写 “8.6% / 3.1% / 1.4% are `3/N`”,但 3/100 = 3.00%、3/200 = 1.50%;3.1% 和 1.4% 是旧日历值 3/97.5 和 3/208.9。
   读数必须选一个。0.1 个百分点的差,比 N = 200 时排除最多 4 个安装的影响还大。`--checkpoint` 按约定打印的是 3/N 和 3/(N+114)。
   → decided: 框第 8 条 —— 检查点触发时用观测到的、调整后的 N 算 `3/N`;8.6% / 3.1% / 1.4% 是日历时代的示例,和 `3/N` 在第二位小数上不一致时以 `3/N` 为准。
10. **(Q3.10)基数和 N 之间的缺口。** 114 的基数截止 2026-08-27;08-28 到 09-08 的 23 个安装(累计 114 → 137)既不在基数里也不在 N 里,
    所以 “≤ 323 devices ever exposed” 没算它们。影响的是上限分母:3/(N+114) 还是 3/(N+137)。你以前自己的下载可能在基数里、在缺口里、或者都不在,未核实。
    → decided: 框第 9 条 —— 上限分母保持预注册的 +114;缺口里的 23 个安装两边都不算,所以 “against the ceiling” 那一行最多少算 23 台设备的曝光;不改,因为它是预注册的量,而且没有决策规则读那一行。
11. **(Q3.11)用哪个窗口。** “Window: 90 days” 和 “Go / iterate / stop at day 90” 从未修订,而修订框写的是 N = 200 或 day 180。
    如果排除是在固定窗口上做的,选哪个窗口会改变被排除的是哪些行。
    → decided: 框第 10 条 —— 以 2026-09-09 修订框的时间表为准(N = 35 / N = 100 / 2026-12-08 中期记录 / N = 200 或 2027-03-08 决定 / 2027-03-08 退款),旧的 “Window: 90 days” 和 “at day 90” 在决定上被它取代;排除适用于太平洋报表日在 2026-09-09 到本次读数最新报表日之间的每一条登记。

### 另外两个问题 —— 这里**允许**给建议,并明确标为代理的建议

12. **校准的 M4 盲区。** 把分类对调(UPDATE := F1/1F,DOWNLOAD := F7)后 `--calibrate` 照样 PASS(1.24x / 1.65x)。
    `sales_report.py` 的文档字符串说 「updates must be release-locked and downloads must not be」,后半句只被**打印**,从未被**检查**。
    所以今天的 「calibration OK」 只证明"发布日有东西升高",证明不了 F7 就是更新。这不等于分类是错的 —— 分类本来就是从本 app 自己的数据推出来的(见脚本文档字符串),而且没有证据表明它错了;只是这个 OK 比文档说的弱。
    → decided: 框第 11 条 —— 加了 check B(更新的升高倍数必须大于首次下载的升高倍数),但只卡 `--checkpoint` 的上界,`--calibrate` 不变;事先写定后在缓存上实测一次:2.35x > 1.54x,PASS,M4 对调在这个定义下会读成 1.54x / 2.35x、在 check B 上失败 —— 见 `docs/measurements/2026-09-16-release-day-control.md` §6。
    **2026-09-17 同晚更正:** 这次 PASS 是**一致性检查,不是盲测** —— "后一天"这条规则来自更新潮落点,暴露日均值恰好是 09-16 已看过的 M2、M3 的平均,结果事先可以算出;它不能单独证明 M4 盲区在真实数据上已被堵上。见 §K 框末尾的更正。
13. **"发布日"是什么意思。** 现有 `RELEASE_DAYS` 是日本时间的观察日(≈ 发布后的那个太平洋日,也就是更新潮到达的那天);08-22 没有任何来源;
    交接文档提的 09-04 / 09-07 / 09-09 / 09-10 没有一个是太平洋发布日;09 月唯一确定的发布日是 09-11。不同定义下的实测(2026-09-16,真实缓存,无网络):
    现有集合 1.65x / 1.24x PASS;只用确定的太平洋发布日 {08-11, 08-15, 08-17, 08-31, 09-11} updates 1.14x、downloads 1.75x PASS;
    发布日 +1 {08-12, 08-16, 08-18, 09-01, 09-12} 2.43x / 1.22x PASS;加上交接文档的四个九月日子 1.41x / 1.08x PASS(但那些不是发布日)。
    → decided: 框第 11 条 —— 第二个发布日对照:曝光日 = 确定的太平洋发布日 {08-11, 08-15, 08-17, 08-31, 09-11} 及其后一天,不确定的日子及其后一天两边都不算,其余从 2026-08-01 起为其他日;它只卡上界,所以 `--calibrate` 前后仍是同一个仪器,下面代理建议里"放在已知阳性确认之后"的时机顾虑由此避开;实测(10 个曝光日 / 7 个其他日)见 `docs/measurements/2026-09-16-release-day-control.md` §6。

> **代理的建议(不是决定,只针对第 12、13 条):**
>
> * 只根据**发布时间的证据**(不看 F7 数量)预先写定:发布日 = "确定的太平洋发布日**及其后一天**";
>   不确定的日子放进第三类"排除",既不算发布日也不算其他日(现有代码表达不了这一类,需要改);08-22 没有来源,不再作为发布日。
> * 加一条检查:**更新的升高倍数必须大于下载的升高倍数**。它会让 M4 变红(1.24x < 1.65x)。
> * **要明说的两点:** "发布日及其后一天"这个合并集合**没有测过**(测过的是只有发布日、只有后一天);
>   而在"只有发布日"的定义下(1.14x vs 1.75x),这条新检查**会失败** —— 所以它必须在选定的定义上先测,再决定是否采用。
>   另外 M0–M6 的结果已经被看过了,现在挑定义天然带着"知道哪个会过"的污染;只按发布时间证据选,是把这份污染压到最小的办法,不是消除它。
> * **时机:如果要采用,放在已知阳性确认之后。** §K 要的是 “`--calibrate` still passes”:购买前后必须是同一个仪器,"仍然"才有意义。
>   在确认之前改仪器,"仍然通过"比较的就是两个不同的仪器。

---

## 7. 一个标记出来、但没有被使用的观察

§L 那句前提(`43d0da7` 的第 663 行;之后 §J、§K 加了文字,行号下移,**按原文定位,不要按行号**;内容逐字未变)字面上约束的是 **“before v1.30 is submitted”**。它字面上**没有**约束 v1.31 或 v1.32。

这个观察在这里只是报告给你。本分支的任何文字都**没有**用它 —— 既没有用来论证"v1.31/v1.32 不需要这些检查",
也没有用来把这句话扩展到后续版本。那句话保持逐字不变;怎么读它,由你决定。

---

## 8. N = 200 记录 —— 草稿(数字留空,到当天填;分支行留给你)

写于 2026-10-28(JST),对应 `docs/PLAN-V1.37.md` P0-8(`:209`)和 C-2 卡(`:98`)。本文件里原来**没有** N = 200 的草稿,这一节是新加的。

**它和前七节不一样的地方。** 前七节是你的 §K / §L 记录草稿,只有你能放。这一份是**检查点记录**,按 C-2 卡的默认,到时由代理照 N = 35、N = 100 的先例提交进 `docs/measurements/stage1-checkpoints.md`(只写数字,`:98`)。它**不进 §K,也不进 `docs/PLAN-STAGE1.md`**。分支由你读(`stage1-checkpoints.md:16-17` 规则 3;`PLAN-V1.34.md:1087`),这份记录里不替你写。

**形状**完全照 N = 100 那一条(`docs/measurements/stage1-checkpoints.md:183-290`):标题 → 规则 4 → 读数原文 → 规则 5 → 规则 7 → 规则 2 和 3。多出来的只有最后一行"分支",留空给你。

**跑之前(都做完才跑):**
1. **v1.37 的上架日已经进了 `FIRM_RELEASE_DATES_PT`**(P0-2 的批准日杂事,`docs/PLAN-V1.37.md:202`)。少了它,`--checkpoint` 会以 "release registry incomplete" 扣住上界(`scripts/sales_report.py:1372-1378`)。v1.37 的 build 是 macOS 62 / iOS 63(`docs/STATE-2026-10-27.md:73`)。
2. **规则 4**:窗口里每一个走查安装、每一个参与者安装都已登记进 `docs/measurements/stage1-known-positives.json`。最小走查也有安装(Mac 和 iPhone,`docs/PLAN-V1.37.md:101`)。没登记的安装工具看不见(`docs/PLAN-STAGE1.md:778-781`)。
3. 命令和 N = 100 一样:`python3 scripts/sales_report.py --checkpoint`。**不加** `--no-cache`、`--since`(它会拒绝,`scripts/sales_report.py:1666-1673`)。输出存在仓库外,记下 md5。
4. 同一个 JST 日跑 `python3 scripts/review_watch.py`,原文贴进来(规则 7,`stage1-checkpoints.md:26-29`)。
5. 不手算任何上界(规则 2),不评分支(规则 3)。
6. 什么时候:工具第一次对 N = 200 打印 `REACHED` 的那次读数。按 2.596/天投影,太平洋报表日约 11-23..25,日本时间约 11-25..27 读到(`docs/PLAN-V1.37.md:171`);每多一个登记的走查安装约晚 0.4 天。

**要填的空,当天从工具输出里抄,不从这里抄:** 日期、窗口、所有计数、暴露日和其他日列表(会多出 2026-10-26、10-27 和 v1.37 的上架日及其后一天)、退出码、md5。

````markdown
### N = 200 — the reading of <YYYY-MM-DD> (JST)

**Rule 4: confirmed before the reading.** <one of the two below>

<(i) No walk happened.> The agent made this finding before running, under the owner's delegation
(*"你想办法自己做掉 你全权负责 没办法再找我"*, 2026-10-07; renewed *"你继续做到收尾吧"*, 2026-10-26). It is the
agent's finding, not the owner's confirmation. The window is Pacific 2026-09-09 .. <YYYY-MM-DD>. Finding: **no walk
install and no registered-session install.**
* `stage1-known-positives.json` has <0> entries, and no session was ever registered (`docs/sessions/` holds only its
  README).
* The walk has not started: <the owner has never said "开始走查", and no walk snapshot was written after <date>>.
* On this Mac: `stage1_walk.py preflight` on <YYYY-MM-DD> <finds no `/Applications/Nihongo Ride.app`, and
  `NihongoRide.entitlement.v1` absent>; LaunchServices has <0> records of the bundle under `/Applications`.
* The reading below shows <0> purchases, so the walk never reached its purchase step.
* **Limits, as in the N = 35 and N = 100 records:** a download never opened, devices on other accounts, a family
  member's devices, and the owner's iPhone after 2026-09-15 cannot be seen. No device was queried. The margin is
  <N − 200> units (N = <N> against 200).

<(ii) A walk happened.> <"Owner confirmed <YYYY-MM-DD>: …" verbatim, or the agent's finding under the delegation,
labelled as such.> Every walk install in Pacific 2026-09-09 .. <YYYY-MM-DD> is registered: <entry ids>. <The margin
is <N − 200> units.>

**The reading, verbatim.** `python3 scripts/sales_report.py --checkpoint`, run <YYYY-MM-DD> (JST), newest report day
Pacific <YYYY-MM-DD>. Kept outside the repo at `<work dir>/checkpoint-<YYYY-MM-DD>.txt`, md5 `<…>`. The last line is
the shell's capture of the exit code. <There were no adjusted purchases, so there is no territory line. — or delete
this sentence if the tool printed one.>

```
<replace this whole block with the tool's output, verbatim. Check it against this skeleton:>
checkpoint — PLAN-STAGE1 §K, day 0 = 2026-09-09
  registry docs/measurements/stage1-known-positives.json · schema 1 · <n> entries
  decisions: exclude_walk_first_downloads_from_N=true · exclude_owner_refund_from_refund_ceiling=true
    (exclude_owner_refund_from_refund_ceiling is echoed, never applied: nothing here evaluates the day-180 refund ceiling)
window 2026-06-06 .. <YYYY-MM-DD>  (<n> days)
  report states: data=<n>
calibration (the full default window — every check --calibrate runs):
  positive control · updates  release-day <…>/d vs other <…>/d = <…>x
  positive control · downloads release-day <…>/d vs other <…>/d = <…>x
  OK — the instrument responds to known-positive events.
second release-day control (PLAN-STAGE1 §K "DECIDED 2026-09-17" item 11 — gates the bound only; --calibrate does not run it):
  exposure days (<n>): <…>
  other days (<n>): <…>
  updates (F7)                  exposure <…>/d vs other <…>/d = <…>x
  first-time downloads (F1/1F)  exposure <…>/d vs other <…>/d = <…>x
    other-day first-time downloads <…>/d before 2026-09-09 over <n> day(s), <…>/d from 2026-09-09 over <n> day(s)
  OK — check A: updates elevated on exposure days · check B: update ratio <…>x > first-time download ratio <…>x
cohort since day 0: 2026-09-09 .. <YYYY-MM-DD>  (<n> days · report states: data=<n>)
  2026-09-08 first-time downloads (F1/1F): 0 — N is the same whether day 0 is 09-08 or 09-09
  FIRST-TIME DOWNLOADS  raw <n> (macOS <n> · iOS <n>)
    registered walk first_download: <none in the cohort window | n entries · n unit(s) · SUBTRACTED (decision true)>
  N = <n> (macOS <n> · iOS <n>)  first-time downloads F1+1F since 2026-09-09
  PURCHASES  raw gross <n> (macOS <n> · iOS <n>) · refunded <n> · net <n>
    registered, always subtracted (§K: "exclude it from the cohort"): purchase <n> · refund <n>
  ADJUSTED PURCHASES  gross <n> (macOS <n> · iOS <n>) · refunded <n> · net <n>
  registry entries: <none | one line per entry>
pre-registered checkpoints (§K, quoted):
  REACHED      N = 35   record, falsifies nothing
  REACHED      N = 100  first checkpoint that can falsify §D's 8.2%
  <not reached | REACHED>  2026-12-08 (day 90)  interim record, no decision attached — a dated waypoint regardless of N
  REACHED      N = 200, or 2027-03-08 (day 180), whichever comes first  the go / iterate / stop decision
  not reached  2027-03-08 (day 180)  refunds
  (read at N = <n>, with <YYYY-MM-DD> the newest report day read)
<the tail is one of these, exactly as printed:>
<(A′, no matched known positive)>
BOUND WITHHELD:
  - no matched day-0 known-positive purchase: the registry holds no kind=purchase entry with status=matched in the cohort window — §K: "this project does not trust an instrument that has not fired"
<(and, if adjusted net purchases > 0)>  (and the zero-purchase bound would not apply anyway: adjusted net purchases = <n>)
exit=5
<(matched known positive, zero purchases)>
BOUND (rule of three, 95%) — zero adjusted net purchases in N = <n> first-time downloads (F1+1F) since 2026-09-09, <which>:
  per-install conversion ≥ 3/<n> = <…>% is ruled out
  against the ceiling denominator N + 114 = <n>: ≥ 3/<n> = <…>%
exit=0
<(matched known positive, purchases > 0)>
ZERO-PURCHASE BOUND DOES NOT APPLY: adjusted net purchases = <n> since 2026-09-09
exit=0
```

<Only if N is within a release day's installs of 200:> The 2026-10-26 box asks for this split: “Near a threshold,
split the cohort at v1.36's `FIRM_RELEASE_DATES_PT` entries” (`docs/PLAN-STAGE1.md:1059-1060`). <`--checkpoint
--daily` output, verbatim, and <the same for v1.37's box, if it asks>.>

**Rule 5: what this reading shares data with.** Its cache contains every report day of:
* the N = 35 record (2026-09-25 JST) and its re-runs, and the N = 100 record (2026-10-26 JST);
* the agent readings of 2026-09-29 (N = 50), 2026-10-03 (N = 59) and 2026-10-07 (N = 68);
* the cache-only re-runs and row scans of the 2026-10-07 investigation (through 10-01);
* the calibration and release-day controls computed on those days;
* the P0-7 census runs of 2026-10-27 (`sales_report.py --since 2026-09-20 --until 2026-10-25`,
  `docs/measurements/v137-funnel-post-day0.md:118-127`);
* the offline cache tallies of 2026-10-28 made for `docs/PLAN-WINDOW2.md` §5 (through Pacific 10-26);
* <every later reading, run or tally, by date>.
None of them was blind to it. <What was decided before this reading, and that nothing in it depends on this reading.>

**Rule 7: `review_watch.py`, the same JST day, verbatim.** <one sentence per review since day 0 a person read against
§K's “negatively”.>

```
<review_watch output, verbatim, including its exit code and the shell's exit line>
```

**Rules 2 and 3.** <one of:>
<(bound withheld)> No bound is computed, because the tool withholds for the <one> reason<s> quoted above. With no matched
known positive, N = 200 is a record of N only (`docs/PLAN-V1.34.md:1126-1128`).
<(bound printed)> The bound is quoted as the tool printed it, without a caveat (rule 2).
No branch is evaluated here (rule 3).

**Branch** (C-2(a)): read by the owner against §K's text (`docs/PLAN-STAGE1.md:526-554`), not by this file.
_(owner — blank on silence. If the owner reads it, the owner's words are quoted here verbatim with their date, or this
line points to where the owner wrote them.)_
````

**这份草稿里我拿不准的一处。** 规则 3 说分支 "not in this file"(`stage1-checkpoints.md:16-17`),C-2 卡又说代理 "leaves the
branch line for the owner"(`PLAN-V1.37.md:98`)。上面那一行两边都守:它不评分支,只给你留一个位置,你不写就是空的。要不要这一行、
放在这里还是放进你自己的 §K 框,由你定。

---

## 9. 附录 A 的 owner 框 —— 可直接复制的版本

写于 2026-10-28(JST)。底本是 `docs/PLAN-V1.37.md` 附录 A(`:556-605`)。**`PLAN-V1.37.md` 没有改动**;下面每一处和底本不同的地方都标了出来,
理由写在框后面。逐条核对了每一句引文在 `892ef68` 是否还这么写。

**本节的引号约定**(比本文件开头的约定宽一点):粘贴块里弯引号 “…” 括起来的,都是逐字引用其后标注的那个文件那一行,
连 `*` / `**` 强调符号也照抄;不再只限于 `PLAN-STAGE1.md`。`<尖括号>` 是必须由你替换的空位。

**什么时候用哪一个**
* **A-1**:N = 200 读数之后,你选 E3(C-2(b))。放进 `docs/PLAN-STAGE1.md` §K,只由你放。
* **A-2**:你在 N = 200 之前说"B"(C-0)。同上,只由你放。
* **A-3**:走查记录,就是本文件的 §1 / §1b / §2 / §3 / §4,原样不动。
* 你不回:三个都不写,§K 现有文字照原样管(`PLAN-STAGE1.md:526-554`,第 10 条在 `:808-810`)。
* 不选 E3、但想写 Window 2 的后果(C-2(e)):不需要 §K 框,直接把你的话填进 `docs/PLAN-WINDOW2.md` §2 那几格,带日期。
* C-2(f)("P1-12 等一个已知阳性")不是 §K 框,一句话说给代理即可(`PLAN-V1.37.md:243`)。

### A-1:N = 200 读数之后,你选 E3

```markdown
> ### 📌 DECIDED <YYYY-MM-DD> (JST) by the owner, AFTER reading the N = 200 record: E3 and its price
>
> Written by the owner, or drafted by the agent and confirmed in the owner's words: "<verbatim>". Nothing above is
> reworded. No threshold, branch, denominator or exclusion moves.
>
> 1. The Stage 1 window ended by its own rule at the N = 200 reading of <YYYY-MM-DD>. Its branch, read by the owner,
>    was <GO / STOP / STOP BUILDING (UNINTERPRETABLE)>.
> 2. *(only if the branch is STOP or STOP BUILDING)* The owner overrides, for exactly one good, a one-time depth
>    unlock (PLAN-V1.37 §E, E3) with every existing install grandfathered: §K's “instrumentation and
>    placement, not price and not Pro” (`PLAN-STAGE1.md:551-552`); “zero still means *do not build Pro*”
>    (`PLAN-STAGE1.md:176`); “near-zero over the window **kills H2 as well as H1** — do not build Pro”
>    (`PLAN-V2-PRODUCT.md:547`); “**Nobody tips** → the constraint is distribution or desire, not checkout. Do not
>    build Pro.” (`PLAN-V2-PRODUCT.md:236`); §J “Not in this plan”, item “**Building Pro before Stage 1 reports** — the
>    whole point of the staging” (`PLAN-V2-PRODUCT.md:633, 639`); and PLAN-WINDOW §G “What must not be built”, row
>    “**A second SKU**” (`PLAN-WINDOW.md:265-269`), whose separate precondition, the counter split, v1.38's P1-11
>    meets. This is a decision made after seeing the reading, and is recorded as such.
> 2b. *(only if the branch is GO, and only if wanted)* GO's “Run to day 90 anyway for the repeat rate.”
>    (`PLAN-STAGE1.md:528-529`) is cut short on <YYYY-MM-DD>, so v1.38's offer-changing items may be released before
>    Pacific 2026-12-09.
> 3. E3's price: CNY <owner's figure> (base territory CHN, manual price), effective the day the release carrying it is
>    live. The road west's price: <unchanged at CNY 10.00 / owner's figure>.
> 4. *(optional)* E3's boundary: <candidate 1 / candidate 2 / owner's words>.
> 5. Window 2 is pre-registered in `docs/PLAN-WINDOW2.md` (variant E) before that release's `--submit`. Its branch
>    consequences, in the owner's words: <GO-2 → … / BELOW-FLOOR → … / ZERO → … / ZERO, pipeline unproven → … /
>    owner box mid-window → … / refunds at D₀′+180 → … / a purchase review or a lost-access report → …, or "as drafted
>    in PLAN-V1.37 §H" for the rows §H drafts>.
```

**和底本不同的地方,以及为什么:**
1. **引文改成逐字。** 底本第 2 条的几句是转述或拼接:
   * "not price and not Pro" (§K) —— 原文是 “instrumentation and placement, not price and not Pro”(`PLAN-STAGE1.md:551-552`),补全并标了行号。
   * "zero still means do not build Pro" (`:174-176`) —— 原文 `:176` 带强调:“zero still means *do not build Pro*”。
   * "Nobody tips → … Do not build Pro" —— 原文在 `PLAN-V2-PRODUCT.md:236` 一行里,照抄全句。
   * "Not in this plan: … Building Pro before Stage 1 reports" (`:639`) —— "Not in this plan" 是 `:633` 的小节标题,不是句子的一部分;改成标题 + 条目两段引文。
2. **加了 2b(底本没有)。** §0 和 §I 都说 GO 之下 v1.38 的改价页部分不早于太平洋 12-09 上线,"unless the owner writes in the C-2 box that the repeat-rate run is cut short"(`PLAN-V1.37.md:56`、`:384`),C-2(b) 也列了它(`:98`),但底本 A-1 没有地方写这一句。不需要就删掉 2b。
3. **第 5 条列全了 `PLAN-WINDOW2.md` 变体 E 的每一个空格。** 底本只列 ZERO / BELOW-FLOOR / GO-2 三个;`PLAN-WINDOW2.md` 还留了 "ZERO, pipeline unproven"、"owner box mid-window"、day-180 退款、被盯的评论和丢失权限报告。§H 只给其中一部分起草了后果(`PLAN-V1.37.md:365-372`),所以 "as drafted in PLAN-V1.37 §H" 只能用于 §H 写过的那几行。
4. 第 5 条注明了"variant E"。

### A-2:N = 200 之前,你选 B

```markdown
> ### 📌 ENDED EARLY <YYYY-MM-DD> (JST) by the owner's decision, after the N = 35 and N = 100 readings had been read
>
> This is a decision made after seeing data, recorded as such. §K says of deciding after a checkpoint: “What is NOT
> available any more is deciding it after seeing a checkpoint” (`PLAN-STAGE1.md:390-391`).
> The final Stage 1 record is the N = 100 reading of 2026-10-26: N = 122, 0 purchases, BOUND WITHHELD, for the one
> reason that no matched known-positive purchase exists (`docs/measurements/stage1-checkpoints.md:228-246`). No bound
> is quoted, and the zero is UNINTERPRETABLE. If a known positive is matched later, 3/122 = 2.46% may be quoted as
> arithmetic, never as a registered reading.
> Nothing above is reworded. Window 2 begins with the first release that changes the offer, under a pre-registration
> committed before its `--submit`. E3's price is the owner's, recorded before that release.
>
> The owner also overrides, for exactly one good, a one-time depth unlock (PLAN-V1.37 §E, E3) with every existing
> install grandfathered, the written rules that are not §K branches and still bind when the window ends at
> N = 122 with 0 purchases: “zero still means *do not build Pro*” (`PLAN-STAGE1.md:176`); “near-zero over the
> window **kills H2 as well as H1** — do not build Pro” (`PLAN-V2-PRODUCT.md:547`); “**Nobody tips** → the
> constraint is distribution or desire, not checkout. Do not build Pro.” (`PLAN-V2-PRODUCT.md:236`); §J “Not in this
> plan”, item “**Building Pro before Stage 1 reports** — the whole point of the staging” (`PLAN-V2-PRODUCT.md:633,
> 639`); and PLAN-WINDOW §G “What must not be built”, row “**A second SKU**” (`PLAN-WINDOW.md:265-269`). This too is
> a decision made after seeing data.
```

**和底本不同的地方:** 只有引文改成逐字(同 A-1 第 1 点),并给 "§K forbids deciding 'after seeing a checkpoint'" 补上原句和行号
(`PLAN-STAGE1.md:390-391`),给 N = 100 读数补上出处(`stage1-checkpoints.md:228-246`)。3/122 = 2.459…%,写作 2.46%,和底本一致。
**它只在 N = 200 读数之前有效**:标题写的是"after the N = 35 and N = 100 readings";N = 200 之后就不是 B 了,而是 A-1。

### A-3:走查记录

原样不动:本文件 §1 / §1b(走了,代理填数字)、§2 和 §4(决定不走,只由你贴或用你的原话确认)、§3(§L 结果)。
最小走查下,Mac 上第 1 道检查的放弃,由你在选 (b) 时记在 §4 下;第 2、3 道要么在退款之前补走,要么由你记在 §4 下。代理一条都不记
(`PLAN-V1.37.md:605`)。

**核对时发现、但这里没改的一处:** §1、§3、§4 的粘贴块写死了 "App Store 1.36 (61)" / "1.36 (62)"(本文件 `:35`、`:139-141`、
`:149-151`、`:173-174`)。走查在"批准日杂事之后正在上架的那个版本"上做(`PLAN-V1.37.md:97`),11-15 那天可能已经是 1.37
(macOS 62 / iOS 63)。P0-1 的杂事包括 DRAFTS,P0-2 的杂事清单没有列它(`PLAN-V1.37.md:202`)。到时按实际版本改那几个数字。
