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
> | platform · device · build | macOS · <Mac model>, macOS <version> · App Store 1.32 (56) |
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
直到分类器被改 —— 改分类器是仪器变更,由你决定,不是记录的一部分。

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
> | No App Store account signed in | `<YYYY-MM-DDTHH:MM+09:00>` | <Mac model>, macOS <version>, App Store 1.32 (56); signed out via <path used> | <outcome>. Price area after ≥ 10 s, verbatim: `<…>`. <If it differs from Expect:> Expect reads “the price area says prices are unavailable and offers Retry”; observed `<…>`; owner's judgement: <…>. |
> | Family Sharing | `<…>` | family member's own <device>, <OS version>, App Store 1.32 (<build>) | <offer shown / owned shown>, after launch and after one relaunch. Positive control added by the walk card (not by this table) — Purchase Sharing visible on that device: <yes / no / not checked>. <Any Expect mismatch, verbatim.> |
> | Cross-platform restore (macOS ↔ iOS) | `<…>` | purchase on the Mac; iPhone <model>, iOS <version>, App Store 1.32 (57) | Direction walked: macOS → iOS only. Pre-purchase offer screenshot: `<file>`. Relaunch: <owned / not owned>; waited 2 min: <no / yes>; Restore tapped: <no / yes → result>. Cold install (delete + reinstall): <owned / not owned>; waited 2 min: <…>; Restore tapped: <…>. <Any Expect / Fail-if mismatch, verbatim.> |
>
> Evidence is kept outside git: `<manifest file name>` (sha256 per file).
```

**表格行怎么填**(本分支给 §L 表加了 `date | device | outcome` 三列;前三列不动,`walked` 列的标记由你选):

```markdown
| **No App Store account signed in** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <Mac model, macOS version, 1.32 (56)> | <one-line outcome> |
| **Family Sharing** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <family device, OS version, 1.32 (build)> | <one-line outcome> |
| **Cross-platform restore (macOS ↔ iOS)** | <unchanged> | <unchanged> | <your mark> | <YYYY-MM-DD> | <Mac → iPhone model, iOS version, 1.32 (57)> | <one-line outcome> |
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
> The asymmetry this box describes has resolved to its second row. macOS 1.32 (build 56) and iOS
> 1.32 (build 57) are `READY_FOR_SALE` (ASC, 2026-09-16), so if one of these paths is broken the cost
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
而登记表里一旦有 `first_download` 条目、这个决定还是 null,`--checkpoint` 就会把两种 N 都打印出来。所以这个决定应在走查之前、
至少在第一次跑含 walk 安装条目的 `--checkpoint` 之前做出,并把下面这段(日期是做决定的那一刻)记进 §K:

```markdown
> **Decided <YYYY-MM-DDTHH:MM+09:00>, before any `--checkpoint` reading that held a walk install:**
> walk-caused first-time downloads are <subtracted from | kept in> N
> (`decisions.exclude_walk_first_downloads_from_N` = <true | false> in `docs/measurements/stage1-known-positives.json`).
> Reason: <reason>.
```

两个决定字段(`"decisions"`)也只由你填:`exclude_walk_first_downloads_from_N` 为 null 且窗口里存在 `first_download` 条目时,
`--checkpoint` 不减、打印未决条目数,并扣住上界;`exclude_owner_refund_from_refund_ceiling` 只记录和回显,这一轮没有工具评估 day-180 退款上限。

---

## 6. 给你的问题 —— 没有替你决定

§K 没有写清的地方。每条只写"不同回答会怎样改变读数",**不给建议**。编号后括号里是审计文件里的原编号。
记号:`g` = 真实售出单位,`r` = 真实退款,`k` = 走查造成的安装。

1. **(Q3.4)你自己设备上的计数器算不算 “returned counter”?** §K 的 STOP 分支没说是谁的计数器。
   算:排除后零购买 + 你的设备在 kyoto 桶里 `offerAppeared > 0` → STOP(走查本身会产生 `offerAppeared`;它落不落在 kyoto 桶,取决于那台设备的累计里程是否 ≥ 25 km,未核实)。不算 → STOP BUILDING / UNINTERPRETABLE。
   **这是清单里影响最大的一条,它直接翻转分支。** 退款之后你算不算「non-buyer」(`docs/PLAN-WINDOW.md` 的用语,不是 PLAN-STAGE1 的)也没写。
2. **(Q3.2)走查造成的安装要不要从 N 里减掉?**(登记表 `exclude_walk_first_downloads_from_N`;**时机见 §5:要在看到含 walk 安装的读数之前定**)k 在 0 到 4 之间,前提是它们真是首次下载。
   不减:真实安装的上界是 3/(N−k),N = 35 时 k=0 为 8.6%、k=2 为 9.1%、k=4 为 9.7%;N = 100 时 3.00% → 3.06%。
   没有哪条规则只因 k 翻转;变的是检查点什么时候触发、打印的上界是多少。null 期间 `--checkpoint` 扣住上界。
3. **(Q3.3)家人的安装算不算 cohort?** 算:N 和那个 storefront 的下载数 +1(两台设备 +2),它的计数器也可能成为 “returned counter”
   (但 0 米时 `offerAppeared` 落在 nihonbashi 桶,除非那个账号骑过 25 km,否则触发不了 STOP)。不算:这些数不动,它的计数器忽略。
4. **(Q3.5)退款把净额抵消,算不算 “exclude it from the cohort”?** (i) 算:从购买行到退款行之间(最长约 90 天)net = 1,GO 会因你那一单触发,
   “at any point” 甚至可以读成 GO 已经永久触发。(ii) 不算,必须显式排除:GO 永远不会因你那一单触发。
   事实说明,不是建议:按本轮约定,`--checkpoint` 实现的是 (ii) —— `purchase` 和 `refund` 条目总是从购买分子里减掉(最多减到报表那一格实际持有的数量);选 (i) 意味着要改这个实现。
5. **(Q3.6)Apple 拒绝退款怎么办?** §K 没有规则。按 (i),GO 永久成立;按 (ii),登记的购买照样被减掉,只是永远没有退款行可匹配。
6. **(Q3.7)已知阳性要不要等到退款行也出现才算完成?** 要:day 0 要等负数行出现才算完,可能几周。
   不要:day 180 的退款数为零时,那个零来自一条从未触发过的代码路径 —— 和购买为零是同一个问题。
   事实说明,不是建议:`--checkpoint` 现在的实现是"不要" —— 购买条目一旦 `matched` 就可能打印上界,不等退款行;选"要"意味着要改这个实现。
7. **(Q3.1)你的退款要不要从 day-180 退款上限里排除?**(登记表 `exclude_owner_refund_from_refund_ceiling`,只记录不应用)
   r = 1 时:购买和退款都算 → g ≤ 9 就触发停售;都排除 → “no action”;退款算但你那单不进分母 → g ≤ 10 触发。
   r = 2 且 g ≤ 18 时:都算 → 3 次退款 → 调查产品主张;排除 → 2 次,只有 g ≤ 10 才停售。另外 “units” 是毛还是净、“n ≤ 18” 的 n 是什么,都没定义。
8. **(Q3.8)day 0 和登记表用哪个日历?** 报表是太平洋日;JST 16:00 前的购买落在前一个太平洋日。登记表同时记 `report_day_pt` 和带时区的本地时间。
   §K 的 “DAY 0 = 2026-09-09” 是日本时间的观察日;按太平洋时间,macOS 1.31 的上架是 09-07 或 09-08(release-days 核对,未能定案),
   `--since 2026-09-09` 不含太平洋 09-08。今天的缓存里 09-08 没有 F1/1F 行,所以按 09-08 还是 09-09 算 N 一样;09-07 这里没有核对。
9. **(Q3.9)打印的阈值还是 3/N?** §K 写 “8.6% / 3.1% / 1.4% are `3/N`”,但 3/100 = 3.00%、3/200 = 1.50%;3.1% 和 1.4% 是旧日历值 3/97.5 和 3/208.9。
   读数必须选一个。0.1 个百分点的差,比 N = 200 时排除最多 4 个安装的影响还大。`--checkpoint` 按约定打印的是 3/N 和 3/(N+114)。
10. **(Q3.10)基数和 N 之间的缺口。** 114 的基数截止 2026-08-27;08-28 到 09-08 的 23 个安装(累计 114 → 137)既不在基数里也不在 N 里,
    所以 “≤ 323 devices ever exposed” 没算它们。影响的是上限分母:3/(N+114) 还是 3/(N+137)。你以前自己的下载可能在基数里、在缺口里、或者都不在,未核实。
11. **(Q3.11)用哪个窗口。** “Window: 90 days” 和 “Go / iterate / stop at day 90” 从未修订,而修订框写的是 N = 200 或 day 180。
    如果排除是在固定窗口上做的,选哪个窗口会改变被排除的是哪些行。

### 另外两个问题 —— 这里**允许**给建议,并明确标为代理的建议

12. **校准的 M4 盲区。** 把分类对调(UPDATE := F1/1F,DOWNLOAD := F7)后 `--calibrate` 照样 PASS(1.24x / 1.65x)。
    `sales_report.py` 的文档字符串说 「updates must be release-locked and downloads must not be」,后半句只被**打印**,从未被**检查**。
    所以今天的 「calibration OK」 只证明"发布日有东西升高",证明不了 F7 就是更新。这不等于分类是错的 —— 分类本来就是从本 app 自己的数据推出来的(见脚本文档字符串),而且没有证据表明它错了;只是这个 OK 比文档说的弱。
13. **"发布日"是什么意思。** 现有 `RELEASE_DAYS` 是日本时间的观察日(≈ 发布后的那个太平洋日,也就是更新潮到达的那天);08-22 没有任何来源;
    交接文档提的 09-04 / 09-07 / 09-09 / 09-10 没有一个是太平洋发布日;09 月唯一确定的发布日是 09-11。不同定义下的实测(2026-09-16,真实缓存,无网络):
    现有集合 1.65x / 1.24x PASS;只用确定的太平洋发布日 {08-11, 08-15, 08-17, 08-31, 09-11} updates 1.14x、downloads 1.75x PASS;
    发布日 +1 {08-12, 08-16, 08-18, 09-01, 09-12} 2.43x / 1.22x PASS;加上交接文档的四个九月日子 1.41x / 1.08x PASS(但那些不是发布日)。

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
