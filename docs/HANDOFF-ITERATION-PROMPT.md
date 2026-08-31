Nihongo Ride — 快速迭代交接(2026-08-31)

你接手 Nihongo Ride 的开发,仓库 `/Users/jason/Documents/typing_app`,macOS + iOS 日语打字练习 app。用中文跟我交流,代码里的标识符和注释用英文。

**方向是 owner 定的:快速迭代,把功能做得更多更好。** 上一阶段刚结束(v1.30 —— app 的第一次变现 —— 已提交审核)。你的工作是**做功能**,不是等。

# 权限

完整的构建/发布权限:改代码、跑测试、打包、上传 ASC、提交审核,不必每步问我。

一个例外: 另一个 Claude session 共用这个仓库(`ListAgents` 找 `typing-app-*`)。谁都不能不打招呼就写 App Store Connect,动手前先 `SendMessage` 通知。读 ASC 随便读。

分工:你 = 功能开发、语料、instrument 脚本、`docs/measurements/*`、发布(含 ASC)。产品/ASO 是**另一个会话**(`PLAN-V2-PRODUCT.md`、`v2-stage0-baseline.*`、`sales_report.py`、`acquisition_funnel.py` 是它的地盘)。

# 先读,按这个顺序

1. **`docs/PLAN-ITERATION.md`** —— 这是你的工作清单。§A 瓶颈在哪(有实测数字)、§C Tier 1 三件事、§D 挂着的、§E 只有 owner 能做的
2. `docs/PLAN-WINDOW.md` —— **为什么约束只有四条**。别跳过 §C(一个被否决的提案)和两个更正框,它们记录了两次我把话说得比事实更严的地方
3. `docs/STATE-2026-08-18.md` —— **先读 Traps 段最顶上那个「两族」引言**,它决定你怎么读下面 40 多条
4. `docs/PLAN-STAGE1.md` §K/§L —— 只在你要碰发布或报价时读

# 现在的状态(2026-09-01 重新核过,与 08-31 提交时相同)

* v1.30 macOS build 54 / iOS build 55 + IAP `com.jasonye.nihongoride.scenery.lifetime`(6806755720),**三个都 `WAITING_FOR_REVIEW`**
* 仓库停在 1.30,工作树干净,HEAD `99e734c`
* `swift test` 632 绿 · iOS 放置测试 7/7 · `run_store_gates.sh` **exit 3,九个 skip,零覆盖**(如实报告,不是通过)

# 开工前先说这两件,它们有到期时间

**1. 提醒 owner 走 §L 的三个手动购买 gate。** 没登录 App Store 账号 · 家庭共享不继承 · macOS↔iOS 跨平台恢复 —— **一个都没走**,而 §L 自己要求在 v1.30 提交前走完。不对称在这里:

| gate 现在失败 | 代价 |
|---|---|
| 还在 `WAITING_FOR_REVIEW` | 撤回、修、重交。**分钟级**,8-31 实测过两次 |
| 已经 `READY_FOR_SALE` | 一整个新版本,期间线上用户遇到坏掉的购买流程 |

三个里两个只要一台 Mac 加一台 iPhone。**owner 动作,agent 不能做也不要尝试。**

**2. 上架后立刻把日期填进 `PLAN-STAGE1.md` §K。** 90 天从两个平台都 `READY_FOR_SALE` 起算。另外 §F 提议把 checkpoint 从「第 15/42/90 天」改成「累计第 35/100/200 个新装机」(实测增长是每月约翻倍,原表按 2.321/天 拉平),**这个改动只在 day 0 之前是自由的**,需要 owner 拍板。

# 四条约束 —— 只有这四条,功能开发是开放的

1. **不碰报价、价格、放置**(Settings 里那一行 + 菜单的路线条)。这会作废预注册
2. **不动 `en-US`/`zh-Hans`/`ja` 的关键词、标题、副标题、截图**
3. **大幅改变骑行距离的功能会改变「每装机曝光率」** —— 二阶影响,**登记它,不用回避**
4. **免费发出去的东西以后仍然可以卖。** `PLAN-V2-PRODUCT` §E 的红线是「**用 `originalAppVersion` 祖父化,而不是永久冻结免费层;新用户拿到什么仍是开放的产品决定**」,§I 补充它「可回溯读取」。**我第一版把这条写成了「永久免费」,是错的,两个外部评审独立指出。** 不要按错的那版做决定

其余全开:模式、复习调度、统计、小组件、UI、无障碍、内容。

> **附带:发布节奏本身是一次轻度的获取干预。** §L 记过「十四天七个版本」和流量翻三倍同时发生,并刻意归为「四个候选之一 —— 而且是附带不良激励的那个」。**把每次发布日期记下来**,让 day 90 能看见;不要声称是节奏带来的。

# Tier 1,按这个顺序(完整版在 `PLAN-ITERATION.md` §C)

**1. 抽出发布模板。** `submit_1_30.py` 792 行里,每次发布真正要改的只有 162 行,另外 630 行是手抄的机器,磁盘上有 28 个这样的脚本。留每个 `submit_<version>.py` 的配置,机器进一个模块。**老文件不要删**,它们是每次实际发出去什么的记录。不碰 app 代码,零测量风险,后面每一项都受益。

**2. 活用练习的题目时钟。** `ConjugationSRSCard.quality(from:)` 给**每个干净答案打 5**,因为 `ConjugationSession` 不传 `durationRatio`,默认 1.0 让 `<= 1.5` 恒真。有实测探针(注入时钟每键 30 秒打 たべます,报告比率仍是 1.0)加负控(同样的慢速经 `GameSession` 打 4)。`NoPromptTimingTests` held 着这个发现。修法代码里已划好:**会暂停的题目时钟 + 按数据选的基线 + live-WPM 走 `RunClock`**,最后一项用户看得见。⚠️ 它会重写 SM-2 排期,基线要按数据选 —— 现成的 `secondsPerKanaBaseline`(0.8 秒/假名)是为「抄一个看得见的词」标定的,活用是回忆加产出。

**3. Practice 里「打你自己的文本」。** F1 有边界的那一半。两个拦路虎都比计划里记的软:
* **设备上有分词器。** §N 原来写着「设备上根本没有分词器」——**假的,已更正**。`CFStringTokenizer` 就在 Foundation 里,`ja` locale + `kCFStringTokenizerAttributeLatinTranscription`,离线出读音,两平台都有,零依赖
* **它的质量问题在这里不咬人。** 同一次运行把 日本語 拆成 日本[nippon]+語[go],正是 Sudachi 那个毛病 —— 但**curated 语料里的错读是「教错了」,用户自己粘贴的文本里的错读他看得见、他自己改**。把读音显示出来、让他能改
* ⚠️ **划在 SRS 之外。** `SRSCard(id: entryID)` 用语料 id 做卡身份,`SyncMerge` 通过 CloudKit 跨设备合并;给粘贴的词发卡身份是危险且昂贵的那一半。先只做 Practice —— 它已经能回答「到底有没有人会粘贴自己的材料」,那个答案才决定 SRS 那一半值不值得建

**4. 用一遍 app,把 Tier 1 之后的清单补出来。** 上面三件是我能从仓库记录里论证的全部;再往后的应该来自**用它**而不是读它。`DiagnosticsKit`/`StumbledWords` 已建好接好,还有小组件、提醒调度、分享卡、六个模式、21 个 kit —— 值得看的是哪些**露出不足**而不是缺失。

# 绝对不能做

改价格 · 改报价 · 改放置 · 加第二个 SKU(`UnlockOfferLedger.counts` 没有产品维度,加之前必须先拆计数器,且不能同一个版本做)· 任何需要服务器的东西 · 任何上传的遥测(`Data Not Collected` 保持;本地永不上传的计数器可以,禁止的是收集不是计数)· 为「用户拿回自己的数据」收费(纯 CSV 导出永久免费)· `zh-Hant`/`ko` 商店页(`AppSettings.swift:129` 的 `validLanguages` 是 `["en","zh"]`,做了就是把读者送进一个显示不了他们语言的 app)

# 这个项目已经付过学费的

* **正控和负控证明仪器能分辨它被给到的选项,不证明正确答案在选项里。** 读一个「通过」或「空」的结果之前,先说出候选集/人群/维度是怎么定的,以及什么会落在它外面。STATE 顶上那个引言就是它,8-31 一天出了三个这一族
* **一个绿断言,和一个不覆盖你问题的绿断言,长得一模一样。** 先问「这个断言约束的是哪个维度(空间/时间/频次/人群)」
* **一条规则写在注释里就等于没写。** v1.30 的 `do_submit` 把顺序规则写在注释里没写进控制流,结果两个平台在 IAP 没挂上的情况下发给了 Apple,两单撤回重建。新守卫必须变异证明能变红,并且要有必须触发的配对对照 —— 见 `scripts/test_submit_gate.py`
* **「还没做」和「某份文档要求它在你刚做的那件事之前做完」字面完全相同**
* **仓库里描述一件工作的产物,在「待办」和「已办」两种情况下长得一模一样。** 只有活系统或 `git log` 能区分,已付两次
* **绝不用连续字符串替换改版本号**(v1.25 让两平台拿到同一个 build 48)。用 `python3 scripts/check_versions.py --bump <version>`
* **写语料文件前,先断言序列化能字节级还原原文件。** `id`/`surface`/`kana`/`jlpt`/`vc` 冻结
* **UI 测试必须 `xcodebuild test`,`swift test` 跑不了,而且绝不能用管道**(管道会替换掉前一个命令的退出码)。显示器睡眠会让 `xcodebuild test` 卡在 build→test 交接;两个 harness 已自带 `caffeinate -d -i`
* **给 store 播种要用 store 自己的 writer**,别手搓 encoder —— 日期策略不一致会让 seed 静默加载成空的,然后每个断言都因为错误的原因通过
* **不要为了让套件变绿而削弱 `run_store_gates.sh`**
* **ASC 的错误 `detail` 是摘要,`meta.associatedErrors` 才是证据**

# 发布流程

```
python3 scripts/check_versions.py --bump 1.31
```
然后:构建 → 上传 → 对**真正上传的那个 archive** 跑 `scripts/launch_gate.sh` → `submit_1_31.py`(照 `submit_1_30.py`,它的 `--dry-run` 会打印全部文案和描述 diff 而不碰 Apple)。**每次 PATCH 之后逐字节回读,别信 PATCH 的返回。**

每次必跑:`swift test` · `launch_gate.sh` · 逐字节回读。
只在动了 UI/放置时跑:`run_ios_placement_tests.sh`(~4 分钟)。
`run_store_gates.sh` 现在 exit 3 零覆盖 —— 跑,但它不是证据。
