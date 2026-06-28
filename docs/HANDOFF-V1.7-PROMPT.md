你接手 Nihongo Ride（にほんご ライド）的 v1.7 开发 —— macOS+iOS SwiftUI 日语打字练习 app（Swift 6 strict concurrency，SwiftPM 库模块 + app target，CloudKit/CKSyncEngine 手动模式私有同步，Game Center），已上架。工作目录 /Users/jason/Documents/typing_app。

工作方式：用中文交流；你有完全自主开发权（Jason：你全权负责），代码没问题就推进、小步 commit、每次 push 私有 remote github.com/JasonYeYuhe/nihongo-ride-app（main）；不在 Jason 用机时截屏（headless ImageRenderer 才安全，但注意 ImageRenderer 忽略 dynamicTypeSize，大字号布局只能设备验）；仓库是事实源，深层背景在自动记忆 /Users/jason/.claude/projects/-Users-jason-Documents-typing-app/memory/project-nihongo-ride.md。

开工前必读：① docs/PLAN-V1.7.md（v1.7 计划，**已过 Gemini 3.1 Pro review，5 条修订已纳入**，本期事实源）② 上面的自动记忆。

当前状态（2026-06-28）：**v1.6（动词变形 MVP）双端 READY_FOR_SALE**，一次过审上架。v1.5 等旧版仍在售。**「一次一个版本在审」已解锁**，v1.7 开发+发版都能直接走。

v1.7 = **质量与可达性的一刀**（Jason 选了全部四方向，已诚实控范围、按依赖拆分）：
- **A 头牌 Dynamic Type**（L）：全 app **129 处固定 `.system(size:)` 跨 11 屏**迁动态字号。**策略 = `@ScaledMetric`-first**：紧凑/HUD/游戏屏（Game/Conjugation 卡+pill）用 `@ScaledMetric` 包现有精确字号（默认字号 100% 与 v1.6 一致、能随系统放大、限幅防撑爆）；正文/标题/菜单可重排处再迁语义 `Font.TextStyle`。慎用 `ScrollView` 回包紧 VStack（破 Spacer/GeometryReader），优先 `minimumScaleFactor`。逐屏独立小 commit + 默认字号 headless 渲染不回归。
- **B 弱词训练**（S–M，纯本地，**cram-不写-SRS**）：新增 `ReviewStore.weakestCards(limit:)` 纯 readonly 排序（isLeech>ease升>lapses降>错误率，只取 totalReviews>0）；`GameSession.makeWeak`（建议给 GameSession 加显式 `recordsSRS:Bool` 开关，弱词/practice 传 false，把"不写 SRS"从 mode 判定升级为显式标记）；菜单入口按池 gating + resolve-then-guard。**关键红线：弱词提前复习未到期卡会腐蚀 SM-2，绝不写 SRS scheduling**。
- **C 变形选形**（S，纯本地）：`AppSettings.conjugationForms:[String]`（解码 `compactMap{ConjugationForm(rawValue:)}` 容错、空=全选）→ 传 `ConjugationSession.Config.forms`；MenuView 变形模式下多选形 picker。**纯本地零云状态**——真·变形 SRS 是 v1.8。
- **D 硬化**（S–M）：`try?` 写盘（18 处）**按谁触发分流**——后台/自动写失败只 log/assert（防 alert 死循环），用户主动写失败才弹 alert（仿 lastListError）；AppModel 测试缝（只抽缝不改行为）。绝不碰写盘的同步/主 actor/.atomic 红线。

不做（1.8+）：**变形 SRS**（独立 ConjugationReviewStore + 新 CKRecord Production schema，**依赖设备门 E 双设备验证先过**）、TTS 假名朗读、句子打字模式、vz「ずる」paradigm、widget/统计图/分享卡。

设备门 E（Jason 设备，按 docs/V1.5-VERIFICATION.md）：**v1.7 发版闸 = Release 启动自测（CKSyncEngine 崩溃门）+ 大字号/触屏走查**；**v1.8 前置（非 v1.7 ship 闸）= 双设备/跨版本 iCloud 读验证**（v1.7 零云状态新增故不阻塞 v1.7，但建议审核窗口内尽早做完，作为 v1.8 开工前提）。

排序：先 B+C（小赢快出）→ A（头牌逐屏）→ D（硬化）→ 发前对抗 re-review + 设备门 E + bump + 提交。

绝对红线（承袭 v1.6，务必保留）：①绝不在 CKSyncEngine delegate 驱动引擎（recordLocalChanges→scheduleSync Task hop；nextRecordZoneChangeBatch 按值快照+CKRecord 深拷贝 as? 降级）②所有文件写同步/主 actor/.atomic——**硬化只改"失败是否上报"不改"怎么写"** ③Practice/变形/**弱词** 永不写 SRS；变形 SRS（v1.8）必用独立 store ④非游戏屏抑制键盘、游戏屏（含变形、弱词）复用 .playing 自动召唤键盘+isTouchDevice HUD（2.1a）⑤kana 全局唯一、变形输出临时绝不持久化为 VocabEntry ⑥xcodegen 版本字面量 CFBundleShortVersionString:$(MARKETING_VERSION)/CFBundleVersion:$(CURRENT_PROJECT_VERSION) 显式引用 ⑦**构建号每平台递增：当前 macOS=9/iOS=10，v1.7 用 macOS≥10/iOS≥11** ⑧Dynamic Type 不破坏 C3 已 ship 的 VoiceOver label/value。

构建&发版（管线已很顺）：repo 在 ~/Documents 下有 sticky com.apple.provenance xattr 会让 codesign 报 detritus 失败——已自动化：就地跑 scripts/build-appstore.sh --upload / -ios.sh --upload，脚本检测到自动 rsync（无 -X 丢 xattr、带未提交改动）到临时副本再构建。**Release 本地启动自测须显式传 `DEVELOPMENT_TEAM=KHMK6Q3L3K`**（否则报 entitlements require development certificate）：`xcodegen generate && xcodebuild build -scheme NihongoRide -configuration Release -derivedDataPath build/rel -allowProvisioningUpdates DEVELOPMENT_TEAM=KHMK6Q3L3K`，跑二进制看 stderr 无 CKSyncEngine fatal。提交仿 scripts/submit_1_6.py 改 submit_1_7.py（**find_build 必须按平台解析**——build 号每平台独立、会跨平台撞号；--metadata 建版本+What's New，--submit attach+提交）。team KHMK6Q3L3K，bundle com.jasonye.nihongoride，CloudKit 容器 iCloud.com.jasonye.nihongoride（Production），ASC app id 6777469778，asc_api.sh 端点要带前导 /。

验证&工具：swift test 当前 **170 全绿**基线不得回归（弱词/选形/硬化都加测）；发版前 Release 本地启动自测；发版前对抗 review 用 Claude 多智能体 Workflow（find→verify，并行会撞瞬时限流→必要时串行）或 Gemini 3.1 Pro（agy CLI `agy -p "<prompt>" </dev/null`，本次 review 实测能出结果；或 codex exec </dev/null 自捕 stdout）。

需 Jason 拍板的（已在 PLAN §12，可先问）：范围切法确认（A+B+C+D，变形 SRS 推 1.8）；设备门 E 双设备验证发前做还是审核窗口内做。

先读 docs/PLAN-V1.7.md 和自动记忆，再从 Phase B+C（小赢先行）推进。开工吧。
