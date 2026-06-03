# 日语打字练习 App(工作名:TypingApp)

给**外国日语学习者**(JLPT N5–N1)用的 macOS 打字练习 App——「像寿司打一样好玩,但真正帮你学会」。边打边给**假名 + 罗马字提示(可关)+ 词义**,打错的词进 **SRS 复习队列**;MVP 主玩法是「打字环游日本」(打对就前进、解锁经典景点)。

> macOS / SwiftUI 原生,物理键盘场景。我们自己当**迷你 IME**:逐键、多路径匹配的罗马字状态机,**不走系统 IME**。

## 当前状态

- ✅ **阶段 0 研究** → [`docs/RESEARCH.md`](docs/RESEARCH.md)
- ✅ **阶段 1 计划** → [`docs/PLAN.md`](docs/PLAN.md)
- 🟢 **阶段 2:罗马字引擎(`RomajiKana`)** —— 本仓库当前内容。纯 Swift、零 UI 依赖、TDD。
- ⏭️ 之后:词库(VocabKit)→ 复习(ReviewKit)→ 输入 UI → 游戏循环 → 骑行模式。

## 模块:`RomajiKana`(引擎)

逐键、多路径、**目标感知**的假名打字匹配状态机:

- `KanaInputMatcher(target:)` —— 给定目标假名串(如 `"がっこう"`),逐键喂入罗马字,实时返回 `accepted / rejected / completed`,并给出"下一键可以是哪些"与进度。
- `KanaRomanizer.romaji(for:)` —— 生成 Hepburn 风罗马字提示(如 `がっこう → "gakkou"`、`れんあい → "ren'ai"`)。
- 多路径(`shi/si/ci`)、促音 `っ`(辅音双写 / `xtu`/`ltu` / `tch`)、撥音 `ん`(`n/nn/n'/xn`)、拗音、長音全覆盖。
- 引擎采用**表驱动 NFA**:把"通往目标的所有合法罗马字路径"编译成字符级状态图,逐键过滤可达状态。详见 [`docs/PLAN.md`](docs/PLAN.md) §4。

## 构建与测试

```sh
swift build
swift test
```

需要 Swift 6 工具链(开发于 Swift 6.3 / Xcode 26)。测试用 **Swift Testing**。

## 目录

```
Sources/RomajiKana/      引擎(table / matcher / romanizer + Mozc 数据资源)
Tests/RomajiKanaTests/   边界用例测试矩阵
docs/                    RESEARCH.md / PLAN.md
THIRD_PARTY_LICENSES.md  第三方数据/代码署名(Mozc 等)
```

## 数据与许可

引擎的罗马字映射表源自 **Google Mozc**(BSD-3-Clause)。词库以后用 JMdict(CC BY-SA 4.0)、JLPT 分级用 Tanos(CC BY)、例句用 Tatoeba(CC BY 2.0 FR)——均可商用,义务为署名。详见 [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) 与 [`docs/RESEARCH.md`](docs/RESEARCH.md) §4。
