接手 Nihongo Ride:/Users/jason/Documents/typing_app,macOS + iOS 的日语打字练习 app,两端都已上线。用中文跟我交流,代码里的标识符和注释用英文。

**上一轮(2026-09-17/18,以及 09-24 的收尾)已经做完的事,不要重做,直接读记录:**
- v1.33 已于 2026-09-17(太平洋时间)在两个平台上线:macOS build 57 / iOS build 58。发布日两步(`FIRM_RELEASE_DATES_PT` 追加 2026-09-17;`scripts/stage1_walk.py` 的 `EXPECTED_*` 和 `docs/WALKCARD-STAGE1.md` 切到 1.33)已完成并推送。
- 下一阶段的计划在 `docs/PLAN-V1.34.md`,已经过 Gemini 3.1 Pro 和 Gemini 3.8 Flash 两轮审查,§K 记录了它们改了什么。**这一轮从执行这份计划开始。**

**阅读顺序(全部读完再动手):**
1. `docs/HANDOFF-STAGE1-GATES-PROMPT.md` —— 这个仓库对代理的常设规则(行号已失效,按引文找)。
2. `docs/STATE-2026-09-24.md` —— 现状快照(商店状态是当天直接读 ASC 的)。
3. `docs/PLAN-V1.34.md` —— 整份,包括 §I(有意不做的)和 §K(两轮审查改了什么)。
4. `docs/PLAN-V1.33.md` §E 和 §G —— 上一版的验证标准和它推迟了什么。
5. `docs/measurements/stage1-checkpoints.md` 的规则段 —— 记录 N=35 之前必须读。
6. `~/.claude/projects/-Users-jason-Documents-typing-app/memory/` 下的 feedback-*.md —— 这个项目付过学费的教训,每条一行。

**先做,再开工:**
- `bash scripts/run_all_gates.sh`(地板 13);`python3 scripts/stage1_walk.py preflight`(直接读 ASC,不信文档);`ListAgents` 看有没有其他会话共用这个仓库。
  - *2026-09-25 注:§C2 落地后地板是 **14**(`--headless` **13**)——`scripts/test_review_watch.py` 入闸;上一行的 13 是写这份交接时的数字。评论的**实时**读取(`python3 scripts/review_watch.py`)需要 ASC 密钥,不是闸门,发布日和检查点日各跑一次,输出逐字贴进检查点记录。*
- `python3 scripts/sales_report.py --checkpoint`:如果 N=35 那一行打印 "reached",按 `stage1-checkpoints.md` 的规则**逐字**记录(先向我确认没有未登记的走查安装),不算界限、不评判分支。

**这一轮的目标:按 `PLAN-V1.34.md` §F 的顺序把 v1.34 做出来并提交审核。**
- 顺序:§C3(截图工具修好,先在未改动的树上证明它复现 1.33 基线)→ §B1–B5 各自在独立 worktree 里按文件分组实现 → §C2/C5/C6/D1/D2 的文档与工具 → §G 的验证 → 文案 → 构建、上传、dry-run、写元数据、提交。
- 你全权负责实现、审查、构建、上传、提交,不用逐步问我;每次对 App Store Connect 写入前先 `ListAgents`,有共用仓库的活跃会话就先 `SendMessage` 通知。
- 提交前必须做 §G 的全部验证:默认字号渲染逐像素对照 1.33 基线(只允许计划里点名的差异);模拟器 AX5 截图前后对比;`run_ios_placement_tests.sh`;多镜头对抗审查,每条非 NOTE 的发现给独立反驳者;冻结面镜头(`git diff` 不得触碰 `RoadView.swift`、Settings 的 The Road 卡、菜单路线条、价格、About 的计数文本、商店元数据)。1.33 用了四轮审查才修好一个 HUD 行,不要少于两轮。
- What's New 逐句对照代码核实后再发;三语无 ★;描述、关键词、截图一律不动。
- 发布上线当天:`FIRM_RELEASE_DATES_PT` 追加太平洋日期,`stage1_walk.py` 的 `EXPECTED_*` 和走查卡切到新构建,记录到 STATE。

**三条红线,原文在 HANDOFF 里,这里只重复结论:**
1. §K 的 day-0 已知阳性购买和 §L 的三道手动检查**只有我本人能做**。不要在任何环境里做任何购买——不是生产、不是 sandbox、不是 TestFlight、不是对着本地 .storekit 配置;不要登入登出任何 Apple 账户;走查前不要在这台 Mac 上用 Xcode 直接运行 Nihongo Ride(会生成本地 StoreKit 配置)。
2. 不要往 §L 的 walked 栏或 §K 里写"已完成",也不要自行记录"跳过";不要改写 `PLAN-STAGE1.md` 里 "Each needs a date, a device and an outcome written beside it **before v1.30 is submitted**." 那句话;不要为了让闸门变绿去削弱它。
3. 观测窗口内不碰购买页、价格、放置、三语商店元数据;会改变骑行距离的功能要在 §K 登记,不是回避。`PLAN-V1.34.md` §I 列了有意不做的项目和理由,不要重新把它们捡起来。

**如果我这几天走查了 §K / §L:** 先按 `docs/DRAFTS-STAGE1-RECORDS.md` 的草稿把记录给我确认,再按计划 §E 处理购买闸门。走查之前的所有工作都不依赖它。

开工前把上面的阅读和检查做完,然后告诉我你打算怎么分组实现 v1.34,再开始。
