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

- **已完成(MVP 纵切):** 引擎、N5 词库(**202 词**,中英双语)、SM-2 复习、游戏循环、骑行 UI。
- **下一步:** N5 全量词库导入管线(JMdict_e + Tanos,见 RESEARCH §4)、例句(Tatoeba)、设置/复习专屏、骑行视觉打磨、音效。
- **以后:** 片假名、动词变位、长句、排名、N4–N1、云同步、传送带皮肤。

## 数据与许可

引擎罗马字表源自 **Google Mozc**(BSD-3)。当前 202 词的 N5 词库为**原创/LLM 起草并经人工校验的中英释义**(读音逐条经引擎校验为可打)——选这条路是因为**不存在干净可商用的「日→中」开放词典**(JMdict 几乎无中文、Wiktionary/JMdict-zh 为 CC BY-SA copyleft;LLM 原创短释义可商用且无 copyleft,见 RESEARCH §4)。全量词库的读音/英文/分级仍可用 JMdict(CC BY-SA 4.0)+ Tanos JLPT(CC BY),中文维持原创/校验路线。商用前建议请母语者过一遍。见 [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) 与 [`docs/RESEARCH.md`](docs/RESEARCH.md) §4。
