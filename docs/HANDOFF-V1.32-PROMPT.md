Nihongo Ride — v1.32 阶段交接(2026-09-10)

你接手 Nihongo Ride 的开发,仓库 `/Users/jason/Documents/typing_app`,macOS + iOS 日语打字练习 app。**用中文跟我交流,代码里的标识符和注释用英文。**

方向是 owner 定的:**快速迭代,把功能做得更多更好。你的工作是做功能,不是等。**

# 现在的状态(2026-09-10)

**v1.31 双端已上架,内购已获批,Stage 1 的 90 天测量窗口正在跑。**

```
MAC_OS 1.31 READY_FOR_SALE   IOS 1.31 READY_FOR_SALE   IAP APPROVED
¥10.00 · 分成 ¥8.42 · 175 个地区 · day 0 = 2026-09-09
checkpoint 已改成安装量口径:N = 35 / 100 / 200(不是第 15/42/90 天)
```

`swift test` 682 绿,工作树干净,`check_versions` ok。

# 权限

完整的构建/发布权限:改代码、跑测试、打包、上传 ASC、提交审核,不必每步问我。

**一个例外:** 另一个 Claude session 共用这个仓库(`ListAgents` 找 `typing-app-*`)。**谁都不能不打招呼就写 App Store Connect,动手前先 `SendMessage` 通知。读 ASC 随便读。**

分工:你 = 功能开发、语料、instrument 脚本、`docs/measurements/*`、发布(含 ASC)。产品/ASO 是**另一个会话**(`PLAN-V2-PRODUCT.md`、`v2-stage0-baseline.*`、`sales_report.py`、`acquisition_funnel.py` 是它的地盘)。

# 先读,按这个顺序

1. **`docs/PLAN-V1.32.md`** —— 你的工作清单。**先读 §A 那个警告框**:这份计划的第一稿重犯了 owner 在 8-31 已经书面纠正过的错误,§J 记录了两次 Gemini review 推翻的八条。§F 是执行顺序(四个条目动同一个文件)。
2. `docs/PLAN-WINDOW.md` §99-131 —— **为什么约束只有四条**。owner 的原话是「我宁可多做功能」,而「窗口期只能做维护」是**被否决过的**说法。别再推导一遍。
3. `docs/PLAN-STAGE1.md` §K —— day 0 的框、checkpoint 修正案、以及 §L 的三个手动 gate。
4. `docs/STATE-2026-08-18.md` —— 陷阱。**先读 Traps 前面那段「two families」的引子**,一半的陷阱需要相反的防御。
5. `docs/PLAN-ITERATION.md` —— 上一阶段的记录,含节奏表(**注意 macOS 1.31 那一行的 `createdDate` 警告**)。

# 开工前先跟我说两件事,都有时效

**1. §K 的 day-0 已知阳性购买 —— 已经晚了,而且它挡着整个测量。**

在生产环境买一次 ¥10,确认 `sales_report.py --calibrate` 报得出来,退款,记日期,把它排除。**没有它,以后任何一个零都无法解释** —— 因为 StoreKit → Apple 报表 → `sales_report.py` 这条链从未被证明**有能力**报出非零。脚本自己就印着 *"zero is a RESULT only if calibration passed"*。这是 owner 动作,agent 不能做也不要尝试。

**2. §L 的三个手动购买 gate —— 便宜窗口已经关了。**

没登 App Store 账号 · 家庭共享不继承 · macOS↔iOS 跨平台恢复。双端都上架之后,发现问题只能靠发新版本修。三个里两个只需要一台 Mac 和一台 iPhone。同样是 owner 动作。

# 约束只有四条,其余全开

1. **不要动报价、价格、位置**(Settings 那一行 + 菜单路线条)。会作废预注册。
2. **不要改 en-US / zh-Hans / ja 的关键词、标题、副标题、截图。**
3. **实质改变骑行距离的功能会改变每次安装的曝光量 —— 登记它,不要回避它**(写进 `PLAN-STAGE1` §K,在发布前)。
4. **免费发出去的东西以后仍然可以卖。** 红线是「按 `originalAppVersion` 祖父条款」,**不是**「免费层永远冻结」。owner 明确说过自己最初的措辞是错的。

模式、复习调度、统计、widget、UI、无障碍、内容 —— **全开**。

# 不要问都别做

* 改价格/报价/位置
* 加第二个 SKU(`UnlockOfferLedger.counts` 没有 product 维度,必须先拆计数器,而且**绝不能和第二个报价同一个版本发**)
* 任何服务端依赖
* **任何上传的遥测**(`Data Not Collected` 保持;本地永不上传的计数器可以 —— 禁止的是收集不是计数)
* 对数据导出收费(CSV 导出永久免费)
* zh-Hant / ko 商店页(`AppSettings.swift:129` 的 `validLanguages` 是 `["en","zh"]`)

# 每次都要跑的

`swift test` · `scripts/run_all_gates.sh`(如果 §D6 已经建好)· 每次 PATCH 之后**逐字节读回**。

**只在 UI/位置改动时:** `scripts/run_ios_placement_tests.sh`(约 4 分钟)。**绝不能用管道**(管道会替换掉前一个命令的退出码)—— 用重定向。0 = 通过,65 = 有测试失败。

`scripts/run_store_gates.sh` 现在 exit 3 且零覆盖 —— **照跑,但它不是证据,也绝不要为了让它变绿而削弱它。**
只有 **3** 是被容忍的状态。v1.32 起 **exit 4 = harness 起不来**(生成的 scheme 丢了 `StoreKitConfigurationFileReference`),**65 = 真的有闸门失败**;这两个都是失败,不是"零覆盖"。

# 这一轮踩过的坑,写下来省你的时间

* **多个 session 共用这台机器的模拟器和工作树。** 一个 UI gate 报过 *"an owner lost the road row entirely"* —— 是另一个 session 在同一台模拟器上跑测试。**判据:失败在说「app 够不着」而不是「被测性质不成立」,就先查 `pgrep -fl xcodebuild`。** 隔离用**同型号克隆**(`SIM_NAME=NihongoRide-Placement`),不要换机型 —— 这些测试断言命中区域,屏幕尺寸是仪器的一部分。我的 `swift test` 也被 subagent 的构建撞过一次。
* **ASC 查询错了会静默返回 0。** 我有三个查询报了错,解析器把它印成 `NONE` 和 `0 territories`,差点被我当成「内购没有价格」报出去。**看原始响应再下结论。**
* **`launch_gate.sh` 没有 iOS 形态** —— 它读 `Contents/Info.plist`,那是 macOS 包结构。iOS 上架的产物**从来没做过启动测试**,这是记录在案的缺口。
* **复用的版本记录会带旧时间戳。** macOS 1.31 是复用 1.30 的记录改版本号来的,所以 ASC 报它 `createdDate` 是 08-31 而实际 09-07 提交。节奏表那一行要取 `submittedDate`。
* **撤单后 Apple 不让建新版本**(`DEVELOPER_REJECTED`),报错只有一句 "You cannot create a new version of the App in the current state"。`asc_release.py` 的 `ensure_version` 现在会指出解法(PATCH `versionString`),但**不会自动改名** —— 那正是版本记录悄悄和 build 对不上的方式。

# 发布流程

```
python3 scripts/check_versions.py --bump <version>     # 绝不用连续字符串替换改版本号
scripts/build-appstore.sh --upload                     # macOS
scripts/build-appstore-ios.sh --upload                 # iOS
python3 scripts/submit_<version>.py --dry-run  --platform=ios|macos|both
python3 scripts/submit_<version>.py --metadata --platform=...
python3 scripts/submit_<version>.py --submit   --platform=...
```

`submit_1_31.py` 是模板(只有配置 + 一次 `main(Release(...))`),机器在 `scripts/asc_release.py`,被 `scripts/test_asc_release.py` 用 11 个场景对着 `submit_1_30.py` 卡住。`--platform` 是**必填**,因为两端会分开发。`--dry-run` 打印所有文案和 description diff 而不碰 Apple。

**每次 PATCH 之后逐字节读回,永远不要相信 PATCH 的返回值。**

# 我要你怎么工作

按 `PLAN-V1.32.md` §F 的顺序做。功能那条线(§B)和硬化那条线可以并行 —— **功能不是次要的**,这是 owner 明确纠正过的。

这个仓库的标准是:**用变异测试证明一个 gate 能失败,而不是看它是绿的**。一个「没找到问题」的检查器,在它被标定之前不算证据。
