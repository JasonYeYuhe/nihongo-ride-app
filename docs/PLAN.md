# 开发计划书(PLAN)

> macOS / SwiftUI 日语打字练习 App。基于产品 brief 与 [`RESEARCH.md`](RESEARCH.md)。
> 范围纪律:**MVP = 罗马字引擎 + 一种限时动作模式 + N5 词库 + 错词 SRS 复习**。其余明确标「以后」。

---

## 1. 产品定位回顾

「像寿司打一样好玩,但真正帮你学会。」面向 JLPT N5–N1 的**外国**学习者(次要:刚学完五十音者)。差异化:边打边给**假名 + 罗马字提示(可关)+ 词义**,打错的词进 **SRS 复习队列**。我们当**迷你 IME**,逐键多路径匹配,不走系统 IME。

### MVP 游戏模式:「打字环游日本(Bike/Journey)」

采纳 brief 里新提的点子,定为 MVP 主模式:

- 屏幕上是一条日本路线(如东京→京都),骑手随**打对的假名/词**前进,沿途解锁经典景点卡片(富士山、金阁寺……),景点卡片顺带教一个词。
- 核心循环与金山「警察抓小偷」同构:**输入正确 → 位移**。把它包装成"限时动作":每词有时限/节奏(词从前方逼近,或体力/时间条递减),打对得速度与连击,打错丢时间——满足 brief 的"传送带式限时动作模式"诉求,只是表现为骑行进度而非寿司带。
- 「传送带/寿司带」纯横向滚动作为**后续变体**(同一套引擎与游戏循环,仅换 UI 皮肤与生成器)。

> **关键解耦:** 罗马字引擎对游戏模式**完全无感知**。它只回答"这一键对不对、词打完没、下一键可以是哪些"。骑行 vs 传送带只是消费引擎事件的不同 UI/计分层。**所以 Phase 2 只实现引擎,不受模式选择影响。**

---

## 2. 架构总览与模块拆分

分层(自底向上,依赖单向向下):

```
┌─────────────────────────────────────────────────────────┐
│ App 层 (SwiftUI)  TypingAppApp / 场景 / 设置 / 导航          │  ← 以后
├─────────────────────────────────────────────────────────┤
│ UI 组件层  KeyCaptureView(NSViewRepresentable, 旁路 IME)    │  ← 以后
│           词卡 / 假名+罗马字提示(可关) / 骑行进度 / 景点      │
├─────────────────────────────────────────────────────────┤
│ 游戏循环层  GameSession: 出词→喂键→计分→连击→时间/进度        │  ← 以后
│           生成下一词(混合:新词 + 到期复习词)               │
├──────────────────┬──────────────────┬─────────────────────┤
│ 复习层 ReviewKit  │ 词库层 VocabKit   │ ★引擎 RomajiKana★    │
│ SM-2 / 错词队列   │ 词条 / 加载 / 查询 │ 逐键多路径匹配状态机   │  ← 引擎=Phase 2
│ 复习记录持久化     │ JLPT 分级 / 难度  │ (纯 Swift, 零 UI 依赖) │
└──────────────────┴──────────────────┴─────────────────────┘
```

| 模块 | 职责 | MVP? |
|------|------|------|
| **RomajiKana**(引擎) | 逐键、多路径、目标感知的假名打字匹配;假名→罗马字提示生成 | **MVP(本次实现)** |
| VocabKit(词库) | 词条模型、N5 词库加载(JMdict_e + Tanos)、查询 | MVP(引擎后) |
| ReviewKit(复习) | SM-2、错词队列、复习记录持久化(SwiftData/Codable) | MVP(引擎后) |
| GameSession(游戏循环) | 出词、喂键给引擎、计分/连击/时间、混合新词与复习词 | MVP(引擎后) |
| UI / App | SwiftUI 界面、KeyCaptureView、骑行/景点、提示开关、设置 | MVP(引擎后) |
| 片假名 / 动词变位 / 长句 / 排名 / N4–N1 / 云同步 | — | **以后** |

引擎是唯一独立可单测、复用价值最高、风险最高的部分,故**最先做、做到测试全绿再停**。

---

## 3. 数据模型

### 3.1 词条 VocabEntry(VocabKit,引擎后实现;此处定型供引擎对齐)

```swift
struct VocabEntry: Identifiable, Codable, Hashable {
    let id: String           // 稳定 id,如 "jmdict:1567610" 或 "kana+surface"
    let surface: String      // 书写形(含汉字),如 "学校";若纯假名词则同 kana
    let kana: String         // 读音假名(平假名)——★引擎的打字目标★,如 "がっこう"
    let romajiHint: String   // 罗马字提示(可关),由引擎 KanaRomanizer 生成,如 "gakkou"
    let meanings: [String]   // 英文释义(默认语言),如 ["school"]
    let partsOfSpeech: [String]  // 词性,如 ["noun"]
    let jlptLevel: JLPTLevel // .n5 ... .n1
    let difficulty: Double   // 0...1 综合难度(频率 + 长度 + 含促音/拗音/ん 等),用于排序/出词
    let exampleJP: String?   // 可选 Tatoeba 例句
    let exampleEN: String?
}

enum JLPTLevel: Int, Codable, CaseIterable { case n5 = 5, n4, n3, n2, n1 }
```
> 多语言释义余地:MVP `meanings` 为英文;以后可改 `meanings: [Locale: [String]]` 或加 `meaningsZH`。

### 3.2 复习记录 SRSCard(ReviewKit,引擎后)

```swift
struct SRSCard: Codable, Identifiable {
    let id: String           // = VocabEntry.id
    var easeFactor: Double = 2.5     // EF, 下限 1.3
    var interval: Int = 0            // 天
    var repetitions: Int = 0
    var dueDate: Date
    var lapses: Int = 0
    var lastReviewed: Date?
    // 统计(供派生 q 与展示)
    var totalSeen: Int = 0
    var totalMistakes: Int = 0
}
```
持久化:MVP 用 SwiftData(macOS 26 原生)或 Codable+JSON 文件;先封装 `ReviewStore` 协议,实现可换。

### 3.3 引擎对外事件 / 结果(本次实现,见 §4)

```swift
enum InputResult: Equatable { case accepted, rejected, completed }
```

---

## 4. ★ 罗马字引擎设计(本次 Phase 2 实现)★

### 4.1 设计目标

给定一个**目标假名串**(如 `"がっこう"`),逐键接收罗马字按键,实时回答:
1. 这一键是否合法(在通往目标的某条路径上)?(`accepted` / `rejected`)
2. 词是否打完?(`completed`)
3. 下一键可以是哪些字符?(`expectedNextCharacters`,供提示/高亮)
4. 已完成多少假名?(进度展示)

并提供:**假名→罗马字提示串**生成(`KanaRomanizer`,供"罗马字提示(可关)")。

要求:**多路径**(shi/si/ci 同时有效)、**目标感知**(知道答案,故可宽容:みんな 接受 `minna`/`minnna`/`min'na`)、纯 Swift、零 UI 依赖、可单测。

### 4.2 为什么用「表驱动 NFA」而非「盲转 IME + 比对」

盲目的 romaji→kana 转换器(像真 IME)把 `minna` 转成 みんあ,无法匹配目标 みんな;且无法回答"下一键可以是哪些"。所以引擎采用**目标感知的字符级 NFA(非确定有限自动机)模拟**:

- 用 Mozc 表,把"通往目标假名串的所有合法罗马字路径"编译成一张以**单字符**为边的状态图。
- 维护**当前可达状态集合**`Set<NodeID>`;每来一键,过滤出能消费该字符的后继。集合空=这一键错;某状态到达接受节点=词完成。
- 多路径天然并行探索(shi/si/ci 各是一条边路径);ん 的 n/nn/n' 各是分支,靠目标后续键自然消歧;`expectedNextCharacters` = 当前状态集所有出边字符。

### 4.3 NFA 构建(核心算法)

数据:把 Mozc TSV 解析成条目 `(romaji, kana, pending)`,并按**输出假名**建索引 `producers: [kana: [(romaji, pending)]]`(假名输出长度 1–2,如 `か`、`きゃ`、`っ`)。

节点 = `(kanaPos: Int, pending: String)`:`kanaPos` 是已消费到目标假名串的位置;`pending` 是**已敲下、必须作为下一条目 romaji 前缀的残留**(促音机制)。起点 `(0, "")`,接受点 `(target.count, "")`。

从节点 `(p, pending)` 扩展:遍历目标在 `p` 处可匹配的输出假名(取 `target[p..<p+1]` 与 `target[p..<p+2]`),对每个 producer `(r, nextPending)`:
- 要求 `r` 以 `pending` 开头;`rem = r` 去掉 `pending` 前缀后剩余要敲的字符。
- 沿 `rem` 逐字符建边,从 `(p, pending)` 到 `(p + kana.count, nextPending)`。

促音(`pending`)如何工作,以 **っか** 为例(目标 `["っ","か"]`):
- 条目 `kk → っ, pending "k"`:敲 `kk`(2 键)到达 `(1,"k")`(っ 后、欠一个 `k`)。
- 在 `(1,"k")` 匹配 か:条目 `ka` 以 `k` 开头,`rem="a"`,敲 `a` 到 `(2,"")`。合计 `kk`+`a` = **`kka`** ✓。
- 同时 `xtu/xtsu/ltu/ltsu → っ`(无 pending)给出 `xtuka` 等显式路径。

ん(目标某位是 `ん`):producers 给出 `n`/`nn`/`n'`/`xn` 四条边并行;单 `n` 始终允许(目标感知下宽容,且词尾单 `n` 也接受)。

### 4.4 公开 API(本次交付)

```swift
public struct KanaInputMatcher {
    public init(target: String, table: RomajiKanaTable = .shared)
    public private(set) var isComplete: Bool { get }
    public mutating func input(_ character: Character) -> InputResult  // 错键不改状态
    public var typedRomaji: String { get }                 // 已接受的罗马字
    public var expectedNextCharacters: Set<Character> { get }
    public var completedKanaCount: Int { get }             // 活动状态中最靠前的进度
}

public enum KanaRomanizer {
    public static func romaji(for kana: String) -> String  // Hepburn 风提示:がっこう→"gakkou", れんあい→"ren'ai"
}
```
> `RomajiKanaTable`:从 `Bundle.module` 的 Mozc TSV 解析,`.shared` 懒加载缓存。
> 进度 `completedKanaCount`:NFA 多路径下取活动状态的最大 `kanaPos`(乐观,够进度条用)。
> 设计决定(已记录):**词尾单 `n`、ん 前单 `n` 一律接受**(宽容、对学习者友好,异于严格 IME);**`m` 不接受**作 ん(`しんぶん` 拒 `shimbun` 于 `m`,与 IME 一致)。

### 4.5 边界用例测试矩阵(TDD,测试先行)

> 全部写成 Swift Testing 参数化用例;✅=应接受并打完,❌=应在指定键被拒。

**A. 多路径(单假名异拼)**

| 目标 | 接受 | 备注 |
|------|------|------|
| し | `shi` `si` `ci` | 三路径 |
| つ | `tsu` `tu` | |
| ち | `chi` `ti` | |
| ふ | `fu` `hu` | |
| じ | `ji` `zi` | |
| か | `ka` `ca` | |
| を | `wo` | |

**B. 拗音(youon)**

| 目标 | 接受 |
|------|------|
| しゃ | `sha` `sya` |
| ちゃ | `cha` `tya` `cya` |
| じゃ | `ja` `zya` `jya` |
| きゃ | `kya` `kixya` `kilya`(整体 + 分解小ゃ) |
| にゃ | `nya` |

**C. 促音 っ(辅音双写 + 显式)**

| 目标 | 接受 | 备注 |
|------|------|------|
| がっこう | `gakkou` `gaxtukou` `galtukou` | 双写 + xtu/ltu |
| きって | `kitte` `kixtute` | |
| ざっし | `zasshi` `zassi` | っ+し:双写 sh/s |
| まっちゃ | `maccha` `mattya` `matcha` | っ+ちゃ,含 `tch` 路径 |
| きっぷ | `kippu` `kixtupu` | |

**D. 撥音 ん(n / nn / n' / xn)**

| 目标 | 接受 | ❌ 拒绝 |
|------|------|--------|
| ほん | `hon` `honn` `hon'` | |
| みんな | `minna` `minnna` `min'na` | |
| かんじ | `kanji` `kanzi` | |
| れんあい | `ren'ai` `rennai` `renai` | |
| しんぶん | `shinbun` `sinbun` | `shimbun`(在 `m` 处拒)|
| きんようび | `kin'youbi` `kinnyoubi` `kinyoubi` | |

**E. 長音(literal 元音;ー 属片假名=以后)**

| 目标 | 接受 |
|------|------|
| とうきょう | `toukyou` |
| こうこう | `koukou` |
| おおきい | `ookii` |
| ねえ | `nee` |

**F. 整词集成(N5)**

| 目标 | 接受(示例) |
|------|------------|
| にほんご | `nihongo` |
| せんせい | `sensei` |
| がくせい | `gakusei` |
| でんしゃ | `densha` `densya` |
| しんかんせん | `shinkansen` |

**G. 拒绝 / 状态机健壮性**

- `にほん`:敲到 `niho` 后再敲 `a` → `rejected` 且状态不变,可继续正确敲 `n`。
- 完成后 `isComplete == true`,`expectedNextCharacters` 为空。
- 空目标 / 非法目标的处理(防御性)。

**H. KanaRomanizer 提示生成**

| 假名 | 提示 |
|------|------|
| にほんご | `nihongo` |
| がっこう | `gakkou` |
| しんぶん | `shinbun` |
| とうきょう | `toukyou` |
| でんしゃ | `densha` |
| れんあい | `ren'ai`(ん 在元音前用 `'`) |
| きって | `kitte` |

---

## 5. 技术决定

| 项 | 决定 | 理由 |
|----|------|------|
| 语言 | Swift 6(本机 6.3.2),严格并发 | 现代、地道 |
| 引擎平台 | 纯 Swift,无平台依赖(可跨平台/CI on Linux) | 引擎零 UI 依赖,便于单测 |
| App 最低系统 | **macOS 14 (Sonoma)** | 覆盖面 + 现代 SwiftUI;引擎本身门槛更低 |
| 测试框架 | **Swift Testing**(非 XCTest) | 2026 现代选型,`@Test`/`#expect`/参数化清爽 |
| 工程形态 | **SPM package**(本阶段);引擎为 library target | Phase 2 只需引擎,SPM 最轻;App 以后作 Xcode 工程依赖此包,或加 app target |
| 引擎数据 | Mozc TSV 打包为资源,`Bundle.module` 加载 | 原样借用 + 清晰署名,免手抄出错 |
| 持久化(以后) | SwiftData 或 Codable JSON,封 `ReviewStore` 协议 | 可换 |

### 目录结构(本阶段)

```
typing_app/
├─ Package.swift
├─ README.md
├─ NOTICE / THIRD_PARTY_LICENSES.md      # Mozc BSD-3 等署名
├─ .gitignore
├─ docs/
│  ├─ RESEARCH.md
│  └─ PLAN.md
├─ Sources/
│  └─ RomajiKana/
│     ├─ RomajiKanaTable.swift           # 解析 Mozc TSV → producers 索引
│     ├─ KanaInputMatcher.swift          # 表驱动 NFA 逐键匹配
│     ├─ KanaRomanizer.swift             # 假名→罗马字提示
│     └─ Resources/
│        └─ romaji-hiragana.tsv          # Mozc 原始表(BSD-3)
└─ Tests/
   └─ RomajiKanaTests/
      ├─ MultiPathTests.swift            # A
      ├─ YouonTests.swift                # B
      ├─ SokuonTests.swift               # C
      ├─ HatsuonTests.swift              # D
      ├─ ChoonTests.swift                # E
      ├─ IntegrationTests.swift          # F、G
      └─ RomanizerTests.swift            # H
```
> App / VocabKit / ReviewKit / GameSession 目录在引擎报告后再加。

---

## 6. 里程碑

| 里程碑 | 内容 | 范围 |
|--------|------|------|
| **M0 研究** ✅ | RESEARCH.md | 完成 |
| **M1 计划** ✅ | PLAN.md | 完成 |
| **M2 引擎(本次)** | RomajiKana:表 + 匹配器 + 提示 + 全测试矩阵绿;**完成后停下汇报** | **MVP** |
| M3 词库 | VocabKit:N5 词库(JMdict_e+Tanos)管线、模型、加载查询 | MVP |
| M4 复习 | ReviewKit:SM-2、错词队列、持久化 | MVP |
| M5 输入 UI | KeyCaptureView(旁路 IME)+ 词卡 + 提示(可关) | MVP |
| M6 游戏循环 | GameSession:出词/计分/连击/时间,混合新词与到期复习 | MVP |
| M7 骑行模式 | 环游日本路线 + 景点解锁 + 结算 | MVP |
| 之后 | 片假名 / 动词变位 / 长句 / 排名 / N4–N1 / 云同步 / 传送带皮肤 | 以后 |

**MVP 完成线 = M2–M7。** 本次只交付 **M2**。

---

## 7. 开放问题(已拍板)

1. **释义默认语言:** ✅ 多语言——`meanings` 按语言码存(`en`/`zh`/…),菜单可切 English / 中文,默认英文带回退。
2. **App 最低 macOS:** ✅ **macOS 14**(引擎不受影响)。
3. **产品/包名:** ✅ 定名 **Nihongo Ride**(App 图标由产品方提供,见 `design/`)。SPM 包名 `NihongoRide`,App target `NihongoRideApp`,引擎模块 `RomajiKana`。原名 "Nihongo Dash" 因 Marduk Corp 的 prior use 改名,见 `TRADEMARK.md`。
