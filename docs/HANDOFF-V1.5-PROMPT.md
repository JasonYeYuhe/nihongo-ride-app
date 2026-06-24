# v1.5 开发启动 Prompt(粘贴给 fresh session)

> 复制下面分隔线之间的全部内容,发给一个新的 Claude Code 会话(工作目录 `/Users/jason/typing_app`)即可无缝开工。

---

你接手 **Nihongo Ride**(にほんご ライド)的 v1.5 开发 —— 一个 macOS+iOS 的 SwiftUI 日语打字练习 app(Swift 6 strict concurrency,SwiftPM 库模块 + app target,CloudKit/CKSyncEngine 手动模式同步,Game Center),已上架 App Store。

**工作方式(重要):**
- **用中文交流。**
- 你有**完全自主开发权**(Jason:「你全权负责」)。代码层面没问题就推进,小步 commit,**每次 commit 后 push 到私有 remote `github.com/JasonYeYuhe/nihongo-ride-app`**(分支 main)。commit message 末尾加 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- **不要在 Jason 用机时截屏**(ScreenCaptureKit/`screencapture` 会抓到他正在用的屏);headless ImageRenderer 渲染才安全。
- 仓库是事实源。深层背景在自动记忆 `/Users/jason/.claude/projects/-Users-jason-typing-app/memory/project-nihongo-ride.md`(开发史/ASC id/各种坑)。

**开工前先读两份:**
1. `docs/PLAN-V1.5.md` —— v1.5 开发计划(已经过 4 视角对抗 review 修订,是本期的事实源)。
2. 上面那个自动记忆文件 —— 历史与红线。

**当前状态(2026-06-24):**
- v1.4.1(macOS build 7 / iOS build 8)双端 **WAITING_FOR_REVIEW**(修了 macOS 1.4 的 CKSyncEngine 启动崩溃 2.1a)。iOS 1.4 已上架;macOS 1.4 被拒已被 1.4.1 取代。
- **ASC 一次只能一个版本在审 —— 必须等 1.4.1 上架后再提 1.5。** v1.5 开发可以现在就开始(本地),提交等 1.4.1 过。

**v1.5 范围(Jason 选的 1+3+4,review 后定的诚实范围):**
- **A 自定义词单 + C 打磨/验证 = 确定进 1.5。**
- **B 动词变形 = 默认 1.6**;其数据/引擎本期照做,但**只有 B0 数据 spike(JMdict 覆盖率)+ ConjugationKit golden 测试在冻结前达标,才把 B 提进 1.5**。细节见 PLAN-V1.5.md §0/§3。

**第一步(Phase 0,并行起三件):**
1. **B0 数据 spike**(纯测量,先做):写 `scripts/enrich_verb_classes.py`(走 JMdict + kana 启发式,**不依赖死掉的 gemini/agy**),按 JLPT **拆来源**报告动词类覆盖(精确标签 / 启发式无歧义 / **JMdict 解出** / 未解出)。关键事实:精确类标签只盖 ~107 条,>95% 动词靠启发式+JMdict,**纯启发式 N5–N3 只 ~23%,所以 JMdict 是承重项**;启发式必须**排除 ~480 个 suru-noun**(带 noun 标签 / 纯汉字无送り仮名的「泛 v」)。闸 = 人工策展核心动词集经引擎跑 **100% 正确**(不是「90% 被分类」)。
2. **A 纯模块**:`WordListsKit`(`WordList`/`WordListStore` + CRUD + cap + 抗损坏迁移 + tombstone)+ `SyncMerge.wordLists`(**ids per-id union / name 标量 LWW / 软删传播** —— 不是整单 LWW),配齐 §A6 测试矩阵。无 UI 先行。
3. **ConjugationKit 引擎**(零依赖,可最早写):纯函数 + lemma 例外表(行く/ある/する/くる/v5aru 敬语)+ suru-noun 组合路径 + 海量 golden 向量(见 §B2)。

**绝对红线(违反会被拒或丢数据,务必遵守):**
1. **绝不在 CKSyncEngine 的 delegate 回调里驱动引擎**(await fetch/send)—— 这正是 1.4 被拒的崩因。一律 `recordLocalChanges → scheduleSync()`(Task hop)/ 守卫合并的 `syncNow()`;`nextRecordZoneChangeBatch` 里先把 model 状态**按值快照**到主 actor 外 + CKRecord 深拷贝。
2. **所有文件写:同步、主 actor、`options:.atomic`**(不可 Task.detached 写盘 —— 会和同步合并写同文件 last-writer 覆盖)。
3. **Practice 模式永不写 SRS**;conjugation 若写 SRS **必须独立 store**(`ConjugationReviewStore`,独立文件/CKRecord/键),**绝不复用 `ReviewStore`**。
4. **非游戏屏**(菜单/结算/about/设置/**新的词单·引导屏**)抑制软键盘 + Esc/Back + navCount/zIndex 入屏置顶;**游戏屏(含新 conjugation 屏)必须复用 `.playing` 路径自动召唤键盘 + `isTouchDevice` 触屏 HUD**(否则 iOS 键盘不出 = 2.1a)。
5. **kana 读音全局唯一**(`VocabKitTests` 强制,只管 bundled entries);conjugation 输出是临时形,绝不持久化为 VocabEntry。
6. **词单同步用 ids per-id union(保 v1.4 ★ 的 add-wins,并发加词不丢)**,只对 name/deleted 标量做 LWW;**不要整单 LWW**(依赖跨设备时钟、会回归 ★)。默认「收藏」单用**常量 id `"default"`**(非随机 UUID,否则两设备分裂成两个默认单)。
7. **xcodegen 版本字面量坑**:project.yml 里 `CFBundleShortVersionString:$(MARKETING_VERSION)` / `CFBundleVersion:$(CURRENT_PROJECT_VERSION)` 必须显式引用 build setting,否则生成的 Info.plist 写死 1.0/1。
8. **构建号每平台严格递增**:当前 macOS=7 / iOS=8。v1.5 用 **macOS≥8 / iOS≥9**。

**验证 & 工具:**
- `swift test` 当前 **113 测试基线全绿**,不得回归;新模块配纯单测。
- **发版前务必跑 Release 本地启动自测**(1.4 就是 Release 才暴露的启动崩):`xcodebuild build -scheme NihongoRide -configuration Release -derivedDataPath build/macrel -allowProvisioningUpdates DEVELOPMENT_TEAM=KHMK6Q3L3K CODE_SIGN_STYLE=Automatic`,再直接跑产物可执行文件看是否秒退。
- 构建+上传:`scripts/build-appstore.sh --upload`(macOS)/ `scripts/build-appstore-ios.sh --upload`(iOS);提交:`scripts/asc_api.sh` + 仿 `scripts/submit_1_4_1.py`(挂 build → reviewSubmissions + items → submitted=true)。元数据/截图新建版本会自动继承。
- 真机 js(iPhone「js」,UDID `00008130-00146CD01E12001C`):`xcodebuild -destination 'generic/platform=iOS'` 然后 `xcrun devicectl device install/launch`(js 无线时别用 `-destination id=`,会超时;装前先解锁)。
- 对抗 review:Gemini(`agy` CLI / `antigravity-intern` MCP)目前**不稳定**(headless 常 hang/无输出);可改用 Claude 多智能体 Workflow 做发版前对抗 review(参照本仓库历史用过的「N 视角 + 逐发现 verify」模式),或 Codex。

**App ID / 签名:** team `KHMK6Q3L3K`,bundle `com.jasonye.nihongoride`,CloudKit 容器 `iCloud.com.jasonye.nihongoride`(已建+已部署 schema 到 Production),ASC app id `6777469778`。ASC API key 在 `~/.appstoreconnect/private_keys/`,issuer/key id 见 `scripts/` 里现成调用。

先读 `docs/PLAN-V1.5.md` 和自动记忆,然后从 Phase 0 开始推进,有需要 Jason 拍板的(尤其 §9 待定:JMdict 用不用、B 进 1.5 还是 1.6)再问。开工吧。

---
