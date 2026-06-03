# 阶段 0:技术研究(RESEARCH)

> 日语打字练习 App(macOS / SwiftUI)。本文给出五个技术选型问题的**结论 → 依据 → 决策 → 来源**。
> 调研日期:2026-06-03。本机环境:Swift 6.3.2 / Xcode 26.5 / macOS 26(arm64)。

## TL;DR 决策表

| # | 问题 | 决策 |
|---|------|------|
| 1 | 捕获物理键 + 绕过系统 IME | 用 `NSViewRepresentable` 包一个**不实现 `NSTextInputClient`、不调用 `interpretKeyEvents(_:)`** 的自定义 `NSView`,覆写 `keyDown(with:)`,读 `charactersIgnoringModifiers`。这样系统 IME 结构上**根本不参与**。无需辅助功能(Accessibility)权限,沙盒兼容。 |
| 2 | 借现成 Swift 罗马字库? | **自建引擎**(逐键、多路径状态机)。现有 Swift 库(WanaKanaSwift、Kana)全是整段批量转换,无一支持逐键增量 IME 匹配。 |
| 3 | 罗马字映射表来源 | **以 Mozc(Google 日本語入力)`romanji-hiragana.tsv` 为权威数据源**(BSD-3,可商用 + 可再分发),WanaKana(MIT)做交叉校验。已下载,见 `Sources/RomajiKana/Resources/`。 |
| 4 | 词库 + 授权 | **JMdict_e**(CC BY-SA 4.0,明确允许商用)做词义;**Tanos JLPT 列表**(CC BY)做 N5–N1 分级;**Tatoeba**(CC BY 2.0 FR)做例句;难度长尾用 **wordfreq**(CC BY-SA)。全部可商用,义务=署名(+ 对数据本身的 share-alike)。 |
| 5 | SRS 算法 | **简化版 SM-2**:EF 初值 2.5、下限 1.3;I(1)=1d、I(2)=6d、I(n)=round(I(n-1)·EF);q<3 视为遗忘,重置重复计数、回到 1 天。q 由打字表现(首次正确/犹豫/出错/求助)派生,而非手动自评。 |

---

## 1. macOS 物理按键捕获 + 绕过系统 IME

**结论:** 在 macOS 上,系统输入法(IME,如日语「ことえり」)**只通过文本输入管理系统介入**,而一个视图进入该系统的唯一方式是调用 `interpretKeyEvents(_:)` 或实现 `NSTextInputClient`。**只要我们都不做**,自定义 `NSView` 的 `keyDown(with:)` 就会直接拿到原始 `NSEvent`,无论当前系统输入源是不是日语 IME——IME 在结构上被旁路了。

**关键事件流:**
```
按键 → NSApp(键盘等价 / 界面控制)→ key NSWindow → firstResponder.keyDown(with: NSEvent)
        ├─ 若你调用 interpretKeyEvents: → 文本输入管理 → IME(汉字转换)→ insertText:/doCommandBySelector:
        └─ 若你不调用             → 原始 ASCII 归你,喂给自己的罗马字状态机
```
Apple 文档原文:文本输入管理系统「allows key events to be interpreted as text not directly available on the keyboard, such as Kanji」——这正是我们要避开的。终端模拟器(Terminal、Ghostty)、游戏(读 `charactersIgnoringModifiers`)、SDL/GLFW 都用同样手法:把"原始按键"与"IME 合成文本"当成两条独立通道。

**字符读取:** 用 `charactersIgnoringModifiers`(忽略除 Shift 外的修饰键;死键如 Option-e 仍返回 `"e"`,而 `characters` 在死键时返回空串)。**统一转小写**(已知坑:keyDown 看到 `"a"`,配合 Shift 的 keyUp 可能看到 `"A"`)。控制键(Return/Space/Backspace/Esc/方向键)用 `keyCode` 兜底。我们自己不进入输入管理系统,所以 macOS 自带的死键合成不会触发——`'` `^` 等按字面标点处理,正合罗马字所需。

**权限:** 焦点窗口内的 `keyDown` 覆写或 `addLocalMonitorForEvents` **不需要**辅助功能权限、沙盒友好。只有 `addGlobalMonitorForEvents` / `CGEventTap` 才需要(我们用不到,避免)。

**推荐架构:** `NSViewRepresentable` 包自定义 `NSView`(`acceptsFirstResponder = true`,出现时 `makeFirstResponder`,覆写 `keyDown`/`keyUp`,**不碰 NSTextInputClient/interpretKeyEvents**)。可选用 `addLocalMonitorForEvents(matching: .keyDown)` 作补充(同样旁路 IME、无需权限)。不用 SwiftUI `.onKeyPress` 作根基(无 `keyCode`、IME 行为 Apple 未明文、有已知缺口),不用全局监听/CGEventTap(会触发权限弹窗)。

**来源:**
- Apple, *Handling Key Events* — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html
- Apple, `charactersIgnoringModifiers` — https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers
- Apple, `addLocalMonitorForEvents` — https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:) ;`addGlobalMonitorForEvents`(需辅助功能)— https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
- keyDown in SwiftUI/macOS — https://onmyway133.com/posts/how-to-handle-keydown-in-swiftui-for-macos/ ;macOS 游戏键盘输入 — https://blog.bitbebop.com/macos-game-keyboard-input/
- Ghostty 绕过 interpretKeyEvents 讨论 — https://github.com/ghostty-org/ghostty/discussions/2934
- 沙盒/权限确认 — https://developer.apple.com/forums/thread/707680

---

## 2. 现成 Swift 罗马字↔假名库:Build vs Borrow

**结论:自建引擎,只借映射表。** 我们要的是**逐键、增量、多路径**的 IME 式匹配(し 接受 shi/si/ci;っ 接受辅音双写或 xtu/ltu;ん 接受 n/nn/n')。市面 Swift 库无一具备此能力——全是整段批量转换。

| 候选 | 许可 | 维护状态 | 增量逐键? | 结论 |
|------|------|---------|-----------|------|
| [profburke/WanaKanaSwift](https://github.com/profburke/WanaKanaSwift) | Swift 部分 BSD-3 / 内嵌 wanakana.js MIT | 停滞(末次提交 2021-01) | ❌ 仅整段(且包了 JS 运行时,实时游戏不宜) | 不用 |
| [mcvnh/Kana](https://github.com/mcvnh/Kana) | MIT | 停滞(2022-04) | ❌ 仅批量转换 | 不用 |
| [shinjukunian/Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift) | — | — | 形态分析/读音,工具不对口 | 不用 |

引擎本体 = **trie/前缀匹配 + pending 缓冲的确定状态机**,几百行 Swift;真正的难点是**数据**(所有异拼、促音、ん 边界),而那正是该借的。**这与产品诉求一致:引擎是最该自控、复用价值最高的核心。**

**来源:** 上表各仓库;WanaKana JS 原库 — https://github.com/WaniKani/WanaKana

---

## 3. 罗马字映射表的权威来源(IME 风格、多路径)

**结论:以 Mozc(Google 日本語入力)的 `romanji-hiragana.tsv` 为基准。** 它就是 Google 日语输入法的真实罗马字表,持续维护,且格式天然契合逐键状态机。

- **文件:** https://github.com/google/mozc/blob/master/src/data/preedit/romanji-hiragana.tsv (raw: `https://raw.githubusercontent.com/google/mozc/master/src/data/preedit/romanji-hiragana.tsv`)
- **许可:** **BSD-3-Clause**(顶层 `LICENSE`,Copyright 2010-2018 Google Inc.;`preedit/` 目录下无单独 license)。**明确允许商用 + 再分发**,义务=保留版权声明与免责声明。(注:Mozc 中更严格的 NAIST/IPADIC 词典许可只约束 `dictionary_oss/`,与本罗马字表无关。)
- **格式(已下载验证,323 行):** `romaji <TAB> kana [<TAB> pending]`。两列=普通映射;三列=带 **pending(待定残留)**,即状态机转移:
  - 促音双写:`kk → っ + k`、`ss → っ + s`、`tt → っ + t`、`tch → っ + ch`……第三列残留辅音再喂给下一键。
  - 多路径俱全:`shi/si/ci → し`、`sha/sya → しゃ`、`n / nn / n' / xn → ん`、`xtu/ltu/xtsu/ltsu → っ`、`tsu/tu → つ`、`chi/ti → ち`、`fu/hu → ふ`、`ji/zi → じ`、`ja/zya/jya → じゃ`、`cha/tya/cya → ちゃ`。

  **这张表本质就是序列化的状态机转移表**,我们近乎原样借用并附署名。

**交叉校验:** WanaKana 的 [`romajiToKanaMap.js`](https://github.com/WaniKani/WanaKana/blob/master/src/utils/romajiToKanaMap.js)(MIT)用嵌套 trie(`tree['k']['a'][''] === 'か'`)+ 递归 `addTsu` 程序化生成促音,设计思路可直接借鉴。

**决策:** 把 Mozc 的 TSV 原样打包进引擎资源(`Bundle.module`),运行时解析为匹配用的数据结构;`NOTICE`/`THIRD_PARTY_LICENSES.md` 附 BSD-3 声明。

---

## 4. 词库与授权(可合法商用)

**结论:JMdict_e + Tanos JLPT + Tatoeba(+ wordfreq 长尾),全部可商用,核心义务是署名。** 两个「坑」:JMdict 与 wordfreq 带 **share-alike**(只约束数据本身,不传染 App 代码);**勿用** BCCWJ 频表(仅限研究/教育)与来路不明的 Kaggle/爬取 JLPT 表。

| 层 | 用途 | 数据源 | 许可 | 义务 |
|----|------|--------|------|------|
| 词条 + 词义 | 假名、读音、英文释义、词性 | **JMdict_e**(`ftp.edrdg.org/pub/Nihongo/JMdict_e.gz`)、KANJIDIC2 | **CC BY-SA 4.0** | 在「关于/致谢」页署名 EDRDG/Jim Breen + 链接;**派生的词典数据**需保持 CC BY-SA 可分发(不波及 App 私有代码) |
| JLPT 分级 | N5–N1 标签 | **Tanos / Jonathan Waller**(tanos.co.uk/jlpt),按词头+读音 join 到 JMdict | **CC BY** | 署名 tanos.co.uk + 链接 |
| 例句 | 日文例句 + 英译 | **Tatoeba** 批量导出(`sentences.csv`+`links.csv`,筛 jpn/eng) | **CC BY 2.0 FR**(部分 CC0) | 署名 Tatoeba;跳过/核查带 NC 的音频 |
| 难度长尾(可选) | JLPT 表外词排序 | **wordfreq**(rspeer) | 数据 CC BY-SA 4.0 / 代码 Apache 2.0 | 署名;派生频率数据保持可分发。注:2021 后冻结("sunset") |

**关键事实:**
- **JMdict 明确允许商用**:EDRDG 许可页原文「there is NO restriction placed on commercial use of the files... Software using these files does not have to be under any form of open-source licence.」
- **JLPT 官方词表 2010 改版后停发**(JEES/国际交流基金,理由是测试目标是交际能力而非背词表);市面所有分级均为非官方重建。**Tanos 是事实标准**且明确 CC BY——连 Jisho.org 的 JLPT 标签都来自 Tanos。
- 累计规模(非官方,粗估):N5≈800、N4≈1500、N3≈3700、N2≈6000、N1≈10000 词。

**MVP 数据计划:** 取 N5 子集——以 Tanos N5 词头为种子,join JMdict_e 取读音+英文释义,可选挂 1 条 Tatoeba 例句。可商用、署名即可。

**致谢区文案(可直接用):**
- *Dictionary data: JMdict / KANJIDIC2, © James William Breen & EDRDG, CC BY-SA 4.0 — edrdg.org*
- *JLPT level data: based on Jonathan Waller's JLPT Resources (tanos.co.uk), CC BY*
- *Example sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR*

**来源:** EDRDG 许可 — https://www.edrdg.org/edrdg/licence.html ;JMdict 项目 — https://www.edrdg.org/wiki/JMdict-EDICT_Dictionary_Project.html ;JLPT 停发官方表 — https://www.jlpt.jp/sp/e/faq/ ;Tanos 共享条款 — https://www.tanos.co.uk/jlpt/sharing/ ;Jisho 数据出处 — https://jisho.org/about ;Tatoeba 下载/条款 — https://tatoeba.org/en/downloads 、https://tatoeba.org/en/terms_of_use ;wordfreq — https://github.com/rspeer/wordfreq ;BCCWJ(勿商用)— https://clrd.ninjal.ac.jp/bccwj/en/freq-list.html

---

## 5. SRS:简化版 SM-2

**结论:用经典 SM-2 的参数,但把质量分 q 从打字表现派生(而非手动自评)。**

**经典 SM-2(已对原始描述核对):**
- **EF(易度因子):** 初值 **2.5**,下限 **1.3**(`if EF < 1.3 then EF = 1.3`,只钳下限,可超 2.5)。
- **EF 更新:** `EF' = EF + (0.1 − (5−q)·(0.08 + (5−q)·0.02))`(已逐字核对原文)。
- **间隔:** `I(1)=1d`、`I(2)=6d`、`n>2: I(n)=round(I(n−1)·EF)`。
- **遗忘(q<3):** 重复计数归零、从 I(1)=1d 重学;**原始 SM-2 在遗忘时不改 EF**(只有 q≥3 才更新 EF)。多数"SM-2"实现会在遗忘时也罚 EF——那是偏离原版。**本项目采用原版的宽容行为**(派生 q 噪声大,宽容更合理)。

**派生质量分 q(打字遥测 → 0–5):**

| 表现 | q | 判据 |
|------|---|------|
| 完美且快 | 5 | 首次正确、无退格、用时 ≤ 个人中位 |
| 正确但犹豫 | 4 | 首次正确、无退格,但慢(>1.5–2× 中位) |
| 出错后纠正 | 3 | 最终正确、≥1 次退格/纠正、未求助 |
| 需揭示答案 | 2 | 用了提示/揭示,或首次整体错但识得 |
| 多次错 | 1 | 揭示前多次错 |
| 放弃/空白 | 0 | 跳过或无有效尝试 |

界线 **q≥3 通过、q<3 遗忘**,与 SM-2 一致。速度按**个人滚动基线**(该长度的 CPM 中位)归一。

**参数:** EF 初 2.5、下限 1.3(可选软上限 ~3.0 防快手间隔爆炸);I(1)=1、I(2)=6(MVP 不改);遗忘=q<3,重置 repetitions、回 1 天,可加一次同场次 10 分钟再现(Anki 式 learning step);每日上限新词 ~10–20 / 复习 ~100–200(可调);连续遗忘 ≥6–8 次标记为 leech。

**与 Anki 区别(参考,不实现):** Anki 用百分比 ease(默认 250%)、Again/Hard/Good/Easy 四键、learning steps(默认 `1m 10m`)、毕业间隔 1d、Easy 4d、lapse 用 relearning。**FSRS** 是现代继任者(基于 难度/稳定性/可提取性,省 ~15–20% 复习量)——**MVP 不用**,但数据模型留余地以后可换。

**Swift 数据结构(MVP):**
```swift
struct SRSCard: Codable {
    var easeFactor: Double = 2.5
    var interval: Int = 0          // 天
    var repetitions: Int = 0
    var dueDate: Date
    var lapses: Int = 0
    // review(quality:) 按上文公式;复习队列 = dueDate <= today,按 dueDate 排序、限每日上限
}
```

**来源:** SM-2 原始算法 — https://www.supermemo.com/en/archives1990-2015/english/ol/sm2 ;Anki 算法 — https://faqs.ankiweb.net/what-spaced-repetition-algorithm.html 、https://docs.ankiweb.net/deck-options.html ;FSRS — https://github.com/open-spaced-repetition/fsrs4anki

---

## 附:许可证义务速查

| 数据/代码 | 许可 | 商用 | 再分发义务 |
|-----------|------|------|-----------|
| Mozc 罗马字表 | BSD-3 | ✅ | 保留版权 + 免责声明 |
| WanaKana(参考) | MIT | ✅ | 保留版权 |
| JMdict / KANJIDIC2 | CC BY-SA 4.0 | ✅ | 署名 + 派生数据 share-alike |
| Tanos JLPT | CC BY | ✅ | 署名 |
| Tatoeba | CC BY 2.0 FR | ✅ | 署名 |
| wordfreq 数据 | CC BY-SA 4.0 | ✅ | 署名 + share-alike |
| BCCWJ 频表 | 研究/教育限定 | ❌ | **不可用于商用 App** |

> share-alike 只约束**被许可的数据本身**(及其修改),**不强制 App 源码开源**。实践上:把这些数据以"可按原许可再分发"的形式保存,别与私有逻辑熔成不可分发的黑盒。
