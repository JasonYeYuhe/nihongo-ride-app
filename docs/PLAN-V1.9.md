# Nihongo Ride — v1.9 开发计划(硬化 + 统计 headline + 小赢)

> 状态:v1.9 事实源。经 **6 视角并行 grounding(读真实代码/数据)+ 综合 + 对抗 review(verdict REVISE-THEN-GO,核心修订:收敛过满范围 + 前置两个已核实的真 bug)**,2026-07-06 立。
> 承接:v1.8(变形本地 SRS + vz ずる + TTS)双端 **READY_FOR_SALE**;v1.8.1(打开变形 SRS iCloud 同步)双端 **WAITING_FOR_REVIEW**。`swift test` 基线 **213/35 全绿**(不得回归)。
> Jason 全权授权(「准备下一个版本 你全权负责」)。本计划按对抗 review 的收敛意见成稿:**committed = A + B + C**,其余明确降 stretch / 推迟。

## 0. 一句话范围

**v1.9 = 先补齐同步正确性(A,必做),再把 v1.8 已建但没露脸的数据变成一个真·统计面(B,headline:Swift Charts 统计屏,吸收变形 forecast/leech),外加一个纯站内小赢(C:结算复习词朗读)。** 不追新维度(widget / kanji SRS 是「大赌注」,诚实推后)——这是一次「深化 + 硬化」,不是新前沿,明写在明面上。

**核心 ethos(承袭):诚实控范围,装不下推下一版。** 对抗 review 抓的头号问题就是「6 阶段=几乎整个 1.9 backlog 塞一版」→ 本计划**硬砍到 A+B+C 三个 committed**,C/D/E/F 里只留一个小赢 committed,其余进 stretch/deferred,并给出**硬 cut 线**(不是「也许砍」的含糊 firstCut)。

---

## 1. 现状 + 两个已核实的真 bug(grounding 抓出、已对代码复核)

- **变形 SRS(v1.8)结构干净**:独立 `ConjugationReviewStore`/文件/CKRecord,`SyncMerge.conjugationReviewStores` 与设备验证过的 `reviewStores` 同构,弱形加权纯只读,GameCore 不 import ConjugationReviewKit。v1.8.1 刚把 `conjSRSSyncAvailable=true`、Production schema 已部署(含顺带修的 WordList 缺口)。
- **🐞 Bug-1(必做,Phase A1):变形 SRS 同步 back-fill 缺口。** `CloudKitSyncController.start()` 仅 `if saved == nil || fullResync { enqueueAllLocal() }`(CloudKitSyncController.swift:71)。老 v1.8 用户升级 v1.8.1 后 flag 打开,但其 CKSyncEngine state 非 nil(早就同步过 SRS/rides)→ enqueueAllLocal 不跑 → **已积累的变形卡永不回传到云/其他设备**(新练的卡会经 recordLocalChanges 上传,但历史 backlog 卡住,除非手动关开同步触发 fullResync)。非数据丢失(本地完好),是一次性 back-fill 遗漏。
- **🐞 Bug-2(必做,Phase A2,HIGH):finishGame SRS 合并竞态 = 在野跨设备数据丢失。** `GameSession.review` 是**值类型快照**(建 session 时拷贝,GameSession.swift:118/137)。finishGame 用 `reviewStore = session.review` **整体覆盖**(AppModel.swift:830),`changedSRS` 对当前 `reviewStore.cards` 求 diff(:826)。若局中云 fetch 经 `applyCloudChanges` 合并进 `reviewStore`(scenePhase active 时可触发),则 finishGame 用 session 的**合并前快照**覆盖掉这次云合并→**另一设备的 SRS 更新被静默回退**,且 `changedSRS` 会把这些云卡标脏→**重传陈旧值**。自 v1.4 iCloud 上线起潜伏于**核心 vocab SRS**,窄但真。
- **🐞 Bug-3(必做,Phase A3):静默同步失败盲区。** `handleSent` 对 `failedRecordSaves` 只处理 `serverRecordChanged`,其余错误「留给 engine 重试」不 log、不改 SyncStatus——**正是把 WordList Production schema 缺失藏了 3 个版本的那个盲区**。加 `PersistLog.failure` + 非瞬时 CKError 置 degraded 状态(**红线:绝不在 handleSent 驱动引擎**,只 log + 状态)。
- **grounding 事实(锚定后续判断)**:例句 `exJP` **2072/2121 含汉字**、无例句假名字段、kanji→kana 工具链本机全无(mecab/fugashi/pykakasi 未装;gemini/agy CLI 在);`passages.json` **233 条**纯假名(gen_passages.py 直出、有 swift 可打性闸);Swift Charts 原生可用(min iOS17/macOS14 ✓,零新 target/entitlement/schema);`ConjugationReviewStore` 有 `weakestFormCards()/leeches()` 但**无 dueForecast**(ReviewKit.DueForecast 是 ReviewStore 的方法)。

---

## 2. Phase A —— 同步正确性硬化(必做,committed,**最先落地、独立**)

**先于 headline 落地**,这样同步回归不会和功能改动混在一起。三个改动都在 `CloudKitSyncController`/`AppModel` 同步路径(正是 WordList 藏 3 版的高危区),故 **re-size S→S-M,按改动拆验证**。

- **A1 变形 back-fill**:flag `false→true` 转换时一次性 `enqueueAllLocal` 变形卡,**由持久化 marker gating**(`conjSRSBackfilled`,仿 odometer backfill / legacy deck 收敛)防重复。红线:只 `engine.state.add + scheduleSync`(Task hop),绝不在此驱动引擎。
- **A2 finishGame 合并竞态**:`reviewStore = session.review` → **`reviewStore = SyncMerge.reviewStores(session.review, reviewStore)`**(session 结果与当前(可能已云合并)store 合并);`changedSRS` 对**局开始快照**求 diff(只重传本局真改的卡,不重传局中云卡)。复用已测 `SyncMerge.reviewStores`。
- **A3 静默失败 log**:`handleSent` 对每个 `failedRecordSaves` `PersistLog.failure`;非瞬时 CKError 置 degraded SyncStatus。**红线:log/状态-only,绝不 fetch/send。**
- **测试**:A2 回归单测(局中注入云合并,断言不丢、不重传陈旧)+ A1 幂等测(marker 阻止二次 enqueue)+ A3 测(非瞬时 CKError 置 degraded 且不调引擎)。均走 GameCore/SyncKit 纯函数缝或 CloudKitSyncController 测试缝。
- **闸**:三测绿 + **Release 启动崩溃门**(动了 CloudKitSyncController,须复跑签名 Release~10s 看无 CKSyncEngine fatal)+ 设备门:双设备验证 v1.8 用户变形卡升级后回传(顺带完成 v1.8 欠的 ConjugationSRSCard 双设备读验证)。

---

## 3. Phase B —— HEADLINE:统一「统计/Stats」屏(committed,M,Swift Charts)

一个独立 `.stats` 屏,比骑行日志更深:从 `RideRecord` 历史出 **每日词数柱 / 正确率趋势 / WPM 分布 / 模式·等级分布**,**并吸收变形区**(`DueForecast` + `weakestFormCards/leeches`——v1.8 建了却没露脸)。变形统计放这里,不另起「变形日志」第二个 UI。

- **数据**:`JournalKit.RideRecord`(10 个可图字段/局)+ `RideJournal` + `OdometerLog` lifetime;变形区读 `conjugationReviewStore`。
- **新代码(诚实,不是「零新码」)**:`ConjugationReviewStore.dueForecast()`——ReviewKit.DueForecast 是 ReviewStore 方法,变形 store 无等价物;**加到 ConjugationReviewKit(app 已 import),纯计算不改 SRS**(红线:pure-read)。
- **✅ 前置验证已过(B0,2026-07-14)**:Swift Charts 在 ImageRenderer(headless capture)下**完美渲染**(真柱/轴/网格/标签,非占位)——统计屏可自由用 Charts,含 store 截图,**无需在 isCapturing 时省略**。最大未知已清。
- **UI 契约**:非游戏屏(抑键盘、Esc/Back、RootView zIndex);`.scaledSystemFont`(Dynamic Type 不回退);C3 VoiceOver(图表加合成 label/summary,仿 v1.5 JournalView sparkline 处理)。
- **闸**:统计读取纯函数测(空历史/单局/多局降级)+ headless 渲染(capture 模式确定性,chart 缺失优雅降级)+ 不破现有屏。

---

## 4. Phase C —— 小赢:结算屏复习词朗读(committed,S,独立零外部依赖)

`ResultsView` 的「复习这些词」列表每词加朗读钮,读**安全的 `.kana` 字段**(词自身读音、无歧义、每点一次一 utterance)。复用 `AppModel.speak/ttsEnabled/ttsAvailable` + `SpeakButton`(Image+onTapGesture 非 Button,红线:不抢 KeyCaptureView 焦点)。选它做小赢因为:**全站内、无外部依赖、无数据尾巴**(review 明确推荐它优先于 share card / GC)。

- **闸**:朗读钮不破结算布局(headless)+ 设备门:结算屏朗读不丢按键(macOS KeyCaptureNSView 续收 keyDown / iOS 软键盘不被永久 dismiss)、ja-JP 离线读 .kana。

---

## 5. Stretch(只在 A/B/C 早落地后才做;否则不做)

明确 **stretch 层**,不是 committed。硬 cut 线:**A+B+C 是本版承诺;下面按序只在有余量时加。**

- **S1 分享卡(S)**:复用 `Screenshot.swift` 的 ImageRenderer 路径渲染紧凑结果卡 + `ResultsView` 出 `ShareLink`。**设计专用紧凑卡,不复用整个 ResultsView。** 无新 target/entitlement/网络。设备门:macOS `NSSharingServicePicker` 在 App Sandbox 下的行为。
- **S2 例句 Practice 子选项(L 数据尾,首个被砍)**:Practice 内容 picker 加第三项「例句」(段落/词流/例句),复用 PLAN-V1.8 §E 已 spec 的 `GameSession.makeExampleSentences(id=exmp-<vocabid>, recordsSRS=false)`。**方向决策(见 §8)**:Option A 生成 exKana(L,同音字读音是雷:可打但读错会把用户正确输入判错——须 gemini 生成 + fugashi/MeCab 交叉核 + 新 swift 可打性闸 + 人工裁决,绝不自动应用)vs **Option B 扩 passages.json(S,纯假名零 kanji→kana 风险,现成可打性闸,交付 ~80% 同价值)**。**推荐 Option B**;Option A 仅在有 exKana 验证预算时。**红线:例句 drill `recordsSRS=false` 绝不写扁平 vocab SRS(+零写守卫测,仿弱词 cram);例句假名绝不进全局唯一 kana 词池。**

---

## 6. 明确推迟到 v1.10+(不进 1.9)

- **Widget(WidgetKit)** —— 第 5 次推迟,诚实:需新 xcodegen extension target + App ID/provisioning + 新 App Review 面,且要把**所有 store 写(review/history/odometer + CKSyncEngine state 文件)从 applicationSupportDirectory 迁进 App Group 容器**并保 .atomic/主 actor/合并顺序。唯一「headline 级」engagement 项,但也最贵最险——自成一版。
- **kanji/部首 SRS** —— XL 多版赌注:零 per-kanji/部首数据(须从头 ETL KANJIDIC2 + kradfile/KanjiVG)、需**新的非打字交互**(脱离 romaji→kana 本体)、且重演完整第三 SRS 集成含 CloudKit Prod schema 部署。
- **SRSLike 协议抽取** —— 过早:v1.9 不加第三 SRS 类型,红线前置条件(「出现第三种才抽」)未满足。kanji SRS 真做时才是 groundwork。
- **更多变形形**(ました/ません/命令/ば・たら/たい/受身・使役)—— additive 但依赖 ConjugationKit golden 扩充 + 受身/可能 られる 消歧决策(一段可能形与受身字符串同形);更大的可选赌注。
- **GC 变形成就(原草案 Phase D,review 砍出 committed)** —— 最弱性价比:依赖 ASC 服务端 achievement-id 配置 + 完整提审周期(外部、可独立于工程滑期),且**成就 id 上架后近乎不可移除**、承诺一个近永久 GC 面,换「变形终于有 GC 面」的边际价值。留后续或与未来变形内容扩充捆绑;**若做也绝不 gate 发版**。
- **un-save tombstone(跨设备删词不复活)** —— 真、用户可见(词单 marquee 功能),但需**协调的 CloudKit Prod schema 部署**(给 WordList 加 deletedAt map 字段)。为保 **v1.9 schema-stable**,与 §7 的 schema-export guardrail 一起批到 v1.10。
- **例句 TTS 朗读** —— exJP 是汉字无假名读音(29% 覆盖、仅 macOS/iPad),ja-JP 易读错;仅在设备发音抽检过才追。HUD 快速朗读 / 母语朗读钮标签 = **DROP**(与卡上钮冗余 / 已由 language 参数交付)。
- **DROP(非推迟)变形 store trim/压缩**:store 按 (verb,form) 键、最坏 ~16k 卡自 bound,与不封顶的 ReviewStore 同形,**永不需要 trim**。

---

## 7. 承诺的保险项(committed insurance,review 从 optional 提升)

- **cktool Prod schema-export guardrail + 提审前 diff**:一个脚本/流程,发版前 `cktool export-schema --environment production` 对比代码期望的 record types/字段,**任何缺失/漂移即红旗**——这是防止再犯 WordList 缺失(藏 3 版)的真·保险。token 已在本机 keychain(`nihongo-cktool-schema`)。列 committed,因为它是 v1.10 tombstone schema 部署不静默回归的前提。

---

## 8. 待拍板(Jason 已全权授权,仅列可见)

- **例句方向(Phase S2)**:Option A exKana 生成(L,同音字雷)vs Option B 扩 passages.json(S,零风险,~80% 价值)。**推荐 B**;S2 本就是首砍。
- **统计屏是否吸收变形 forecast/leech(一屏)而非另建变形日志**?**推荐是**——深化变形不再 headline、免第二个 UI。
- **un-save tombstone 进 v1.9 还是 v1.10**?**推荐 v1.10**(保 v1.9 schema-stable,避免又一次 Prod schema 部署 dance)。
- **正式 DROP 变形 store trim**(自 bound,永不需要)——确认。

---

## 9. 排序

1. **Phase A**(硬化,最先、独立):A1 back-fill / A2 finishGame 合并 / A3 静默失败 log + 三测 + Release 崩溃门 + 双设备验证。
2. **Phase B**(headline Stats):**Day-1 先验 Swift Charts under ImageRenderer** → vocab 图表 → 变形区(+ `ConjugationReviewStore.dueForecast()`)。
3. **Phase C**(小赢):结算复习词朗读。
4. **(committed insurance)**§7 schema-export guardrail。
5. **Stretch**(有余量才做):S1 分享卡 → S2 例句子选项(首砍,走 Option B)。
6. **发前**:对抗 re-review(同步正确性/红线)+ 设备门(双设备变形回传 + TTS 结算朗读不丢键 + Charts 渲染)+ Release 崩溃门 + bump 1.9(mac≥13/iOS≥14)+ submit_1_9.py(find_build 按平台解析)。

---

## 10. 红线(承袭 v1.6/1.7/1.8,务必保留)

1. 变形 SRS 必用独立 `ConjugationReviewStore`/文件/CKRecord,绝不复用扁平 ReviewStore;弱词 cram/Practice/例句 `recordsSRS=false` 永不写扁平 vocab SRS、永不喂变形 SRS。
2. **CKSyncEngine 绝不在 delegate 回调驱动引擎**(A3 的 handleSent 改动只 log+状态;A1 back-fill 走 state.add + scheduleSync Task hop);nextRecordZoneChangeBatch 按值快照 + CKRecord 深拷贝;preserve unknown fields;**新 record type / 字段须 dev→prod 部署**(v1.9 目标 schema-stable,不加新 record type)。
3. 所有文件写同步、主 actor、.atomic。
4. app 经 GameCore 触达 ConjugationKit(不直接 import;`ConjugationReviewKit` 可 app 直接持,已如此);SpeechKit 叶子可直接依赖。
5. 非游戏屏抑键盘;游戏屏复用 `.playing` 自动召唤 + isTouchDevice HUD;朗读钮 Image+onTapGesture 不抢焦点。
6. kana 全局唯一(例句假名不进词池);Dynamic Type 不回退,新 UI(统计屏/朗读钮/例句选项)`.scaledSystemFont`,不破 C3 VoiceOver。

---

## 11. 版本与提交

- bump `MARKETING_VERSION 1.9`;build **每平台递增**:当前 v1.8.1 = macOS 12 / iOS 13,v1.9 用 **macOS≥13 / iOS≥14**。
- What's New 双语写:统计面(Stats)、同步稳定性修复、结算朗读;无 ★ 字形。
- submit_1_9.py 仿 submit_1_8_1.py(find_build 按平台解析防撞号)。**须等 v1.8.1 上架**(一次一个版本在审)。

---

## 12. 诚实红旗(review 记录)

- v1.9 无「大新维度」headline(widget/kanji 都推后)——这是**刻意的、路线图一致优先于大赌注**的选择,但要明面:Stats 是深化不是新前沿。
- Bug-2(finishGame 合并竞态)是**今天在野的数据丢失**,Phase A 必做;修必须对**局开始快照**求 changedSRS diff,否则仍重传陈旧。
- 推迟 un-save tombstone = 「跨设备删词复活」bug 持续整个 v1.9(词单 marquee 上可见);仅因修它需 Prod schema 部署、选择批到 v1.10 才可接受——用 §7 guardrail 兜底。
- Swift Charts under ImageRenderer 未证:Phase B Day-1 先验,失败则 capture 省 chart,不阻塞。
