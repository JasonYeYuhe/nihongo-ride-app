接手 Nihongo Ride 的 v1.26 开发。项目在 `/Users/jason/Documents/typing_app`,macOS + iOS 双端日语打字练习 app,v1.25 已于 2026-08-24 双端上架。**用中文跟我交流,代码里的标识符和注释用英文。**

**你有完整的构建和发布权限**——从改代码、跑测试、构建归档,到上传 ASC 并提交审核,不用每一步问我。判断可以发就发。

---

## 动手前先读这三份,顺序别换

1. `docs/PLAN-V1.26.md` —— 这个版本要做什么,以及每个结论是怎么量出来的。**它已经过三家外部评审**(Codex、Gemini 3.1 Pro、Gemini 3.7 Flash),评审意见已经吸收进正文,包括一条被推翻的候选项(B2)和几条被修正的数字。
2. `docs/STATE-2026-08-18.md` —— 项目现状、语料、流水线,以及「已经付过学费的陷阱」那一节。411 行,别跳读。
3. `docs/PLAN-V1.25.md` —— 上一个版本,尤其是末尾的 `# Shipped`。

按 **§A → §B → §D → 发布加固** 的顺序做。**§C 和 §E 都已经砍掉**,不要碰——理由写在计划里,不是因为不重要,而是因为诚实的修法都超出了这个版本的范围。

## 三条硬约束,做 §A 之前先记住

1. **听写讲的是 `exJP` 汉字句,不是 `exKana`。**(`GameView.swift:194`,注释里写了原因:Kyoko 会把裸假名的 は 念成 "ha"。)所以**改 `exKana` 不改变学习者听到的声音**——只会让答案和音频对不上。§A 的三条修正必须逐条测音频,凡是语音仍念旧读音的,在同一次改动里把它排除出听写。漏了这一步,§A 会让听写学习者的体验变差,而不是变好。
2. **`swift test` 跑不了 UI 测试。** `Tests/NihongoRideiOSUITests/` 有三个文件,要 `xcodebuild test` 才跑。仓库里说的「520 个测试」不包含它们。§D 就是扩展其中一个既有的流程测试,不要另起炉灶。
3. **扩展那个 UI 测试之前,先把它隔离。** 它启动的是正常 app 并跑完一次真实 run,会写 SRS、日志和里程表,而 CloudKit 同步是开着的。先加一个 DEBUG 的 UI-test 模式关掉同步并重定向所有 store。这是 v1.24 那次小组件事故的放大版——那次只写坏了本地 App Group,这次能把幽灵骑行推进机主真实的 CloudKit 库。

---

## 这个项目最贵的一条方法论,它同时是 v1.26 的主题

> **一个报「没发现问题」的检查器,在它被证明能对已知阳性样本报警之前,和一个坏掉的检查器无法区分。**

三条推论,每一条都是拿版本换来的:

1. **闸门和它守护的东西会共享盲区。** v1.25 的读音闸门抓到 21 条、双向校准过、可以被 mutation 弄红——它仍然漏掉了 240 个词条,因为它只匹配单 token。修好之后,又因为「抓到 26 条」被当成验证过了,再漏 106 条。
2. **一个用「它抓到了什么」来验证的闸门,等于没验证。** 要算的是**它没检查的那部分集合**,并且抽样看。v1.26 §A 就是把这个问题第三次问出来的结果:874 句现有闸门根本看不见,其中 3 句教错了读音。
3. **在一个语料上校准过,不代表在另一个上成立。**

这条同样适用于**你自己写的测试**:**新测试必须先被证明会变红,才能相信它。** 一个从没红过的测试不是证据。v1.26 的 stop rule 里逐条写了每个新测试该怎么弄红。

还有一条 v1.26 新增的,写在计划开头:

> **对谓词的单元测试,不是对使用它的屏幕的测试。**

`ConjugationSRSCard.quality` 的单元测试自己喂 `durationRatio`,而生产代码从不喂——所以评分逻辑最后一行是个常量(§C)。`GameMode.lapsesAreWords` 被测得很好,但它的全部消费者都在 `ResultsView` 里,而整个测试套件不提这个文件(§D)。两边都是诚实的绿色,两边都没有证明学习者看到了什么。

---

## 语料数据的红线

- `id` / `surface` / `kana` / `jlpt` / `vc` **冻结**。`SRSCard.id` 就是 `VocabEntry.id`,改 kana 等于在保留学习者进度的同时偷换答案。
- 释义只能追加,例句 write-once。
- 结构性改动必须走 `scripts/check_vocab_diff.py --manifest`,**永远不要靠关掉守卫来通过**。带 manifest 时它更严格,不是更宽松:manifest 没预测到的改动会失败,manifest 承诺了却没发生的改动也会失败。
- 注意一个已知弱点:`load_manifest` 会静默去重同 id 的声明(v1.25 声明 71 条,实际 69 个唯一 id)。§A 只有三条,影响不到,但别依赖它。

## 构建与发布

- **不要手搓 `xcodebuild`。** `~/Documents` 下的文件带 `com.apple.provenance` 扩展属性,codesign 会拒签。构建脚本会先 rsync 到干净的临时副本。用 `scripts/build-appstore.sh` 和 `scripts/build-appstore-ios.sh --upload`。
- **文案里不能出现 ★ 字形。**(app 内的 UI 字符串不受此限,里面本来就有。)
- 两个平台的构建号**分别递增**:macOS 47 → 48,iOS 48 → 49。**不要用链式字符串替换**——v1.25 用 `"46"→"47"` 再 `"47"→"48"`,结果两端都变成 48,那是会被拒的。按目标定位,逐个改,改完程序化交叉核对 `project.yml`(它有 8 处版本号)和提交脚本(3 处)。
- `scripts/submit_1_25.py` 是当前模板(先 `--metadata` 后 `--submit`)。已知缺陷:它的 `submittable()` 遇到不认识的版本状态会友好跳过并返回 0,**所以一次什么都没提交的运行看起来和干净运行一样**。照抄的时候把这个修掉。
- 崩溃闸门:`scripts/launch_gate.sh <archive>/Products/Applications/Nihongo\ Ride.app`。**必须跑在真正上传的那个归档上**——`--upload` 会 `rm -rf` 构建目录并重新归档,旁边那个是不同的二进制。
- **一条命令里用 `&&` 串两个平台会吞掉前一个的失败**(返回的是最后一条的退出码)。分开跑。
- 发布文案里的任何数字都必须从语料现算。v1.25 告诉用户「Fifty more sentences」,真值是 42——那 8 句在文案写完之后被重新排除了,没人回头改。

## 一个当下的环境限制,动手前先确认

**这台机器上没有任何 python 装了 `sudachipy`。** 我实测过 `/usr/bin/python3`、`/opt/homebrew/bin/python3`、anaconda 的 python3,全部 `ModuleNotFoundError`,磁盘上也找不到这个包。

影响范围是七个脚本:`pilot_gate.py`、`gen_sentence_kana.py`、`apply_batch.py`、`check_dictation_readings.py`、`check_example_readings.py`、`check_forces_reading.py`、`gate_calibration.py`。

对 v1.26 的实际后果:

- **§A 的前两条修正不受影响。** 它们是对 `exKana`/`exTokens` 的定点编辑,由 `check_vocab_diff.py --manifest` 把关(不依赖分词器),round-trip 校验就是把 token 拼起来和 `exKana`/`exJP` 比字符串,纯 Python 就够。这两个脚本我实测可以导入。
- **§A 的第三条 `n1-b045` 被卡住**,因为重新测量它的排除证据要用 `check_dictation_readings.py`。要么先把 sudachipy 装上(`pip install sudachipy sudachidict_core`,这属于改机器环境,**装之前问我一声**),要么把 `n1-b045` 挪到下个版本,只做前两条。

顺带一个警示,值得当成方法论看:我这轮调研里,有一个 agent 和它的对抗验证器**都声称跑过 `pilot_gate` 并得到「81 条被拒」**——而那个模块在这台机器上根本 import 不了。这个数字不可能是量出来的。它本来就因为别的理由被否掉了,但请记住:**别人报给你的数字,包括我报给你的,在你自己复现之前都不算数。**

## 其他已知陷阱(完整清单在 STATE 里)

- 给 library target 的 struct 加存储属性后,SPM 增量构建可能残留不一致,表现成**完全无关的测试 SIGSEGV**。先 `rm -rf .build` 再重建,然后才开始怀疑自己的代码。
- 测试里 `try!` 配 `#require` 会终止整个进程,拖垮十几个无关测试。用 `throws` 测试 + 普通 `try #require`。
- **任何构造 `AppModel` 的测试都必须用 `sandboxed(vocab:)`。** v1.24 的第一批 app 层测试把十四天的零写进了机主真实的桌面小组件——`refreshWidgetSnapshot` 写的是 App Group 容器,在 `supportDirectoryOverride` 管辖之外。
- `Sources/` 里会凭空冒出 `ListsView 2.swift` 这种 iCloud/Finder 副本,让构建报重复声明。`.gitignore` 挡不住。构建报了没人写过的重复声明,先找带空格和数字的文件名。
- agent 并行之后查一次 `git worktree list`。残留的 worktree 在仓库内(`.claude/worktrees/`),曾经攒到 1.5 GB。

---

## 什么时候算做完(完整版在计划的 Stop rule 一节)

- `swift test` 全绿,**并且每个新测试都被证明过会红**——§A 的闸门要在把 `n1-g305` 的 `exKana` 改回 もぐって 时变红,§B 的检查要在把 B1 的标签改回去时变红,§C 的测试要在拆掉时序接线时变红,§D 的每条断言要在还原对应的 v1.24/v1.25 修复时变红。
- §A 的总体数字在构建时**重新测量**,不要引用计划里的数字;并且**新闸门自己跳过的总体要算出来并打印**,不能断言它是空的。
- `check_vocab_diff` 在三条 manifest 下干净,它自己的 18 个探针行为正常。
- §A 改动前后 diff 一次听写排除表,任何变化都要解释,不能吸收掉。**`n1-b045` 当前就在排除表里,它的证据记录要重新测量而不是重新盖章**——原因写在 §A 里。
- 没有 `Sources/**/* [0-9]*.swift` 重复文件。
- 发布前的对抗性评审跑过,阻塞项修完。
- `launch_gate.sh` 在真正上传的归档上通过。

---

先把计划读完,然后告诉我你打算怎么开始、以及你打算先验证计划里的哪个数字。**计划里的数字是我量的,不是你量的**——按这个项目的规矩,你应该重新量一遍再动手。
