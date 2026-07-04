# v1.8 开工 Prompt(粘给 fresh new session,无缝衔接)

> 用法:开一个全新 Claude Code session,把下面 `---` 之间整段粘进去即可。它自包含,读完 PLAN-V1.8 + 自动记忆就能从 Phase A 起手。

---

你接手 Nihongo Ride(にほんご ライド)的 **v1.8 开发** —— macOS+iOS SwiftUI 日语打字练习 app(Swift 6 strict concurrency,SwiftPM 库模块 + app target,CloudKit/CKSyncEngine 手动模式私有同步,Game Center),已上架。工作目录 `/Users/jason/Documents/typing_app`。

**工作方式**:用中文交流;你有完全自主开发权(Jason:你全权负责),代码没问题就推进、小步 commit、每次 push 私有 remote `github.com/JasonYeYuhe/nihongo-ride-app`(main);不在 Jason 用机时截屏(headless ImageRenderer 才安全,但注意 **ImageRenderer 忽略 dynamicTypeSize,大字号布局只能设备验**);仓库是事实源,深层背景在自动记忆 `/Users/jason/.claude/projects/-Users-jason-Documents-typing-app/memory/project-nihongo-ride.md`。

**开工前必读**:① `docs/PLAN-V1.8.md`(v1.8 计划,已过 Gemini 3.1 Pro review,verdict REVISE-THEN-GO、4 条修订已全纳入,本期事实源)② 上面的自动记忆。

**当前状态(2026-06-29)**:v1.7(Dynamic Type + 弱词训练 + 变形选形 + 硬化)双端 **READY_FOR_SALE**,一次过审上架。旧版仍在售。`swift test` 基线 **185/32 全绿**(不得回归)。「一次一个版本在审」已解锁,v1.8 开发+发版都能直接走。构建号 v1.7 后 **macOS 10 / iOS 11**,v1.8 用 **macOS≥11 / iOS≥12**。

**v1.8 = 把 v1.6 的变形 MVP 深化成真·学习循环**(Jason 选全部四方向,已诚实控范围、按依赖拆分):

- **A vz「ずる」引擎解禁(小赢先行,S,独立)**:`VerbClass` 加 `.zuru`(raw `"zuru"`)+ `Conjugator.zuruForm`(ずる→じ-stem:演ずる→演じ/演じて/演じた/演じない/演じなかった/演じられる/演じよう/演じます,无音便,不以 ずる 结尾返 nil);`enrich_verb_classes.py` 把 `zuru` sentinel 从 withhold 改成 stamp `vc="zuru"`(--write 戳 12 个 N1/N2)+ golden(12 词×7 形 + 数据端到端)。**红线:只解禁 JMdict 标 zuru 的真 zuru,绝不误升 godan_r 的 削る/譲る(18 个 ずる 结尾里 6 个是真 godan_r)**。给变形 SRS 池加料。

- **B 变形 SRS 本地核心(头牌,M)+ 弱形加权**:新模块 **`ConjugationReviewKit`**(sibling ReviewKit,零依赖)= `ConjugationSRSCard`(id=`sourceID#form` **形级**,字段同 SRSCard,SM-2 逻辑 **Option A 平行类型**从 SRSCard 复制 ~30 LOC 换干净边界)+ `ConjugationReviewStore`(dueCards/record/weakestFormCards + 原子 JSON `conjugation-review.json`)。**红线:独立 store/文件,绝不复用扁平 ReviewStore**(否则变形错题以形级 id 混进 vocab journey due)。`GameCore.ConjugationSession` 加**可选 `onOutcome:((ConjugationPrompt,TypingOutcome)->Void)?`**(默认 nil=保 MVP 结构性零写,session **仍不持任何 store**,只 emit outcome)。AppModel 持 `conjugationReviewStore`、装配 onOutcome 写入(变形 drill 默认写变形 SRS,加 `AppSettings.conjugationSRSEnabled` 但默认 true);**弱词 cram 绝不喂变形 SRS**。`ConjugationSession.makeReview(due:[(entryID,form)],...)` 到期优先 + 新形填充(GameCore 只收 plain data)+ 菜单「复习 N 个到期变形」按 dueCount gating。**弱形加权:`WeakFormPicker` 定义在 app 层(非 GameCore——红线 6),AppModel 读 store 算弱形、传纯闭包 `(entryID,[ConjugationForm])->ConjugationForm` 进 make;GameCore 对 store 无知**;概率偏向弱形(60/40 防只练一形),store 只读。

- **C 变形 SRS iCloud 同步(头牌云,M,设备门 E 前置)**:`CloudKitSyncController` 加 `RT.conjSRS="ConjugationSRSCard"`(recordName `ConjugationSRSCard:sourceID#form`,字段同 SRSCard,照 SRSCard/RideRecord/SavedWords 模式);`SyncMerge.conjugationReviewStores`(promptID/lastReviewed 新者胜);AppModel.applyCloudChanges 加参数。**红线:绝不在 delegate 驱动引擎(recordLocalChanges→scheduleSync Task hop)、nextRecordZoneChangeBatch 按值快照 + CKRecord 深拷贝、preserve unknown fields**。**部署 prod schema 前必审 v1.7 已上架的 parse 对未知 record type 是安全 skip 不是 fatalError(否则在野 v1.7 崩)**。**设备门 E 跑完才 flip on,否则 gated land(`conjSRSSyncAvailable=false`,仿 v1.2–v1.4 iCloud 分期),v1.8 只 ship 本地变形 SRS**。

- **D TTS 假名朗读(自成一面,M,独立零云零 SRS)**:新模块 **`SpeechKit`**(@MainActor 包 `AVSpeechSynthesizer`,ja-JP 离线,切卡 cancel;**SpeechKit 可作 app 直接依赖,叶子模块无红线 6 约束**)。`AppSettings.ttsEnabled=false`(opt-in)/`ttsRate`。WordCard/ConjugationCard 加朗读钮(`speaker.wave.2`)+ SettingsView TTS 卡。**红线:朗读钮在游戏屏但不触发键盘且绝不抢焦点**——游戏屏靠隐藏 KeyCaptureView 捕键,点击后须立即重夺焦点(iOS `KeyboardSummon.summon()`/macOS `.focusable(false)`)否则丢按键。语音缺失优雅降级不 alert。新 UI 用 `.scaledSystemFont`(不回退 Dynamic Type)。

- **E 句子模式(诚实收缩,S–M,首砍候选)**:**不做新顶级模式**(与 Practice/内联例句差异化弱)→ 收缩为 **Practice 内容 picker 第三选项「例句」**。`GameSession.makeExampleSentences`(有 exJP 的 vocab,每例句一 item)复用 PracticeView。**红线(CRITICAL):`recordsSRS=false` 绝不写 SRS**(Practice 永不写扁平 vocab SRS + 整句判分会污染单词 SM-2);闸=整局例句 drill 对 flat ReviewStore 零写守卫。**v1.8 装不下时 E 第一个砍到 v1.9**。

**设备门 E(Jason 设备,解锁 Phase C 云同步;Jason 已确认会尽快做)**:① 签名 Release 启动崩溃门(动了 CloudKitSyncController 必复跑,须真跑二进制~10s,headless 不算)② 双设备变形 SRS 读/合并验证 ③ 1.7↔1.8 跨版本收敛 ④ 云 schema dev→prod 部署 ⑤ TTS 实机 + 大字号走查。

**绝对红线(承袭 v1.6/v1.7 + 变形 SRS 新增,务必保留)**:①变形 SRS 必用独立 `ConjugationReviewStore`(独立文件 + 独立 CKRecord),绝不复用扁平 ReviewStore ②ConjugationSession 仍不持 store(只 onOutcome 闭包);弱词 cram/Practice/例句 永不写扁平 vocab SRS(recordsSRS=false)、永不喂变形 SRS ③CKSyncEngine delegate 不驱动引擎(scheduleSync Task hop)、按值快照 + CKRecord 深拷贝、preserve unknown fields、新 record type 需 dev schema JIT→prod 部署 ④所有文件写同步/主 actor/.atomic ⑤zuru 只解禁真 zuru 绝不误升 godan_r;conjugatedKana 临时绝不持久化;kana 全局唯一 ⑥app 经 GameCore 触达 ConjugationKit;ConjugationReviewKit 由 AppModel 直接持;GameCore 不 import ConjugationReviewKit;SpeechKit 可 app 直接依赖 ⑦非游戏屏抑键盘,游戏屏(含到期变形复习)复用 .playing 自动召唤 + isTouchDevice HUD;朗读钮不抢焦点 ⑧xcodegen 版本字面量 $(MARKETING_VERSION)/$(CURRENT_PROJECT_VERSION);构建号每平台递增 v1.8≥macOS 11/iOS 12 ⑨Dynamic Type(v1.7)不回退,新 UI 用 .scaledSystemFont、不破 C3 VoiceOver。

**排序**:先 A(vz 小赢独立)→ B(变形 SRS 本地头牌 + 弱形加权)→ D(TTS,可与 B 并行)→ C(变形 SRS 云,设备门 E 前置、否则 gated land)→ E(例句子模式,首砍候选)→ 发前对抗 re-review + 设备门 E + Release 崩溃门 + bump + 提交。

**构建&发版(管线已很顺)**:repo 在 ~/Documents 下有 sticky `com.apple.provenance` xattr → codesign detritus 失败——已自动化:就地跑 `scripts/build-appstore.sh --upload` / `-ios.sh --upload`(检测到自动 rsync 无 -X 临时副本绕 provenance,双端各独立 mktemp 可并行)。**Release 启动崩溃门**须 rsync /private/tmp 副本 + `xcodegen generate && xcodebuild build -scheme NihongoRide -configuration Release -derivedDataPath build/rel -allowProvisioningUpdates DEVELOPMENT_TEAM=KHMK6Q3L3K` → **真跑签名二进制~10s+ 看 stderr 无 CKSyncEngine fatal**(headless NIHONGO_SHOT 不能当崩溃门:sync start() 是 Task hop,渲染完即 terminate 跑不到;且 swift run Debug 无 entitlement→sync 控制器返 nil 不启)。提交仿 `scripts/submit_1_7.py` 改 `submit_1_8.py`(**find_build 必须按平台解析**——build 号每平台独立会撞号;--metadata 建版本+What's New,--submit attach+提交)。team `KHMK6Q3L3K`,bundle `com.jasonye.nihongoride`,CloudKit 容器 `iCloud.com.jasonye.nihongoride`(Production),ASC app id `6777469778`,`asc_api.sh` 端点带前导 `/`。What's New 存 `docs/ASC_METADATA.md`。

**验证&工具**:`swift test` 当前 **185/32** 全绿基线不得回归(变形 SRS/vz/例句/TTS 都加测);`swift build` 才编译 app target(swift test 不编 executable);默认字号 headless 渲染回归对比**须先 `rm -rf $TMPDIR/NihongoRideCapture`**(capture 固定临时目录,results 捕获跑 finishGame 写 SRS 残留会污染后续 menu 渲染)。发版前 Release 启动自测;发版前对抗 review 用 **Claude 多智能体 Workflow**(find→verify,并行会撞瞬时限流→必要时串行)或 **Gemini 3.1 Pro**(`agy -p "<prompt>" </dev/null`,内嵌内容不依赖其文件读)或 `codex exec </dev/null`。

**需 Jason 拍板的(PLAN §13,多已定)**:范围切法(A+B+C+D+E,E 首砍);句子=Practice 子选项;变形 drill 默认写变形 SRS(always-on);设备门 E 发前做还是审核窗口内做。

先读 `docs/PLAN-V1.8.md` 和自动记忆,再从 **Phase A(vz「ずる」解禁,小赢先行)** 推进。开工吧。

---
