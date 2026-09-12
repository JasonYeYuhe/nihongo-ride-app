接手 Nihongo Ride —— Stage 1 的两件 owner 动作,2026-09-12

仓库 `/Users/jason/Documents/typing_app`,macOS + iOS 的日语打字练习 app,两端都已上线。**用中文跟我交流,代码里的标识符和注释用英文。**

---

# 1. 方向(owner 定的)

**从 §K 的 day-0 已知阳性购买、和 §L 的三道手动购买检查开始。你全权负责,尝试去测这两件事。**

先把话说清楚,因为这句话最容易被执行成错误的样子:**这两件事的核心动作只有 owner 本人能做**,计划里写死了("An agent cannot do this step and must not try")。所以"尝试去测"对你的正确含义是:

> 把 owner 那部分压缩到几分钟,把它前后**所有**能自动化的都自动化,把证据槽位、核对脚本、两种结果的记录草稿全部提前准备好;然后如实说出哪一步你没做、为什么不能做。

**不要用一个你认为"不花真钱"的环境代跑,然后写下"已完成"。** 这是这轮最可能、也最糟的失败方式,比什么都不做更糟。第 8 节把原因写全了,动手前读它。

不要空转。除了那两件之外,第 6 节列了一串真正该做、而且你完全能做的活。

---

# 2. 现在的状态(全部是实测,不是回忆)

```
商店(2026-09-12 直接读 ASC,app id 6777469778)
  macOS 1.32  READY_FOR_SALE  build 56        ← 已上线
  iOS   1.32  READY_FOR_SALE  build 57        ← 已上线
  macOS 1.31  READY_FOR_SALE  build 55
  iOS   1.31  READY_FOR_SALE  build 56
  待审提交:0 个
  内购 com.jasonye.nihongoride.scenery.lifetime  APPROVED  ¥10.00
       proceeds ¥8.42,base territory CHN,175 个地区在售
  ⚠️ 两端构建号是一条交错的序列:下一次上传(任一平台)必须大于 57

测量窗口
  day 0 = 2026-09-09(§K 记录;真实 day 0 是 09-08 或 09-09,绝不会更晚)
  §K 的 day-0 已知阳性购买:未走,已晚 3 天
  §L 的三道手动检查:三个 ☐ 全空

代码
  swift test           766 个测试 / 120 个 suite,全绿
  run_all_gates.sh     10 个闸门,0 失败(地板就是 10;--headless 是 9)
  run_ios_placement_tests.sh  默认 12 个方法,两台设备,全过
  工作树干净,check_versions.py 通过

购买路径的自动化覆盖(2026-09-12 实跑)
  run_store_gates.sh → exit 3
    "Executed 11 tests, with 9 tests skipped and 0 failures"
    9 个 skip 全在 Tests/NihongoRideMacTests/StoreGateTests.swift,
    就是 test00_theStoreIsReachable 到 test08_neverPurchasedIsNotEntitled 全部九个
    (可达性、离线加载、离线购买、恢复、退款、Ask-to-Buy、storefront 变更、未知商品、未购买)
    原因:SKTestSession 对这个 app 在这台机器上是 inert 的,
         每次操作都记 SKInternalErrorDomain Code=3
    脚本自己打的横幅:"NO PURCHASE COVERAGE: with 9 tests skipped.
         The StoreKit gates did not run ... PLAN-STAGE1 §L's manual list is
         the only purchase coverage in that state."
  → 也就是说:购买路径今天的自动化覆盖是零。这是诚实状态,不是缺陷。

钱的仪器(2026-09-12 实跑)
  python3 scripts/sales_report.py --calibrate            → exit 0
      "OK — the instrument responds to known-positive events"
  python3 scripts/sales_report.py --since 2026-09-09 --calibrate --daily
                                                         → exit 4
      "CALIBRATION-FAIL: no release days in window — cannot run the positive control"
  ⚠️ 这两个退出码都要记住。见第 9 节。

购买前的基线(确认 owner 那一单时要用它来对照)
  全窗口 2026-06-06..2026-09-10,exit 0:
      首次下载 144(macOS 81 / iOS 63)
      PURCHASES gross 0,refunded 0,proceeds 0.00
  day 0 之后 --since 2026-09-09:09-09..09-10 共 7 次首次下载(mac 4 / iOS 3)
  → 实测约 3.5/天,高于 §K 投影用的 2.0/天。
    N=35 可能在 2026-09-19 前后就到,而不是投影的 09-23~09-26。

凭据(都能读,不必找 owner)
  vendor number 在 ~/Documents/credits.md
  ASC key 在 ~/.appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8(mode 600)
  被权限系统挡住的 CLI-Pulse-Secrets 目录不在这条路径上
  → 所以"确认销售行"这一腿你能独立跑完,它不是 owner 动作
```

Apple 的销售报告有约两天延迟(脚本自己的 newest = 美西昨天)。**所以 owner 点下购买那一刻不是终点** —— 两天后还有一次确认,§K 的记录行在那之前写不了。

---

# 3. 权限

构建、发布、提交全权自主,不用逐步问我。**一个例外:另一个 Claude 会话共用这个仓库 —— 任何人在对 App Store Connect 做写操作之前,必须先用 `SendMessage` 通知。读 ASC 不受限制。** 这一轮大概率根本不需要写 ASC。

改公开内容(法务站 `JasonYeYuhe/nihongo-ride`)要先问我。`site/` 只是源拷贝,线上是另一个公开仓库。

---

# 4. 阅读顺序

1. **`docs/PLAN-STAGE1.md` §K**(约 339–655 行)—— 先读结尾那段 day-0 已知阳性的定义,再往回读整节。这是这轮的第一优先级,PLAN-V1.32 里写着"It belongs above every item in this plan"。
2. **`docs/PLAN-STAGE1.md` §L**(657–729 行)—— 三道闸门、书面前提、以及那个 ⚠️ 框。**整节读完,包括每一个框。**
3. `docs/STATE-2026-09-11.md` —— 冷启动快照。注意它写于 1.32 还在审核时,那一条已经过期(见第 9 节)。
4. `docs/PLAN-WINDOW.md` —— 四条约束。第 9 节列了它内部自相矛盾的地方,别照单全收。
5. `docs/PLAN-V1.32.md` —— 上一轮做了什么,以及提交前审查发现的东西。
6. `scripts/sales_report.py` 的文件头 —— 退出码语义,和"zero is a RESULT only if calibration passed"那句。

---

# 5. 两件 owner 动作 —— 它们不是同一件事

**把它们分开报告。** §K 测的是**测量仪器能不能动**;§L 测的是**产品是不是对的**。说"闸门还没走"会把 §K 漏掉;说"§K 走了"一道 §L 闸门也没走。

## §K —— day-0 已知阳性购买(owner 动作,已晚)

原文(`docs/PLAN-STAGE1.md:650-655`):

> **Day 0, before the SKU goes on sale — non-negotiable, and it is an OWNER action:** make one real ¥10 purchase on the owner's own Apple Account **in production** (sandbox never appears in `salesReports`), confirm the row appears and `--calibrate` still passes, then refund it. Record the date here and **exclude it from the cohort**, or it will later look like the signal. This is the money instrument's known-positive, and this project does not trust an instrument that has not fired. *An agent cannot do this step and must not try.*

为什么没有它窗口读不了:StoreKit → Apple 销售报告 → `sales_report.py` 这条链**从来没被证明过能报出一个非零**。所以窗口跑出的"0"和"分类器从来就认不出任何东西"是无法区分的两件事。脚本自己在打印时就写着这句话。

**§K 对"晚了"这件事什么都没说** —— 我完整读过,没有补救条款、没有替代方案、没有"校准落在第 N 天该怎么解读"的规则。它隐含的补救就是去走,不是去重新解释。所以别发明一套补救逻辑。

**"exclude it from the cohort"现在是承重的。** 因为"上架前"这个时机已经过了,owner 那一单会落在窗口**内部**、和任何真实销售同一个报告周期里,只靠记录的日期区分。而 §K 的 GO 分支是**单笔净购买就触发**(`PLAN-STAGE1.md:503-505`)。也就是说,排除做不干净,owner 自己那一单就能把 GO 点着。

## §L —— 三道手动闸门(owner 动作)

书面前提,原文一句(`docs/PLAN-STAGE1.md:663`):

> Each needs a date, a device and an outcome written beside it **before v1.30 is submitted**.

紧接着的 ⚠️ 框(`665-669`)写着这个前提**没有被满足**:v1.30 于 2026-08-31 提交时三道全空。框里特意保留了原句不改,理由是"a gate that gets quietly reworded after it is crossed stops being a gate"。

三道闸门:

| # | 闸门 | 需要什么 | 判据 |
|---|---|---|---|
| 1 | **No App Store account signed in** | 一台已**登出** App Store 的 Mac 或设备 | 四条 Expect + 一条 Fail-if,§L 原文里有 |
| 2 | **Family Sharing**(不继承) | 同一家庭组里的**第二个** Apple 账户 | 家庭成员看到的是 offer,**不是**已拥有状态 |
| 3 | **Cross-platform restore**(macOS ↔ iOS) | 一次**真实购买**,加另一平台同账户,加一次冷装重试 | 不点 Restore 就是 owned;需要点且点了没用 = 失败 |

三道里只有闸门 2 需要第二个 Apple 账户;另外两道一台 Mac + 一台 iPhone 就够。

**闸门 3 也需要一次真实购买。** 所以**一次购买可以同时服务 §K 和闸门 3** —— 但前提是平台和账户在事前就选定。这是你写 walk card 时要替 owner 想好的事。

§L **没有**规定"已经发布了才发现没走"该怎么办。它只有要求、一张失败成本表、和一条"事后必须往框里写什么"的指示。那张成本表现在已经过期:它说的"还在审核时取消重提只要几分钟"已经不成立了,两端从 2026-09-09 起就是 READY_FOR_SALE。

---

# 6. 你实际能做的(按价值排序,每条都有据可查)

1. **做出 walk card,并且端到端预演一遍**,让 owner 那部分只要几分钟、而且不会白费。必须在卡片上写死一件所有计划都漏掉的事:**四次走查全部在从 App Store 下载的 1.32 正式版上进行**(mac 56 / iOS 57),不是本地构建,不是 TestFlight。给出进入 offer 的确切路径(设置 → The Road,或过京都后菜单的路线条),照抄 §L 的 Expect / Fail-if,列出要截什么图,并把顺序排成"一次购买同时服务 §K 和闸门 3"。把今天的购买前基线写在卡片上,好让 owner 那一单落地时能被认出来。

2. **先修掉 calibrate 的陷阱,再让确认那一腿上场。** `RELEASE_DAYS`(`sales_report.py:106`)停在 2026-08-24,而 09-04 / 09-07 / 09-09 / 09-10 都是发布日。在 §K 里写清"`--calibrate` still passes"指的是**默认全窗口调用**。然后用变异证明 release-day 那个控制项**还能失败**,而不是读到它是绿的就算数。

3. **把 cohort exclusion 从一句话变成结构。** `sales_report.py` 现在没有任何地方能表达"排除"。做一个 known-positive 登记表(日期、平台、地区、单数、退款日期),让每次 checkpoint 读数在报出任何 bound 之前先减掉它,并配一个成对控制:一组含 owner 那单、一组不含,断言两者数字不同。另外把一个 §K 没写的问题**原样交给 owner 决定、你不要替他决定**:owner 自己那笔退款,要不要也排除在 day-180 退款上限之外?那个上限是绝对计数(≥2 笔退款且 ≥20% 单数;n ≤ 18 时 ≥3 笔),n 很小的时候一笔就是很大一块。

4. **给 §L 的表加上它自己前提要求的证据槽位** —— date、device、outcome 三列,现在只有一个 ☐。并把**两种**结果的框更新都提前起草好:走了(带结果)、和有意跳过(带理由)。**☐ 留空,663 行一个字不要动。**

5. **修两处已经不成立的 doc comment。** `Sources/EntitlementKit/Entitlement.swift:37-38` 和 `Sources/NihongoRideApp/RouteStore.swift:15-16` 都写着适配器"is proven separately on macOS against a local StoreKit configuration"。那九个测试全部 skip。改成今天为真的话,并按 `PLAN-V1.32.md:425` 的要求在 §J 补一条带日期的行 —— §J 最后一条停在 2026-08-30,今天的实测(exit 3,11 执行 / 9 跳过 / 0 失败)哪里都没记。

6. **把不需要 StoreKit 就能测的钱路径补上。** `RouteStore.observedNow(after:)` 是 nonisolated static,守的是"退款和重新购买之间时钟被往回拨会不会把付费用户锁在外面",今天在它自己文件之外零引用、零测试。`RouteStore.purchase()` 的 notice / lastOutcome 映射可以注入 StoreKit 结果来测,不需要买任何东西。还有两处"不要重构成 apply 返回 + caller 保存"的禁令,和已有的两个 debug seam 不同,**没有任何东西在执行它们** —— 加源码扫描。

7. **花一个限时盒子查清 SKTestSession 为什么对这个 app 是 inert 的。** 计划里已经点名了仅剩的两个未测差异:真实 App Store bundle id、和嵌入的 widget extension(`PLAN-STAGE1.md:712`)。在一份 scratch 拷贝里把最小探针 app 各构建一次,测出是哪一个让 session 失效。**成功与否都要写下带日期的结论。** 如果命中,九个已经写好的闸门(退款、恢复、离线、Ask-to-Buy)不用改一行就开始跑 —— 那正是 owner 要你测的东西里可自动化的那一半。

8. **清掉一批过期物,每个都是一句话的事**,但每个都是后来的人会照着做的假话:`project.yml:429` 指向 `scripts/check_storekit_wiring.sh`,这个文件不存在(真正的 grep 内联在 `run_store_gates.sh:114-122`);`xcode/NihongoRide.storekit` 里的产品描述还带着已经从三个商店本地化里撤掉的承诺 "A second journey west, and every route after",而 `PurchasePromiseTests` 只扫 `RoadView.swift`,看不见它。

9. **给时钟上闹钟。** 实测装机速度高于投影,N=35 可能 09-19 前后就到。让任何 checkpoint 读数在 day-0 已知阳性没走之前,**拒绝打印 bound**,而不是打印一个带脚注的数。

---

# 7. 四条约束(`PLAN-WINDOW.md:118-126`)

1. **不要碰 offer、价格、位置。** —— 这条的违反会**作废整个预注册**。
2. 免费发出去的东西不能再收回。**注意**:这条在同一份文件里自相矛盾,见第 9 节;正确的形式是 `originalAppVersion` grandfathering,不是"永久免费"。
3. 显著改变骑行距离 = 改变 exposure-per-install → **登记,不要回避**,登记在 `PLAN-STAGE1` §K。
4. 不要改 en-US / zh-Hans / ja 的商店元数据。

**除此之外都是开放的。** 这份文件在 2026-08-31 被 owner 当场纠正过一次,因为它把两件无关的事混在了一起;别再推导一遍"窗口期不该做功能"那个前提。

---

# 8. 绝对不要做

**第 1 条是这一轮唯一真正危险的一条,其余是常规。**

1. **不要在任何环境里做任何购买。** 不是生产、不是 sandbox、不是 TestFlight、不是对着本地 `.storekit` 配置、不是用测试账户、不是"就按一下看看按钮通不通"。

   这不是关于钱的规矩,是关于**谁有资格证明一次购买发生过**。没有任何环境下你的购买能为 §K 或 §L 产生有效证据:
   - §K 的全部主题就是**一行记录有没有到达 Apple 的 `salesReports`**,而 sandbox 永远不会出现在那里;
   - 本地构建会对着 `xcode/NihongoRide.storekit` 解析商品 —— `PLAN-STAGE1` §J 记着,scheme 的 `storeKitConfiguration` "arms the app's store environment independently of the session",**这正是第一次校准通过却什么都没证明的原因**;
   - Debug 构建编进了 `NIHONGO_FAKE_ENTITLEMENT`、跑在 `ENABLE_APP_SANDBOX: NO` 下,它不是任何顾客会遇到的东西;
   - TestFlight 购买是 sandbox,同样到不了 `salesReports`。

   **你做的购买不是 owner 那次购买的廉价版本,它是另一件事,没有证据价值。** 而如果你把它写成"已走查",你就把一个"可见地未满足"的书面前提变成了"看起来已满足" —— §L 那个框存在的全部意义就是保住这个区别。

2. **不要登入、登出、创建或切换任何 Apple 账户**,包括模拟器上的,包括你认为是一次性的账户。**闸门 1 本身就是一次登出**,这正是它属于 owner 的原因。

3. **不要往 §L 的 `walked` 栏写字,也不要往 §K 写"walked on <date>"。** 两种草稿都写好,交给 owner 确认后由他落定。同样地,**不要自行记录"跳过"** —— §L 要求有意的跳过必须作为一个**决定**被写下来,而那是 owner 的决定。

4. **不要改写、软化或"更新" `docs/PLAN-STAGE1.md:663` 那句话。** 它现在就是不成立的,而且是故意留着的。表格旁边加列可以,改那句不行。它的措辞是"before **v1.30** is submitted",字面上对 v1.31 / v1.32 没有约束力 —— **如果你发现自己正在顺着这个逻辑推理,那件事本身是要报告给 owner 的,不是拿来行动的。**

5. **不要为了变绿削弱任何闸门,也不要为了能引用一个数字去改校准。** `StoreGateTests.swift:82` 那个 XCTSkipIf 探针:exit 3 = 零覆盖,是诚实状态,被容忍;**exit 4 和 65 是失败**。`--calibrate` 在窗口范围内退出 4,是"这个控制项需要窗口里有一个发布日"的既定行为,不是要绕过去的缺陷。**加强控制项永远可以,放松控制项换一个绿色永远不行。**

6. **不要为这个 SKU 打开 Family Sharing**,在 ASC 里或任何地方,理由包括"为了测一下"。Apple 写明它**不可逆**,而闸门 2 要验的恰恰是家庭成员**不会**继承。打开它就永久摧毁了被测对象。

7. **不要对 App Store Connect 做任何写操作** —— 不 POST、不 PATCH、不 DELETE,不提交、不取消、不改元数据、不改价格或地区。读不受限,而且鼓励读。现在没有待审提交可取消;如果走查暴露出产品缺陷,修法是发一个新版本,而那是 owner 的决定。写之前先 `SendMessage` 查同仓库会话。

8. **不要碰 offer、价格、位置,不要碰三个语言的商店元数据。** 准备走查不需要动它们任何一个。如果你认为走查需要改 UI 才能测,那个判断是给 owner 的报告,不是一次改动。

9. **不要把你做的任何事当成那两件 owner 动作的替代品**,也不要让报告只说"还是没做"就完事。**"还没做"和"违反了一条书面前提"是两句一模一样的话,但不是同一件事。** 如果今天 owner 什么都没走,正确的终态是:☐ 原样留空、两种框更新都已起草、用 §L 自己的话点明那条被违反的前提、以及今天实测的购买前基线已经记好,好让走查随时都很便宜。

---

# 9. 这一轮的陷阱 / 已经过期的说法

**文档之间彼此矛盾的地方,都已经核实过,以下是正确的一侧。**

- **`PLAN-WINDOW` 约束 2 自相矛盾。** 119 行说 "Anything shipped free is permanently free";**同一份文件** 295-297 行说 "anything shipped free can still be sold later — grandfather on `originalAppVersion`, do not freeze the free tier"。后者是正确的,另外三份文档一致,owner 本人承认前者是自己的措辞失误。从头读这份文件会拿到更严的那条错规则。
- **`PLAN-WINDOW` §F 的 checkpoint 表已被取代**,绑定文本在 `PLAN-STAGE1` §K:决定点是 N=200 或 2027-03-08 **先到者**;2026-12-08(day 90)只是一条"interim record, no decision attached"。
- **`PLAN-WINDOW` §H 的成本表已过期**,而且方向翻转了。它说"还在审核时失败只要取消重提,几分钟"—— 两端从 2026-09-09 起就已上线,现在的代价是"一整个新版本,而且有活跃顾客"。
- **§H 通篇写 v1.30,但 day 0 实际上是 v1.31 发布的**(mac 55 / iOS 56)。
- **`docs/STATE-2026-09-11.md` 写着 1.32 WAITING_FOR_REVIEW** —— 它写于提交当晚,现在两端都是 READY_FOR_SALE。文件顶部已加了纠正行。**任何状态都以直接读 ASC 为准,不要信文档,也不要信记忆。**
- **日报缓存永不失效。** `collect()` 把每一天永久缓存在 `~/Library/Application Support/NihongoRide-Stats/sales`,除非传 `--no-cache`。**确认购买那一天时必须加 `--no-cache`**,否则一个"当时还没有销售"的缓存会替一个后来被重述的日子回答。
- **`--calibrate` 的两个退出码都是真的,含义不同**(第 2 节有实测)。全窗口默认调用 exit 0;`--since <day> --calibrate` exit 4。你在购买后最自然会敲的那条命令,正是会拿到 exit 4 的那条。
- **"最小 non-App-Store app 在同一台机器上 10/10 通过"这条被所有文档反复引用、但没人重测过。** 它是 2026-08-30 的测量,此后逐字照抄至今。

---

# 10. 每次都要跑的

```bash
bash scripts/run_all_gates.sh          # 10 个闸门;地板就是 10(--headless 是 9)
bash scripts/run_store_gates.sh        # exit 3 = 零覆盖(诚实);4 = harness 起不来;65 = 真失败
bash scripts/run_ios_placement_tests.sh  # 默认 12 个方法,两台设备
python3 scripts/check_versions.py
```

发布(这一轮大概率用不到)按 `docs/STATE-2026-09-11.md` 的 runbook;两个构建脚本现在都会在上传前对归档跑 `launch_gate.sh`。**提交前 curl 一次线上的隐私页和支持页** —— 它们在另一个公开仓库,`PrivacyClaimTests` 只看得到 `site/`,看不到线上。

---

# 11. 这个项目的立场

不信一个没有被证明过**能失败**的闸门。修好一个检查之后,把缺陷改回去,确认它会变红 —— 这个仓库里反复出现的缺陷是"显示的数字和实际跑的东西由两个不同的谓词算出来",以及"一条只写在注释里、没有任何东西执行的保证"。

而这一轮的主题比那还要窄一点:**一个从来没有被证明能动过的仪器,读出来的零不是结果。** 这就是 §K 那一单为什么排在所有事情前面。
