# Nihongo Dash(にほんご ダッシュ)

> 「**Dash**」系列打字学习游戏的日语版:给**外国日语学习者**(JLPT N5–N1)用的 macOS 打字练习 App——「像寿司打一样好玩,但真正帮你学会」。
> 边打边给**假名 + 罗马字提示(可关)+ 词义(中/英,可扩展)**,打错的词进 **SRS 复习队列**;主玩法「**打字环游日本**」:打对就前进、解锁经典景点。
> macOS / SwiftUI 原生,物理键盘。我们自己当**迷你 IME**:逐键、多路径匹配,不走系统 IME。
> App 图标(系列:日/中/法/西/韩,本作用日本 え)见 [`design/`](design/)。

> ⚠️ 商用前就「Nihongo Dash」做一次商标检索。

## 当前状态(MVP 纵切已打通)

- ✅ 阶段 0 研究 → [`docs/RESEARCH.md`](docs/RESEARCH.md)
- ✅ 阶段 1 计划 → [`docs/PLAN.md`](docs/PLAN.md)
- ✅ 罗马字引擎 + 词库 + SRS + 游戏循环 + SwiftUI App,**全部编译通过、逻辑层 43 个测试全绿**。

## 运行 / 测试

```sh
swift test            # 43 tests / 12 suites（引擎/词库/SM-2/游戏循环）
swift run NihongoDashApp  # 启动游戏窗口（会抢占焦点以打开窗口,SPM 运行的 GUI 特性)
```

需要 Swift 6 工具链(开发于 Swift 6.3 / Xcode 26,最低 macOS 14)。
> 注:`swift run` 出的是开发用可执行档,不含 App 图标/签名。**正式打包(图标、签名、上架)用 Xcode 工程包一层**,依赖本仓库的 SPM 模块即可。App 图标由产品方提供。

## 架构(模块)

| 模块 | 职责 | 依赖 | 测试 |
|------|------|------|------|
| **RomajiKana** | 引擎:逐键、多路径、目标感知的假名打字匹配(表驱动 NFA)+ Hepburn 提示生成 | — | 16 |
| **VocabKit** | 词条模型(多语言释义 / JLPT / 难度)+ N5 词库加载 | RomajiKana | 8 |
| **ReviewKit** | 简化版 SM-2 间隔复习 + 错词队列 + 持久化 | — | 11 |
| **GameCore** | 游戏循环:出词(新词+到期复习)、计分/连击、骑行进度、记录 SRS | 上面三个 | 8 |
| **NihongoDashApp** | SwiftUI App:`KeyCaptureView`(绕过 IME)+ 骑行/词卡/HUD/结算 + App 图标 | 全部 | — |

数据流:`KeyCaptureView` 抓原始按键 → `GameSession.input(_:)` → `KanaInputMatcher` 判定 → 完成时 `ReviewStore` 按 SM-2 记账 → UI 观察 `@Observable` 状态刷新。

## 多语言

词义按语言码存储(`meanings: ["en": [...], "zh": [...]]`),菜单可切 **English / 中文**,默认值与回退已内建,后续加语言只需补数据。

## 路线图

- **已完成(MVP 纵切):** 引擎(含**片假名**)、**N5–N1 词库(3994 词,跨 5 级,中英双语)**、**N5–N1 例句(各 120,中/英)**、SM-2 复习、游戏循环、**等级选择**、骑行 UI(**骑手动画 + 音效**)。
- **下一步:** 继续扩充各级词库到全量(同一套流水线)、补足覆盖均衡度、母语者终审现有释义、例句扩到更多词、Tatoeba 例句。
- **以后:** 动词变位、长句、排名、云同步、传送带皮肤、iCloud。

## 数据与许可

引擎罗马字表源自 **Google Mozc**(BSD-3)。当前 **3994 词**(N5–N1,`Resources/n{5..1}.json`;含约 450 片假名外来词),中英双语,N5–N1 各含 120 条例句(共 600,中/英)。**读音/等级来源:** `n5-xxx` 由我手写并审过;`*-g*` 词条由 Gemini 3.1 Pro 生成(读音经机器校验 + 两轮独立 Gemini 审核,0 报错);`*-b*` 词条的**词形/读音/等级取自 Bluskyo(MIT,Tanos CC BY 衍生),读音权威**、释义由 LLM 生成。**释义(中/英)均为原创/LLM**——选此路因为**没有干净可商用的「日→中」开放词典**(JMdict 无中文、Wiktionary/JMdict-zh 为 CC BY-SA copyleft;见 RESEARCH §4)。仍有「LLM 参与」,⚠️ 商用前请母语者终审。片假名外来词(`*-k*`)现已支持(引擎归一化 + 罗马字外来音 digraph)。署名见 [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md),细节见 [`docs/RESEARCH.md`](docs/RESEARCH.md) §4。
