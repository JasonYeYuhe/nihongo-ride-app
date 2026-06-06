# 上架准备 / Shipping Checklist

> Nihongo Ride 当前以 SwiftPM 包形态开发,`swift run NihongoRideApp` 即可跑游戏。
> 上架 macOS App Store(或对外分发 .dmg)需要用 **Xcode 工程**包一层,做签名/公证/上架。本文给出完整清单。

---

## 0. 前置(必备账号 / 工具)

- [ ] **Apple Developer Program 会员**($99/yr) — 个人或公司均可
- [ ] 在 [Apple Developer](https://developer.apple.com/account) 完成
  - Bundle ID(建议 `com.<yourname>.nihongoride`)
  - 一个 **Distribution(Mac App Store)证书** 或 **Developer ID Application 证书**(直接分发用)
  - Provisioning Profile(App Store 上架用 Mac App Store Profile;DMG/直分发用 Developer ID Profile)
- [ ] **Xcode 26+**(本仓库验证过 26.5)
- [ ] 本仓库 `git clone` 到本机,确认 `swift build && swift test` 全绿(应 56 测试通过)

---

## 1. 商标 / 命名 / 隐私文案

- [ ] **「Nihongo Ride」商标检索**(USPTO TESS + JPO J-PlatPat 手动查)。前序名 "Nihongo Dash" 已确认撞 prior use 改名,见 [`TRADEMARK.md`](TRADEMARK.md)。"Ride" 候选 Gemini 初筛 CLEAR,但请上架前再正式查一遍。
- [ ] 准备 **App Store 文案**:
  - 名称(macOS Store 显示名最长 30 chars)
  - 副标题(30 chars)
  - 推广文本(170 chars)
  - 描述(4000 chars,中英双语建议各写一份;中文为简体)
  - 关键词(100 chars,逗号分隔)
  - 支持网址、营销网址(可指向同一 GitHub Pages 占位)
  - **隐私政策 URL**(必填)——本 App **无网络、无追踪、无账号**,SRS 数据仅本地;隐私政策可写"本应用不收集任何用户数据"
- [ ] 准备 **应用支持邮箱**(必填)
- [ ] **截图**:macOS Store 需要 **2880×1800**(Retina,推荐)或 1280×800,1-10 张
  - 用 **store 模式** 一键渲染:
    ```sh
    mkdir -p /tmp/nihongo-store
    NIHONGO_SHOT=/tmp/nihongo-store NIHONGO_SHOT_STORE=1 swift run NihongoRideApp
    ```
  - 输出:menu / game / game-mid / results / practice / practice-blind 全部 2880×1800
  - 建议上架顺序:**game** → **practice** → **menu** → **results** → **practice-blind**(展示骑行 + 文章 + 选项 + 评级 + 高级模式)
  - 文案可以放 Figma 里给截图加 tagline 叠加(本仓库不重复造 Figma 工作)

---

## 2. 包壳成 Xcode 工程(一次性,然后用 Xcode 维护)

> SwiftPM 不签名也不打 .app bundle;Xcode 工程才能上架。

### 推荐:用 xcodegen 一键生成 Xcode 工程 ✅ 已就绪

仓库根的 [`project.yml`](../project.yml) 是 Xcode 工程的「源代码」,由 `xcodegen` 在本地生成出
`NihongoRide.xcodeproj`(不入 git)。所有 Info.plist / entitlements / sources / package
dependencies / build settings 都集中在这一个文件里。

```sh
brew install xcodegen
cd /Users/jason/typing_app
xcodegen generate            # writes NihongoRide.xcodeproj
open NihongoRide.xcodeproj
# Xcode 里 Signing & Capabilities → 选你的 Apple Dev Team(其他都已配置)
# Product → Archive
```

**验证已通过**:`xcodebuild -scheme NihongoRide -configuration Debug build` 在本机出 `Nihongo Ride.app`
(7.2 MB,Bundle ID `com.jasonye.nihongoride`,带 AppIcon、SPM 资源、教育分类)。

`project.yml` 关键设置:
- Bundle ID: `com.jasonye.nihongoride`(改前缀就改 `PRODUCT_BUNDLE_IDENTIFIER`)
- Min deployment: macOS 14.0
- App Sandbox: ON,不申请网络权限(本应用全离线)
- 引擎/词库/SRS/游戏 依赖通过 SPM local package 引入(`packages.Nihongo`)
- Sources 排除 `Sources/NihongoRideApp/Resources/AppIcon.png` — Xcode 用 Assets.xcassets,不重复打包
- `#if SWIFT_PACKAGE` 已在 `NihongoRideApp.swift` 把 SPM 专属 Bundle.module 调用隔离

每次改 `project.yml`(比如改版本号 / bump CURRENT_PROJECT_VERSION)后,**只需 `xcodegen generate`**
就能同步;`.xcodeproj` 不入 git,无 merge 冲突烦恼。

### 替代:手动创建 Xcode App 工程(若不想用 xcodegen)

参见旧 commit `feat(D)` 之前的版本。手动操作和 `project.yml` 等价,但每次升级要点 GUI。

---

## 3. 签名 & 公证(macOS Store 上架的硬要求)

### App Store 路线

- [ ] Xcode → Project → Signing & Capabilities → Automatically manage signing(选你的 Team)
- [ ] Product → Archive → Distribute App → **App Store Connect** → Upload
- [ ] 在 [App Store Connect](https://appstoreconnect.apple.com) 创建 macOS App,填上 §1 的文案 + 截图
- [ ] 等审核(macOS 审核通常 24-48h)

### 直接分发 .dmg(不走 Store)

- [ ] Xcode → Project → Signing & Capabilities → 选 Developer ID Application 证书
- [ ] Product → Archive → Distribute App → **Developer ID** → Export
- [ ] **公证(必须!不然新 macOS 会拒绝运行):**
  ```sh
  xcrun notarytool submit NihongoRide.app.zip \
    --apple-id you@example.com \
    --team-id YOURTEAMID \
    --password app-specific-password \
    --wait
  xcrun stapler staple NihongoRide.app   # 把公证票据 staple 进 app
  ```
- [ ] 用 `create-dmg`(`brew install create-dmg`)打 `.dmg`,再 `notarytool` + `stapler` 给 dmg 公证

---

## 4. 母语者终审(发布前必做)

⚠️ 当前数据中 **N4–N1 词库释义** 与 **183 篇 Practice 段落** 都有 LLM 参与生成(读音/译文)。
机器审核已发现并修过 ~20 条错误(`design/known-bad-readings.txt` 黑名单存档),但 **母语者一遍**
是上架前的不可省步骤。

具体建议:
- [ ] 找 1-2 个日语母语者(最好有语言教学背景),按等级抽样:
  - N5 全量(~646)
  - N4 全量(~642)
  - N3 抽 50%
  - N2/N1 抽 25%
  - Practice 段落:全量 183 篇
- [ ] 任何"读音错"立刻进黑名单 + 黑名单生效后下次构建词池时自动排除
- [ ] **中文译文**:简体中文母语者校对(英文 Gemini 已审多轮,中文未独立审过)

---

## 5. CI / 自动化(可选,但能省时间)

- [ ] **GitHub Actions** macOS runner:`swift test` + `xcodebuild -scheme NihongoRide test`
- [ ] **Fastlane** (可选)
  - `fastlane match` 管证书
  - `fastlane gym` 自动 archive
  - `fastlane pilot` 上 TestFlight
  - `fastlane deliver` 上 App Store
- [ ] **每月一次 `gemini reading-recheck`**(`/scripts` 下放一个 shell),把所有 LLM 数据再 audit 一遍

---

## 6. 第一版发布范围建议

不必一次上齐所有功能。最小上架版可以:

- ✅ 引擎 + 词库 + 3 种模式 + 骑行 UI + Practice 文章 + 图标 + 持久化(都已就绪)
- 🚫 **暂缓**:动词变位、长句、排名、云同步、传送带皮肤

发布后再逐步加,降低首版被拒风险。

---

## 7. 已知风险 / 提示

- **「Sushida」(寿司打)是一款知名日语打字游戏**,我们定位不同(教学 vs 反应游戏)且没有侵权材料,
  但描述里**不要拿它直接对标**(可类比"like a kanji typing game"而不点名)
- **图标版权**:5 张系列图标(JA/ZH/FR/ES/KR)是你做的,版权归你,可以放心用
- **Mozc 罗马字表**(BSD-3)、**Tanos JLPT 等级**(CC BY)、**Bluskyo 词库**(MIT 转 Tanos CC BY 衍生)、
  **Tatoeba 句子**(CC BY 2.0 FR):上架的 App 内的「关于/致谢」页**必须**包含这些署名行
  (`THIRD_PARTY_LICENSES.md` 里已备好文案)

---

## 8. TL;DR(就要现在开始)

1. **今天**:跑 `swift test` 确认全绿(已 56 绿) → 新建 Xcode App 工程依赖本仓库 SPM → 拖图标 → Archive → 自分发 .app 给你自己试用
2. **本周**:母语者审 N5 + Practice 段落 → 修一轮 → 在 App Store Connect 占位创建
3. **下周**:上传 TestFlight → 找 5-10 个学习者内测 → 收反馈 → 改 → 提审 macOS App Store
