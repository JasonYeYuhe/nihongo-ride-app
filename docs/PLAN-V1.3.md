# Nihongo Ride — v1.3 开发计划书(Game Center + iCloud 同步上线)

> 写于 2026-06-19。当前状态:**macOS + iOS 1.2 均 READY_FOR_SALE**(设置持久化 + 到期提醒已上架)。
> 决策(Jason):v1.3 **两块一起发** —— ① Game Center(社交)+ ② 把 v1.2 推迟的 iCloud 同步真正上线。
> 工作方式不变:中文沟通、全权自主、每段过 Gemini/Codex review、小步提交、推私有远程。

---

## 0. 范围

| 模块 | 内容 | 主要新面 |
|------|------|---------|
| **A. Game Center** | Time Attack 排行榜 + 5 个成就;认证 + 入口(GKAccessPoint) | `game-center` entitlement + ASC 排行榜/成就配置 + Sandbox 测试 |
| **B. iCloud 同步上线** | 把已写好的 CKSyncEngine 同步翻开(`cloudSyncAvailable=true` + 恢复 entitlement) | CloudKit 容器 + schema dev→prod + 双设备验证(Jason 关卡) |

A 是全新代码(我现在就能写+编译验证);B 的代码 v1.2 已完成,主要是恢复 entitlement + 翻开关 + 配置/验证。

> **更新(2026-06-19):v1.3 最终只发 A(Game Center),B(iCloud)推迟到 v1.4。** 原因:开发者后台已开 iCloud 能力,但 CloudKit **容器 `iCloud.com.jasonye.nihongoride` 未创建/未挂到 App ID**,导致归档签名失败(profile 不含该容器);而容器创建 + 真机出 schema + 双设备验证都需要 Jason 亲自操作,无法自动化。Game Center 全部就绪(代码 + 排行榜/成就 + 图 + 能力),故先发。B 的代码保留、`cloudSyncAvailable=false` 关着、iCloud entitlement 撤出构建,v1.4 翻开即可。

---

## 1. 模块 A — Game Center

### 1.1 现状依据(已读码)
- 评分(`GameSession`):`score = max(10, (100 + 5·kana − 15·mistakes) · combo)`,combo 倍率 `1.0 + min(combo,10)·0.1`(10 连击封顶 2×)。另有 `accuracy / maxCombo / wordsCompleted / distanceMeters`。
- 三模式:`journey` / `timeAttack`(固定 60s sprint)/ `practice`(临时 SRS,永不计分上榜)。
- `ResultsView.gradeOf` 评级:**flawless** = `accuracy≥0.97 && 无 hint && maxCombo≥max(5, wordsCompleted−1)`;steady ≥0.90;building ≥0.75;lap 其余。
- `AppModel`:`lastSummary`(分数/连击/词数/准确率)、`odometer.totalWords`(终身词数)、`journal.streakDays()`、`journal.totalRuns`。

### 1.2 排行榜(只做 1 个,保持干净)
- **Time Attack 高分榜** —— leaderboard id `ta_score`,格式 **Integer**,排序 **High to Low**。
- 只有 **Time Attack 模式**的局才提交(它固定 60s,时长有界、最能横向比;journey/practice 不上榜)。**防刷**:仅当 `mode==.timeAttack && score>0 && wordsCompleted>0` 才 `submitScore`。
- (Journey 高分 / 最佳 WPM 榜留待 v1.4 视反馈;WPM 上榜的刷分风险大,先不做。)

### 1.3 成就(5 个,id 与代码常量一一对应)
| id | 名称 | 触发 |
|----|------|------|
| `ach_first_ride` | First Ride 首次出发 | 第一局完成(`journal.totalRuns≥1`)|
| `ach_words_100` | Century 百词 | 终身词数 ≥100(`odometer.totalWords`)|
| `ach_words_1000` | Long Hauler 千里 | 终身词数 ≥1000 |
| `ach_streak_7` | Seven-Day Streak 七日连骑 | `journal.streakDays()≥7` |
| `ach_flawless` | Flawless Run 完美一程 | 单局 `gradeOf==.flawless` |

- 进度型成就(百词/千词)用 `percentComplete = min(100, value/target·100)` 上报,让 Game Center 显示进度条。
- **共享评级**:把 `ResultsView.gradeOf` 抽到一个共享处(如 `GameSummary` 扩展 / `Grade` 类型),`ResultsView` 与成就上报共用同一逻辑,避免「界面显示完美但成就没解锁」错位(red line)。

### 1.4 GameCenterManager(新文件,`@MainActor`)
- 启动时 `GKLocalPlayer.local.authenticateHandler` 认证;认证成功 → `isAuthenticated=true`,激活入口。
- **入口 = `GKAccessPoint`**(Apple 推荐,跨 macOS/iOS 自动处理 dashboard 弹出,省去平台特定的 VC presentation):
  - `GKAccessPoint.shared.location = .topLeading`、`isActive = true` **仅在非游戏屏**(menu / results / settings)显示;进入 `.playing` 时 `isActive=false`,免得浮标盖住骑行画面(配合 `RootView` 的 screen 切换)。
- `submitTimeAttackScore(_:)` → `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)`。
- `report(achievementID:percent:)` → `GKAchievement.report`。
- 所有 GC 调用都 `guard isAuthenticated`,未认证则静默跳过(同步是增益、非依赖)。
- **可用性闸**:同 ReminderScheduler,`Bundle.main.bundleIdentifier != nil`(`swift run` 下不跑)。

### 1.5 接线
- `AppModel.finishGame()` 之后(非 practice):调用 `gameCenter.recordRun(summary:, mode:, lifetimeWords:, streak:, totalRuns:)`,内部判定提交分数 + 上报达成的成就。
- 认证在 app 启动(`AppModel.init` 或 App `.task`)触发一次。
- `RootView`:进入/离开 `.playing` 时切 `GKAccessPoint.isActive`。

### 1.6 entitlement / ASC(Jason 关卡)
- 两 target entitlements 加 `com.apple.developer.game-center = true`。
- 开发者后台:App ID 勾 Game Center。
- ASC → 该 app → Features → Game Center:建 1 个排行榜(`ta_score`,Integer,High-Low,带本地化名 en/zh)+ 5 个成就(上面的 id,带名称/描述/图标/分值)。**id 必须和代码常量逐字一致。**
- **Sandbox 测试**:用一个 Sandbox Game Center 账号在真机/模拟器登,验证认证弹窗、分数上榜、成就解锁。

---

## 2. 模块 B — iCloud 同步上线

> v1.2 已写完 CKSyncEngine 同步(`CloudKitSyncController` + `SyncKit` 合并 + odometer G-Counter),当时为了干净上架把它**关掉 + 撤 entitlement**。v1.3 把它打开。

### 2.1 代码侧(我做)
- `project.yml` + `xcode/NihongoRide.entitlements` + `xcode/NihongoRide-iOS.entitlements`:**恢复** iCloud 容器 entitlement(`com.apple.developer.icloud-container-identifiers = [iCloud.com.jasonye.nihongoride]`、`com.apple.developer.icloud-services=[CloudKit]`)。macOS 保留 app-sandbox。
- `AppModel.cloudSyncAvailable = true`(翻开关)→ 控制器启动、Settings 的 iCloud 卡片显示。
- **保持手动模式**(`automaticallySync=false`,不加 push/后台模式)——v1.2 已定的最小能力面。
- 已带的正确性修复(serverRecordChanged 先合并再回推、fetch-before-send、账号切换、G-Counter)保持不动。

### 2.2 Jason 关卡(必须,顺序不能错)
1. 开发者后台:App ID 开 iCloud + 新建容器 `iCloud.com.jasonye.nihongoride`。
2. **先在 Development 跑一次**(真机/模拟器,登 iCloud),让 CKSyncEngine 保存出 `SRSCard`/`RideRecord`/`Odometer` 记录 → CloudKit Dashboard 自动 JIT 出 schema。
3. CloudKit Dashboard **把 schema 部署到 Production**(漏了上架后真机同步全空)。
4. **双设备验证**:同一 iCloud 账号两台设备 —— A 复习→B due 增加;A 跑一局→B 多一条历史 + 里程累加(不是覆盖);离线改→联网收敛。
5. App Privacy 复核仍为「Data Not Collected」(私有库,开发者无访问权)。

---

## 3. 构建 / 测试 / 发布

- **可 `swift test` / 编译验证**:GameCenterManager 编译过(GameKit API)、共享 grade 逻辑可单测、SyncKit 合并已测(103 绿)。GC 的实际上榜/成就 + iCloud 双设备同样**只能真机验证**(Jason 关卡)。
- 版本:`MARKETING_VERSION 1.3`,`CURRENT_PROJECT_VERSION` macOS→4、iOS→5(上次 3/4)。
- 截图:GKAccessPoint 浮标不强制进截图;新增屏无原生控件截图需求(沿用纯绘制那套,避开 ImageRenderer 占位坑)。
- What's New(中英):iCloud 同步、Game Center 排行榜与成就。
- 发布:`build-appstore.sh --upload` / `build-appstore-ios.sh --upload` → 挂 build → ASC API 建 1.3 版本 + What's New + 审核备注 + 提交(流程同 v1.2,全 API)。审核备注补:Game Center 为可选、iCloud 私有库不收集数据。

---

## 4. 红线(沿用 v1.2 + 新增)
1. **Practice 永不计分上榜 / 永不写 SRS**(`mode==.practice` 一律排除;R0 不变)。
2. **只有 Time Attack 上 `ta_score` 榜**,且 `score>0`。
3. **成就/排行榜 id 必须与 ASC 配置逐字一致**;flawless 成就复用 `gradeOf` 同一逻辑(抽共享常量)。
4. **GKAccessPoint 只在非游戏屏显示**(进 `.playing` 关掉),别盖住骑行画面。
5. iCloud:**CloudKit schema 先 Dev JIT 再 deploy Production**;首次同步**先拉后推**;账号切换清 state;里程用 G-Counter sum 不用 max(均已在代码里)。
6. ImageRenderer 渲不出原生控件;iPadOS 26 无视横屏限定;RootView `.id` 切屏配 zIndex;UI 测试关硬件键盘 —— 一切照旧。
7. ASC 凭据 / 脚本 / 版本号规则同 v1.2(build 号每端必须比上次大:macOS 3→4,iOS 4→5)。

---

## 5. Jason 的关卡汇总(我做不了、需你配合)
- **Game Center**:开发者后台开 GC;ASC 建排行榜 `ta_score` + 5 个成就(id 对齐);Sandbox 账号点测。
- **iCloud**:建容器;Dev 跑一次出 schema → 部署 Production;双设备验证。
- **App Privacy 复核(两项)**:① iCloud 私有库 → 仍「Data Not Collected」;② **Game Center —— 需确认是否要新增隐私披露**(排行榜把分数绑到玩家的 Game Center 身份;Apple 可能要求声明 "User ID / Gameplay" 之类)。提交前在 ASC App Privacy 按当前措辞核对。
- 这两块的真机验证做完前,**1.3 不提交**(GC 上不去/同步连不上都是上架后才暴露,审核风险)。

---

## 6. 评审记录(2026-06-19)

> ⚠️ **Gemini CLI 已不可用** —— 报 `IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals`(免费层客户端被弃用,要求迁移到 Antigravity)。原定的「Gemini 3.1 Pro review」这一步**跑不了**。本计划改为**自审**(Codex 亦可,sanctioned;若 Jason 重新授权/迁移 Gemini 可补跑)。

自审结论:**可动工**。要点 + 自审发现的修正:
1. GameKit API 用法正确(authenticateHandler / GKAccessPoint / submitScore / GKAchievement.report,均 macOS 14/iOS 17 可用)。**修正**:macOS 认证时若 handler 给了 viewController 仍需 present(GKAccessPoint 只管 dashboard,不管登录弹窗)——编码时处理。
2. 防刷设计成立(仅 Time Attack、score>0;固定 60s)。
3. 成就数据源可靠;**flawless 复用 `gradeOf`** —— 已确认它只依赖 `GameSummary` 公开字段(accuracy/reviewWords/maxCombo/wordsCompleted,`clean = reviewWords.isEmpty`),抽成 `GameSummary` 扩展即可。
4. **成就重复上报安全**:`GKAchievement.report` 对已 100% 的成就幂等,每局重报无害;`showsCompletionBanner=true` 给解锁横幅。
5. iCloud 重新启用:首启 `saved==nil` → 先 fetch(空)再 enqueueAll 再 send,正确上传本地;account 切换已处理;odometer 在 1.2 已 backfill。无新风险。
6. **新增风险(自审发现)**:Game Center 可能触发 App Privacy 披露 —— 已加入 §5 关卡。两套新苹果服务同发审核面较宽,但 Jason 已选合并。
