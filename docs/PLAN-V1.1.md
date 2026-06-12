# Nihongo Ride — 下阶段开发计划(v1.1 →)

> 写于 2026-06-12。当前状态:**macOS 1.0 与 iOS (iPad) 1.0 均 READY_FOR_SALE(已上架)**。
> 本文是 v1.0 上架后的下一阶段单一计划来源;完成一项勾一项,顺序即优先级。
> 工作方式不变:中文沟通、全权自主推进、每完成一段让 Gemini 3.1 Pro / Codex review、小步提交。

---

## Phase 0 — 上线后看护(立刻做,半天)

- [ ] **建私有 GitHub 仓库并推送**。主仓库目前没有任何远程(纯本地)——产品已经上架,代码必须有异地备份。
      `gh repo create nihongo-ride-app --private` → `git remote add origin … && git push -u origin main`。
      注意:**不要**推到现有的公开 `nihongo-ride`(那是法务/官网页面仓库)。
- [ ] **跑通审核后例行检查**:`scripts/asc_api.sh GET "/v1/apps/6777469778/appStoreVersions?…"` 确认两端状态;
      App Store 实搜 "Nihongo Ride" 确认能搜到、商店页截图/文案显示正常。
- [ ] **每周看一次评分/评论与崩溃**(ASC → Ratings;Xcode Organizer → Crashes)。有崩溃,优先级最高。

## Phase 1 — v1.1「iPhone + 骑行日志」(主版本,1–2 周)

### 1A. iPhone 支持(最大增量市场)
- [ ] `project.yml`:`TARGETED_DEVICE_FAMILY: "1,2"`;布局核对从 iPad 紧凑模式出发(竖屏已在 iPad 验证过可用,iPhone 更窄)。
- [ ] 竖屏布局:菜单(纵向堆叠,已基本兼容)、GameView(词卡 maxWidth 收窄、键盘弹出时复用 `compact` 模式)、Practice(字号降一档)、Results(卡片 2×3 改 3×2 或纵向)。
- [ ] 触屏键盘体验:沿用系统键盘 + KeyCaptureUIView(iPad 已验证的模式)。自定义罗马字键条留到 v1.2+。
- [ ] **UI 测试扩到 iPhone 模拟器**:`TouchFlowTests` 加 iPhone destination 跑一遍(先 `xcrun simctl list devices` 确认本机有 iPhone 模拟器,没有就 `xcodebuild -downloadPlatform iOS` 或 simctl create)。
- [ ] iPhone 截图(6.9" 2868×1320 或竖屏 1320×2868)双语渲染 + `ASC_SHOT_TYPE=APP_IPHONE_67`(确认最新 enum)上传。
- [ ] 版本号:MARKETING_VERSION 1.1,CURRENT_PROJECT_VERSION 双端各自 +1。

### 1B. 「骑行日志」进度页(留存核心)
- [ ] 新模块数据:每局结束把 GameSummary 追加到 `Application Support/NihongoRide/history.json`(轻量 JSON 数组,字段:date/mode/level/score/wpm/accuracy/wordsCompleted/lapsed)。
- [ ] 新屏 `JournalView`(菜单入口「骑行日志 / Ride Log」):连续天数 streak、累计词数/距离、WPM 趋势(Swift Charts 或手绘 sparkline)、SRS 各等级到期预报(due today/tomorrow/this week)、最近 10 程列表。
- [ ] 设计走 /frontend-design 一次,保持与三模式同语言(深色骑行系 or 和纸系皆可,但要成体系)。
- [ ] 单元测试:history 持久化 + streak 计算(跨午夜、断档)。

### 1C. 内容扩充(流水线已就绪)
- [ ] 例句:N3/N2/N1 各再 +2 批(120/批,Gemini 生成 → 机器校验 → reading audit → 人工裁定 flags)→ 覆盖率 N3≈40% N2≈34% N1≈23%。
- [ ] Practice 段落:+50 篇 hard 文学段(同 para 流水线,黑名单照查)。
- [ ] **母语者审回填**:写 `scripts/import_review_sheets.py`,把审完 CSV 的 `status/correction` 列合并回 n*.json / passages.json + 黑名单。

### 1D. 商店资产修补(随 1.1 提交一起)
- [ ] **换掉 macOS 列表里的 menu.png**(黄色占位条,2.3.3 风险)。方案 A:真窗口截屏(`swift run` + `screencapture -l`,需屏幕录制权限);方案 B:直接从截图集里去掉 menu,用 game-mid 顶上(纯绘制,5 张照旧)。版本未提交状态下截图可改;1.0 已发布,改动会挂在 1.1 版本上。
- [ ] What's New 文案(中英):iPhone 支持 + 骑行日志 + 内容扩充。

### 1E. 发布
- [ ] 双端 archive + upload(`scripts/build-appstore.sh --upload` / `build-appstore-ios.sh --upload`)→ build VALID → API 挂 build → Chrome「Add for Review」→ Submit。
- [ ] 审核备注沿用 v1.0(2) 的触屏说明,补一句 iPhone 同样适用。

## Phase 2 — v1.2「同步与社交」(上架后视反馈排期)

- [ ] iCloud 同步:CloudKit(private DB)同步 review.json + history.json;冲突策略=按 SRS item 的 lastReviewed 新者胜。entitlement 变更 → 双端重新 provisioning。
- [ ] Game Center:Time Attack 排行榜(score)+ 几个成就(首程、百词、7 日 streak)。
- [ ] SRS 到期本地通知(默认关,设置里开)。
- [ ] iPhone 自定义罗马字键条(替代系统键盘的探索,A/B 自测后再决定)。

## Parking lot(v2+,不排期)

动词变位练习模式 / 自定义词单 / 文章导入(用户粘贴假名文本练)/ Hanyu Ride 等系列复用(design/icons 已备)/ 上架日本区域日语 locale 文案。

---

## 红线与教训(新 session 必读)

1. **ImageRenderer 渲不出原生控件**(Picker/Toggle → 黄色占位)——含菜单的截图不能用渲染器出,要么真窗口截屏要么不用菜单截图。
2. **iPadOS 26 无视横屏限定**(UIRequiresFullScreen 已废)——所有新布局必须竖屏可用;别再加方向限制。
3. **RootView 的 .id 切屏必须配 zIndex 递增**(AppModel.navCount 模式),否则旧屏吞点击 ~0.4s。新增任何 .id 切换容器照抄此模式。
4. **UI 测试跑前**:`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`,否则软键盘不弹、测试假红。失败时 `xcresulttool export attachments` 拿 UI 树 + 录屏,ffmpeg 抽帧看地面真相。
5. **Gemini 审词会过度报错**(集まる/発足这类误报)——它的 flag 一律人工裁定,真错才进 `design/known-bad-readings.txt`。
6. **Practice 完局不能存 SRS**(makePractice 是临时 store,存了会清空真实数据——已修,别回退)。
7. ASC:app id `6777469778`,bundle `com.jasonye.nihongoride`,Team `KHMK6Q3L3K`,API key `~/.appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8`,issuer `c5671c11-49ec-47d9-bd38-5e3c1a249416`。新建 app 之外的 ASC 操作全可走 `scripts/asc_api.sh`;截图上传 `scripts/asc_upload_screenshots.py`(`ASC_SHOT_TYPE` 选 display type)。版本在审核中/已发布时截图锁死,改截图挂下个版本。
8. 法务站(公开仓库 `JasonYeYuhe/nihongo-ride`)≠ 代码仓库;隐私政策 URL 已绑定商店,别动路径。
