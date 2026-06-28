# Nihongo Ride — v1.7 开发计划(无障碍补完 + 打磨 + 小赢 + 解锁未来)

> 状态:v1.7 事实源。**已过 Gemini 3.1 Pro review(agy CLI,gemini-3.1-pro-preview;verdict REVISE-THEN-GO → 5 条已全修)**:①弱词训练改 cram-不写-SRS(提前复习未到期卡会腐蚀 SM-2 间隔/ease)②`try?` 硬化对后台写只 log、仅用户主动写弹 alert(防 alert 死循环)③选形 `compactMap(rawValue:)` 容错(未知形不 crash settings)④Dynamic Type 紧凑/游戏屏用 `@ScaledMetric` 保精确基线、语义 TextStyle 只给正文⑤Gate E 双设备验证精确定位为 v1.8 前置(非 v1.7 ship 闸,因 v1.7 零云状态)。
> v1.6(动词变形 MVP)已双端 **READY_FOR_SALE**(2026-06-28)。
> Jason 选了全部四个方向(无障碍+硬化 / 变形深化 / 新学习模式 / 同步欠账),嘱「诚实控范围、装不下推 1.8」。本计划据此**按依赖排序拆分**。

## 0. 一句话范围

**v1.7 = 质量与可达性的一刀**:把欠了三个版本的 **Dynamic Type(动态字号,无障碍头牌)** 补完,顺手落两个**纯本地、低风险的小赢**(弱词训练、变形选形),做两项**静默债硬化**(`try?` 写盘、AppModel 测试缝);并把拖到现在的 **双设备/跨版本 iCloud 验证**作为本期设备门跑完——它**不是 v1.7 的代码内容,而是 v1.8「变形 SRS」的前置闸**(新同步状态不能建在未验证的同步地基上)。

**明确推迟到 1.8+**:变形 SRS(独立 `ConjugationReviewStore` + 新 CKRecord Production schema,**依赖本期设备门 E 跑完**)、TTS 假名朗读、句子打字模式、vz「ずる」paradigm、widget、统计图、分享卡。

理由:Dynamic Type 是计划早已点名的 1.7 头牌(PLAN-V1.6 §8),是真·无障碍债且**不新增任何云同步状态**;弱词训练/变形选形是高性价比小赢;设备门 E 闭合后,v1.8 才能干净地上变形 SRS。四个方向各取其**能在不引入未验证云状态的前提下落地的部分**,其余诚实推后。

---

## 1. 现状(已 grounded 核实,2026-06-28)

- **Dynamic Type = 真债,规模已核**:全 app **129 处固定 `.font(.system(size:…))`,跨 11 屏**(Journal 21 / Game 19 / **ConjugationGame 16** / Lists 13 / About 13 / Practice 11 / Results 9 / Menu 8 / Settings 7 / **ConjugationResults 7** / Onboarding 5)。注意 v1.6 我新加的两屏(变形)也用固定字号,**把债从旧版的 ~106 抬到了 129**——本期一并补。`Font.system(size:relativeTo:)` 这个 initializer 不存在,但**不必抛弃精确字号**:`@ScaledMetric var s: CGFloat = 16` + `.font(.system(size: s, design:.rounded))` 既随系统字号缩放、又**保留 v1.6 精确基线**(避开语义 `TextStyle` 改变字号/字重/tracking 的回归风险);正文/标题等可重排处再用语义 `Font.TextStyle`。**ImageRenderer 忽略 `dynamicTypeSize`**(已在 Screenshot.swift 注释 + V1.5-VERIFICATION 记过)→ 大字号布局**只能设备/模拟器验证**,headless 渲染验不了。
- **`try?` 静默写盘 = 18 处**(AppModel 10 / CloudKitSyncController 1 / WordListMigration 5 / Screenshot 1):持久化失败被静默吞掉,用户无感知地丢进度。需「失败不静默」策略。
- **AppModel 零单测**:661 LOC 的中枢逻辑(startGame/finishGame/applyCloudChanges/★/list CRUD)无任何单元测试(executable target 难直接 import)。需抽测试缝。
- **弱词训练:`weakestCards` 不存在**——ReviewKit 现有 `dueCards`/`dueCount`/`dueForecast`,**没有** weakest API(自动记忆里「ReviewStore.weakestCards」是臆想)。但 `SRSCard` 有 `lapses`/`easeFactor`/`totalMistakes`/`totalReviews`/`isLeech`,**弱度可派生**。所以弱词训练 = 新增 `weakestCards(limit:)` 纯函数 + builder(复用 makeSaved 模式)+ 菜单入口。
- **变形选形:基础已就位**——`ConjugationSession.Config.forms: [ConjugationForm]`(默认 `allCases`)+ `make(chooseForm:)` 已存在;`AppSettings` **尚无**变形形集字段。所以选形 = 菜单 picker + AppSettings 持久化 + 传入 Config。**纯本地、零云状态**。
- **同步验证欠账**:`docs/V1.5-VERIFICATION.md` 是现成清单(Release 启动自测[已随 v1.6 跑过]、双设备 iCloud 读验证、1.4.1↔新版跨版本收敛、VoiceOver/Dynamic Type 走查、触屏键盘 2.1a)。双设备物理验证**从 v1.4 欠到现在**,写路径已设备验、合并已单测,但**双设备读/合并 + 跨版本收敛未在真机走过**。
- 红线全保(v1.6 review 复核过):CKSyncEngine delegate 不驱动引擎;文件写同步/主 actor/.atomic;Practice/变形 不写 SRS;kana 全局唯一。

---

## 2. Phase A —— Dynamic Type(头牌,L)

把 129 处固定字号迁到**语义字体 + 缩放**,让系统「更大字体」设置生效,不破坏现有视觉基线。

- **策略(Gemini #4:`@ScaledMetric`-first,保基线)**:① **紧凑/HUD/游戏屏(Game/Conjugation 卡 + pill)用 `@ScaledMetric` 包住现有精确字号** → 默认字号下 100% 与 v1.6 一致,只是能随系统放大(限幅防撑爆);② 正文/标题/菜单/按钮等**可重排**处迁语义 `Font.TextStyle`,保留 `design:.rounded`/`weight`;③ 大字号下易溢出处加 `minimumScaleFactor`/`lineLimit`(已有则补齐)。**慎用 `ScrollView` 回包紧 `VStack`**——会破坏 `Spacer()`/`GeometryReader` 行为(Gemini #3 风险),优先 `minimumScaleFactor`。
- **分屏推进**(每屏独立小 commit,降爆炸半径):Menu→Settings→Results/ConjugationResults→Game/ConjugationGame HUD+卡→Practice→Journal→Lists/ListDetail→About→Onboarding。
- **游戏屏特例**:WordCard/ConjugationCard 的大假名是核心可读性元素——用 `@ScaledMetric` 让它**随系统字号放大但有上限**(避免撑爆游戏屏布局),`keyboardUp` compact 态同步缩放。
- **不变量**:① 默认字号下视觉与 v1.6 一致(headless 渲染 menu/game/results/conjugation 对比,布局不回归);② VoiceOver label/value(C3 已 ship)不受影响。
- **闸**:默认字号 headless 渲染无回归 + **设备门 E 的大字号走查通过**(`accessibilityXXL` 下 9+ 屏不截断/不重叠)。

---

## 3. Phase B —— 弱词训练(小赢,S–M,纯本地;**cram 模式,不写 SRS**)

针对用户**真正薄弱**的词反复练,复用现有游戏屏。

- **关键(Gemini #1,CRITICAL):弱词训练是 cram,绝不写 SRS scheduling**。提前复习「尚未到期」的卡会腐蚀 SM-2——成功的早练会错误抬高 interval,失败会错误罚 ease/lapse。所以弱词屏走 **Practice 同款「不写 SRS」路径**(`finishGame` 对弱词跳过 `review.record`/`save`,同 practice 判定),只做即时反馈。它不"推进"复习计划,纯粹是"哪些词我老错就多打几遍"。
- **ReviewKit**:新增 `ReviewStore.weakestCards(limit:)` 纯函数——按弱度**只读**排序(`isLeech` 优先,再 `easeFactor` 升序 / `lapses` 降序 / 错误率 `totalMistakes/max(1,totalReviews)`),只取**复习过**的卡(`totalReviews>0`)。**纯 readonly,不改任何卡**。加单测(排序 + 空集 + 阈值 + 不变性:调用后 store 不变)。
- **GameCore**:`GameSession.makeWeak(ids:…)` = 复用 makeSaved 的取词 + **practice-mode 标记(不写 SRS)**;或给 GameSession 加一个 `recordsSRS:Bool` 开关(默认 true,弱词/practice 传 false),把"是否写 SRS"显式化(顺带让 practice 的不写 SRS 从 mode 判定升级为显式标记,更稳)。
- **UI**:菜单一个入口(像「词单」chip),**仅当弱词池 ≥ 阈值时显示**(`weakestCards` 非空);resolve-then-guard 复用。
- **闸**:weakestCards 单测绿(含「调用后 ReviewStore 零写入」)+ **跑完一局弱词对 ReviewStore 零写入**测试 + 入口 gating + 不空屏。

---

## 4. Phase C —— 变形选形(变形深化的非云部分,S)

让用户挑练哪些变形,而非每次全 7 形随机。

- **AppSettings**:加 `conjugationForms: [String]`(ConjugationForm.rawValue);随 settings 持久化。**(Gemini #3)解码必须容错**:`[String]→[ConjugationForm]` 用 `compactMap { ConjugationForm(rawValue: $0) }`(未来删/改形时,未知 rawValue 被静默跳过,**绝不让整个 AppSettings 解码失败而清空用户设置**);沿用 SettingsKit 既有的「枚举 raw 值在 AppModel 边界校验、容错 decode」模式。空数组 = 全选。
- **AppModel.startConjugation**:把选中形传入 `ConjugationSession.Config.forms`(空→`allCases`)。
- **MenuView**:`selectedMode == .conjugation` 时显示一个**多选形 picker**(て/た/ない/可能/意志/ます/なかった;原生控件绕键盘抑制冲突,仿练习内容 picker)。
- **闸**:选形持久化往返正确 + 空选优雅降级全选 + 变形屏只出选中形(扩 ConjugationSessionTests)。
- **注意**:这是**纯本地配置**,不碰 SRS、不加云状态——真正的「变形 SRS」(间隔复习、跨设备同步错题)= **v1.8**(见 §8),依赖 §6 设备门。

---

## 5. Phase D —— 硬化 + 测试缝(债,S–M)

- **`try?` 写盘硬化(18 处)——(Gemini #2)按"谁触发"分流,防 alert 死循环**:
  - **后台/自动写**(odometer、journal、sync 合并后落盘、settings didSet)失败 → **只 `do/catch` + log/`assertionFailure`**,绝不弹 alert(否则一次后台自动保存失败会把用户卡在无限 alert)。
  - **用户主动写**(手动建/改词单、★、明确的数据操作)失败 → 设 `lastPersistError` + RootView 一次性 alert(仿 v1.5 `lastListError`)。
  - 非数据(screenshot 渲染等)保持 `try?`。**绝不改写盘的同步/主 actor/.atomic 红线**——只改"失败是否上报",不改"怎么写"。
- **AppModel 测试缝**:把可纯测的逻辑(模式派发、resolve-then-guard、summary 派生、★/list 边界)抽成可注入依赖的小函数/类型,加单测。**只抽缝、不改行为**(回归面要小)。
- **闸**:`swift test` 基线(v1.6=170/31)只增不减;硬化不破坏现有写盘红线(发前对抗 review 复核)。

---

## 6. 设备门 E —— 同步欠账清理(Jason 设备;**解锁 v1.8 变形 SRS**)

**不是 v1.7 的代码,是发前/周期内的设备验证**,按 `docs/V1.5-VERIFICATION.md`。**(Gemini #5)区分两类闸**:
- **v1.7 发版闸(必过才提交)= 仅第 1 项 Release 启动自测**(CKSyncEngine 崩溃门)+ 第 4–5 项(大字号/触屏,因 v1.7 改了 UI)。
- **v1.8 前置闸(非 v1.7 ship 闸)= 第 2–3 项双设备/跨版本 iCloud 验证**。理由:**v1.7 零云状态新增**(Dynamic Type/弱词-cram/选形全本地),同步合并即便有 bug 也不影响 v1.7 正确性,故不阻塞 v1.7 提交。但它是 v1.8 变形 SRS 的硬前置——Gemini 提醒:**最好在 v1.7 审核窗口内(越早越好)就做完**,这样若暴露 LWW/union-merge bug 能尽早修,不致 v1.8 开工才发现地基裂(那会回头返工 v1.8 baseline)。结论:**不阻塞 v1.7,但强烈建议 v1.7 周期内完成,作为 v1.8 的开工前提**。

1. **签名 Release 启动自测**(CKSyncEngine 崩溃门)——v1.6 已就地跑过,v1.7 改了 UI 字体不碰同步,低风险,仍复跑。
2. **双设备 iCloud 读/合并验证**(欠到现在):两台登同一 iCloud,A 改 SRS/词单/收藏 → B 拉取合并正确(union add-wins、odometer G-Counter 求和、命名单字段级 LWW)。
3. **跨版本收敛**:1.4.1/1.5↔1.7 共存一账号,验证旧版 ★ 加词经 deck 镜像并入新版默认单不丢(review 抓过的「收敛后老设备再加词」case)。
4. **Dynamic Type 设备走查**(Phase A 的验证闸):`accessibilityXXL` / 最大字号下逐屏看截断/重叠;Accessibility Inspector + VoiceOver rotor。
5. **触屏键盘 2.1a**:iPad/iPhone 触屏走变形屏 + 弱词屏,确认软键盘自动召唤(变形屏复用 GameView 同款 KeyCaptureView,低风险)。

**E 的产出 = 一份「双设备 + 跨版本 iCloud 已验证」的事实**,这是 v1.8 上「变形 SRS(新同步 CKRecord 类型)」的前置闸——没它不上新同步状态。

---

## 7. 风险与闸

| 风险 | 说明 | 闸 / 缓解 |
|---|---|---|
| **R1 Dynamic Type 视觉回归** | 129 处迁移易在默认字号改变现有布局/字重 | 每屏独立 commit + 默认字号 headless 渲染逐屏对比;游戏屏大假名用 `@ScaledMetric` 限幅 |
| **R2 大字号布局只能设备验** | ImageRenderer 忽略 dynamicTypeSize | 明确归入设备门 E;headless 只保默认字号不回归 |
| **R3 弱词/选形空池卡死** | 新池为空时进游戏空屏(v1.4 教训) | 复用 resolve-then-guard + 入口按池 gating |
| **R4 硬化误伤写盘红线** | 改 try?→do/catch 时碰同步/主 actor/.atomic | 只改「是否吞错」不改「怎么写」;发前对抗 review 复核同步路径 |
| **R5 变形 SRS 误进本期** | 想一步到位上间隔复习 | 计划明确切到 v1.8 + 设 §6 前置闸;v1.7 选形纯本地无云状态 |

---

## 8. 明确推迟到 1.8+(不进 1.7)

- **变形 SRS / ConjugationReviewStore**(M–L + 新 CKRecord Production schema 部署 + 跨设备错题同步):**v1.8 头牌**,依赖 §6 设备门 E 闭合(双设备/跨版本 iCloud 已验证)。独立 store/文件/键,**绝不复用扁平 ReviewStore**(否则变形错题以 vocab id 回流普通 journey)。
- **TTS 假名朗读**(AVSpeechSynthesizer;离线日语语音):新学习面,自成一期。
- **句子打字模式**(已有 ~233 passages 基建,但模式/计分/UI 是新面):自成一期。
- **vz「ずる」paradigm**(现 withheld):引擎加 zuru 类后可解禁 13 个 N1/N2 动词。
- widget、统计图、分享卡、Game Center 扩充、per-word un-save tombstone、SavedWordsKit 退役准则、tombstone TTL 安全网 —— 均 park。

---

## 9. 红线(从 v1.6 承袭,务必保留)

1. 绝不在 CKSyncEngine delegate 回调驱动引擎;enqueue 走 `recordLocalChanges→scheduleSync`(Task hop);`nextRecordZoneChangeBatch` 按值快照 + CKRecord 深拷贝(`as?` 降级)。
2. 所有文件写**同步、主 actor、.atomic**(不可 Task.detached);**硬化只改「失败是否上报」,不改写盘机制**。
3. **Practice / 变形 / 弱词训练 永不写 SRS**(Gemini #1:弱词是 cram,提前复习未到期卡会腐蚀 SM-2——故弱词走不写 SRS 路径);变形 SRS(v1.8)必用独立 `ConjugationReviewStore`,绝不复用扁平 ReviewStore。
4. 非游戏屏抑制软键盘;**游戏屏(含变形、弱词)自动召唤键盘 + isTouchDevice HUD**(2.1a)。
5. kana 全局唯一;变形输出临时、绝不持久化为 VocabEntry。
6. xcodegen 版本字面量 `CFBundleShortVersionString:$(MARKETING_VERSION)` / `CFBundleVersion:$(CURRENT_PROJECT_VERSION)` 显式引用。
7. **构建号每平台严格递增**:当前 **macOS=9 / iOS=10**(v1.6)。1.7 用 **macOS≥10 / iOS≥11**。
8. 构建从干净源跑:`build-appstore*.sh` 检测 provenance 自动 rsync 临时副本(无 -X 丢 xattr),就地跑即可;Release 本地启动自测须显式传 `DEVELOPMENT_TEAM=KHMK6Q3L3K`。
9. **Dynamic Type 不破坏 VoiceOver**:C3 的 `.accessibility*` label/value 在字体迁移后仍正确。

---

## 10. 排序

1. **Phase B + C**(小赢先行,快速可见价值):弱词训练 + 变形选形 —— 纯本地、低风险、各自小 commit。
2. **Phase A**(头牌,逐屏推进):Dynamic Type,11 屏每屏独立 commit + 默认字号 headless 不回归。
3. **Phase D**(硬化):`try?` 上报 + AppModel 测试缝。
4. **发前**:bump 1.7(macOS≥10 / iOS≥11)+ 对抗 re-review(同步/无障碍/回归)+ **设备门 E**(Jason:双设备/跨版本/大字号/触屏)+ Release 启动自测 + ASC 提交(submit_1_7.py,find_build 按平台解析)。

---

## 11. 版本与提交

- bump `MARKETING_VERSION 1.7`;build **macOS 10 / iOS 11**(每平台递增,注意 build 号跨平台撞号 → submit 脚本 find_build 按 preReleaseVersion.platform 消歧)。
- 元数据/截图自动继承;What's New 双语写:更大字体支持(无障碍)、弱词训练、动词变形可选形;无 ★ 字形。
- 全 API 提交(`scripts/submit_1_6.py` 为模板改 `submit_1_7.py`)。**v1.6 须先上架**(已 READY_FOR_SALE ✓,一次一个版本在审已解锁)。

---

## 12. 待 Jason 拍板

- **范围确认**:v1.7 = A(Dynamic Type)+ B(弱词 cram)+ C(变形选形)+ D(硬化),变形 SRS 推 v1.8(依赖设备门 E 的双设备验证)。是否同意此切法?
- **设备门 E 双设备验证时机**(Gemini #5 已厘清):非 v1.7 ship 闸,但建议 v1.7 周期内尽早做(v1.8 前提)。你倾向发前做、还是审核窗口内做?
- (Gemini review 已解决的两点,无需再拍:弱词 = 不写 SRS 的 cram;`try?` 硬化 = 后台只 log / 用户主动才 alert。)
