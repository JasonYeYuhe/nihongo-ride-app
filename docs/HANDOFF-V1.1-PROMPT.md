# 交接 Prompt(发给新 session,工作目录 /Users/jason/typing_app)

> 复制下面整段作为新会话的第一条消息即可。

---

继续开发 Nihongo Ride(日语打字学习 app,本仓库)。你全权负责推进,中文交流,只在法律问题或真正阻塞时才停下来问我;每完成一段让 Gemini 3.1 Pro(mcp__gemini__query / gemini CLI)或 Codex review 一下,没问题就继续推进,小步提交。

当前状态(2026-06-12):macOS 1.0 和 iOS (iPad) 1.0 都已通过审核、READY_FOR_SALE 上架(一个 ASC 记录 app id 6777469778,bundle com.jasonye.nihongoride)。曾被拒一次(iPad 触屏卡死),已修复并有 XCUITest 回归测试。词库 7075 词(N5–N1)、183 篇 Practice 文章、~1404 条例句,中英双语,56 单元测试 + 2 UI 测试全绿。

第一步:读 docs/PLAN-V1.1.md(下阶段完整计划 + 红线教训,必读),然后按顺序执行:

1. Phase 0:主仓库还没有远程——立刻建私有 GitHub 仓库(gh repo create nihongo-ride-app --private)并推送(注意:公开仓库 nihongo-ride 是官网/隐私政策页面,别推错);然后用 scripts/asc_api.sh 核对双端状态、确认商店页正常。
2. Phase 1(v1.1「iPhone + 骑行日志」):iPhone 竖屏支持(TARGETED_DEVICE_FAMILY "1,2",复用已验证的 compact 模式)、骑行日志进度页(streak/WPM 趋势/SRS 到期预报,history.json 持久化,设计走 /frontend-design)、内容扩充(N3-N1 例句各 +2 批、+50 hard 段落,流水线见 memory)、换掉 macOS 商店列表里带黄色占位条的 menu.png 截图、双端提交 1.1。

验证命令:swift test(56 绿);UI 测试(跑前必须 defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false):
xcodebuild -project NihongoRide.xcodeproj -scheme NihongoRideiOS -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" -derivedDataPath /tmp/nihongo-ios-build CODE_SIGNING_ALLOWED=NO test
工程由 xcodegen generate 从 project.yml 生成(.xcodeproj 不入 git);截图渲染 NIHONGO_SHOT=<dir> [NIHONGO_SHOT_STORE=1] [NIHONGO_SHOT_LANG=zh] swift run NihongoRideApp;发布脚本 scripts/build-appstore.sh / build-appstore-ios.sh(--upload),ASC API 走 scripts/asc_api.sh,截图上传 scripts/asc_upload_screenshots.py。

红线(详见 PLAN-V1.1.md 末尾,务必遵守):ImageRenderer 渲不出原生控件(菜单截图禁用渲染器);iPadOS 26 无视横屏限定,一切布局必须竖屏可用;RootView 的 .id 切屏必须保持 navCount→zIndex 模式否则旧屏吞点击;Practice 完局不能写 SRS store(会清空用户数据,已修别回退);Gemini 审词的 flag 必须人工裁定后才进黑名单。

做完一段就汇报一段,然后继续,不用等我确认。
