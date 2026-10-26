接手 Nihongo Ride:/Users/jason/Documents/typing_app,macOS + iOS 的日语打字练习 app,两端都已上线。用中文跟我交流,代码里的标识符和注释用英文。

**上一轮(2026-10-07 至 10-27)已经做完的事,不要重做,直接读记录:**
- v1.36 已于 2026-10-27(JST)两端提交:macOS build 61 / iOS build 62,`AFTER_APPROVAL`(批准即自动上线),当天 GET 仍是 `WAITING_FOR_REVIEW`。提交记录在 `docs/PLAN-V1.36.md` §H。
- Stage 1 的 N = 100 读数已记录(`f5165ed`):N = 122,0 购买,上界因没有已知阳性而扣住。
- App Review 联系电话已移出公开仓库(`54470d0`):`scripts/asc_release.py` 的 `review_contact()` 从本机 `~/Library/Application Support/NihongoRide-Stats/asc-contact.json`(mode 600)或 `NIHONGO_ASC_CONTACT` 读取。新脚本一律这样读,不要把联系人写进仓库。
- 下一阶段的计划在 `docs/PLAN-V1.37.md`(`bc5ea2a`),已经过 Gemini 4(`gemini-4-argon-high`)和 Gemini 3.8 Flash 两轮审查,§R 逐条记录了改了什么;草稿和两份审查原文在 `docs/evidence/v137-plan/`。**这一轮从执行这份计划开始。** 计划的核心:¥10 的风景到不了 ¥50/30 天的底线,赚钱的路是 E3(完整免费部分 + 一次性深度解锁,老用户全部保留)和 E5(日文界面);先在分支上做,不上 `main`,发布要等我在 N = 200 卡上定价。

**阅读顺序(全部读完再动手):**
1. `docs/HANDOFF-STAGE1-GATES-PROMPT.md` —— 这个仓库对代理的常设规则(行号已失效,按引文找)。
2. `docs/STATE-2026-10-27.md` —— 现状快照,包括 v1.36 批准当天要做的事。
3. `docs/PLAN-V1.37.md` —— 整份。重点:摘要、§0(默认 A)、§1(两张卡 C-1 / C-2 和沉默时的默认)、§C(Phase 0)、§D(v1.38)、§E(E3 的老用户规则)、§J(验证标准)、§K(有意不做的)、附录 A(只在我开口时才提交的框)。
4. `docs/PLAN-V1.36.md` §H 和 `docs/WALKCARD-STAGE1.md`。
5. `docs/measurements/stage1-checkpoints.md` 的规则段 —— N = 200 记录之前必须读。
6. `~/.claude/projects/-Users-jason-Documents-typing-app/memory/` 下的 feedback-*.md —— 这个项目付过学费的教训。

**先做,再开工:**
- `ListAgents` 看有没有其他会话共用这个仓库;`git status`(iCloud 会冒出 `* 2.swift` 副本,SwiftPM 会把它们编进去,先移出 `Sources/`)。
- `bash scripts/run_all_gates.sh`(地板 **17**,`--headless` **16**)。
- 读 ASC(只 GET)看 v1.36 两端状态。上线了就先做批准日杂事(下一节第 1 条)。

**这一轮的目标,按顺序:**
1. **v1.36 批准日杂事(计划 P0-1)**,每个平台按它自己的太平洋日期:`scripts/sales_report.py` 的 `FIRM_RELEASE_DATES_PT`(两端日期不同就各一行)和 `test_sales_report.py` 的钉子;`scripts/stage1_walk.py` 的 `EXPECTED_*` → 1.36 / 61 / 62 和它的 fixtures;走查卡和 `DRAFTS-STAGE1-RECORDS.md`;PLAN-ITERATION 的节奏行;STATE 和 memory;同一天跑 `python3 scripts/review_watch.py` 并逐字记录;再给走查卡加最小走查(选项 b)的附注。然后退休 `~/Library/Caches/NihongoRide-v135-work`:先把文档引用的文件复制进 `docs/evidence/v135/`,再把 `visualpass/` 工具(`run_visual_pass.sh`、`harness/`、`proj/`)搬到 `~/Library/Caches/NihongoRide-v137-work/visualpass/`,最后才用 `/usr/bin/trash`。
2. **v1.37(P0-2 + P0-12)**:修读音(`n2-b277` 六十キロ和 12 条表外数字+量词句)、点 行的容差、取消推送时的 CI 语料检查、删除词的 `accessibilityValue`,加上**只存本机的装机批次标记** `NihongoRide.installCohort.v1`(写一次、只增不改、整数比较版本、`priorDataPresent`)。冻结清单与 `fdb2b5f` 逐字节相同,`road.png`、`road-iap-review.png`、`menu.png` 渲染不变。**只在 1.36 两端都上线后**提交,目标 11-09..13(JST);11-14 前没提交就留到 N = 200 记录之后。`--submit` 之前在 PLAN-STAGE1 §K 追加 constraint-3 登记框(只记录发布了什么,不加规则)。v1.37 自己的批准日杂事必须在 N = 200 的 `--checkpoint` 之前做完,否则读数会因 "release registry incomplete" 扣住上界。提交后到 N = 200 记录之间是静默期,不发版。
3. **Phase 0 的文档(P0-3..P0-8、P0-10、P0-13)**:D3 决策包(所有决策格留空)、定价资料(不提任何价格)、`docs/PLAN-WINDOW2.md`(**只写计量规则**,各分支的"后果"格留空给我)、给我推的 `site/` diff(含隐私页加一句装机批次标记)、只读漏斗报告、N = 200 记录和附录 A 的草稿(不提交)、商店素材草稿(不上传)、`docs/DESIGN-E3-SAMPLER.md`(默认边界候选 1:假名 / N5 / N4 免费,N3–N1 付费)。
4. **分支工作(P0-11)**:Phase 1(P1-1..P1-6、P1-10..P1-12)、E5 日文界面(P1-15)、多 SKU(P1-5,常量关闭)、E3。都在 `~/Library/Caches/NihongoRide-v137-work/<name>` 的私有克隆里做,**N = 200 记录提交之前不合并到 `main`**。我说"停掉分支"就停。每个分支按 §J 验证通过才算完成,v1.37 上线后 rebase。
5. **两张卡,到日子在会话里给我**:C-1 走查卡在 **11-15**(或我说"开始走查"时):完整走查 / 最小走查 / 我写"不走",同卡附上 (d) 走查后要不要签 §E 的 store-gate harness、(e) 推网站、(f) 公开仓库历史里的电话要不要重写历史或设为私有。C-2 是 N = 200 卡(约 11-25..27):我读分支、给 E3 定价并写覆盖框、定 Window 2 各分支的后果。**我不回,就按 §1 的默认走,你什么都不替我记。**
6. **N = 200 读数**:先按规则 4 确认没有未登记的走查 / 参与者安装,再跑 `python3 scripts/sales_report.py --checkpoint`,只记数字,分支那一行留给我;同一天 `review_watch` 逐字贴进记录。
- v1.38(约 11-30..12-04 提交)和 v1.39(E3,只在我定价后)的安排见计划 §I。

**授权和流程:**
- 你全权负责实现、审查、构建、上传、提交,不用逐步问我;每次对 App Store Connect 写入前先 `ListAgents`,有共用仓库的活跃会话就先 `SendMessage` 通知;每次 PATCH 后逐字节读回。
- What's New 逐句对照代码核实后再发;三语无 ★;描述、关键词、截图、价格在 N = 200 记录之前一律不动。
- 每个发布的验证按 `PLAN-V1.37.md` §J:闸门、en/zh(以后加 ja)渲染逐像素对照、AX5 模拟器前后对比、`run_ios_placement_tests.sh`、多镜头对抗审查且每条非 NOTE 发现配独立反驳者、至少两轮、每个修复都要"撤回即变红"。
- 每个发布的 diff 再给两个 Gemini 看:在一次性克隆里跑 `agy --print "$(cat <prompt>)" --model gemini-4-argon-high --sandbox --mode plan --print-timeout 0 > out.md`,Flash 用 `--model gemini-3.8-flash-high`,无头模式要加 `--dangerously-skip-permissions`(只在一次性克隆里用)。范例提示词在 `docs/evidence/v137-plan/review-prompt.txt`。
- 构建纪律:读的人不构建;同一时刻每个在构建的检出一个构建根(`--scratch-path "$(bash scripts/build_root.sh | tail -1)/swiftpm"`,`xcodebuild` 加 `COMPILER_INDEX_STORE_ENABLE=NO`);代理不共用实时工作树;一次性克隆用完用 `/usr/bin/trash`,共享缓存不动;磁盘满就停下叫我清废纸篓。
- 模拟器:iOS 26.5 运行时已不在,`NihongoRide-Placement`、iPhone 17 Pro / Pro Max、iPad mini 都有可用的 **iOS 27.0** 副本,脚本按名字选可用的那个;每个结果记下运行时。需要新设备才建 `NihongoRide-<用途>`,告诉我,用完删掉。visual-pass 工具会在缺失时重建 `NihongoRide-VisualPass`,同样用完删掉。
- 仓库是**公开的**:只放汇总数字,不放设备名、账户标识、联系方式、其他 app 的销售行。网站改动只准备 diff,推送由我来。设备查询只在我点名的设备上做。不读 `CLI-Pulse-Secrets`。任何 SKU 都不开 Family Sharing。
- Documents 会话留下的本地分支 `chore/build-roots-2026-10-15`(本地闸门构建关闭索引)审查已通过、未推送;v1.36 已提交,可以合并:先 `ListAgents` 确认那个会话不在用它,合并后跑一遍闸门。

**三条红线(原话):**
1. §K 的 day-0 已知阳性购买和 §L 的三道手动检查**只有我本人能做**。不要在任何环境里做任何购买——不是生产、不是 sandbox、不是 TestFlight、不是对着本地 .storekit 配置;不要登入登出任何 Apple 账户;走查前不要在这台 Mac 上用 Xcode 直接运行 Nihongo Ride(会生成本地 StoreKit 配置)。
2. 不要往 §L 的 walked 栏或 §K 里写"已完成",也不要自行记录"跳过";不要改写 `PLAN-STAGE1.md` 里 "Each needs a date, a device and an outcome written beside it **before v1.30 is submitted**." 那句话;不要为了让闸门变绿去削弱它。
3. 观测窗口内不碰购买页、价格、放置、三语商店元数据;会改变骑行距离的功能要在 §K 登记,不是回避。`PLAN-V1.37.md` §K 列了有意不做的项目和理由,不要重新把它们捡起来。

另外:代理不定任何价格;E3 的 IAP 只在我的 C-2 框之后才创建;不写任何带新含义的 §K 框;委托下你替我做的判断要标明是"代理在委托下的判断",不能写成我的确认。

开工前把上面的阅读和检查做完,告诉我你打算怎么分组做 v1.37 和分支工作,然后直接开始,不用等我回复。
