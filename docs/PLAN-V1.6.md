# Nihongo Ride — v1.6 开发计划(动词变形 Verb Conjugation)

> 状态:v1.6 事实源。经全局多智能体 review(4 视角 + 综合)产出,**已过 Codex 外部复核(verdict REVISE-THEN-GO → 已据 8 条修订;锚点确认正确)**。
> v1.5(自定义词单 + 引导 + VoiceOver)已提交审核(双端 WAITING_FOR_REVIEW)。

## 0. 一句话范围

**v1.6 = 动词变形 MVP**:把 v1.5 已写好、golden 全绿但**接进 app 为零**的 `ConjugationKit` 引擎,落成一个可玩的变形练习模式。
= **B1 数据**(给词条派生 `vc` 动词类)+ **B3 模式**(`GameMode.conjugation` 复用 `.playing` 屏)+ **必须捆绑的硬化**(suru 变形 bug 修复、数据通路 golden、构建 xattr 修复、EDRDG 致谢、一行 CKRecord 守卫)。
**MVP 不写 SRS**(只即时反馈)。**明确推迟到 1.7+**:Dynamic Type、变形 SRS、双设备同步验证、TTS/句子模式/弱词训练/分享卡/widget/统计图。

理由:这是「最小但完整且诚实」的一刀——引擎已是承重资产却 dead;闭合它即交付一个自成体系的功能,且**不新增任何云同步状态**(不部署新 CKRecord、不碰 applyFetched/merge、不被「欠账的双设备验证」阻塞)。

---

## 1. 现状(已 grounded 核实)

- **引擎已完成但 dead**:`Sources/ConjugationKit/Conjugator.swift` golden 全绿,但 `Package.swift` 只把它声明为 library(:22)+ target(:88),**app target(:94)未依赖**;无任何 `import ConjugationKit`。
- **`VocabEntry` 无 `vc` 字段**:`Sources/VocabKit/VocabEntry.swift` CodingKeys 止于 `exZH`(:48)。B1/B3 数据与接线层全是 greenfield。
- **`enrich_verb_classes.py` 仅测量**(measure-only,从不写)。`--jmdict` 路径**已实现并被分类器使用**(:181-190 等),但**从未对真实 JMdict dump 跑过**(本机无 dump → +jmdict 解出 0)。**实测(codex 跑过)**:N5–N3 共 747 动词,exact+启发式(含 heuristic-suru)= 501(67.1%),**240 个 る 仍需 JMdict 消歧**;全量直方图里 `suru` 高达 1225——**绝大多数是 suru-noun,被一锅端**(见下)。JMdict 的承重作用 = 解 240 个 る 歧义 + **校验 suru-noun vs suru-verb**(纯启发式区分不了)。
- **已确认的引擎 bug**:`ConjugatorTests.swift:96-97` 把 `察する(さっする)` 的可能形 golden 钉成 `さっできる` —— **语法错**(正确是 察せる / 察することができる)。`Conjugator.suruForm`(:147)对所有 `.suru` 一律「去 する + できる」,**无法区分 suru-noun(勉強→勉強できる ✓)与 suru-verb(察する ✗)**;且 `察する` 在 n1.json 里是 `pos:["v"]`,分类器只看「kana 以 する 结尾」就给 `suru` → **会给裸 suru-verb 错打 vc**。修法见 §3(数据派生层 withhold)+ §5。
- 红线全保(v1.5 review 复核过):CKSyncEngine delegate 不驱动引擎;文件写同步/主 actor/.atomic;Practice 不写 SRS;kana 全局唯一(`VocabKitTests.swift:83-85` 已有此测试)。

---

## 2. Gate-0 —— 先做、决定 B 能不能进 1.6(go/no-go)

两条独立、可并行的轨:

**轨 A — JMdict 覆盖测量(承重):**
1. 下载 `JMdict_e`(EDRDG,CC-BY-SA 4.0)。
2. `python3 scripts/enrich_verb_classes.py --jmdict <path>`,**按 JLPT 报告**:①精确标签解出% ②启发式无歧义% ③**JMdict 解出%(单列)** ④未解出% + 残留歧义-る 计数。
3. **闸**:不是覆盖率,而是「正确性」——见轨 B 的策展 golden 100%。

**轨 B — 修引擎 bug + 建两层 golden(独立于 JMdict):**
1. 修 suru 可能形:MVP 取 (a)**数据派生层不给裸 suru-verb 打 `vc`(见 §3),并把任何残留 suru-verb 排除出题池**,**改/删** `ConjugatorTests:96-97` 的错误 golden,使引擎绝不以「已验证」之名输出错变形;或 (b) 拆类 `suruNoun` vs `suruVerb`,可能形仅对 noun 组合出 〜できる。推荐 (a)。
2. **两层 golden(codex 点:别让闸循环依赖)**:
   - **(i) 引擎/分类器内存 golden(Gate-0,无需数据写回)**:手喂 class + 策展 ~50 N5–N3 核心动词,断言每类×每形精确 —— 这层不依赖 B1 的写回,可在 Gate-0 立刻建。
   - **(ii) 数据通路 golden(B1 之后)**:加载**派生 `vc` 后的真实 JSON**,把**所有带 `vc` 的行**跑一遍受支持形,核心集 100% 正确 + 守恒不变量(§3)。这层是发版闸。

**决策**:轨 A 覆盖足够 + 轨 B 两层 golden 全绿 → B 进 1.6;否则 N2/N1 池太薄就**只出 N5–N3**(优雅降级,菜单按池大小 gate),仍可进;若核心集都过不了 → B 退回继续打磨,本期改出小功能(见 §7 备选)。

---

## 3. Phase B1 —— 数据(过 Gate-0 后)

- `VocabEntry` 加 `public let vc: String?`(CodingKey `vc`,可选默认 nil → 现有解码/测试零改动)。**存 raw String = `VerbClass.rawValue`**(codex #7:`VerbClass` 本就是 String-backed,**当前依赖图无 VocabKit→ConjugationKit 环**——别为臆想的环改存 Int;String 对 VocabKit 是不透明值,无需 import CK)。`vc → VerbClass` 的映射放在 **GameCore**(见 §4 依赖),app/VocabKit 都不 import CK。
- **写回脚本**:把 `enrich_verb_classes.py` 加 **WRITE 模式**(`--write` flag),把派生的 `vc`(String)戳进 `Sources/VocabKit/Resources/n5–n1.json`(不动 `pos`,降回归面)。**只 ship 派生的类标签,绝不搬 JMdict 文本**。
- **关键(codex #4):数据派生层就 withhold 裸 suru-verb 的 `vc`**。分类器现在只看「kana 以 する 结尾」就给 `suru`,会把 `察する`(`pos:["v"]`、无 noun 成分)错标。WRITE 模式必须:**仅给「noun + する」的 suru-noun 打 `vc=suru`;裸 suru-verb(汉字+する 且非 noun)一律不打 `vc`(→ 不进题池)**。这是把 suru-noun/suru-verb 之分钉死在数据层,比只在题池排除更稳。
- **守恒测试**(新 `ConjugationDataTests` 或扩 `VocabKitTests`):
  - kana 仍全局唯一(派生重写 JSON **后**再跑 `VocabKitTests.swift:83-85`)。
  - 有 `vc` 的条目:kana 结尾 ↔ 类自洽。
  - **带 noun 标签或无送り仮名者不得有 godan `vc`**(suru-noun 守卫)。
  - **负向:`察する` 这类裸 suru-verb 必须无 `vc`**(不被当可变形项)。
- **EDRDG 致谢**:`AboutView.swift` 已有 `credit(...)` helper —— `credit("EDRDG — JMdict/EDICT", license: "CC-BY-SA 4.0", url:..., en/zh:...)` **必须与 `vc` 派生同一 commit 落地**;派生脚本头注明来源。
- **闸**:§2 轨 B 策展核心 golden 端到端 100% 绿。

---

## 4. Phase B3 —— 变形练习模式

- **依赖接线(codex #2)**:让 **`GameCore` 依赖 `ConjugationKit`**(Package.swift 给 GameCore target 加 CK dep)。app 经 GameCore 间接拿到 CK → **app target 不必 import CK,project.yml 也不必改**(GameCore 已是 app 的依赖,CK 随之传递链接)。VocabKit 不依赖 CK(`vc` 是 String)。⚠️ 别只改 Package.swift 忘了 project.yml——本案因走 GameCore 传递而不用动 project.yml,但**若最终 app 直接 import CK,则 Package.swift + project.yml 两处都要加**(v1.5 WordListsKit 就是两处都加的)。
- `GameMode` 加 `.conjugation`(`GameSession.swift:16`)。
- **GameSession 深度耦合(codex #5,关键)**:现 `GameSession` 的 `queue/current/lapsed` 全是 `[VocabEntry]`,且 `skip()/complete()` **总是调 `review.record`**——**naive 复用会违反「不写 SRS」红线**。必须先做抽象:引入 `GameItem`/prompt 协议(或一个**独立的 conjugation session 类型**),变形路径**完全不碰 `ReviewStore`/`VocabStore`**。**先抽象、后接 UI**。
- **不要复用/伪造 `VocabEntry`**:prompt 结构 `ConjugationPrompt { dictKana, vc, targetForm, conjugatedKana }`;`conjugatedKana` 由 `Conjugator` **运行时临时算**,**绝不持久化为 VocabEntry**(红线 §8.5)。builder `GameSession.makeConjugation(...)`(或独立 `ConjugationSession`)。
- **测试(codex #5)**:断言一局 conjugation session 跑完 **对 `ReviewStore` 与 `VocabStore` 零写入**(守「不写 SRS」红线)。
- 出题:辞书形 + 目标形标签(双语,如「て形 / te-form」「可能形 / potential」),打变形读音,复用 `RomajiKana` 逐键匹配。
- **必须复用 `.playing` 游戏屏路径**(`GameView`/`KeyCaptureView`,`suppressSoftwareKeyboard:false` + `isTouchDevice` HUD)—— 不可新建抑制键盘的屏(否则键盘不出 = 2.1a 重蹈)。
- **题池 gating**:只取引擎能从 kana 无歧义处理的类(ichidan、godan_*、kuru、**仅 noun+する suru-noun**);**排除裸 suru-verb 和派生未解出的歧义条目**。菜单入口仅当可用池 > 阈值时显示。
- **SRS:MVP 完全不写**(`review.record` 一律跳过,不碰 `ReviewStore`)。这是最大的一刀,计划明确背书。
- **持久化模式 + 空池守卫(codex review 点)**:`selectedMode` 以 raw string 持久化(`AppSettings`),`GameMode(rawValue:) ?? .journey` 已能安全降级未知值——加 `.conjugation` 不破坏旧 blob。但若用户停在 `.conjugation` 而本设备/本 build 可用变形池为空(无 `vc` 数据 / 旧词库),`startGame()` 必须 **resolve-then-guard**(仿 v1.4 saved-deck 教训:空池不进游戏、回退或提示),绝不卡在空的已结束屏。
- **母语审**:对新出现的双语目标形标签 + 任何语法说明文案做一轮母语审(golden 保「变形正确」,审保「标签/释义质量」,测试管不了)。

---

## 5. 必须捆绑的硬化(随 B 一起落)

| 项 | 文件 | 动作 | 量 |
|---|---|---|---|
| **suru 可能形 bug** | `Conjugator.swift:147` / `ConjugatorTests.swift:96-97` | 数据层不给裸 suru-verb 打 `vc`(§3)+ 题池排除 + 修/删错误 golden | S |
| **两层 golden** | 新 `ConjugationDataTests` + 扩 `ConjugatorTests` | (i) 内存分类器 golden(Gate-0)+ (ii) 派生数据端到端 golden(发版闸,§2) | M |
| **no-SRS 守卫测试** | GameCore tests | conjugation session 跑完对 ReviewStore/VocabStore 零写入(§4) | S |
| **构建 xattr 修复** | `scripts/build-appstore.sh` + `-ios.sh` | 脚本顶部加 `xattr -rc "$ROOT"`(或定向删 `com.apple.provenance`),让构建可**就地**跑、退掉 /tmp clone 仪式。**关键**:clone 构建会静默漏掉未提交改动 = 发版正确性隐患。落地后先验证一次就地 archive 端到端 | M |
| **EDRDG 致谢** | `AboutView.swift` | 同 B1 commit(§3) | S |
| **CKRecord 守卫** | `CloudKitSyncController.swift:198` | `as! CKRecord` → `compactMapValues { $0.copy() as? CKRecord }`,坏拷贝降级跳过而非崩整批 | S |

---

## 6. 风险与闸

| 风险 | 说明 | 闸 / 缓解 |
|---|---|---|
| **R1 JMdict 覆盖不足** | 承重;纯启发式仅 ~23–26% | Gate-0 测量 + 策展 golden 100%;池薄则**只出 N5–N3**,菜单按池大小 gate(优雅降级,非阻塞) |
| **R2 自信错变形** | 误派生 `vc` / 仅靠读音(Conjugator 忽略 `lemma`,:48-61);suru-noun↔suru-verb 冲突**今日代码确实错** | 题池只收无歧义类 + 数据通路 golden;引擎不能从 kana 单独消歧的类绝不出题 |
| **R3 构建正确性** | clone vs 就地;provenance xattr | 落 xattr 修复 + 发版前验证一次就地 archive |
| **R4 标签/释义质量** | 用户可见的引擎生成语法串 + 新双语标签 | 母语审一轮(en+zh),测试管不了 |

---

## 7. 排序

1. **Gate-0**(并行两轨):JMdict 测量 ‖ suru bug 修 + **内存分类器 golden(layer i)**。→ go/no-go。
2. **B1**:`vc:String?` 字段 + WRITE 模式派生(**裸 suru-verb withhold**)+ 守恒测试 + **数据通路 golden(layer ii)** + EDRDG 致谢(同 commit)。闸:layer ii 100% + 守恒不变量。
3. **B3a 抽象先行**:GameCore 依赖 CK + `GameItem`/prompt 抽象(或独立 ConjugationSession),**no-SRS 零写入测试先绿**。
4. **B3b UI**:`GameMode.conjugation` + `makeConjugation` + `.playing` 接线 + 菜单/空池 gating + 母语审。
5. **硬化 + 发版**:构建脚本 xattr 修复(验证就地 archive)+ CKRecord 守卫 + bump 1.6(**macOS build ≥9 / iOS build ≥10**,> v1.5 的 8/9)+ Release 启动自测(从 /tmp clone,除非 xattr 修复已生效)+ 最终对抗 review + ASC 提交。
5. **备选**(若 B 过不了闸或想要小版本):**弱词训练**(S,纯复用 `GameSession.makeSaved` + `ReviewStore.weakestCards(limit:)`)单独成 1.6,B 推 1.7。

---

## 8. 明确推迟到 1.7+(不进 1.6)

- **Dynamic Type**(L,106 处固定字号跨 9 屏):真债,但与 B 争同一「设备验证预算」且零代码重叠;若 B 落得干净,定为 **1.7 头牌**。
- **变形 SRS / ConjugationReviewStore**(M + 新 CKRecord Production schema 部署):MVP 故意切;待双设备闸闭合后再议。
- **双设备 + 1.4.1↔1.5 跨版本 iCloud 验证**:欠账,但**非 1.6 阻塞**(MVP 不加同步状态);任何未来「同步的变形数据」工作的前置闸。
- **AppModel 测试缝抽取**(661 LOC 零单测)、**`try?` 写盘硬化**(17 处静默丢持久化失败)、TTS、句子打字模式、分享卡、widget、统计图、Game Center 扩充、per-word un-save tombstone、String Catalog 本地化、SavedWordsKit 退役准则、tombstone TTL 安全网 —— 均 park,不进 1.6。

---

## 9. 红线(从 v1.5 承袭,务必保留)

1. 绝不在 CKSyncEngine delegate 回调里驱动引擎;enqueue 一律 `recordLocalChanges→scheduleSync`(Task hop)/ 守卫 `syncNow`;`nextRecordZoneChangeBatch` 按值快照 + CKRecord 深拷贝。
2. 所有文件写同步、主 actor、`.atomic`(不可 Task.detached)。
3. **Practice 永不写 SRS**;**变形 MVP 不写 SRS**;若将来写,必用独立 `ConjugationReviewStore`(独立文件/CKRecord/键),绝不复用 `ReviewStore`。
4. 非游戏屏(菜单/设置/词单/引导)抑制软键盘;**游戏屏(含变形)自动召唤键盘 + isTouchDevice HUD**(2.1a)。
5. **kana 全局唯一**(派生重写 JSON 后再跑测试守恒);**变形输出临时、绝不持久化为 VocabEntry / 不入 VocabStore**。
6. xcodegen 版本字面量:`CFBundleShortVersionString:$(MARKETING_VERSION)` / `CFBundleVersion:$(CURRENT_PROJECT_VERSION)` 显式引用 build setting。
7. **构建号每平台严格递增**:当前 macOS=8 / iOS=9(v1.5)。1.6 用 **macOS≥9 / iOS≥10**。
8. 不复制第三方版权内容(JMdict 仅取「动词类」事实 + EDRDG 归属;只 ship 派生类整数)。
9. **构建从干净源跑**:repo 在 `~/Documents` 下有 `com.apple.provenance` xattr 致 codesign 失败;落 §5 的脚本 xattr 修复前,必须从 `/tmp` git clone 构建。

---

## 10. 版本与提交

- bump `MARKETING_VERSION 1.6`;build **macOS 9 / iOS 10**。
- 元数据/截图自动继承;What's New 双语写动词变形(明确「N5–N3 起步」若降级);若 B1 落地,EDRDG 致谢同 commit 进 About。
- 全 API 提交(`scripts/submit_1_5.py` 为模板改 `submit_1_6.py`,或泛化)。1.5 须先上架(一次一个版本在审)。
