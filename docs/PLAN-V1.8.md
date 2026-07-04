# Nihongo Ride — v1.8 开发计划(变形深化:变形 SRS + 引擎扩容 + 新学习面 + 打磨)

> 状态:v1.8 事实源。**四方向已 grounded 核实(2026-06-29,4 视角并行调研)+ 已过 Gemini 3.1 Pro review(agy,gemini-3.1-pro-preview;verdict REVISE-THEN-GO → 4 条已全修:①句子模式 `recordsSRS=false` 零写 SRS[红线 4]②`WeakFormPicker` 在 app 层、GameCore 对 store 无知③TTS 钮不抢焦点④部署云 schema 前审 v1.7 未知 record type 安全降级)**。
> v1.7(Dynamic Type + 弱词训练 + 变形选形 + 硬化)已双端 **READY_FOR_SALE**(2026-06-29,一次过审)。
> Jason 选了全部四方向(变形 SRS 本地优先=头牌 / TTS 假名朗读 / 句子打字模式 / 小而稳 vz+变形打磨),嘱「诚实控范围、装不下推 1.9」;并确认**会尽快做设备门 E(双设备 iCloud 验证)→ 变形 SRS 云同步可进 v1.8**。本计划据此按依赖排序拆分。

## 0. 一句话范围

**v1.8 = 把 v1.6 的变形 MVP 深化成一个真·学习循环**:给动词变形接上**独立的间隔复习(变形 SRS)**——错的变形按 SM-2 到期重练,并**跨设备私有同步**;顺手**扩容引擎**(解禁 12 个「ずる」动词)、落一个**自成一面的 TTS 假名朗读**、把**弱形加权**接到 SRS 上。句子模式**诚实评估后收缩**为 Practice 的一个子选项(见 §6),而非新顶级模式。

**明确推迟到 1.9+**:变形 SRS 的 leech/trim 压缩、kanji 部首 SRS、TTS 例句朗读/结算朗读、句子模式的 POS 过滤/理解计分、widget/统计图/分享卡、Game Center 扩充。

理由:变形 SRS 是 roadmap 三个版本一致点名的 v1.8 头牌,且 v1.6/v1.7 已把地基(独立 ConjugationSession、ConjugationPrompt.id=`sourceID#form`、CKSyncEngine 手动同步的成熟 record 模式)铺好;vz 解禁是引擎小账、给 SRS 池加料;TTS 自成一面、零云零 SRS;弱形加权是 SRS 的自然收益。四方向各取其**能在不引入未验证云状态的前提下落地的部分**,其余诚实推后。

---

## 1. 现状(已 grounded 核实,2026-06-29)

- **变形 SRS 地基已就位、但 store 不存在**:`ReviewKit` 有 `SRSCard`(String id 键、SM-2 `review(quality:on:)`、原子 JSON 持久化)+ `ReviewStore`;`GameCore.ConjugationSession` **结构性零写 SRS**(不持 ReviewStore/VocabStore,`completeCurrent()` 只计分不 record——v1.6 红线)。`ConjugationPrompt.id = sourceID#form`(**形级唯一**,正是变形 SRS 想要的键)。`CloudKitSyncController` 已有成熟的 record 建模(recordName `Type:key`、`fill/parse` nonisolated、`nextRecordZoneChangeBatch` 按值快照 + CKRecord 深拷贝、`recordLocalChanges→scheduleSync` Task hop、`mergeServerRecord` 走 SyncMerge)——照 `SRSCard/RideRecord/SavedWords` 模式加新 record 类型即可。`SyncMerge.reviewStores` 按 id、`lastReviewed` 新者胜——变形 SRS 合并同构。
- **vz「ずる」= 12 个 N1/N2 真 zuru 动词 withheld(`vc:null`)**:`enrich_verb_classes.py` 检测 JMdict「zuru verb」POS→标 `zuru` sentinel→**withhold**(`cls=={'zuru'}→None`)。`VerbClass` 无 `.zuru` case、`Conjugator` 无 zuru 规则。**关键陷阱:18 个 ずる 结尾里 6 个(削る/譲る/引きずる/囀る…)是真 godan_r**(JMdict 明确标 Godan),解禁时**绝不能误升这 6 个**——JMdict POS 是权威判据,WRITE 模式按 JMdict 保留 godan_r。
- **TTS 零基建**:全仓库**无 AVFoundation**(`Sound.swift` 只用 iOS `AudioServices` + macOS `NSSound` 做音效)。`AVSpeechSynthesizer` 跨端(macOS 10.15+/iOS 13+,远低于本项目 min 14/17),日语 `ja-JP` 系统语音离线可用(增强音色需用户在系统设置下载)。`GameSession`/`ConjugationSession` 已暴露 `currentKana`/`currentGloss`/`currentExampleJP` 等——朗读钮有现成数据源。
- **句子模式 = 与 Practice 差异化弱(诚实结论)**:Practice 已做整段 passage 打字(233 Tatoeba passages);Journey/TimeAttack 的 WordCard **已内联展示 currentExampleJP 例句**;vocab 有 ~2121 条 exJP/exZH 例句。一个新「句子模式」= 打 vocab 的例句——**与 Practice 重叠、与内联例句重叠**,差异主要是「只聚焦例句」。调研 verdict:**medium 功能膨胀风险、差异化弱**;建议做成 Practice 的第三个子选项(段落/词流/**例句**)而非新顶级模式,且 SRS **按底层 vocab id 记**(绝不按句子 id,否则碎片化出隐藏并行 SRS)。
- 红线全保(v1.6/v1.7 复核过):CKSyncEngine delegate 不驱动引擎;文件写同步/主 actor/.atomic;Practice/变形/弱词 不写扁平 ReviewStore;kana 全局唯一;app 经 GameCore 触达 ConjugationKit。构建号 v1.7 后 **macOS 10 / iOS 11**,v1.8 用 **macOS≥11 / iOS≥12**。

---

## 2. Phase A —— vz「ずる」引擎解禁(小赢先行,S,独立)

给引擎加 zuru paradigm,解禁 12 个 N1/N2 动词,**给变形 SRS 池加料**(先做,独立零依赖)。

- **`ConjugationKit`**:`VerbClass` 加 `.zuru`(rawValue `"zuru"`,对齐 enrich sentinel);`Conjugator` 加 `zuruForm(kana:form:)` 实现 **ずる→じ-stem** paradigm:演ずる→ 辞書 `演ずる`、て `演じて`、た `演じた`、ない `演じない`、なかった `演じなかった`、可能 `演じられる`、意志 `演じよう`、ます `演じます`(全部建在 じ-stem 上,**无音便**)。守卫:输入不以 `ずる` 结尾→返 nil(仿 ichidan/godan guard)。
- **数据层** `enrich_verb_classes.py`:把 `cls=={'zuru'}→None`(withhold)改成 **stamp `vc="zuru"`**;`--write` 对这 12 个 N1/N2 写 `vc:"zuru"`(格式保真、diff 只增 vc 行)。**红线:只解禁 JMdict 标 zuru 的,godan_r 的 削る/譲る 保持 godan_r**。
- **golden**:`ConjugatorTests` 加 12 个 zuru 动词 ×7 形(对 3 独立语法 pass 一致表决的 ground truth);`ConjugationDataTests` 数据端到端(载 n1/n2.json,全 `vc="zuru"` 条目 7 形非 nil、kana 仍全局唯一)。
- **闸**:zuru golden 全绿 + 池健康(`playableCount` 增 ~12)+ 守恒(vc↔kana、无 godan_r 误升)。

---

## 3. Phase B —— 变形 SRS 本地核心(头牌,M) + 弱形加权

给动词变形接上真·间隔复习:变形错题按 SM-2 到期重练。**纯本地先落地**(fresh session 可立即开工、无需设备);云同步是 §4。

- **新模块 `ConjugationReviewKit`(sibling to ReviewKit,零依赖 Foundation)**:
  - `ConjugationSRSCard`(id=`sourceID#form`,字段同 SRSCard:easeFactor/interval/repetitions/dueDate/lapses/lastReviewed/totalReviews/totalMistakes)—— **Option A 平行类型**:SM-2 逻辑(`review(quality:on:)` ~30 LOC)从 SRSCard 复制过来,**换取干净模块边界**(不做过早泛型化;若 v1.9 出第三种 SRS 类型再抽 `SRSLike` 协议)。
  - `ConjugationReviewStore`(`cards:[String:ConjugationSRSCard]`,`dueCards(on:limit:)`、`record(promptID:outcome:on:)`、`weakestFormCards(limit:)`)+ 原子 JSON 持久化(`conjugation-review.json`)。
  - **红线:独立 store/文件——绝不复用扁平 ReviewStore**(否则变形错题以形级 id 混进 vocab journey due 队列)。加单测(镜像 ReviewKitTests:SM-2 排程、due 过滤、零变性、持久化往返)。
- **`GameCore.ConjugationSession` 加可选 outcome 回调**:`var onOutcome: ((ConjugationPrompt, TypingOutcome) -> Void)?`(默认 nil=**保 MVP 结构性零写**;ConjugationSession **仍不持任何 store**——它只在 complete/skip 时 emit outcome,红线结构性不破)。回调抛错须 catch+log,不崩 session。
- **`AppModel`**:持 `conjugationReviewStore`(init 载 `conjugation-review.json`,原子主 actor 写);`startConjugation` 装配 `onOutcome` 闭包写入 store(**v1.8 变形 drill 默认写变形 SRS**——它现在是学习工具不是 transient drill;加 `AppSettings.conjugationSRSEnabled` 但默认 true 备未来 UI)。**弱词 cram 绝不喂变形 SRS**(cram 是快速复习非学习机会)。
- **到期变形复习(SRS 收益)**:`ConjugationSession` 加 `makeReview(due:[(entryID,form)], vocab:, config:)`——due(verb,form)对优先 + 新形填充(GameCore 只收 plain data `[(String,ConjugationForm)]`,不 import ConjugationReviewKit)。菜单变形段加「复习 N 个到期变形」入口(按 `conjugationReviewStore.dueCount>0` gating)。
- **弱形加权(变形打磨,依赖本 store)**:`ConjugationSession.make` 的 `chooseForm(i,forms)` 回调已在。**`WeakFormPicker` 定义在 app 层(AppModel 旁),不在 GameCore**(红线 6:GameCore 不 import ConjugationReviewKit)——AppModel 读 store 算弱形,把一个**纯闭包 `(entryID:String,[ConjugationForm])->ConjugationForm`** 传进 `make`;GameCore 对 store 全然无知。有数据则按 (mistakes/reviews) per-form 概率偏向弱形(如 60% 弱形/40% 均匀,防只练一形),无数据回退 random。**store 只读**(选题不写 SRS,写只在 complete via onOutcome)。
- **闸**:ConjugationReviewStore 单测绿 + 「整局变形 drill 后 flat ReviewStore 零写入」红线守卫测试 + 到期 drill 只出 due+new + 弱形加权分布测试 + 空池/空 due 优雅降级。

---

## 4. Phase C —— 变形 SRS iCloud 同步(头牌云部分,M,**设备门 E 前置**)

变形错题跨设备私有同步。**依赖设备门 E(双设备 iCloud 读/合并已验证)+ 云 schema dev→prod 部署(Jason 设备)**。

- **`CloudKitSyncController`**(脆弱路径,绝不在 delegate 驱动引擎):加 `RT.conjSRS="ConjugationSRSCard"`,recordName `ConjugationSRSCard:sourceID#form`,字段同 SRSCard;`fillConjugation/parse` nonisolated;`nextRecordZoneChangeBatch` 按值快照 `conjugationCards` + cache 深拷贝;`applyFetched`/`mergeServerRecord` 走字段级合并;`recordLocalChanges(conjugationSRSIDs:)` 只 `engine.state.add`+`scheduleSync` Task hop。
- **`SyncKit`**:`SyncMerge.conjugationReviewStores(local,remote)`(按 promptID、`lastReviewed` 新者胜,同 reviewStores;空 dict no-op 向后兼容)+ 单测。`AppModel.applyCloudChanges` 加 `conjugationCards:` 参数(合并后原子写)。
- **schema**:`ConjugationSRSCard` record type 在 CloudKit dev 首跑 JIT → dev→prod 部署(Jason CloudKit Dashboard)。**v1.7 用户忽略未知 record type,v1.8 用户合并**;升级 1.7→1.8 立即见新 schema。**(Gemini #4)部署 prod 前必审 v1.7 已上架的 `CloudKitSyncController.parse`/`applyFetched` 对未知 record type 有安全 `default→nil/skip`**——若 v1.7 对未知类型 fatal,部署新 schema 会让在野 v1.7 设备崩(先 grep 确认 v1.7 分支是 skip 不是 fatalError)。
- **红线**:CKRecord 批快照按值 + 深拷贝(`as? copy`,坏拷贝降级跳过);preserve unknown fields;engine 只经 scheduleSync 驱动。
- **闸**:SyncMerge 单测绿 + Release 启动崩溃门(动了 CloudKitSyncController,须复跑签名 Release 自测)+ **设备门 E 双设备变形 SRS 读/合并验证**(Jason)。**若设备门 E 发前没跑完:Phase C 代码 land 但 gated(仿 v1.2–v1.4 iCloud 分期),`conjSRSSyncAvailable=false`,v1.8 只 ship 本地变形 SRS,云同步 v1.8.x/v1.9 flip 上**。

---

## 5. Phase D —— TTS 假名朗读(自成一面,M,独立零云零 SRS)

按需朗读假名(离线日语语音),opt-in、非自动播放。

- **新模块 `SpeechKit`**:`SpeechSynthesizer.swift`(@MainActor 包 `AVSpeechSynthesizer`,`AVSpeechUtterance` ja-JP、rate 可调、切卡时 cancel 在飞合成)。**SpeechKit 是叶子模块,app 可直接依赖**(红线 6 只针对 ConjugationKit,TTS 无此约束;不必强套 GameCore facade)。
- **`AppSettings`**:加 `ttsEnabled:Bool=false`(opt-in)、`ttsRate:Float`(默认 AVSpeech rate);容错解码。
- **UI**:WordCard/ConjugationCard 加朗读钮(`speaker.wave.2`,与 ★ 钮同侧),`ttsEnabled` 时显示,点击读 currentKana(+可选 gloss/formLabel),读完弃。SettingsView 加 TTS 卡(开关 + 可选 rate slider)。**(Gemini #3)朗读钮在游戏屏但不触发键盘且绝不抢焦点**——游戏屏靠隐藏 KeyCaptureView(first responder)捕键,朗读钮点击若夺走焦点会丢按键;点击后须立即重夺焦点(iOS 复用 `KeyboardSummon.summon()`,macOS `.focusable(false)`/`.buttonStyle(.plain)`)。a11y label「朗读假名」;TTS 是 VoiceOver 的补充非替代。
- **优雅降级**:ja-JP 语音不可用→钮在但 speak() no-op + log,不弹 alert;若 `ttsEnabled=true` 但语音不可用可 didSet 回落 false。
- **闸**:SpeechKit 单测(voice/locale/rate 初始化)+ 开关往返 + headless 渲染朗读钮不破默认布局(scaledSystemFont 已就位,钮用 SF Symbol)。

---

## 6. Phase E —— 句子模式(诚实收缩:Practice「例句」子选项,S–M,**首砍候选**)

**诚实结论(调研):句子模式与 Practice/内联例句差异化弱、有膨胀风险**。故**不做新顶级模式**,收缩为 **Practice 内容 picker 的第三选项「例句」**(段落/词流/例句),最小改动、复用 90%。

- **`GameSession.makeExampleSentences(level:, config:, vocab:)`**:从有 exJP 的 vocab 建队列,每条例句一 item(id=`exmp-<vocabid>`,kana=例句假名,gloss=例句译);**(Gemini #1,CRITICAL)绝不写 SRS——`recordsSRS=false`,transient drill 同 Practice**。理由:①**红线 4:Practice/例句 永不写扁平 vocab SRS**;②整句打字判分记进单个 vocab 卡会用噪声污染 SM-2 间隔(打错一个助词 ≠ 没记住这个词)。复用 v1.7 已有的 `recordsSRS` 开关(GameSession.Config),零新写盘路径。
- **UI**:复用 PracticeView(它已有段落/词流子 picker);「例句」子选项加进现有 `practicePassages` 类似开关。可选:例句里高亮目标词。
- **降级**:某级无例句→回退提示/隐藏该选项(`exampleJP` 非 null 过滤)。
- **闸**:makeExampleSentences 单测(**整局例句 drill 对 flat ReviewStore 零写入** 守卫,同弱词 cram 红线测试)+ 空例句级降级 + 不破 Practice 现有流。
- **诚实红旗**:若 v1.8 装不下(Phase B/C 是重头),**Phase E 是第一个砍到 v1.9 的**;砍了不影响头牌。

---

## 7. 设备门 E —— 双设备 iCloud 验证(Jason 设备;**解锁 Phase C 云同步**)

按 `docs/V1.5-VERIFICATION.md`。Jason 已确认「会尽快做」。

1. **签名 Release 启动自测**(CKSyncEngine 崩溃门)——v1.8 动了 CloudKitSyncController(加 record type),**必复跑**(rsync /private/tmp 副本 + `xcodebuild build -scheme NihongoRide -configuration Release -allowProvisioningUpdates DEVELOPMENT_TEAM=KHMK6Q3L3K` + 跑签名二进制~10s 看无 CKSyncEngine fatal;注:headless NIHONGO_SHOT 不能当崩溃门,须真跑二进制)。
2. **双设备 iCloud 读/合并验证**(欠账 + 变形 SRS 新增):两台登同一 iCloud,A 练变形错题→B 拉取合并到期正确(变形 SRS union/LWW);旧 SRS/词单/收藏也复验。
3. **跨版本收敛**:1.7↔1.8 共存一账号,验证 v1.7 忽略 `ConjugationSRSCard` record type、v1.8 正确合并,旧数据不丢。
4. **变形 SRS 云 schema dev→prod 部署**:dev 首跑 JIT `ConjugationSRSCard` → CloudKit Dashboard deploy dev→prod。
5. **TTS 实机**:ja-JP 离线语音在 Jason 设备可读(macOS+iOS);大字号下朗读钮不破布局。

**E 的产出 = 变形 SRS 云同步的绿灯**。没它 Phase C 只能 gated land(§4 尾)。

---

## 8. 风险与闸

| 风险 | 说明 | 闸 / 缓解 |
|---|---|---|
| **R1 变形 SRS 泄漏进 vocab journey** | 若复用扁平 ReviewStore 或键混用 | 独立模块/文件/CKRecord;「变形 drill 后 flat ReviewStore 零写」测试 |
| **R2 zuru 误升 godan_r** | 削る/譲る 结尾 ずる 但是 godan_r | enrich 按 JMdict POS;数据 golden 抓误分类 |
| **R3 云 schema 未验证就上** | 新 record type 建在未验证同步地基 | 设备门 E 前置;跑不完则 Phase C gated(仿 v1.2–v1.4) |
| **R4 CKSyncEngine 重入崩溃** | 动 CloudKitSyncController 易重蹈 v1.4 | delegate 不驱动引擎;Release 启动崩溃门必过 |
| **R5 句子模式膨胀 / 误写 SRS** | 差异化弱 + 整句判分污染 vocab SM-2(Gemini #1) | 收缩为 Practice 子选项;**`recordsSRS=false` 零写 SRS(红线 4)**+ builder 零写守卫单测 |
| **R6 TTS 离线语音缺失** | 用户设备无 ja-JP 增强音色 | 系统基础音色离线可用;缺失优雅降级不 alert |
| **R7 装不下** | 四方向 + 云同步一期塞太满 | 排序砍序:Phase E→句子模式先砍;TTS 次之;头牌 B(+C 若 E 过)保住 |

---

## 9. 明确推迟到 1.9+(不进 1.8)

- 变形 SRS 的 leech 治理 / store trim 压缩(v1.8 不 trim,终身学习史;>10MB 再加压缩)。
- kanji 部首 SRS(会触发抽 `SRSLike` 协议)。
- TTS 例句朗读 / 结算复习词朗读 / HUD 快速朗读钮 / 母语 zh 朗读钮标签本地化。
- 句子模式的 POS 过滤 / 理解计分 / 独立顶级模式。
- widget、统计图、分享卡、Game Center 扩充、per-word un-save tombstone。

---

## 10. 红线(从 v1.6/v1.7 承袭 + 变形 SRS 新增,务必保留)

1. **变形 SRS 必用独立 `ConjugationReviewStore`(独立文件 `conjugation-review.json` + 独立 CKRecord `ConjugationSRSCard`),绝不复用扁平 ReviewStore**;变形错题以形级 id(`sourceID#form`)记,永不回流 vocab journey due 队列。
2. **ConjugationSession 仍不持任何 store**——只经可选 `onOutcome` 回调 emit outcome(默认 nil=MVP 零写);写变形 SRS 在 AppModel。**弱词 cram / Practice / 例句子模式 永不写扁平 vocab SRS(`recordsSRS=false`);且永不喂变形 SRS**。
3. 绝不在 CKSyncEngine delegate 回调驱动引擎;`recordLocalChanges→scheduleSync`(Task hop);`nextRecordZoneChangeBatch` 按值快照 + CKRecord 深拷贝(`as?` 降级);preserve unknown fields;新 record type 需 dev schema JIT→prod 部署(Jason 设备)。
4. 所有文件写**同步、主 actor、.atomic**;`conjugation-review.json` 同 review.json 原子主 actor 写。
5. **zuru 只解禁 JMdict 标 zuru 的真 zuru(じ-stem),绝不误升 godan_r 的 削る/譲る**;conjugatedKana 临时、绝不持久化为 VocabEntry;kana 全局唯一。
6. app 经 GameCore 触达 ConjugationKit(不直接 import);`ConjugationReviewKit` 由 AppModel 直接持有(它 owns the store);`GameCore.ConjugationSession` 不 import ConjugationReviewKit(只收 plain data / 闭包);SpeechKit 可作 app 直接依赖(叶子)。
7. 非游戏屏抑制键盘;游戏屏(含变形、到期变形复习)复用 `.playing` 自动召唤键盘 + isTouchDevice HUD;朗读钮是 Button 不触发键盘。
8. xcodegen 版本字面量 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 显式引用;**构建号每平台递增:v1.7=macOS 10/iOS 11,v1.8 用 macOS≥11/iOS≥12**。
9. Dynamic Type(v1.7)不回退:新 UI(朗读钮、到期复习入口、例句子选项)用 `.scaledSystemFont`,不破 C3 VoiceOver。

---

## 11. 排序

1. **Phase A**(vz 解禁,小赢独立):引擎 + enrich + golden。给池加料。
2. **Phase B**(头牌本地):`ConjugationReviewKit` + ConjugationSession onOutcome + AppModel 接线 + 到期变形复习 + 弱形加权。
3. **Phase D**(TTS,独立,可与 B 并行):SpeechKit + 朗读钮 + 设置。
4. **Phase C**(头牌云,设备门 E 前置):CloudKitSyncController 新 record type + SyncMerge + AppModel。**设备门 E 跑完才 flip on,否则 gated land**。
5. **Phase E**(句子模式,收缩子选项,首砍候选):makeExampleSentences + Practice 例句选项。
6. **发前**:对抗 re-review(变形 SRS 独立性/CKSyncEngine 重入/zuru 误升/SRS 碎片化)+ 设备门 E + Release 启动崩溃门 + bump 1.8(macOS≥11/iOS≥12)+ submit_1_8.py(find_build 按平台解析)。

---

## 12. 版本与提交

- bump `MARKETING_VERSION 1.8`;build **macOS 11 / iOS 12**(每平台递增)。
- 元数据/截图自动继承;What's New 双语写:动词变形间隔复习(+跨设备同步,若 Phase C ship)、更多可练动词(ずる)、假名朗读(TTS)、例句练习;无 ★ 字形。
- 全 API 提交(`scripts/submit_1_7.py` 为模板改 `submit_1_8.py`)。**v1.7 已上架**✓,一次一个版本在审已解锁。

---

## 13. 待 Jason 拍板(可先问)

- **范围确认**:v1.8 = A(vz)+ B(变形 SRS 本地)+ C(变形 SRS 云,设备门 E 前置)+ D(TTS)+ E(句子=Practice 子选项)。E 是首砍候选。是否同意此切法?
- **句子模式形态**:同意收缩为 Practice「例句」子选项(而非新顶级模式)?
- **变形 SRS 记录默认**:变形 drill 默认写变形 SRS(always-on,加 settings flag 备用)——同意?
- **设备门 E 时机**:Jason 会尽快做;若发前跑完→Phase C 云同步进 v1.8,否则 gated land 留后续。
- (Gemini 3.1 Pro review 已过,verdict REVISE-THEN-GO,4 条修订已全纳入 §3/§4/§5/§6 + §8/§10;无遗留待拍板项。)
