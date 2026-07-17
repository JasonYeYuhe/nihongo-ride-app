# Nihongo Ride — v1.11 开发计划(Widget:主屏/锁屏上的「今天要复习多少」)

## 0. 一句话范围

**v1.11 = WidgetKit 小组件。** headline:主屏(+ iOS 锁屏)上一眼看到**今天到期的复习数**与**连胜天数**,不必开 app。这是第 6 次从待办里拿出 widget,但前 5 次的推迟前提(「必须把 7 个 store + cksync-state 迁进 App Group」)在 v1.10 已被证伪:**widget 是只读的**,app 只需往 group 容器写**一个派生快照**,widget 只读它——**7 个 store 一个都不动**。这次是已拆弹的推迟,不是又一次绕开。

不追其它新维度(kanji / GC 变形成就 / 例句 仍推后)。

---

## 1. grounding 的核心发现(读过真代码)

- **`ReviewStore.dueForecast` / `ConjugationReviewStore.dueForecast` 是相对分桶**(today/tomorrow/thisWeek,相对传入的 `date`)。**widget 用不了**:widget 时间线在 app 不运行时跨午夜滚动,「today」到了次日午夜就该变,但没有 app 来重算。⇒ 快照必须存**按绝对日历日分桶的到期直方图**,widget 用当前日期去查桶。
- **现成可复用纯函数**:`journal.streakDays()`(RideJournal)、`journal.lifetimeWords`。widget 要的数字全是现成纯函数,无新业务逻辑。
- **🔴 `AppModel.supportFileURL` 的 capture 重定向在函数内部**(`Screenshotter.isCapturing ? tempDir : applicationSupport`)。任何走 App Group 容器的新写入路径**都绕过它** ⇒ **快照 writer 必须自己 honor `isCapturing`**,否则 headless 截图跑 startGame/finishGame 会把真实快照覆盖成演示数据(演示数据会立刻显示在用户主屏 widget 上)。
- **平台坑(v1.10 计划已记)**:App Group 标识符 **macOS 要 team 前缀**(`KHMK6Q3L3K.group.com.jasonye.nihongoride`)、**iOS 不要**(`group.com.jasonye.nihongoride`)⇒ 必须平台条件常量,否则 `containerURL(forSecurityApplicationGroupIdentifier:)` 返回 nil,快照静默丢失(又一个「报成功实则没做」)。

---

## 2. 快照设计(headline 正确性核心,先定死)

### 模块 `WidgetSharedKit`(新,零依赖 leaf,仅 Foundation)

app 与两个 widget extension 都 import。**只放纯数据 + 纯函数**,不 import ReviewKit 等——各 store 自己提供直方图纯函数,快照只做聚合 DTO。

```swift
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: Int          // 前向兼容:未来加字段时 widget 能识别
    public var generatedAt: Date           // 生成时刻(widget 判断快照多旧)
    public var vocabDueByDay: [Int]        // 绝对日直方图,见下
    public var conjugationDueByDay: [Int]  // 同上,变形复习(独立 store,独立直方图)
    public var streakDays: Int
    public var lifetimeWords: Int
}
```

### `dueByDay` 语义(定案 —— 跨午夜累积是唯一微妙点)

新纯函数(与 `dueForecast` 同风格,放各自 store 模块):
`ReviewStore.dueByDay(asOf:D, horizon:H, calendar:) -> [Int]`,长度 H。

- `result[0]` = 到期日 < `startOfDay(D)+1天` 的卡数(**含所有逾期** + D 当天到期)
- `result[i]`(0<i<H)= 到期日落在 `[startOfDay(D)+i, +i+1天)` 的卡数
- **最后一桶不吸收远期**:到期日 ≥ `startOfDay(D)+H天` 的卡**不进直方图**(widget 不提醒两周开外的卡)
- **DST 安全**:一律 `calendar.date(byAdding:.day,…)`,绝不 `+86400`(照抄 dueForecast 的写法)

**widget 第 k 天(距 generatedAt 第 k 个日历日)显示的到期数 = `sum(vocabDueByDay[0...min(k, H-1)])`。** 论证:直方图里的卡在 generation 时都**尚未**到期(逾期的已并入 `result[0]`),一旦到期就一直 due 直到用户复习;而**用户一复习、app 一开就会重写快照**。所以「自上次开 app 以来累计到期」正是 `0…k` 之和。超过 H 天封顶在总和,widget 提示「打开以刷新」。

`H = 14`(两周;14 个 Int 的 JSON 可忽略不计)。

---

## 3. Phase 0 —— App Group entitlement + 门户 capability(需 Chrome/Jason,像 CloudKit token)

- 开发者门户:给 **两个 App ID**(macOS + iOS)加 **App Groups** capability;创建 group `group.com.jasonye.nihongoride`。
- 两个 `.entitlements` 加 `com.apple.security.application-groups`(macOS 带 team 前缀,iOS 不带)。
- **闸**:`containerURL(forSecurityApplicationGroupIdentifier:)` 双端非 nil(数据层有诊断日志 + 一个「写不进就 log failure」而非静默)。
- **不阻塞 Phase A**:数据层纯代码可先做完,entitlement 生效前用临时目录兜底测试。

---

## 4. Phase A —— headline 数据层(先做,零门户依赖,S-M)

1. `ReviewStore.dueByDay` + `ConjugationReviewStore.dueByDay`(纯函数 + 单测:逾期归 0 桶、DST、边界、H 截断)。
2. `WidgetSharedKit`:`WidgetSnapshot` DTO + `AppGroup.identifier`(平台条件常量)+ `WidgetSnapshotStore`(原子读写 group 容器的 `widget-snapshot.json`;**读侧永不 throw**,坏档 → nil → widget 显示占位)。
3. `WidgetSnapshot.make(...)`(聚合)+ 跨午夜累积语义的纯函数 `dueCount(onDayOffset:)` + 单测(**累积语义**、封顶、空档)。
4. app 侧写入器 honor `Screenshotter.isCapturing`(capture 时**绝不**写真实 group 容器)。
5. **闸**:`swift test` 全绿;写入器的 isCapturing 守卫有测试。

## 5. Phase B —— 两个 widget extension target(需 Phase 0 生效才能真跑,M)

- project.yml 加两个 `app-extension` target(macOS + iOS),各自 Info.plist + entitlement(带对应 group)。
- `TimelineProvider`:读快照 → 生成未来 H 天每天午夜一个 entry(`dueCount = sum(0...k)`)。
- widget view:小 + 中尺寸;iOS accessory(锁屏)尺寸评估。**ImageRenderer 坑不适用**(widget 是真 SwiftUI 渲染),但**配色/字体走同一 Theme**。
- `WidgetCenter.shared.reloadAllTimelines()` 由 app 在快照更新后调。
- **闸**:双端 xcodebuild 过;widget 在模拟器/设备真渲染(设备门,Jason)。

## 6. Phase C —— app 侧接线(S)

- 在 **finishGame、复习记录后、启动、进入后台** 写快照 + reload timelines。
- 快照写入必须**便宜且幂等**(纯函数 + 原子写);不上主线程阻塞。
- Screenshotter 也渲染一张 widget 预览(headless,验证快照→视图链路,像 v1.10 分享卡)。

## 7. S —— 发版

bump 1.11(mac build 16 / iOS build 17;**用相邻 DEPLOYMENT_TARGET 锚点改版本,别顺序 replace**)+ submit_1_11.py(文案不含 ★ 字形)+ schema 门自动跑 + Release 崩溃门 + widget 截图。

---

## 8. 红线(承袭 + 本版)

- **绝不全量 store 迁移**(§1 的 UserDefaults/deviceID 双 odometer 陷阱,永久红线)。widget = 只读派生快照,7 个 store 不动。
- **快照 writer 必须 honor `Screenshotter.isCapturing`**(否则演示数据泄漏到用户主屏)。
- **App Group 标识符平台条件**(macOS team 前缀 / iOS 不带),否则 containerURL nil、静默丢失。
- **快照读侧永不 throw**(坏档 → 占位,不崩 widget)。
- **绝不从 delegate 回调驱动引擎**(承袭)。
- **持久化同步原子**(承袭)。

## 9. 待验设备门(Jason)

widget 真渲染(双端 × 小/中/锁屏)、跨午夜时间线滚动是否如预期、快照多旧时的占位、App Group 容器双端可写、widget 首次添加流程、锁屏 accessory(iOS)、深色/浅色 + Dynamic Type。

## 10. 版本

mac 1.11 build 16 / iOS 1.11 build 17(承 v1.10 的 mac 14 / iOS 15,中间 build 15 是 Xcode 静默改号的产物——见 v1.10 §发版坑,已用 manageAppVersionAndBuildNumber=false 堵死)。
