# v1.6 开工 Prompt(发给新 session)

> 复制下面整段发给新会话即可。本文件本身只是存档。

---

你接手 Nihongo Ride(にほんご ライド)的 **v1.6** 开发 —— 一个 macOS+iOS 的 SwiftUI 日语打字练习 app(Swift 6 strict concurrency,SwiftPM 库模块 + app target,CloudKit/CKSyncEngine 手动模式私有同步,Game Center),已上架 App Store。工作目录 `/Users/jason/Documents/typing_app`。

**工作方式(重要):**
- 用中文交流。
- 你有完全自主开发权(Jason:「你全权负责」)。代码层面没问题就推进,小步 commit,每次 commit 后 push 到私有 remote `github.com/JasonYeYuhe/nihongo-ride-app`(分支 main)。
- 不要在 Jason 用机时截屏(会抓到他正在用的屏);headless ImageRenderer 渲染才安全。
- 仓库是事实源;深层背景在自动记忆 `/Users/jason/.claude/projects/-Users-jason-Documents-typing-app/memory/project-nihongo-ride.md`。

**开工前先读两份:** ① `docs/PLAN-V1.6.md`(v1.6 计划,已过 codex 外部 review 修订,是本期事实源)② 上面那个自动记忆文件。

**当前状态(2026-06-25):** v1.5(自定义词单 + 引导 + VoiceOver)双端 **WAITING_FOR_REVIEW**;1.4.1 已 READY_FOR_SALE。v1.5 代码全部完成。**一次只能一个版本在审——v1.5 上架后才能提 1.6**(v1.6 开发现在就能开始)。

**v1.6 范围 = 动词变形 MVP**:把 v1.5 已写好、golden 全绿但**接进 app 为零**的 `ConjugationKit` 引擎,落成一个可玩的变形练习模式(B1 数据派生 `vc` + B3 `GameMode.conjugation`,**不写 SRS**,只收引擎能无歧义处理的类)。**明确不做(留 1.7+)**:Dynamic Type、变形 SRS、双设备同步验证、TTS/句子模式/弱词训练/分享卡/widget/统计图。

**第一步(Gate-0,并行两轨,决定 B 能否进 1.6):**
1. **JMdict 测量**:下载 `JMdict_e`(EDRDG,CC-BY-SA),`python3 scripts/enrich_verb_classes.py --jmdict <path>`,按 JLPT 报覆盖 + 残留歧义-る 计数。(无 dump 实测:N5–N3 67.1% 含 heuristic-suru,**240 个 る 需 JMdict**;直方图 suru=1225 多为 suru-noun 被一锅端。)
2. **修引擎 bug + 内存分类器 golden**:`Conjugator.suruForm`(:147)对所有 `.suru` 一律「去 する+できる」,把 `察する` 错出 `さっできる`(`ConjugatorTests:96-97` 把这钉成 golden)。修 = **数据派生层不给裸 suru-verb 打 `vc`**(`察する` 是 `pos:["v"]`,只看 する 结尾会误标)+ 题池排除 + 改/删错误 golden;建 ~50 个 N5–N3 核心动词的**内存分类器 golden**。

**闸**:两层 golden 全绿 —— (i) 内存分类器(Gate-0)+ (ii) 派生数据端到端核心集 100% + 守恒不变量;池薄就**只出 N5–N3**(优雅降级,菜单按池大小 gate)。过闸才进 1.6;否则 B 留继续打磨,本期改出**弱词训练**备选(纯复用 `GameSession.makeSaved` + `ReviewStore.weakestCards`)。

**绝对红线(违反会丢数据/被拒):**
1. 绝不在 CKSyncEngine 的 delegate 回调里驱动引擎;enqueue 一律 `recordLocalChanges→scheduleSync`(Task hop);`nextRecordZoneChangeBatch` 按值快照 + CKRecord 深拷贝。
2. 所有文件写:同步、主 actor、`options:.atomic`(不可 Task.detached 写盘)。
3. **Practice 永不写 SRS;变形 MVP 不写 SRS**。⚠️ `GameSession` 的 `queue/current/lapsed` 全是 `[VocabEntry]` 且 `skip()/complete()` 总调 `review.record` —— **naive 复用就违红线**;必须先做 `GameItem`/prompt 抽象(或独立 `ConjugationSession`),并加「conjugation session 跑完对 `ReviewStore`/`VocabStore` 零写入」测试。**先抽象、后接 UI**。
4. 非游戏屏抑制软键盘;**游戏屏(含变形)必须复用 `.playing` 路径自动召唤键盘 + isTouchDevice 触屏 HUD**(否则 iOS 键盘不出 = 2.1a 被拒)。
5. **kana 全局唯一**(派生重写 JSON **后**再跑 `VocabKitTests.swift:83-85` 守恒);**变形输出临时、绝不持久化为 VocabEntry / 不入 VocabStore**。
6. `vc` 存 **raw String**(= `VerbClass.rawValue`;`VerbClass` 本就 String-backed,当前依赖图**无 VocabKit→ConjugationKit 环**,别为臆想的环改存 Int);`vc → VerbClass` 映射放 **GameCore**;VocabKit 不 import CK。
7. **ConjugationKit 经 GameCore 接入**(Package.swift 给 GameCore target 加 CK dep;app 不直接 import → **project.yml 不用改**,CK 随 GameCore 传递链接)。若最终 app 直接 import CK,则 **Package.swift + project.yml 两处都要加**(v1.5 WordListsKit 就是两处)。
8. 构建号每平台严格递增:当前 macOS=8 / iOS=9;v1.6 用 **macOS≥9 / iOS≥10**。
9. xcodegen 版本字面量坑:project.yml 里 `CFBundleShortVersionString:$(MARKETING_VERSION)` / `CFBundleVersion:$(CURRENT_PROJECT_VERSION)` 必须显式引用 build setting。
10. JMdict 只取「动词类」事实 + EDRDG 归属(CC-BY-SA,与 `vc` 派生**同一 commit** 落 AboutView 的 `credit(...)`),只 ship 派生的类标签,绝不搬 JMdict 文本。

**⚠️ 构建关键坑(会复发,务必照做):** repo 在 `~/Documents` 下,macOS Sequoia 给文件打 `com.apple.provenance` xattr(`xattr -c`/`-d` 都删不掉)→ Xcode codesign 报「resource fork, Finder information, or similar detritus not allowed」构建失败。**签名构建必须从 `git clone /Users/jason/Documents/typing_app /tmp/nrbuild` 到 /tmp 跑**(`xcodegen generate` + `scripts/build-appstore.sh --upload` / `build-appstore-ios.sh --upload`)。v1.6 可顺带把 build 脚本顶部加 `xattr -rc "$ROOT"` 修复(落地后先验证一次**就地** archive 端到端再信)。

**验证 & 工具:** `swift test` 当前 **154 测试全绿基线不得回归**;发版前务必跑 **Release 本地启动自测**(从 /tmp clone 构签名 app 启动,确认无 CKSyncEngine 启动崩——1.4 栽在此);构建上传 `scripts/build-appstore.sh --upload` 与 `build-appstore-ios.sh --upload`;提交仿 `scripts/submit_1_5.py`(`asc_api.sh`;`--metadata` 建版本+双语 What's New+审核备注,`--submit` attach VALID build+提交)。**发版前对抗 review** 用 Claude 多智能体 Workflow(**并行会撞瞬时服务器限流 → 用串行 for-loop 跑**)或 `codex exec`(注意 `</dev/null` 否则 hang;且 codex 插件的 forwarder agent 不回传,直接 `codex exec` 自己捕获 stdout 更稳)。team `KHMK6Q3L3K`,bundle `com.jasonye.nihongoride`,CloudKit 容器 `iCloud.com.jasonye.nihongoride`(schema 已部署 Production),ASC app id `6777469778`。

**需 Jason 拍板的(再问):** 用哪个 JMdict dump / 许可二次确认(已原则同意用)、B 过不过闸的边界(N2/N1 池薄是否接受只出 N5–N3)、变形第一批形集是否就用 `ConjugationForm.allCases`(ます/て/た/ない/なかった/可能/意志)。

先读 `docs/PLAN-V1.6.md` 和自动记忆,再从 **Gate-0** 推进。需要拍板的再问。开工吧。
