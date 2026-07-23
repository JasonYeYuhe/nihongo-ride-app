# v1.13 开发计划 —— 同步层停止撒谎(续)+ 锁屏 widget + 小组件诚实

grounding:对当前 HEAD 跑了 5-lens grounding(wf_98f286ef-c25),**5 个 lens 全部独立
指向同一个 HIGH**。kanji SRS 被数据否掉(词库只有 id/surface/kana/pos/jlpt/meanings/vc,
无部首/字形分解字段)。

## 0. 一句话范围

**v1.13 = 把 v1.12 漏网的最后一句同步谎言堵掉,顺带上锁屏 widget(便宜的新面)。**
headline(用户可见):**锁屏 accessory widget**;correctness spine:**zone 删除后不再
谎报「已同步」、并重新上传**;supporting:**小组件不再在只剩变形到期时谎称「全部复习完」**。

已在 main 排队进本版:地标穿透词卡修复(92fef11)、状态栏滚动遮罩(282f8c2)。

## 1. Phase A(headline correctness)—— zone 删除处理

**bug(HIGH,5 lens 确认)**:`CloudKitSyncController.handleEvent` 把 `.fetchedDatabaseChanges`
当空 `break`(:258)。用户在「设置 > Apple ID > iCloud > 管理存储 > 删除 App 数据」
删掉数据 → zone 被 server 端删除,以该事件的 `deletions` 送达 → **被丢弃**。
- 当前会话:`.saveZone` 的 pending change 早已消费,已发记录不在 pending 集,**不重传**。
- 下次启动:`clearState()` 只在 signOut/switchAccounts 跑(**不在 zone 删除**),所以
  `loadState()` 返回非 nil → `saved == nil || fullResync` 为 false → **`enqueueAllLocal()`
  被跳过**;`start()` 无条件重加 `.saveZone` → **重建空 zone**;`syncNow()` 收尾报 `.synced`。
- ⇒ **iCloud 空了、状态却显示「已同步」,第二台设备/重装同步到空。这正是 v1.12 要杀的谎言。**
- 非本地数据丢失(本地 JSON 是 system-of-record,完好);是 **misreport + 无自动恢复**。
  唯一恢复是手动关开同步(fullResync),用户没理由做——因为 UI 说已同步。

**🔴 红线(v1.4 崩溃教训):绝不能从 delegate 回调(handleEvent)驱动引擎。**
必须走既有模式:delegate 里只**置标志**,Task hop 后在 `syncNow`/受控点重新入队。

**修复设计(待 Codex 审)**:
1. `handleEvent` 的 `.fetchedDatabaseChanges` 分支:检测 `event.deletions`(zone 删除)。
   命中 → 置 `zoneWasDeleted = true`(不在此处碰引擎)。
2. Task hop / 下一 `syncNow` 轮:若 `zoneWasDeleted`,先确保 `.saveZone` 再 `enqueueAllLocal()`
   (重新入队全部本地记录),清标志。
3. 期间状态**不得报 `.synced`**——要么 `.syncing`,要么等重传真正完成。
4. **启动兜底**:即使 app 没在跑时删的(下次启动 fetchChanges 才拿到删除),同一标志路径
   要能接住;或在 start() 里,若 fetch 后发现 zone 为空但本地有数据,触发一次 re-enqueue。
   (具体走"事件驱动"还是"启动探测",Codex 定夺——CKSyncEngine 删除后是否重发删除事件
   是 device-only 未验问题,设计要对两种都稳。)
5. ⚠️ 不重复 enqueue:标志消费一次;re-enqueue 的记录集用现有 `enqueueAllLocal` 的口径。

**闸**:新单测覆盖标志/入队逻辑(能测的部分);**真机门(Jason)**:真删 iCloud 数据 →
看是否重传 + 状态是否诚实(headless 测不了 CloudKit 端到端)。

## 2. Phase B(supporting)—— 小组件诚实

**bug(LOW)**:`ReviewWidgetContent` 的 small 布局只读 `vocabDue`,当它 0 就印
「全部复习完啦 / all caught up」(:90-95),**从不看 `conjugationDue`**。用户词汇清空但
变形仍有到期 → 谎称全清。快照数据是对的,只是 small copy 过度声称。
**修复**:small 布局在 `vocabDue==0 && conjugationDue>0` 时显示变形到期数,而非「全部复习完」;
只有两者都 0 才「全部复习完」。medium 布局已同时显示两者,不动。

## 3. Phase C(feature headline)—— 锁屏 / accessory widget

**机会(S,grounding 确认便宜)**:widget 只声明 `.supportedFamilies([.systemSmall, .systemMedium])`。
数据管线 family-agnostic、`WidgetSnapshot` 已携带 voc/conj/streak——加 accessory family 主要是
**新布局**,非新数据。
- 加 `.accessoryRectangular`(锁屏矩形:到期数 + streak)、`.accessoryInline`(锁屏行内:一句话)、
  `.accessoryCircular`(可选:到期数圆环)。
- 复用 `ReviewWidgetContent` 或新增紧凑变体;headless 渲染验证(App Group 快照已在 v1.11 验通)。
- entitlement/plist 无新增(accessory 不需要新权限)。

## 4. 执行顺序

1. **Phase B**(最小、独立)→ 测试 + headless 渲染验证 → commit。
2. **Phase C**(锁屏 widget,加法、低风险)→ headless 渲染 8 态目检 → commit。
3. **Phase A**(zone 删除,最高风险)→ **先 Codex 审设计** → 实现 → 单测 → commit。
   放最后,因为它碰引擎;前两个先落地不受它阻塞。
4. bump 1.13(mac≥19/iOS≥20)+ submit_1_13.py + 双端 build(schema 门自动)+ 崩溃门 + 送审。

## 5. 明确不做

- kanji/radical SRS(数据不支持,需新内容非新代码——XL,推后待内容)。
- 自动"zone 删除后弹窗引导"(Phase A 先做静默正确的重传;提示是后续 nicety)。
- 生图(承袭 §D:场景纯代码)。
