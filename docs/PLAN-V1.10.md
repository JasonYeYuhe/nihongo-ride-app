# Nihongo Ride — v1.10 开发计划(说真话的一版:词单删除真生效 + 同步层不撒谎 + 分享卡)

> 状态:v1.10 事实源。经 **5 视角并行 grounding(读真实代码 + 真查了线上 Production schema + 真跑了 gen_passages 的 validator)+ 综合 + 对抗 review(verdict REVISE-THEN-GO;4 条 HIGH + 3 条 MEDIUM + 2 条 LOW 已全部纳入本稿)**,2026-07-14 立。
> 承接:v1.8 / v1.8.1 / v1.9 三版**均已 READY_FOR_SALE**。`swift test` 基线 **221/36 全绿**(不得回归)。v1.9 的 2 个发前 nit 已于 commit 4c53bee 收尾。
> Jason 全权授权。

## 0. 一句话范围

**v1.10 = 把「同步层报成功、实则做错事」这一类谎言修掉。** headline:**词单的「删除」真正跨设备生效**(v1.5 起就在野的 marquee 谎言);supporting:**同步层生命周期不撒谎**(stop() 真能停、失败状态真能留)+ **分享卡**(本版唯一新面)。**不追新维度——widget / kanji 诚实推后。这是一次「说真话」的版本,明写在明面上。**

**硬 cut 线:committed = Phase 0 + A + B + C。** 其余全部 stretch / cut-first(见 §5),不进承诺范围。

---

## 1. 现状 + grounding 的核心发现

- **🔴 headline 的由来:词单「删除」在野是坏的。** `SyncMerge.wordLists` 的 ids 是 **per-id UNION(add-wins)**——加★ 生效,但**逐词移除 / clear / 整单删除三者全部被 peer 的 union 复活**。这是 marquee 功能(v1.5「自定义词单」)上的用户可见谎言,自 v1.5 在野至今。
- **widget 的推迟理由被证伪(但仍推后)**:v1.9 说 widget 必须把全部 store + cksync-state.json 迁进 App Group ——**这个前提是错的**:widget 是**只读**的,它要显示的数字全是现成纯函数(`ReviewStore.dueForecast` / `ConjugationReviewStore.dueForecast` / `RideJournal.streakDays`)。app 只需往 group 容器写**一个派生 snapshot**,widget 只读它,**7 个 store 一个都不动** → 迁移与其数据丢失风险消失,widget 降为 **M/ready**。**但本版仍推后**:tombstone 是在野真 bug、更该占 headline;widget 进 **v1.11**(已拆弹的推迟,不是又一次绕开)。
- **🔴 grounding 挖出的最锋利的雷(永久进红线):绝不做全量 store 迁移。** 雷不在文件那半、在 **UserDefaults 那半**:`AppSettings` 在 `UserDefaults.standard` 且**同时**携带 `deviceID` 与 `languageCode`。若迁移的 defaults 半边失手 → AppModel 铸新 `deviceID` → init 的 odometer backfill 用**整个 journal lifetime** 播种一个**新 slot**,旧 slot 仍在 → `OdometerLog` 总数是**各 slot 求和**、`SyncMerge.odometers` 是 per-slot max+union → **lifetime 里程翻倍、同步上云、落到每台设备,且没有任何 UI 能删 slot**。不可修复。
- **v1.9 的两处自查(诚实记账)**:① **结算朗读钮命中区太小**(ResultsView.swift:208-209,10pt)——误触会穿透到 chip 的 `onTapGesture` **静默取消收藏**。今天几乎无害(peer union 会复活),但 **Phase A 一落地,这个胖手指就变成 v1.9 peer 设计上无法复活的真·跨设备删除** → 必须与 Phase A **同版**修(见 §3 A4)。② `statsRunsByMode` / `RideJournal.runsByMode()` 已建、有 2 个绿测,**但从未被渲染**——PLAN-V1.9 §3 承诺的「模式·等级分布」没落地(见 §5 S2)。
- **passages 管线可复活**:`gen_passages.py` 因 gemini CLI 认证 IneligibleTierError 已死,但 **~10 行改 agy 即活**(grounding 实证:真 GEN_PROMPT + 真 validator **35/35 全过**)。但见 §6:例句子选项**正式 DROP**。

---

## 2. Phase 0 —— Prod schema 部署 + 字段级 guardrail(committed,S,最先、独立、无 app 码)

给 `WordList` 加 **`deletedAt` TIMESTAMP + `wordMeta` STRING**:dev import → validate → Console Deploy Dev→Prod;并把 `check_prod_schema.sh` 从「record type 存在」升级到**字段级**核对。

- **(review HIGH#2)「先在 Dev 跑个非破坏性探针」不是诊断闸——它逻辑上不成立**:CloudKit Development 对任何成功保存都会 JIT 未知字段,所以「若保存失败 → 铁证」这一支**不可达**,Dev 永远无法复现 Prod 的拒绝未知字段行为。**本步的真实身份 = schema 的「创作机制」**(对 Dev 软删一个词单 → JIT 出 deletedAt → export → Console Deploy),**不是**对 Phase A 写路径的独立确认。删掉「保存失败=铁证」那一支。
- **诊断证据另有其人(已足够)**:`cktool export-schema` 显示 **Dev 也没有 `deletedAt`** ⇒ 任何环境下从没有一个 build 成功保存过软删的 WordList。这条推断本身就交付了全部诊断。
- **闸**:部署后 `check_prod_schema.sh`(字段级)全绿 + Prod export 里 `WordList.deletedAt/wordMeta` 在。

---

## 3. Phase A —— HEADLINE:词单移除语义真正收敛(committed,M)

逐词 remove / clear / 整单 delete **全部跨设备生效**,用 **LWW-element-set**。

- **A1 数据模型**:`wordMeta`(JSON-in-STRING)承载 `r`(removedAt)与 `a`(addedAt)两张表;成员判定 = `addedAt[id] >= removedAt[id]`。
- **(review HIGH#3)`a` 必须是「争议集」而不是「全量普查」**:原设计里 `a` 一旦采用就**永不能裁剪**(丢 a[id] 会让该词输给任何幸存 r[id] → 删除复活),于是 `a` 沦为「每一个曾被加过的 id 的永久普查」——默认 ★ 单可达数千(词库 7074),按 ~30–40 B/条 JSON = **六位数字节的 STRING,且每次 ★ toggle 都要整体重写**,还与 ids 同乘一条 CKRecord。**改法:只在存在 r[id] 时才写 a[id]**(a 条目的唯一职责就是打败一个 r 条目;在 `ids` 里且无 r 条目者默认即成员,不需时间戳)。于是压缩可**成对丢弃 a/r**——当 removedAt 老于 tombstoneTTL —— 把 wordMeta 收敛为「近 30 天被移除的 id」而非「历史全部 id」,并继承计划已认可的 TTL 复活风险。**加一个 7k ids 的编码体积断言测。合并规则文本在实现前就改对,不要边写边改。**
- **(review MEDIUM#7)本地格式也变了,不只云端**:`wordMeta` 要给 `WordList`(Codable、持久化到 `wordLists.json`)加字段 → **有向后解码义务**(旧文件无 meta 必须干净默认)。`WordListMigration.swift` 就是这类事该待的地方。**新红线:旧 wordLists.json 解码零数据丢失**;加 `WordListStoreTests` 用例载入 v1.9 期文件、断言每个 id 存活且无幻影移除。
- **A2 合并**:`SyncMerge.wordLists` 改 LWW-element-set;**保持纯/交换律/幂等/结合律**(作为测试义务而非事后想起)。压缩**只在 applyCloudChanges 路径**(AppModel.swift:385 是唯一调用点),**绝不在加载路径**。
- **A3 `foldLegacyDeck`(头号静默失败路径)**:**(review LOW#9)两条注释都要改**——AppModel.swift:390 说「the persisted flag in foldLegacyDeck enforces once」是**假的**(函数自己 :650 的文档说它每次 fetch 都跑,且不存在该 flag)。:390 那条更危险(未来读者问「这条路径会不会把 addedAt 戳成 now?」时先看到它,而它答「不会,只跑一次」= 谎)。
- **A4(review MEDIUM#5,Phase A 的命名依赖,同版必修)**:**结算朗读钮命中区**(ResultsView.swift:208-209,10pt)——误触穿透到 chip 的 onTapGesture 静默取消收藏。**Phase A 正是把它从「装饰性命中区 bug」升级成「会传播、且 v1.9 peer 设计上无法复活的数据丢失」的那个东西。** 明写此耦合;扩大命中区 / 隔离手势。
- **(review HIGH#1)headline 文案不得超过证据**:「部署 deletedAt 就能追溯修好 v1.5–v1.9 所有在野版本的整单删除、零二进制更新」这一说法**依赖 Phase B #2 那个未解的 CKSyncEngine 语义**(非瞬时 per-record 失败后,引擎是丢弃还是重试待发变更?)。若是丢弃,则每台在野 peer 上早已失败的墓碑**已永久离开待发队列**,部署字段只能修**未来**的删除。`enqueueAllLocal()` 确实会重新入队带墓碑的单(已核:注释「Every list (incl. tombstoned, so deletions propagate)」),但它**只在 saved state 为 nil 或显式 fullResync 时跑**——即要用户手动关开 iCloud 同步。**计划不能既把它当已证(Phase 0)又当未知(Phase B#2)。** → **强制失败门提到闸列表最前、且它 gate 的是 headline 文案与 What's New 那一行**,不只是 #2 的 sizing。未解前,文案降级为:**「修好已上架二进制上所有未来的整单删除;历史墓碑需一次 full resync(同步关→开)才冲出」。**

---

## 4. Phase B —— supporting:同步层生命周期不撒谎(committed,S-M,**独立提交、先于 Phase A 的 merge 改动**)

与 headline 同一失败类(「同步层报成功、实则做错事」),但**必须独立提交**——照抄 v1.9 §A 那套有效配方:同步回归绝不与功能改动混一次提交。

- **B1 `stop()` 真能停**。**(review HIGH#4)修法必须先把规则说清,否则自相矛盾**:红线写「绝不中途把 engine 置 nil(await 中 dealloc 会 CKSyncEngine fatal)」,而 `stop()`(CloudKitSyncController.swift:85)**今天就在这么做**——一个 pass 可能正悬在 `await engine.fetchChanges()` 里。**明写规则:一个 pass 在入口取 ONE 局部强绑定并持有它跨越该轮所有 await(不 dealloc);循环只在每轮顶部重读 `self.engine`;`stopped` 同时 gate 循环继续与每一次 `model?` 写。**
- **B2 stop→start 的复位必须指定**:`start()` 必须清 `stopped` **和** `passFailure`,且 **`syncing` 为真时不得开新 pass**——否则合并循环会把 engine 2 交给 engine 1 在飞的 pass,正是要杀的「两个引擎一个 cksync-state.json」竞态**在修完之后仍然存活**。加 stop-mid-pass → restart 的测试。
- **B3(review MEDIUM#6,折进本 Phase)`enqueueAllLocal` 上传了每一台 peer 的 odometer slot**(已核:`changes += model.odometer.slots.keys.map { .saveRecord(recordID(RT.odo, $0)) }`),而 `OdometerLog` 的文档宣称「每设备恰一个 slot,故永不冲突」——**文档在撒谎**。改成只入队 `model.deviceID` 自己的 slot + 改正 OdometerLog 文档。同文件、同主题、边际成本≈0,且每次 full resync 能省掉每个活跃 peer 一次必然的冲突往返。
- **闸**:三项各自的测试 + **签名 Release 启动崩溃门**(动了 CloudKitSyncController 必跑;**Phase B 与 Phase A 各跑一次,别合并成一次提交**)。

---

## 5. Phase C(committed,S)+ Stretch(不进承诺)

- **Phase C —— 分享卡 + 结算/菜单真 bug(本版唯一新面)**:结算屏 `ShareLink` 分享卡(grounding 实证:`Transferable`/`DataRepresentation(.png)` 在 `-swift-version 6 -strict-concurrency=complete` 下双端编译通过)。**(review LOW#8)菜单页脚计数**:先**读** `GameSession.make` 真实的取池逻辑再改,要么精确匹配、要么说更弱但为真的话(如去掉计数、保留已正确的「Due for review: N」)——别猜。
- **Stretch S1 Practice 轮换记忆**(S):`makePractice`(GameSession.swift:148)是 filter→shuffle→prefix,**无 seen-set**;AppModel.swift:692 也不传历史 → 短语料下重复率高。
- **Stretch S2 Stats 补完**(XS):`statsRunsByMode` + `RideJournal.runsByMode()` 已建、有 2 个绿测、**从未被渲染** —— PLAN-V1.9 §3 承诺的「模式·等级分布」没落地。**这是 v1.9 的欠账,诚实记在这。**
- **Stretch S3 AppModel 测试缝**(S-M):app target **零测试**。缝:`RunPersistPlan(completion:changedIDs:appended:)` 等纯值,仿 `RunCompletion` / `SyncMerge.applyRun` 的房规。
- **Cut-first C1 passages 扩容**(S):管线可复活(~10 行改 agy,validator 35/35 实证),但见 §6 —— 价值存疑,首砍。

---

## 6. 明确推迟 / DROP

- **Widget(WidgetKit)→ v1.11 headline** —— 第 6 次推迟,但这次是**已拆弹的推迟**:snapshot 方案(app 写一个派生 snapshot,widget 只读)使其为 **M/ready**。不可约的仍有:App Group **entitlement**(两个 app target + 门户 App ID capability)、两个 extension target(macOS+iOS)、新 App Review 面。**平台坑:macOS 要 team 前缀(`KHMK6Q3L3K.group.com.jasonye.nihongoride`)、iOS 不要 → 必须平台条件常量。** **snapshot 必须带「每日到期直方图」而非计数**(widget 时间线在 app 不运行时跨午夜滚动;DueForecast 的 today/tomorrow/thisWeek 太粗,午夜后 tomorrow' 是 thisWeek 的未知子集)。**snapshot 写入者必须自己 honor `Screenshotter.isCapturing`**——capture 的临时目录重定向在 `supportFileURL` **内部**,任何新的 group 路径都会绕过它,headless 截图会把真实 snapshot 覆盖成演示数据。
- **绝不尝试全量 store 迁移**(即使将来做 widget)—— §1 的 UserDefaults/deviceID 双 odometer 陷阱,**永久红线**。
- **kanji/部首 SRS** —— XL 多版赌注,不变。 **SRSLike 协议抽取** —— 前置条件(第三种 SRS)仍不满足,过早。
- **GC 变形成就** —— 继续推,且**边际价值已下降**:当初理由是「变形没有露脸面」,而 v1.9 Stats 的变形卡已补上这个缺口。
- **例句 Practice 子选项 —— 正式 DROP,不再推迟**(就此结掉 PLAN-V1.9 §8 悬案)。v1.9 的框架(「Option B 交付 ~80% 同价值」)**是错的**:passages 是与词汇无关的泛文,对「打一句含目标词的例句」这件事**并不替代**。**例句 TTS 朗读**随之 DROP。
- **变形 store trim** —— 确认 DROP(自 bound)。
- **@MainActor 标注 ConjugationSession/GameSession(去 assumeIsolated)** —— 今天成立(两者只经 @MainActor AppModel 触达),是运行期断言非编译期保证;**仅在真做 widget 时再评**。
- **文档级不立项**:dueForecast().today(< 当日末)与 dueCount()(<= now)口径不一致(是跨屏措辞问题非缺陷);`Passage.topic` 是死数据;`makePractice` 文档说「at or below level」而代码是 `==`。
- **提审时 metadata 扫尾**(不进工程范围):`docs/ASC_METADATA.md:36` 促销文案仍写「183 calm Practice passages」实为 233;`THIRD_PARTY_LICENSES.md:50` 同样陈旧。

---

## 7. 设备门(Jason;**强制失败门已提到最前,它 gate headline 文案**)

1. **强制失败门(最先,gate headline 与 What's New 文案)**:写一个 Dev schema 里不存在的 record type,观察 CKSyncEngine 对**非瞬时** per-record save 失败是**丢弃**还是**重试**待发变更。决定 §3 HIGH#1 的文案能不能说「追溯修复」。
2. **双设备移除矩阵(本版核心门,不可跳过)**:A 逐词取消收藏 → B 消失;A 再收藏 → B 重现(证明墓碑没杀掉合法再加);A 清空 ★ → B 清空;**A 删整单 → B 隐藏**(最后这条从未有人验证过)。
3. **混合舰队门(Phase A 成败的真判据)**:第二台跑 v1.9 已上架二进制 —— 断言 v1.9 peer **不能复活**已删词(其无戳 ids 恒输给 tombstone)。
4. **签名 Release 启动崩溃门**:Phase A / Phase B **各跑一次**(勿合并提交)。
5. **同步开关竞态门(B1 现场复现)**:pass 进行中关掉 iCloud 同步 → 断言上传停止、无云数据写进本地、状态显示「关闭」而**非绿色「已同步」**;再打开 → 断言没有第二个引擎。
6. **Phase 0 的 Dev 授权步骤**(§2:这是创作机制不是诊断)。
7. **分享卡 iOS 门(必做,会崩)**:`xcode/Info-iOS.plist` **当前没有** `NSPhotoLibraryAddUsageDescription`,而 iOS 分享单对图片一定会给「存储图像」→ **必须先加,否则崩**。
8. **分享卡 macOS 门**:App Sandbox 下 `NSSharingServicePicker` 实际行为(哪些服务、popover 锚定)headless 验不了。
9. **焦点门(双端)**:分享单/popover 关闭后 macOS `KeyCaptureNSView` 是否续收 keyDown、iOS 软键盘是否被永久 dismiss。

---

## 8. 红线(承袭 + 本版新增)

1. 变形 SRS 独立 store/文件/CKRecord;Practice/cram/例句 永不写扁平 vocab SRS。
2. **CKSyncEngine 绝不在 delegate 驱动引擎**;**pass 入口取一个局部强绑定持有跨 await,循环只在轮顶重读 self.engine**;`stopped` gate 循环与每次 model 写。
3. 所有文件写同步/主 actor/.atomic;**压缩只在 applyCloudChanges 路径,绝不在加载路径**。
4. **新红线:绝不做全量 store/UserDefaults 迁移**(deviceID 双 odometer 陷阱不可修复)。
5. **新红线:旧 `wordLists.json` 解码零数据丢失**(wordMeta 是本地格式变更)。
6. **新红线:merge 保持纯 / 交换律 / 幂等 / 结合律**(测试义务)。
7. app 经 GameCore 触达 ConjugationKit;kana 全局唯一;Dynamic Type `.scaledSystemFont` 不回退。

---

## 9. 排序 + 版本

1. **设备门 #1(强制失败门)** —— 先跑,它 gate headline 文案。
2. **Phase 0**(Prod schema 部署 + 字段级 guardrail)。
3. **Phase B**(同步生命周期,**独立提交 + 独立崩溃门**)。
4. **Phase A**(headline:LWW-element-set + A4 命中区,**独立提交 + 独立崩溃门**)。
5. **Phase C**(分享卡 + 页脚)。
6. **发前**:对抗 re-review + 设备门全跑 + bump 1.10(mac≥14/iOS≥15)+ `check_prod_schema.sh`(字段级)+ submit_1_10.py(find_build 按平台解析)。

What's New 双语:词单删除跨设备生效(文案受设备门 #1 结论约束)、同步稳定性、分享成绩卡;无 ★ 字形。
