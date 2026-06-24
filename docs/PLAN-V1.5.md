# PLAN-V1.5 — 自定义词单 + 动词变形 + 打磨/验证

> 作者:opus-4-8(2026-06-23,2026-06-24 按多智能体对抗 review 修订 → 本版已纳入全部确认问题)。
> Jason 选定 v1.5 = 方向 **1 + 3 + 4**(自定义词单 / 动词变形 / 打磨+验证)。开发在 fresh session 进行(末尾 handoff prompt)。
> **基线数字已对真实 JSON 逐条核计**(见 §1);所有 file:line 锚点可点。

---

## 0. 范围与目标(**已按 review 调整为「诚实范围」**)

| | 工作流 | 一句话 | 风险 | **v1.5 去留** |
|---|---|---|---|---|
| **A** | 自定义词单 Custom Word Lists | 单一「收藏」→ **多个命名词单**:建/改/删、分组、按单练习、iCloud 同步 | 中 | **✅ 进 1.5** |
| **C** | 打磨 & 验证 | 双设备 iCloud 读验证 + 删除同步 + 无障碍(近乎从零)+ 新手引导 | 低 | **✅ 进 1.5** |
| **B** | 动词变形 Verb Conjugation | 动词活用练习,新打字模式 | **高**(数据 = 几乎从零分类;JMdict 是承重项) | **默认 1.6;过 B0 闸 + golden 全绿才提进 1.5** |

**范围诚实化(review 的核心建议):** v1.5 **确定**发 A + C。B 三件套(数据/引擎/模式)在 1.5 周期内**照做**,但 **B0 数据 spike + ConjugationKit golden 测试**是硬闸:**先量化 JMdict 覆盖与逐 lemma 正确性,达标且在冻结前完成才把 B 提进 1.5,否则 B 作为 1.6 发**(引擎/数据可 gated 不出 UI 先 land)。这样既「三个都做」,又不让动词数据拖垮 A/C。⚠️ 这是需 Jason 知会的范围判断。

非目标:Widgets(方向 2 未选);内容 gen 流水线修复(`gen_examples/gen_passages` 仍调死的 `gemini`,不在本版);B 之外语法点。

---

## 1. 现状基线(**逐条核计,修正旧版高估**)

- **VocabEntry**(`Sources/VocabKit/VocabEntry.swift:23-71`):`id, surface(汉字), kana(平假名=打字目标), partsOfSpeech([String],JSON键"pos"), jlpt, meanings, exJP/EN/ZH?`。数据 `Sources/VocabKit/Resources/{n5..n1}.json` 共 **7074** 条;`VocabStore.loadBundled()`(`VocabStore.swift:35-51`)。**kana 全局唯一**(测试 `VocabKitTests.swift:83-87`)。
- **POS 实况(已核计 —— 旧版数字错,这是 B 的真相):**
  - 动词精确类标签**总计仅 ~107**:`v1`×16(一段)、`vs`×69(サ变)、**`v5*` 带行仅 ×22**(v5r9/v5s7/v5m3/v5g1/v5u1/v5t1)。**旧版写的「v5*×~85」高估约 4 倍。**
  - 泛 `v`×2126(**无类**)、`verb/Verb`×125、`vi/vt`×40 —— **全无行/类**。
  - **结论:动词类基本是「从零分类」**:>95% 动词靠 kana 结尾启发式 + JMdict;**る 歧义(一段 vs 五段 v5r)是主流而非边角**,精确 v5r 锚点只有 9 个。
  - **`['n','v']` 在本语料 = 「サ变名词(取する)」而非「该词自身活用」**:902 个「泛 v 且 kana 结尾合法五段音」里 **479(53%)同时带 noun 标签**、483 个 surface 是纯汉字无送り仮名 → 这些是 **suru-noun,绝不能按 kana 结尾当五段变形**(暗殺/あんさつ 若误判 v5t → あんさって 是错的)。
- **SavedWordsKit**(`SavedWordsStore.swift:10-58`):`ids:[String]`(存序去重)+ add/remove/toggle/contains + Codable;落 `~/Library/Application Support/NihongoRide/saved-words.json`。**`load` 解码失败静默返回空 store(`:51-57`)—— 迁移要规避这点(见 A2)。**
- **GameCore**:`GameMode{journey,timeAttack,practice}`;`makeSaved(ids:)`(`GameSession.swift:157-169`)compactMap 解析 + shuffle + journey。
- **ReviewKit**:`ReviewStore` = **单一扁平 `[String:SRSCard]` 按 vocab id 键**(`ReviewStore.swift:5-43`);`GameSession.make` 从 `review.dueCards` 抽词(`:137-152`)。→ **conjugation 错题若复用它会污染普通跑的到期队列**(见 B3)。
- **CloudKitSyncController**:`RT{srs,ride,odo,saved}`(`:40-42`);收藏 = 单条 `SavedWords:deck` 字段 `ids`(`:430-436`)。**`applyFetched` 显式忽略所有 deletion(`:217-239`,「this app never deletes synced records」)** —— A 的 tombstone 设计必须改这条路径(见 A4)。`nextRecordZoneChangeBatch` 先把 cards/rides/slots/savedIDs **按值快照到主 actor 外**(`:179-183`)+ recordCache 深拷贝 —— 新 RT.list 必须同样接进快照(见 A4)。
- **SyncMerge**(`SyncKit/SyncMerge.swift`):reviewStores 按 card `lastReviewed` 取较新;odometers G-Counter 求和;rideRecords union 后 trim;savedWords **union/add-wins**(`:73-78`)。**全部刻意 skew-free(不依赖跨设备时钟)** —— A 的合并必须沿用这个原则(见 A4)。
- **无障碍现状**:全 app **只有 `GameView` 有 1 处 `accessibilityLabel`**(`:200 "Pause"`);其余 17 处 `accessibilityIdentifier` 全是 UI 测试 hook,不是 VoiceOver 标签。→ **C3 是从零建,不是补几个**(见 C3)。
- **新手引导/首启标志**:**当前不存在**任何 first-launch flag;通知权限是用户在设置里 opt-in 时才请求。→ C4 要新建标志 + 与通知请求不打架。

---

## 2. Workstream A — 自定义词单(进 1.5)

单一「收藏」→「N 个命名词单」;**收藏 = 一个 `isDefault` 词单**,保留 v1.4 ★ 体验与 **add-wins 保证**。

### A1. 数据模型(新模块 `WordListsKit`,纯逻辑 + 测试)
```swift
public struct WordList: Identifiable, Codable, Sendable, Equatable {
    public let id: String          // 稳定 id;默认单用「常量 id "default"」,非随机 UUID(见 A2 收敛)
    public var name: String
    public var ids: [String]       // 存序、去重(沿用 SavedWordsStore 语义)
    public var nameUpdatedAt: Date // 仅供 name 标量 LWW(不决定 ids)
    public var deleted: Bool       // 软删 tombstone
    public var deletedAt: Date?    // tombstone 压缩用
    public let isDefault: Bool      // 默认「★ 收藏」单:禁删、可清空
}
public struct WordListStore: Codable, Sendable, Equatable {
    public private(set) var lists: [WordList]
    // CRUD(均 bump 对应字段时间;注入 now 闭包保持可测):
    //   createList(name)->Result(含 cap 检查) / rename(id,name) / softDelete(id) /
    //   addWord(listID,vocabID) / removeWord(listID,vocabID) / toggle(listID,vocabID)
    //   defaultList(常量 id) / list(id) / containsAnywhere(vocabID)  // ★ 高亮
    // 软上限(A1 不变量,见 §9 已落实):≤50 单 × ≤500 词/单;越界 add 返回可被 UI 提示的失败,不静默丢
}
```
- **删除 = 软删**(`deleted=true`+`deletedAt`),不发 CKRecord 删除。本地展示过滤 tombstone。
- **tombstone 压缩**:本地丢弃 `deletedAt` 早于 ~30 天的软删单;合并时不复活已知更晚 `deletedAt` 的删除。防无界累积。

### A2. 迁移(一次性、幂等、抗损坏)
- **默认单 id = 常量 `"default"`(非随机 UUID)** —— 否则两设备各自生成不同 UUID 的默认单 → 永远收敛成两个默认单。常量 id 保证跨设备同一条。
- 启动迁移:若无可解码的 `word-lists.json`:把旧 `saved-words.json` 的 `ids` 包成 `id="default", isDefault=true, name=本地化「★ 收藏」` 的单,**原子写 + 读回校验**,**保留** `saved-words.json`(回滚)。
- **抗损坏(review 的数据丢失洞)**:`WordListStore.load` 必须**区分「文件不存在」与「存在但解码失败」**。解码失败时**不可**像 SavedWordsStore 那样静默返回空 —— 而是:把坏文件备份成 `.corrupt`,**回退到从 `saved-words.json` 重跑迁移**(至少不丢默认单),并上报。
- 迁移**幂等**:以「`word-lists.json` 可解码且含 default 单」为已迁移判据,而非仅「文件存在」。
- **迁移 vs 首次云拉取竞态**:迁移在 sync `start()` 之前完成(本地先成型),再让首次 fetch 把远端 default 单按 A4 规则并入(union ids + name LWW),避免本地空默认单覆盖云端。

### A3. 持久化
- `word-lists.json`(Application Support/NihongoRide)。**所有写同步、主 actor、`options:.atomic`**,与 SavedWordsStore 完全一致(红线 §8.3);UI 变更路径与 `applyCloudChanges` 合并路径都走同一同步 save。

### A4. iCloud 同步 —— **per-list record + 字段级合并(ids union / 标量 LWW)**【已按 review 改正】
- 新 record type `RT.list="WordList"`,recordName `WordList:<listID>`,字段 `name:String, ids:[String], nameUpdatedAt:Date, deleted:Int, deletedAt:Date?`。
- **合并 = 字段级,保持 skew-free 的 add-wins:**
  - `ids` = **per-id union**(union(local,remote),保序)—— **保留 v1.4 ★ 的 add-wins 保证**,并发加词永不丢。**(不再整单 LWW —— 那依赖跨设备时钟、会回归 ★ 并丢词。)**
  - `name` = 按 `nameUpdatedAt` LWW(改名是唯一真冲突的标量)。
  - `deleted` = **once-true-wins**(任一端删了就删;`deletedAt` 取较早或较晚一致即可)—— 这把「删整单」做成可传播。
  - **「移除单内某词」要跨设备生效**:union 不会传播单条移除。MVP 取舍:**单内 per-word 不做 tombstone**;移除词在本地与同一端生效,跨设备靠「整单删/清空」或后续 per-word tombstone(列为 §9 待定,**不进 1.5**)。★ 收藏的「取消收藏」跨设备传播亦同此约束 —— **明确写进 What's New/已知行为,别声称 un-save 全局同步。**
- `SyncMerge.wordLists(local, remote) -> WordListStore` 纯函数 + 单测(见 A6)。
- **下行接线(review 抓的硬缺口,必须显式做):**
  - `applyFetched`(`CloudKitSyncController.swift:217-239`)的 modifications 分支加 `RT.list`:解析 `WordList`(含 `deleted`),收集 `[WordList]` 注入 `applyCloudChanges(wordLists:)`;**「无变化就 return」的 guard 要加 wordLists 项**,否则只含 list 的批次被静默丢。
  - `mergeServerRecord`/`serverRecordChanged` 冲突路径加 `RT.list`(用上面的字段级合并,不是整单覆盖)。
  - `nextRecordZoneChangeBatch`:把 `model.wordLists.lists` **按值快照成 `[String:WordListSnapshot]`(Sendable)** 放到闭包外(仿 `:179-183` 的 savedIDs),RT.list 分支按 listID 查快照填 name/ids/deleted;recordCache 深拷贝(红线 §8.4)。
- **上行**:`recordLocalChanges` 增 `listIDs:[String]`(变更哪些单 → enqueue 对应 record;软删也是 saveRecord(deleted=1));**只做 `engine.state.add` + `scheduleSync()`(Task hop),与 saved 路径完全一致 —— 绝不在此驱动引擎(红线 §8.4,刚被拒过)。** `enqueueAllLocal` 每个 list 各 enqueue 一条。
- **遗留 `SavedWords:deck` 共存(防复活/回声,review 抓的洞):**
  - **单向、一次性,不做稳态双读**:首次 v1.5 启动把 `SavedWords:deck` 折进 default 单(union),**之后 v1.5 把 deck record 再写一次 = default 单当前 ids**(让仍在 v1.4 的老设备收敛),并标记本地已迁移;此后只写 `WordList:default`,不再把 deck 折回(避免老设备 add-wins 的 deck 把本地已移除的词永久复活、与 default 单来回 ping-pong)。
  - C1 必须实测「一台 1.4.1 + 一台 1.5 同账号」的双向收敛(见 C1)。

### A5. UI(遵守非游戏屏契约:抑制键盘、Esc/Back、navCount/zIndex —— 红线 §8.2)
- **Lists 屏**(菜单入口,替换原「Saved N」chip —— **net chip 数不增,MenuFlow 本就换行,排版无忧**):列出所有单(名 + 词数 + 「练」)、新建(+,名输入,**越上限给空态提示**)、改名/删除(默认单禁删可清空)。
- **List 详情**:词列表 + 「开始练习」+ 移除词。**「开始练习」必须复用 `startSavedGame` 的 resolve-then-guard**:`let resolvable = list.ids.filter{ VocabStore.shared.entry(id:$0) != nil }; guard !resolvable.isEmpty else { 提示空/不可练; return }` —— **否则重蹈 v1.4「全不可解析 id 卡死在已结束空屏」的坑(每个 list 都要防)。**
- **加入词单**:WordCard 的 ★ → default 单 toggle(不变);**长按 ★ / 旁 ⋯** → 「选择词单」多选(可入多单 + 新建)。Results chips 同理。
- `makeSaved(ids:)` 建议改名 `makeDeck(ids:)`(语义泛化,复用现有测试)。

### A6. 测试矩阵(扩充 —— review 指原 6 类不够)
WordListsKit 纯测:CRUD、去重存序、cap 边界(加到上限返回失败)、迁移(正常/无旧文件/**坏 word-lists.json→回退重迁**/幂等二次运行 no-op)、tombstone 过滤 + 压缩。
SyncMerge.wordLists 纯测:新单、改名(nameUpdatedAt LWW)、**并发加词→union 不丢(★ 回归守卫)**、移除词(本地生效、跨端按约束)、软删传播、**default 单常量 id 跨端收敛(不分裂)**、**新设备移除 vs 老设备 deck 重加→不复活**、**default 单一轮 fetch/send 不来回震荡**。

---

## 3. Workstream B — 动词变形(默认 1.6;B0+golden 达标才提 1.5)【高风险】

### B0. 数据 spike(**先做、只测量;JMdict 是承重输入而非可选**)
目标:给「确为活用动词」的条目定类 `verbClass ∈ {ichidan, godan_{k,g,s,t,n,b,m,r,u}, suru, kuru, special}`。
- **来源(注意:精确标签只盖 ~107,几乎全靠后两条):**
  1. 精确标签:`v1`→ichidan;`v5{...}`→对应行;`vs`→suru(且走 noun+する 组合,见 B2)。仅 ~107 条。
  2. **kana 结尾启发式,但加双重排除门**:仅当 **surface 以与 kana 结尾匹配的送り仮名结尾** 且 **不带 noun 标签** 才按非-る 五段定类;**任何带 `n/noun` 或纯汉字无送り仮名的「泛 v」一律排除(那是 ~480 个 suru-noun)**。结尾 する→suru;くる/来る→kuru;**结尾 る → 歧义,交来源 3**。
  3. **JMdict(EDRDG,CC-BY-SA,离线)按 (surface,kana) 匹配**取精确 v1/v5*:**解 る 歧义 + 兜底核心动词**(食べる/見る/ある/する/くる/行く/くださる/いらっしゃる 全是裸 `v`,落在 る/启发式失败桶 → **没有 JMdict,N5–N3 纯启发式覆盖仅 ~23%**)。
  4. 仍未定 → **排除出变形练习**(不猜)。
- **B0 产出(决策闸,按来源拆开报告):**脚本 `scripts/enrich_verb_classes.py`(走 JMdict+启发式,**不依赖 gemini/agy**)跑一遍,**按 JLPT 报告**:①精确标签解出% ②启发式无歧义解出% ③**JMdict 解出%(承重项,必须单列)** ④未解出%。
- **决策闸(改为「验证正确」而非「覆盖率」):** 维护一个**人工策展的 N5–N3 核心动词集 + 期望活用形 golden**;**只有该集经引擎 + 数据跑出 100% 正确**(不是「90% 被分了类」)才算过闸 → B 提 1.5;否则 B 留 1.6。原因:即便 90% 被分类,JMdict 误配 surface/读音、以及 lemma 级特例(下条)仍会**自信地输出错变形**。

### B1. 数据补全(过 B0 后)
- 脚本写 **新字段 `vc`**(不动 `pos`,降回归面)。VocabEntry 加 `public let verbClass: VerbClass?`(CodingKey `vc`,可选默认 nil,不影响现有解码/测试)。
- 守恒测试:kana 仍全局唯一;有 `vc` 的条目其 kana 结尾 ↔ 类自洽;**带 noun 标签或无送り仮名者不得有 godan `vc`**(挡 suru-noun)。
- 许可:JMdict/EDICT(EDRDG,CC-BY-SA 4.0)。**仅 build 时取「动词类」这种事实、只 ship 派生的类整数(不搬 JMdict 文本)**;**About/致谢加 EDRDG 归属(与 B1 同一 commit 落地)**;派生脚本注明来源。

### B2. `ConjugationKit` 引擎(纯、重测试 —— B 的确定硬核)
- 输入 `(dictKana, verbClass, lemmaSurface)` → 各活用形 kana。**第一批**:ます/て/た/ない/なかった/可能/意志。
- **lemma 例外表(在 class 规则之前查 —— review 的关键修正):** `行く→行って/行った`(非 行いて)、`ある→ない`(非 あらない)、`する/くる` 全套补充式(可能 = できる/こられる、意志 = しよう/こよう)、**v5aru 敬语 くださる/いらっしゃる/なさる/おっしゃる→…って/…います**(裸 `v`、结尾 る,JMdict 可能标 v5r → 会错出 くださります,必须例外)。
- **suru-noun 路径**:`勉強する→勉強して/勉強した` 从 **noun+する 组合**生成,不是从 noun 的 kana 变形。
- 五段音便:う/つ/る→って;ぶ/む/ぬ→んで;く→いて;ぐ→いで;す→して。
- **golden 单测(补齐 review 点名缺的特例):**每类×每形 + `くださる/いらっしゃる/なさる/おっしゃる`(te+masu,期望 v5aru 不规则 masu 干)+ suru-noun(勉強)+ `する可能=できる`/`くる可能=こられる`/`する意志=しよう`/`くる意志=こよう` + **帰る(v5r,帰って) vs 食べる(ichidan,食べて) る-消歧对** + **负向控制:suru-noun / i-形容词 永不被作为可变形项**。
- 纯函数、无 IO、Sendable;**输出是临时形,绝不持久化为 VocabEntry / 绝不入 VocabStore**(kana 唯一性测试只管 bundled entries,红线 §8.5 不受影响)。

### B3. 变形练习模式(过闸后)
- 新 `GameMode.conjugation`。出题:辞书形 + 目标形标签(双语),打变形读音,复用 RomajiKana 逐键匹配。题源 = 有 `vc` 的动词(可按 JLPT/词单)。
- **必须复用 `.playing` 游戏屏路径**(`GameView`/`KeyCaptureView`,`suppressSoftwareKeyboard:false` + `isTouchDevice` HUD)—— **不可新建抑制键盘的屏**(否则键盘不出 = 2.1a 重蹈)。
- **SRS 隔离(review 的硬约束):** 若 conjugation 写 SRS,**必须独立 `ConjugationReviewStore`**(独立文件 + 独立 CKRecord 类型,键 = `(vocabID,targetForm)` 命名空间),**绝不复用 `ReviewStore`**(否则错题以 vocab id 回流普通 journey 跑,污染识词队列)。**1.6 MVP 最简:conjugation 先不写 SRS**(只即时反馈),SRS 留增强。
- 菜单入口仅当有可用动词数据时显示。

---

## 4. Workstream C — 打磨 & 验证(进 1.5)

### C1. 双设备 iCloud 读验证(欠账)
- 同账号两台(js + Mac)。验证 merge:SRS 取新、ride union、odometer 求和、**词单 ids union / name LWW / 软删传播 / default 单不分裂**。
- **新增跨版本场景(review 点的盲区):一台 1.4.1 + 一台 1.5 同账号** —— 验证收藏编辑双向收敛、**无僵尸复活/丢失**(A4 遗留 deck 共存的实测)。记录步骤到 `docs/`。可能暴露真 bug → 留缓冲。

### C2. 删除同步
- **已并入 A4**:整单删/清空经软删 tombstone 传播;default 单(原收藏)的清空可跨端。**per-word un-save 全局传播不进 1.5**(MVP 取舍,列 §9)。本节收尾 = 给 `SyncMerge.savedWords` 旧 add-wins 路径写「已被 wordLists 取代」的说明,不新做 per-id tombstone。

### C3. 无障碍(**从零建 + 带验证 —— review 改正**)
- 现状近零(只有 GameView 1 个 label)。**逐屏列控件**加 `accessibilityLabel`:★ 切换、list 行、练/改名/删、conjugation 目标形标签、HUD、词卡读音/义、模式按钮。
- Dynamic Type:菜单/结算/词单/设置文本随系统字号(游戏词卡可固定护排版,说明文字跟随)。
- **验证步骤(进 §7):** macOS Accessibility Inspector 审 + iOS 真机 VoiceOver rotor 走查 + 新屏(Lists/conjugation/onboarding)最大无障碍字号 Dynamic Type 冒烟。

### C4. 新手引导
- **新建 first-launch flag(当前无)**,走 SettingsKit。首启一次性 ≤3 屏:罗马音多拼(shi/si)、模式简介、★ 收藏。可跳过、只显示一次。
- **与通知权限不打架**:引导**不**触发通知请求(通知仍只在设置里 opt-in 时请求);引导结束落到菜单,不抢首启的任何系统弹窗。非游戏屏契约。

---

## 5. 阶段与排序

1. **Phase 0 — 立项 & spike**:跑 **B0 覆盖+正确性 spike**(JMdict 匹配率 + 核心动词集 golden);据结果定 B 进 1.5 还是 1.6。**并行**起 A 纯模块(WordListsKit + SyncMerge.wordLists + 测试,无 UI)与 **ConjugationKit 引擎**(零依赖,可最早写、独立测)。
2. **Phase A**(进 1.5):Custom Word Lists 全链路(模型→迁移→**下行接线 applyFetched/mergeServerRecord/snapshot**→上行→UI→测试矩阵)。
3. **Phase C**(穿插):tombstone/遗留 deck 收敛随 A4 落;无障碍从零建 + 验证;新手引导 + first-launch flag;C1 双设备(含跨版本)放 A 同步落地后。
4. **Phase B**(过闸才进 1.5):B1 数据写回 → B2 引擎 golden 全绿 → B3 模式/UI(复用 .playing + SRS 隔离)。
5. **收尾**:全量 `swift test`(不回归现 113);**Release 本地启动自测(防 CKSyncEngine 启动崩,刚踩过)**;多智能体对抗 review;bump 版本 + ASC 提交。

---

## 6. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| **动词类几乎从零 + JMdict 承重** | B 题库小/错 | B0 按来源拆报 + JMdict 匹配率单列;闸 = 核心集 100% 正确;不达标 B 留 1.6 |
| **kana 启发式误判 ~480 suru-noun** | 错变形 | 双重排除门(noun 标签 / 无送り仮名);带 noun 不得有 godan vc(测试守) |
| **lemma 特例**(行く/ある/v5aru/する・くる) | 自信错变形 | 引擎先查 lemma 例外表;golden 覆盖每个特例 |
| **词单 LWW 时钟偏移丢词** | ★ 回归 | **改字段级:ids union(add-wins)+ 标量 LWW** —— skew-free |
| **遗留 deck 复活已删词** | 数据回声 | 单向一次性折叠 + 写一次 deck=default 收敛,之后只写 WordList;C1 跨版本实测 |
| **tombstone 无界** | 同步膨胀 | deletedAt>30 天本地丢 + 合并不复活 |
| **迁移坏文件丢全部命名单** | 数据丢失 | load 区分缺失/损坏;损坏备份 .corrupt + 回退重迁;原子写+读回;default 常量 id |
| **下行 deletion 被忽略** | 删不同步 | applyFetched/guard/mergeServerRecord/snapshot 显式加 RT.list |
| **conjugation SRS 污染识词队列** | 错乱 | 独立 ConjugationReviewStore(独立文件/record/键);MVP 先不写 SRS |
| **CKSyncEngine 重入崩**(刚被拒) | 又被拒 | 新 enqueue 全走 recordLocalChanges→scheduleSync;delegate 不驱动引擎;Release 启动自测 |
| **无障碍从零被低估** | C3 超期 | 逐屏列控件 + 命名验证步骤;新屏优先 |
| **三工作流体量** | 拖期 | A+C 进 1.5;B 默认 1.6、过闸才提;B2 引擎可最早并行 |

## 7. 测试策略
- **纯模块全测**:WordListsKit(CRUD/cap/迁移含坏文件/tombstone)、SyncMerge.wordLists(§A6 矩阵)、ConjugationKit(每类×每形 + lemma 特例 + suru-noun + 负向控制)。
- 现 113 测试不回归;VocabKit 守恒测试扩(有 vc 自洽 + 挡 suru-noun)。
- 集成/设备:js 真机 conjugation 打字 + 词单同步;**C1 双设备 + 跨版本(1.4.1↔1.5)读验证**。
- **无障碍验证**:Accessibility Inspector(mac)+ VoiceOver rotor(iOS)+ Dynamic Type 最大字号冒烟。
- 发版前:**Release 本地启动自测** + 3 视角对抗 review workflow。

## 8. 红线(必须保留)
1. **Practice 永不写 SRS**;**conjugation 若写 SRS 必用独立 store**,绝不复用 ReviewStore。
2. **非游戏屏**(菜单/结算/about/设置/**词单/引导**)抑制软键盘 + Esc/Back + navCount/zIndex 置顶;**游戏屏(含新 conjugation)自动召唤键盘 + isTouchDevice HUD**。
3. **所有文件写同步、主 actor、原子**(不可 Task.detached 写盘)。
4. **绝不在 CKSyncEngine delegate 回调里驱动引擎**;一律 `recordLocalChanges→scheduleSync` Task hop / 守卫合并 `syncNow`;`nextRecordZoneChangeBatch` 先按值快照 + CKRecord 深拷贝。
5. **kana 全局唯一**(测试强制,只管 bundled entries);conjugation 输出临时、不持久化为 entry。
6. xcodegen 版本字面量坑:`CFBundleShortVersionString:$(MARKETING_VERSION)` / `CFBundleVersion:$(CURRENT_PROJECT_VERSION)` 显式引用 build setting。
7. **构建号每平台递增**:当前 macOS=7 / iOS=8(1.4.1)。1.5 用 **macOS≥8 / iOS≥9**。
8. 不在 Jason 用机时截屏(headless ImageRenderer 安全);commit 后 push 私有 remote `github.com/JasonYeYuhe/nihongo-ride-app`。
9. 不复制第三方版权内容(JMdict 仅取事实 + 归属;只 ship 派生类整数)。

## 9. 待定问题(开发前定)
1. **B 进 1.5 还是 1.6** —— 由 B0 spike(JMdict 匹配率 + 核心集 golden 正确性)定。**默认 1.6。**
2. **JMdict 用不用** —— **review 结论:承重,基本必须用**(纯启发式只 ~23%)。若不用 JMdict,B 只能覆盖很小子集 → 几乎等于不做 B。请 Jason 拍板用 JMdict + About 致谢。
3. **conjugation 是否写 SRS** —— MVP 建议**先不写**;要写则独立 store。
4. **per-word un-save 全局同步** —— 不进 1.5(MVP:整单删/清空传播;per-id tombstone 留后续)。
5. **第一批变形形集** —— ます/て/た/ない/可能/意志;命令/条件留后。
6. **soft-cap 数值** —— 暂定 50 单 × 500 词(已落为 A1 不变量,可调)。

## 10. 版本与提交
- bump `MARKETING_VERSION 1.5`;build **macOS 8 / iOS 9**(> 1.4.1 的 7/8)。
- 元数据/截图 API 自动继承;What's New 双语写 A(+B 若过闸);**明确「取消收藏/移除词的跨设备传播按整单粒度」别夸大**;review notes:词单/变形均本地、无账号、iCloud 私有库(**Data Not Collected 仍成立**,加一句「词单是用户私有 iCloud 内容」);若用 JMdict,EDRDG 致谢同 commit 落 About。
- 全 API 提交(`scripts/asc_api.sh` + `submit_*.py` 模板)。**一次只能一个版本在审**:确认 1.4.1 已上架再提 1.5。
