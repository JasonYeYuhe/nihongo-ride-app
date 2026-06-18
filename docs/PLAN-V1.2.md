# Nihongo Ride — v1.2 开发计划书(同步 · 提醒 · 社交)

> 写于 2026-06-18。当前状态:**macOS 1.1 与 iOS 1.1 均 READY_FOR_SALE(已上架)**;1.0 仍在售。
> 本文承接 [`docs/PLAN-V1.1.md`](PLAN-V1.1.md) 的 Phase 2,并把它细化为可执行的工程计划。
> 工作方式不变:中文沟通、全权自主推进、每完成一段让 Gemini 3.1 Pro / Codex review、小步提交、提交后推私有远程 `github.com/JasonYeYuhe/nihongo-ride-app`。

---

## 0. 目标与范围划分

PLAN-V1.1 把「同步 + 社交」笼统放进 v1.2。落到工程上,这两块的 **entitlement / App Store Connect 配置 / 审核风险面差异很大**,因此本计划把它拆成两个发版,降低单次审核的不确定性、保持上架节奏:

| 版本 | 主题 | 内容 | 主要风险面 |
|------|------|------|-----------|
| **v1.2** | **「你的数据,处处同步」** | ① 设置持久化(现为 bug)② iCloud 同步(SRS + 骑行日志)③ SRS 到期本地提醒 | iCloud 容器 / CloudKit schema / 通知 opt-in 审核 |
| **v1.3** | **「上路竞速」(社交)** | ④ Game Center:Time Attack 排行榜 + 成就 | Game Center entitlement + ASC 排行榜/成就配置 |

> 拆分理由:v1.2 三项共享一次「iCloud + 通知」能力变更,是一条连贯的「数据」叙事;Game Center 是独立的 ASC 配置和另一种价值主张,单独发能让排行榜从 0 起步时数据更干净,也避免一次提交同时引入两套全新苹果服务时被审核连带卡住。**如 review 认为应合并,可把 v1.3 并入 v1.2。**

本文档详写 **v1.2**,v1.3 列出骨架(§6)。

---

## 1. 现状盘点(已读代码确认)

> 子系统勘探见本次 session;以下为计划依赖的事实,均经读码确认。

- **ReviewStore**(`Sources/ReviewKit/ReviewStore.swift`):值类型,`cards: [String: SRSCard]`,key = 词条 id(等于 `VocabEntry.id`)。`SRSCard`:`easeFactor / interval / repetitions / dueDate / lapses / lastReviewed(Date?) / totalReviews / totalMistakes`。原子写 `~/Library/Application Support/NihongoRide/review.json`(macOS 沙盒下落在容器内)。**`lastReviewed` 即合并冲突的判定字段**。
- **RideJournal**(`Sources/JournalKit/RideJournal.swift`):值类型,`records: [RideRecord]`(每条 `id: UUID`,时间升序,**上限 2000 条,超出丢最旧**)+ 三个**终身里程计**(`lifetimeWords / lifetimeDistanceMeters / lifetimeRuns`,**裁剪后仍累加,不回退**)。原子写 `history.json`。streak 在读时计算(quiet-today 规则、跨午夜)。
- **AppModel**(`Sources/NihongoRideApp/AppModel.swift`):`@MainActor @Observable`。**设置(`languageCode / showRomajiHint / soundEnabled / selectedMode / selectedLevel / practicePassages / practicePassageLevel`)全在内存,从不持久化——退出即丢,下次启动回默认值(这是个真实 UX bug)**。`finishGame()` 已正确实现「Practice 不写 SRS」(`!wasPractice` 判定,red-line)。`Screen` 枚举 + `navCount`(didSet 递增)驱动 RootView 的 zIndex 防吞点击。
- **打包**(`project.yml`):xcodegen 生成;两个 app target——`NihongoRide`(macOS 14)、`NihongoRideiOS`(iOS 17,iPhone+iPad),**同一 bundle id `com.jasonye.nihongoride`**、Team `KHMK6Q3L3K`、自动签名。**macOS target 有 `xcode/NihongoRide.entitlements`(仅 `app-sandbox: true`);iOS target 当前没有 entitlements 文件**。版本经 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 注入 Info.plist(别去掉这两个占位,否则 xcodegen 写死 1.0/1)。
- **评分**(`GameSession`):`score = max(10, (100 + 5·kana − 15·mistakes)·combo)`,combo 倍率封顶 2.0×;另有 `wpm / accuracy / distanceMeters / maxCombo`。**WPM:run < 2s 或 0 正确键 → 0**(排行榜防刷的天然护栏,见 §6)。

---

## 2. v1.2 功能 A — 设置持久化(先做,纯逻辑,半天)

**为什么先做:** 它本身是 bug 修复,且是后面两项的地基(同步开关、通知开关都要落进设置)。零 entitlement、可被 `swift test` 完整覆盖。

### 设计
- 新增 `Settings`(Codable struct)聚合现有 7 个设置字段 + 两个新开关:`iCloudSyncEnabled: Bool`(默认 **true**)、`dueReminderEnabled: Bool`(默认 **false**)、`dueReminderHour: Int`(默认 20,即 20:00)。
- 持久化用 **`UserDefaults`**(单键存整个 `Settings` 的 JSON,或逐字段;倾向单键 JSON,迁移简单)。**不**放进同步范围首版——设置同步留到 §3 评估(见红线)。
- `AppModel.init()` 载入;每次设置 mutation 后 `saveSettings()`(`@Observable` 下用 `didSet` 或集中 setter)。
- **校验**:载入时对 `selectedLevel`(JLPTLevel?)、`practicePassageLevel`、`languageCode` 做白名单解析,非法值回默认——防 UserDefaults 被外部写脏 / 未来同步带进非法字符串导致崩溃。

### 测试(`Tests/SettingsTests` 或并入现有 suite)
- 存→读 round-trip 等值。
- 缺字段 / 脏值 JSON → 安全回默认,不崩。
- 新装(无键)→ 全默认。

---

## 3. v1.2 功能 B — iCloud 同步(核心,分「纯合并引擎」与「CloudKit 接线」两步)

> ⚠️ 这是 v1.2 风险最高的部分。策略:**先把合并写成纯函数并测透,再接 CloudKit**——CloudKit 的真机/双设备验证慢且难自动化,绝不能把合并 bug 留到那一步才发现。

### 3.1 技术选型(决定 + 理由)

调研对比了三条路(详 §8 调研附录):

| 方案 | 结论 |
|------|------|
| **SwiftData + CloudKit** | ❌ 需把 ReviewKit/JournalKit 从值类型 Codable 重写成 `@Model` 类(全属性可选、不支持 `.unique`),是一次大重写,且其字段级 last-writer-wins **无法表达我们「SRS 按 `lastReviewed` 整卡胜出」的语义**。否决。 |
| **NSUbiquitousKeyValueStore** | ❌ 全账户 **1MB 上限**;history 满 2000 条约 ~500KB,加 SRS 接近天花板且随增长会破;整库不透明 last-writer-wins,会**整文件互相覆盖**,SRS 合并语义丢失。否决(仅适合存极小设置,见红线)。 |
| **CloudKit 私有库 + `CKSyncEngine`(逐记录建模)** | ✅ **选定**。保留现有 JSON 为本地 system-of-record,CKSyncEngine(iOS 17+/macOS 14+,正好匹配部署目标)负责同步状态机、离线队列、推送;合并语义在 delegate 里我们自己实现。无重写、尊重我们的冲突规则。 |

**CloudKit 数据建模(私有库 `iCloud.com.jasonye.nihongoride`):**
- record type `SRSCard`:`recordName = 词条 id`;字段镜像 SRSCard;**合并键 `lastReviewed`**。
- record type `RideRecord`:`recordName = UUID 字符串`;字段镜像 RideRecord;**不可变,按 id 去重即可,天然无冲突**。
- record type `Odometer`:**每台设备一条**(`recordName = 安装级 deviceID`,见下),存该设备**自己**累计的 `words/distance/runs`。这是一个 **G-Counter CRDT**:全局 `lifetime* = Σ(各设备 slot)`。**每台设备只写自己那条**,故 odometer 永不产生写冲突。
  > ⚠️ **审核裁定(Gemini 3.1 Pro 2026-06-18):原计划「Odometer 单例 + 逐字段 max()」是丢数据的 bug** —— 设备 A、B 各离线跑一局(各 +50 / +20),`max(1050,1020)=1050`,B 的 +20 被吞。改为 per-device G-Counter:A 的 slot=自己的真实累计(含被裁剪掉的历史,因为 slot 是该设备的单调累计、从不裁剪),全新设备 B 拉到 A 的 slot 即得 A 的完整 lifetime 贡献,不会因 trimming 而少算。`deviceID` 用安装时生成的 UUID,存 UserDefaults(随设置),非 SRS/历史数据。

### 3.2 纯合并引擎(新模块 `SyncKit`,无 CloudKit 依赖,先写先测)

纯函数,输入两个值类型、输出合并结果,**100% 单测**:

- `mergeReviewStores(local:remote:) -> ReviewStore`
  - 按词条 id 取并集;同 id 取 `lastReviewed` 较新者;**`nil < 任何时间`(远端已复习、本地没碰过 → 远端胜)**;两边都 `nil` → 保留任一(数据等价)。
- `mergeJournals(local:remote:) -> RideJournal`
  - records 按 UUID 去重求并集 → 按 date 升序;**先去重再排序,最后才裁剪到 2000**(避免「两边各 <2000、合并后 >2000 把最旧丢掉」时丢错条目)。
- `mergeOdometers(local:remote:) -> [DeviceID: Slot]`(G-Counter)
  - 输入两个 `[deviceID: (words, distance, runs)]` 字典;输出按 key 求并集,**同 key 取逐字段 max**(同一设备只会单调增长,max 安全)。`lifetime* = Σ slots` 在读取时算。每台设备本地只 mutate `slots[myDeviceID]`。
- `mergeSettings(...)`:**首版不同步设置**(见红线 R3);函数预留但不接线。

**对抗式单测必须覆盖:**
1. `lastReviewed` 一边 nil → 非 nil 胜;两边 nil → 不崩、等价。
2. 同 UUID 不同 metrics(理论不该发生)→ 取一条且稳定(按 date / 字典序兜底),不重复。
3. 两边各 1500 条、重叠 500 → 合并后 2500 → 裁剪到 2000,**留最新 2000、丢最旧 500**。
4. **G-Counter 并发增量**:A slot +50、B slot +20(不同 deviceID)→ 合并后 `Σ = base+70`(**不是 max 的 +50**)。同 deviceID 不同进度 → 取 max。全新设备拉到对端 slot → lifetime 等于对端真实累计(即便对端 records 已被裁剪)。
5. 跨时区:streak 在读时算,不入合并;合并只管 records 集合,验证不因时区改变集合。
6. 幂等:`merge(a, merge(a,b)) == merge(a,b)`(records、SRS、odometer 三者皆需)。

### 3.3 CloudKit 接线(`SyncController`,Phase B,需 entitlement)

- `SyncController`(actor / `@MainActor` 视并发模型)持有 `CKSyncEngine`,实现其 delegate:
  - **拉**:收到远端记录 → 转成 `SRSCard`/`RideRecord` → 用 §3.2 合并进本地 store → 原子落盘 → 通知 AppModel 刷新(`@Observable`)。
  - **推**:本地 `finishGame()` 后,把变更的卡片 / 新记录 / 里程计交给 sync engine 的待推队列。
  - **冲突**:`CKSyncEngine` 给到 server/client/ancestor,我们走 §3.2 同一套合并,避免两处逻辑分叉。
  - **回写保留未知字段(前向兼容)**:合并后回写时**修改收到的 `CKRecord` 实例(只覆盖已知字段)而非用 Codable 重建一条**——这样未来版本新增的字段不会被旧客户端抹掉。**审核裁定:采纳 Gemini「forward compatibility」补充**,本项目首版即遵守此原则(成本几乎为零,只是别 rebuild record)。
- **推送 / 同步模式(审核裁定:采纳 Gemini 补充)**:`CKSyncEngine` 默认(`automaticallySync = true`)会建 CloudKit subscription,**需要 Push Notifications 能力(`aps-environment` entitlement)+ remote-notification 后台模式**,否则启动期会持续报错。
  - **首选**:加 Push Notifications capability + 后台模式,用自动同步(近实时,体验最好;沙盒/Mac App Store 均可)。
  - **备选**:`automaticallySync = false` + 在 app 启动/回前台/每局结束后**手动 `fetchChanges`/`sendChanges`**,此模式**不建 subscription、不需 `aps-environment`**。若想最小化能力面可走此路。
  - **决策(v1.2 已实现):走备选——手动模式** `automaticallySync = false`,只在**启动 / 回前台 / 每局结束后** `sendChanges` + `fetchChanges`。**不需 `aps-environment`、不需后台模式**,把 Jason 要在开发者后台/描述文件配置的能力面降到最小(仅 iCloud 容器)。自动+push 留作后续增强(届时再加回 aps-environment + remote-notification)。
- **账号状态变化(审核裁定:采纳 Gemini 补充)**:监听 `CKAccountChanged` / `CKSyncEngine` 的 account-change 状态。用户在系统设置退出或切换 iCloud 账号时,**必须清掉 sync engine 的 state(change token 等),不得把上一个账号的数据写进新账号**;本地 JSON 保留(它是 system-of-record),仅停同步或重新初始化引擎。
- **降级**:未登录 iCloud / 同步关 / 网络无 → 全程用本地 JSON,功能不受影响(同步是增益,非依赖)。
- **首次开启同步的合并**:用户在设备 B 装新版、本地已有历史 → 必须**先完整拉取并合并再覆盖本地**,严禁「空远端覆盖本地历史」(red-line R2)。

### 3.4 entitlements / 能力变更(Phase B —— ✅ 已实现,手动模式)
- `xcode/NihongoRide.entitlements`(macOS)已增(保留 `app-sandbox: true`):
  - `com.apple.developer.icloud-container-identifiers = [iCloud.com.jasonye.nihongoride]`
  - `com.apple.developer.icloud-services = [CloudKit]`
  - **手动模式 → 不加 `aps-environment`、不加后台模式**(见 §3.3 决策)。若日后改自动+push 再加。
- **已新建 `xcode/NihongoRide-iOS.entitlements`** 并在 `project.yml` 的 `NihongoRideiOS` target 挂上(此前 iOS 无 entitlements 文件)——内容同上(仅 CloudKit)。
- `project.yml` 两 target 的 `entitlements.properties` 已加上述键;**未动 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 注入**。
- **待 Jason(开发者后台/Dashboard)**:App ID 勾 iCloud + 新建容器 `iCloud.com.jasonye.nihongoride`;`xcodebuild` 用 `-allowProvisioningUpdates`(脚本已带)。
- **CloudKit schema 顺序(审核裁定:采纳 Gemini「JIT schema」补充)**:CloudKit 的 record type 是**首次在 Development 环境保存记录时即时(JIT)生成**的。流程必须是:① 先在 Development 跑通,让引擎保存出至少一条 `SRSCard`/`RideRecord`/`Odometer`,Dashboard 自动捕获 schema;② 再在 CloudKit Dashboard **把 schema 部署到 Production**。**漏掉①直接 deploy = 无 schema 可部署;漏掉② = 上架后真机同步全空。**

### 3.5 隐私合规(审核裁定:采纳 Gemini「App Privacy」补充)
- 数据存进**用户自己的 iCloud 私有库(CloudKit private DB)**,开发者无法访问 → 按 Apple 定义**不构成「收集(collect)」**,**App Privacy 应仍可保持「Data Not Collected」**。
- ⚠️ 提交前仍需按 Apple 当前措辞复核一次;若文案口径有变,再据实更新 App Privacy。本地通知不涉及数据收集。

### 3.7 测试与验证
- §3.2 全部纯单测随 `swift test` 绿(无 CloudKit,纯逻辑)。
- CloudKit 接线**无法靠 `swift test` 验证**:需 (a) 两台真机 / 一真机 + 一模拟器,同一 sandbox iCloud 账号;(b) 验证 A 复习→B 看到 due 增加、A 跑一局→B 看到历史多一条;(c) 飞行模式离线改→恢复网络收敛。**这步需要 Jason 的 iCloud 测试账号介入,计划里显式标注为「人工验证关卡」**。

---

## 4. v1.2 功能 C — SRS 到期本地提醒(纯调度逻辑 + 权限接线)

**默认关闭**,设置里 opt-in(`dueReminderEnabled`,§2)。

### 设计
> **审核裁定(采纳 Gemini 反对意见):放弃 `repeats: true` 单条日重复**。重复通知的内容在排程那刻定死,用户若连续几天不开 app,每天都收到**同一个过期的「N 个词到期」**,而真实到期数早已变化。

- **改为「未来 N 天精确预排」**:每次 app 进入后台 / 退出 / 启动时,用 SRS 的 `dueDate` 计算**未来 7 天每一天**在 `dueReminderHour` 时刻的**准确累计到期数**,一次性注册 **7 条各自独立(不 repeat)的 `UNCalendarNotificationTrigger`**。每天的 N 因新词到期而递增,数字始终准确。(iOS 同时 pending 上限 64 条,7 条远内。)
- 需给 ReviewKit 加一个纯查询 `dueCount(onOrBefore date:) -> Int`(数 `dueDate <= 当天结束` 的卡)——可独立单测。
- **更新策略**:每次重排前先 `removePendingNotificationRequests`(用我们的固定 id 前缀)清掉旧的 7 条,再注册新的;`UNUserNotificationCenter.setBadgeCount(今天到期数)` 同步角标(旧 `applicationIconBadgeNumber` 已弃用)。
- **权限时机**:不在启动请求;用户在设置里打开开关时才 `requestAuthorization([.alert,.badge,.sound])`;拒绝则把开关弹回 false 并提示去系统设置。
- **关闭 / 清零**:开关关 → `removePendingNotificationRequests` + `setBadgeCount(0)`。
- macOS 与 iOS 同一套 `UNUserNotificationCenter` API。本地通知**无需额外 entitlement**(沙盒下也是)。

### 测试
- 纯逻辑可测(`NotificationKit` 或并入 ReviewKit):给定 SRS 卡集合 + reminderHour + 起始日 → 生成的「未来 7 天 (date, count) 列表」正确;某天 count=0 → **不排该天**(不发「0 个词」的尴尬通知);`dueCount(onOrBefore:)` 边界(当天 23:59 vs 次日 00:00)正确。
- 权限流 + 真正落地系统需真机/模拟器点测。

### 审核(关键)
- Guideline **4.5.4**:通知必须 opt-in 且 app 内可关——已满足(默认关 + 设置开关)。
- 审核备注写明「设置 → 到期提醒」开关位置;通知内容不含敏感信息。

---

## 5. v1.2 功能 D — 设置界面(承载 B/C 的开关)

- 新增 `Screen.settings` + `SettingsView`。**遵守红线**:沿用 `navCount`/zIndex 切屏;非游戏屏 → **键盘抑制**(`KeyCaptureUIView.suppressSoftwareKeyboard`,与 menu/about 同)。
- 入口:菜单 footer(现有 Ride Log / About 旁加「设置 / Settings」)。
- 内容:语言、罗马字提示、音效(把现在散在菜单的开关收纳,菜单可保留快捷)、**iCloud 同步开关 + 状态行**(「已同步 / 未登录 iCloud / 同步关」)、**到期提醒开关 + 时间选择**。
- 双语文案(en/zh,沿用 `languageCode`)。

---

## 6. v1.3 骨架 — Game Center(社交,下一发)

> 仅列要点,详细计划在 v1.2 发布后另写。

- **能力**:`com.apple.developer.game-center` 加进两 target entitlements。
- **排行榜**(ASC → Features → Game Center):
  - Time Attack 分数榜(`Integer`,**High to Low**)。
  - (可选)最佳 WPM 榜。
- **成就**:首程、累计 100 词、累计 1000 词、7 日 streak、单局 flawless(≥97%)。
- **接线**:`GameCenterManager`(authenticate `GKLocalPlayer` → `GKAccessPoint` 显示 → `finishGame()` 后 `Task.detached` 提交分数 / 上报成就)。
- **防刷(必须)**:只对 `duration ≥ 10s 且 wpm > 0` 的局提交榜;评分 combo 封顶 2.0× 已知,排行榜文案与之一致。
- **数据对齐**:成就等级名若复用 Results 的 grade(flawless/steady/building)必须**抽成共享常量**,避免徽章错位。
- **审核**:Game Center sandbox 账号点测;排行榜 ID / 成就 ID 在 ASC 与代码常量一一对应。

---

## 7. 执行顺序与里程碑

**Phase A —— 纯逻辑,可 `swift test` 全验证(本阶段先交付):**
- [ ] A1 设置持久化(§2)+ 测试。
- [ ] A2 `SyncKit` 纯合并引擎(§3.2)+ 对抗式单测(6 类用例)。
- [ ] A3 通知调度纯逻辑(§4 可测部分)。
- [ ] `swift test` 全绿;提交 + 推远程;**让 Gemini / Codex review A 段代码**。

**Phase B —— 基础设施接线(需 entitlement / ASC / 真机):**
- [ ] B1 entitlements + 能力 + provisioning(§3.4)→ 两端 `xcodegen generate` 后能签名构建。
- [ ] B2 `SyncController` CloudKit 接线(§3.3,复用 A2 合并)。
- [ ] B3 通知权限流 + 接 §2 开关(§4)。
- [ ] B4 `SettingsView` + `.settings` 屏(§5)。
- [ ] B5 ASC:CloudKit schema 部署到 Production。
- [ ] **人工验证关卡**:双设备 iCloud 同步 + 通知点测(需 Jason iCloud 测试账号)。

**Phase C —— 发布:**
- [ ] 版本号:`MARKETING_VERSION 1.2`,`CURRENT_PROJECT_VERSION` 双端各 +1(mac→3、iOS→4)。
- [ ] 截图:若新增 Settings 屏需补图(纯绘制,避开 ImageRenderer 渲不出原生控件的坑——用 StoreScreenshotTests 真像素走查,见 R1)。
- [ ] What's New(中英):iCloud 同步 + 到期提醒 + 设置持久化。
- [ ] 双端 archive+upload(`build-appstore.sh --upload` / `build-appstore-ios.sh --upload`)→ 挂 build → 提审(API:POST reviewSubmissions… 全程可走脚本)。
- [ ] 审核备注:沿用 v1.1 触屏说明 + 补「到期提醒在设置内 opt-in」「iCloud 同步为可选增益」。

---

## 8. 调研附录(2026-06,Gemini 联网)

- **iCloud 同步**:小型 app 同步两个 JSON,modern 推荐 SwiftData+CloudKit;但**本项目已有干净的值类型 + 自定义合并语义**,SwiftData 是重写且字段级 LWW 不合我们的语义 → 选 **CKSyncEngine + 逐记录建模 + 自实现合并**(保留本地 JSON)。KVS 因 1MB 上限 + 不透明覆盖否决。CloudKit 需 iCloud 容器 entitlement;推送同步需 remote-notification 后台模式(首版可不用)。
- **Game Center**:Xcode 加 Game Center capability;ASC 配排行榜(注意分数排序方向 / Integer 格式)与成就;`GKAccessPoint` 是推荐入口;sandbox 账号测;常见坑 = 排行榜 ID 拼写、score 格式、未认证就提交。
- **通知**:`UNCalendarNotificationTrigger` 日重复;内容静态需重排更新;`setBadgeCount` 取代弃用 API;Guideline 4.5.4 强制 opt-in + app 内可关,审核备注写明开关位置。

---

## 9. 红线与教训(沿用 v1.1,新增 R0/R2/R3)

1. **R0(新)Practice 永不写 SRS** —— `finishGame()` 的 `!wasPractice` 判定是 red-line;同步引擎写回本地时同样**不得**把 practice 的临时 store 纳入。任何同步/合并路径都要保证 practice run 不污染真实 SRS。加一个测试:记一局 practice 后 `dueCards()` 不变。
2. **R2(新)同步首次合并方向** —— 设备首次开同步,**先拉远端合并再覆盖本地**;空远端 / 加载未完成时**严禁覆盖本地历史**(JournalKit 对空文件优雅解码成空,正是静默丢数据的陷阱)。
3. **R3(新)首版不同步「设置」** —— 设置含 `languageCode` 等设备相关项;首版只同步 SRS + 历史 + 里程计。设置同步留待评估(避免一端改语言把另一端也改了的惊吓)。
4. **ImageRenderer 渲不出原生控件**(Picker/Toggle → 黄色占位)——含菜单/设置原生控件的截图要走真窗口 / StoreScreenshotTests 真像素,不用渲染器。
5. **iPadOS 26 无视横屏限定** —— 新布局(设置屏)必须竖屏可用。
6. **RootView `.id` 切屏必配 zIndex 递增**(`navCount` 模式)——新增 `.settings` 屏照抄。
7. **UI 测试跑前** `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`。
8. **Gemini 审词过度报错** —— flag 一律人工裁定(本计划无新增词,但内容流水线规则不变)。
9. **xcodegen 版本写死坑** —— 加 entitlements 时不要碰 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`。
10. **ASC 凭据**:app id `6777469778`,bundle `com.jasonye.nihongoride`,Team `KHMK6Q3L3K`,API key `~/.appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8`,issuer `c5671c11-49ec-47d9-bd38-5e3c1a249416`;操作走 `scripts/asc_api.sh`。
11. **数据质量留意(非阻塞)**:journal 的 `level` 列把 passage 级(easy/med/hard)与 JLPT 级(N5–N1)混在一列;若 v1.3 做按级排行榜/统计需先 disambiguate(前缀 `jlpt-`/`passage-`),且只能 forward-only(老 history.json 已写入,不回改)。

---

## 10. 待 Jason / review 决策项

- **范围拆分**:v1.2(数据)+ v1.3(Game Center)如本计划,还是合并一次发?(默认:拆。)
- **iCloud 测试账号**:Phase B 人工验证需要一个可在两台设备登录的 sandbox/真机 iCloud 账号。
- **设置是否纳入同步**:首版默认不同步(R3),是否同意?

---

## 11. 评审记录(Gemini 3.1 Pro,2026-06-18)

本计划经 Gemini 3.1 Pro 对抗式评审。结论:**「修订 3 点后可动工」**,已全部修订。逐条裁定:

| # | 评审意见 | 裁定 | 落点 |
|---|---------|------|------|
| 1 | 技术选型 CKSyncEngine + 逐记录 | ✅ 同意 | §3.1 |
| 2 | **里程计 `max()` 合并丢数据(硬 bug)** | ✅ 采纳,改 per-device G-Counter(比建议更稳) | §3.1 / §3.2 / 测试 4 |
| 3 | CKSyncEngine 需 `aps-environment` + JIT schema | ✅ 采纳 | §3.3 / §3.4 |
| 4 | 通知 `repeats:true` 携带过期 N | ✅ 采纳,改未来 7 天精确预排 | §4 |
| 5 | 先纯逻辑测透再接 CloudKit | ✅ 同意 | §7 |
| 6 | v1.2/v1.3 拆分 | ✅ 同意 | §0 |
| 7a | 监听 `CKAccountChanged` 账号切换 | ✅ 采纳 | §3.3 |
| 7b | 前向兼容:保留未知字段 | ✅ 采纳(改 received CKRecord 而非 rebuild) | §3.3 |
| 7c | iCloud 同步是否改 App Privacy | ✅ 采纳,补隐私节(私有库 → 仍「Data Not Collected」,提交前复核) | §3.5 |

**修订后状态:计划可动工。** Phase A(纯逻辑:设置持久化 / `SyncKit` 合并引擎含 G-Counter / 通知调度)零 entitlement、可 `swift test` 全验证,先行实现。Phase B/C 的 iCloud 双设备验证需 Jason 提供可双登的 iCloud 测试账号(见 §10)。
