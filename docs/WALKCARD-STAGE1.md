# Stage 1 走查卡:§L 三道手动检查 + §K day-0 已知阳性购买

写于 2026-09-16(JST)。**这是操作卡,不是记录。** 本卡里任何一行都不是结果;结果写不写、写在哪里,由你决定。
可以直接粘贴的记录草稿在 `docs/DRAFTS-STAGE1-RECORDS.md`。

两条引用规则,方便你(和以后的人)核对:

* 以 `§L 原文 ▸` 或 `§K 原文 ▸` 开头的行,逐字复制自 `docs/PLAN-STAGE1.md`,一个字符都没改。
* 用〔〕括起来的是 app 屏幕上的原文,逐字来自源码(英文界面 / 中文界面各一份)。Apple 系统界面(App Store、
  系统设置、购买弹窗)的文字**不**用〔〕,因为这里没人在 macOS 27 / iOS 26 上核对过它们。

本卡按事先定好的走查顺序写,顺序本身就是约束,每一条约束都写了理由。不要重新设计顺序。

---

## 0. 一屏时间预算

| 步 | 做什么 | 设备 | 你亲手的时间(估计,不是测量) | 自动化的部分 |
|---|---|---|---|---|
| 0 | 预检 + 销售基线快照 | Mac 终端 | ~5 分钟 | `stage1_walk.py preflight` / `baseline`,只读 |
| 1 | 安装 App Store 1.32(Mac + iPhone),iPhone 上拍购买前的 OFFER | Mac、iPhone | ~15 分钟 | `preflight` 复查、`mac-state`、`ios-state` |
| 2 | §L 检查 1:未登录 App Store | Mac | ~12 分钟 | 无 |
| 3 | §K 已知阳性购买(生产环境,你自己的账号) | Mac | ~5 分钟 | 无 —— 这一步永远不能自动化 |
| 4 | §L 检查 3:跨平台恢复 + 冷安装 | iPhone | ~15 分钟(需要等 2 分钟时再加 ~3 分钟) | `ios-state` |
| 5 | §L 检查 2:家庭共享 | 家人自己的设备 | ~15 分钟 | 无 |
| — | 证据文件哈希 | Mac 终端 | ~3 分钟 | `stage1_walk.py manifest` |
| 6 | D+1 / D+2:确认销售报表里出现了这一行 | Mac 终端 | ~5 分钟 | `sales_report.py --confirm-known-positive` |
| 7 | 退款申请;退款行出现后再确认一次 | 浏览器、Mac 终端 | ~5 分钟 + ~5 分钟 | 确认命令 |
| 可选 | 退款后观察是否撤销(**不属于 §K / §L**) | Mac、iPhone | ~5 分钟 | `mac-state` |

步 0–5 一次坐下来,亲手时间大约 65–75 分钟。步 6、7 是之后几天的事。

---

## 1. 先确认:每一步都在 App Store 上的 1.32 上走

**唯一有效的二进制:App Store 发布的 1.32 —— macOS 1.32 (build 56) / iOS 1.32 (build 57)。**
2026-09-16 用 ASC GET 实测,两个平台都是 `READY_FOR_SALE`,没有进行中的审核提交。

**不是**本地构建,**不是** TestFlight,**不是** Xcode 里点 Run。理由:

* Mac 的 Debug scheme 带着 `xcode/NihongoRide.storekit`,购买是本地测试交易,登没登录 App Store 都无关,走完什么都证明不了。
* iOS 从 Xcode 装的、TestFlight 装的,用的是 Apple 的 sandbox 商店;§K 写明 sandbox 永远不会出现在 `salesReports` 里。
  而且它会以同一个 bundle id 覆盖掉 App Store 版本。
* app 自己分不出来:关于页只显示 app 名和 `v` + 版本号,**没有 build 号**,也没有 Debug / TestFlight / App Store 的标记。

**Mac 上怎么确认**(在仓库目录里跑):

```bash
cd /Users/jason/Documents/typing_app
python3 scripts/stage1_walk.py preflight; echo "exit=$?"
python3 scripts/stage1_walk.py mac-state; echo "exit=$?"
```

* `preflight` 退出码:**0** 没有 FAIL · **1** 至少一个 FAIL · **3** ASC/API 失败。它检查
  `"/Applications/Nihongo Ride.app"` 存在、`CFBundleShortVersionString` 1.32、`CFBundleVersion` 56、
  `Contents/_MASReceipt/receipt` 存在。
* 这台 Mac 上还有同 bundle id 的旧副本(`build/macrel …` 1.17 (32)、`build/macrel 2 …` 1.5 (8)、archive、模拟器构建),
  LaunchServices 可能启动错的那个。**只用这一条命令启动 app:**

  ```bash
  open "/Applications/Nihongo Ride.app"
  ```

  `preflight` 发现有一个 Nihongo Ride 进程的可执行文件不在 `/Applications` 下,会 FAIL。
* `mac-state` 退出码 0,打印正在运行的进程路径、receipt、版本/build、解码后的 entitlement 记录和计数器。

**iPhone 上怎么确认:** 删掉 iPhone 上已有的任何 Nihongo Ride(见步 1),从 App Store 重新安装,然后**解锁 iPhone**,在 Mac 上跑:

```bash
python3 scripts/stage1_walk.py ios-state; echo "exit=$?"
```

退出码 **0**;**2** 表示没读到任何已配对设备。设备锁着时读不到已安装的版本 —— 解锁后重跑。它显示已安装的 `com.jasonye.nihongoride` 版本和 build,应为 1.32 / 57。

---

## 2. 导航(Mac、iPhone、iPad 路径相同)

**语言。** 界面语言不跟系统语言,新安装**永远是英文**。新安装会先出引导页,右上角〔Skip〕(中文界面是〔跳过〕)。
想换中文:菜单上的分段选择〔English〕|〔中文〕,或设置里〔GENERAL〕/〔通用〕卡片的〔Language〕/〔界面语言〕行。
价格字符串跟 storefront 走,Apple 的购买/登录弹窗跟系统语言走,都不受这个设置影响。

**菜单 → 设置。** 菜单最下面一排胶囊按钮里,带齿轮图标的〔Settings〕/〔设置〕。Mac 窗口太矮时菜单会滚动,按钮可能在折叠线下面。

> ⚠️ **陷阱:在菜单上按 Return 或 Space 会直接开始一次骑行。** 用鼠标点 / 手指点,不要用键盘确认。

**设置 → 路。** 滚到设置页**最后一张卡片**〔THE ROAD〕/〔路〕。卡片里只有一行:地图图标 + 文字 + 右箭头。
这一行的文字就是状态:

| 状态 | 英文 | 中文 |
|---|---|---|
| 未拥有 | 〔The road past Kyōto〕 | 〔京都之后的路〕 |
| 已拥有 | 〔The Tōkaidō and the Road West〕 | 〔东海道与西の道〕 |

点这一行进入〔The Road〕/〔路〕页面。页面上可能出现的东西:

* 报价卡〔OPEN THE ROAD WEST〕/〔开启西の道〕,按钮〔One-time purchase〕/〔一次性购买〕,右边是价格字符串(由 StoreKit 格式化)。
* 商品没取到:〔Prices are unavailable right now. Try again later.〕/〔暂时无法读取价格。稍后再试。〕
* 请求出错:〔Could not reach the App Store.〕/〔连接 App Store 失败。〕
* 以上两种都会带一个〔Retry〕/〔重试〕按钮(只重新读价格,不购买、不登录)。
* 第一次读取完成前:〔Loading price…〕/〔正在读取价格…〕
* 已拥有:〔OPENED〕/〔已开启〕卡片,正文〔The road west is open. Thank you — it stays open.〕/〔西の道已经开启。谢谢 —— 这条路会一直在。〕
* **不论是否拥有都在的**恢复卡〔ALREADY BOUGHT IT?〕/〔已经买过?〕,按钮〔Restore Purchases〕/〔恢复购买〕。

返回:〔Back〕/〔返回〕回到设置,再按一次回到菜单。

(菜单上还有第二个入口:骑到京都之后路线条变成按钮,写着〔Tōkaidō complete · Kyōto reached〕。本卡一律走设置这条路,保证每台设备操作一致。)

**两条会误导你的行为:**

1. **app 回到前台时不会刷新 StoreKit,打开 The Road 页面也不会。** 只有三种时候会重新读:启动时、`Transaction.updates` 推送时、点 Restore 时。
   所以本卡里凡是"看它现在是什么状态",都是**强制退出 + 重新启动**:
   * iPhone:从底部上滑停住打开 app 切换器,把 Nihongo Ride 向上划掉,再从主屏幕点开。
   * Mac:⌘Q 退出,然后 `open "/Applications/Nihongo Ride.app"`。
2. **Restore 没有任何反馈。** 没有转圈,没有成功或失败提示,错误被吞掉。唯一可见的结果是卡片和设置行变成已拥有。
   点完什么都没变,不代表它没跑。

---

## 3. 证据放哪里

截图、Apple 收据邮件、订单号里有 Apple ID 邮箱 —— **全部放在 git 外面**:

```bash
EV="$HOME/Documents/NihongoRide-Evidence/stage1-walk-<YYYY-MM-DD>"
mkdir -p "$EV"
```

(`<YYYY-MM-DD>` 填走查当天的日期。)记录里只引用文件名 + sha256。

> 提醒,不替你决定:这台 Mac 自 macOS 27(2026-09-15 安装)起 `~/Documents` 在 iCloud 云盘的 File Provider 下,
> 所以这个文件夹会同步到 iCloud。能不能接受由你决定。

截图:Mac 用 ⇧⌘4 再按空格点窗口(默认存到桌面,移进 `$EV` 并按本卡的文件名改名);iPhone 用侧边键 + 音量上,AirDrop 到 Mac。

记时间(带时区,这就是后面 `--at` 要的格式):

```bash
python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'
```

输出形如 `2026-09-17T14:05:09+09:00`。

全部做完后算哈希(清单写在文件夹**旁边**,不写进文件夹,否则会改变文件夹内容):

```bash
python3 scripts/stage1_walk.py manifest "$EV" > "$EV.manifest.jsonl"; echo "exit=$?"
```

退出码 0。每行是一个文件的 sha256 + 大小 + mtime,可以直接贴进登记表条目的 `"evidence"`。

---

## 4. 今天的基线(2026-09-16 实测,购买之前)

这些数字是为了让你之后一眼认出"自己那一行"。报表按太平洋时间切日,最新一天是 2026-09-14。

**`python3 scripts/sales_report.py --calibrate`(默认全窗口 2026-06-06..09-14):exit 0**

* FIRST-TIME DOWNLOADS 155(macOS 89 · iOS 66);updates 521;redownloads 6;unclassified 0
* **PURCHASES gross 0 · refunded 0 · net 0 · proceeds 0.00** —— 整个窗口一笔购买都没有,所以你那一行出现时,
  它会是这个窗口里第一笔(除非恰好同一天有陌生人也买了;确认命令会把附近几天所有购买类行都列出来)。
* 发布日对照:updates release-day 15.2/d vs other 9.2/d = 1.65x;downloads 2.8/d vs 2.3/d = 1.24x;OK。

**自 day 0 起(`--since 2026-09-08 --no-cache --daily`)**

| 太平洋日 | 首次下载 | macOS | iOS |
|---|---|---|---|
| 09-08 | 0 | 0 | 0 |
| 09-09 | 4 | 3 | 1 |
| 09-10 | 3 | 1 | 2 |
| 09-11 | 5 | 3 | 2 |
| 09-12 | 2 | 1 | 1 |
| 09-13 | 1 | 1 | 0 |
| 09-14 | 3 | 3 | 0 |

09-09..09-14 共 18(mac 12 / iOS 6),3.0/天。地区:JP=8, CN=7, BR=1, NL=1, US=1。购买 0。

**Mac 容器现状:** `NihongoRide.entitlement.v1` **不存在**(检查 1 的前提成立);`NihongoRide.unlockOffer.v1` 已经是
`{"counts":{},"launches":4,"furthestBucket":2}`(来自以前本地的沙盒 Release 构建)。App Store 版本会共用这个容器,
所以 **Mac 上的计数器不会从零开始**。

**时钟。** 自 day 0 起 N = 18,3.0/天(到 2026-09-14 太平洋日)。照这个速度,**N = 35 大约在 2026-09-20(太平洋日)到达,
大约两天后才能在报表里读到**。N = 35 按 §K 本来就"record, falsifies nothing"。`--checkpoint` 在已知阳性匹配上之前,
**不会打印任何上界**,只打印 `BOUND WITHHELD:` 和全部原因。

---

## 步 0 · 预检(自动化,只读)

```bash
cd /Users/jason/Documents/typing_app
python3 scripts/stage1_walk.py preflight; echo "exit=$?"
python3 scripts/stage1_walk.py baseline; echo "exit=$?"
```

* **现在还没装 App Store 版本,所以 Mac 二进制那几行不会是 PASS;`preflight` 此时如果退出 1,只要 FAIL 都在 Mac 二进制那几行,就是预期。** 需要看的是:
  * ASC 那几行必须 PASS(两个平台 1.32 `READY_FOR_SALE`、build mac 56 / iOS 57、0 个进行中的审核提交、购买项目 `APPROVED` 且 `familySharable` false)。
    退出码 **3** = ASC/API 失败 → 先查原因,不要继续。
  * 容器那一行:`NihongoRide.entitlement.v1` absent = PASS,这就是检查 1 的前提。**如果显示 present**,这台 Mac 不能做检查 1
    (见文末"一次做不完怎么办"),停下来自己决定。
* `baseline` 跑 `sales_report.py --calibrate --json …` 和 `sales_report.py --checkpoint`,把两份输出和各自退出码存到
  `"$HOME/Library/Application Support/NihongoRide-Stats/walk/<UTC-timestamp>/"`。预期 `--calibrate` 为 0;
  `--checkpoint` 为 5(上界被扣住:登记表里还没有匹配上的购买)。

---

## 步 1 · 安装 App Store 1.32,并在 iPhone 上拍购买前的 OFFER

### Mac

1. App Store app 里用**你自己的** Apple 账号安装 Nihongo Ride(装到 `/Applications`)。记下安装时刻(上面的时间命令)——
   这次安装在报表里可能是一个首次下载(F1)或重新下载,登记表草稿要用。
2. 启动,只用:`open "/Applications/Nihongo Ride.app"`。新装会出引导页 →〔Skip〕。
3. **在 Mac 上不要打开 The Road,更不要点〔One-time purchase〕。** Mac 要留给检查 1。
4. 存两份输出:

   ```bash
   python3 scripts/stage1_walk.py preflight > "$EV/s1-01-mac-preflight.txt" 2>&1; echo "exit=$?"
   python3 scripts/stage1_walk.py mac-state > "$EV/s1-02-mac-state.txt" 2>&1; echo "exit=$?"
   ```

   `preflight` 现在必须是 **exit 0**。`mac-state` 里进程路径在 `/Applications` 下、有 receipt、1.32 / 56、entitlement 记录不存在。
5. (可选,和 §K 的计数器问题有关)菜单〔About & Credits〕/〔关于与致谢〕→〔ON-DEVICE COUNTERS〕/〔本机计数〕,截图 `s1-06-mac-about-counters.png`。
6. ⌘Q 退出。

### iPhone

1. **如果 iPhone 上已有 Nihongo Ride:** 长按图标 → 移除 App → **删除 App**。**不要**选"从主屏幕移除"或"卸载 App"(Offload 会留下数据)。
   要知道的代价:删除会清掉这台 iPhone 上没同步到 iCloud 的本地数据(设置、计数器等)。
   iCloud 同步只覆盖 SRSCard、RideRecord、Odometer、SavedWords、WordList、ConjugationSRSCard 六类记录。
2. App Store 安装 Nihongo Ride。记下安装时刻。
3. 从主屏幕启动 → 引导页〔Skip〕。
4. iPhone 保持解锁,在 Mac 上:

   ```bash
   python3 scripts/stage1_walk.py ios-state > "$EV/s1-03-ios-state.txt" 2>&1; echo "exit=$?"
   ```

   应为 1.32 / 57。
5. 〔Settings〕→ 滚到〔THE ROAD〕→ 截图 `s1-04-iphone-settings-row-offer.png`(应为〔The road past Kyōto〕)。
6. 点这一行 → The Road → **等至少 10 秒**让价格出来 → 截图 `s1-05-iphone-road-offer.png`(报价卡 + 价格按钮)。

   **这张就是检查 3 的阴性对照。** 没有它,之后看到"已拥有"什么也证明不了 —— 你无法排除它本来就显示已拥有。
   它只能在购买之前拍,购买之后无法补拍。
7. **不要点〔One-time purchase〕。** 拍完后强制退出 app(这样检查 3 观察到的是一次全新启动)。

---

## 步 2 · §L 检查 1:未登录 App Store(Mac,必须在购买之前)

**前提,以及理由**

* **这台 Mac 从未验证过这项购买**:`preflight` 显示 `NihongoRide.entitlement.v1` absent。理由:`Entitlement.swift` 在商店沉默时
  **从不撤销**,所以一台曾经验证过的设备,不管谁登录,都会永远显示〔OPENED〕—— 那会是一次假的 FAIL。这就是检查 1 排在购买之前的原因。
* 二进制是 `/Applications` 里的 App Store 1.32 (56)。
* app 没在运行。

**操作**

1. ⌘Q 退出 Nihongo Ride。
2. **只退出 App Store(媒体与购买项目),不要退出整个 Apple 账户 / iCloud。** 退出 iCloud 会影响钥匙串、iCloud 云盘和这个 app 的 CloudKit 同步。
   可能的路径 —— **在 macOS 27 上没有人核对过,菜单名称可能不同**:App Store app 的菜单栏"商店"→"退出登录";
   或 系统设置 → Apple 账户 → 媒体与购买项目 → 退出登录。记下你实际用的路径,截图显示已退出的状态:`g1-00-appstore-signed-out.png`。
3. `open "/Applications/Nihongo Ride.app"`。如果启动时弹出系统的登录框:**不要登录,点取消**,截图 `g1-00b-launch-prompt.png`,并逐字记下弹窗文字。
4. 〔Settings〕→ 滚到〔THE ROAD〕→ 截图 `g1-01-settings-row.png`。
5. 点这一行,记下时刻,**至少等 10 秒** → 截整个窗口 `g1-02-road-after-10s.png`。往下滚到〔ALREADY BOUGHT IT?〕→ 截图 `g1-03-restore-card.png`。
6. (可选)如果有〔Retry〕:点一次,再等 10 秒,截图 `g1-04-after-retry.png`。Retry 只调用 `store.load()`;
   读取进行中再点不会有任何作用,读过一次后界面会继续显示旧消息而不是〔Loading price…〕。
7. **未登录时不要点〔One-time purchase〕,也不要点〔Restore Purchases〕。** 两者都可能弹出登录框;在检查中途登录会让这次检查作废,而前者本身就是购买。
8. 点〔Back〕两次回到菜单(确认没有卡死),⌘Q。
9. 存状态:

   ```bash
   python3 scripts/stage1_walk.py mac-state > "$EV/g1-05-mac-state.txt" 2>&1; echo "exit=$?"
   ```

   entitlement 记录应仍不存在(`isEntitled` false)。
10. 用你自己的账号**重新登录 App Store**(步 3 需要)。

**要观察并如实记下的**

* 设置行在不在?文字是什么?
* The Road 页面打开了没有?
* **等满 10 秒后,价格区域到底显示什么** —— 以下哪一种,逐字:〔One-time purchase〕按钮 + 价格字符串(写下字符串)/
  〔Prices are unavailable right now. Try again later.〕/〔Could not reach the App Store.〕/〔Loading price…〕;有没有〔Retry〕。
* 〔Restore Purchases〕在不在?
* 有没有崩溃、卡死?

**§L 原文**

§L 原文 ▸ Sign out of the App Store on a Mac or device. Launch. Open Settings → The Road. **Expect:** the row is there, the screen opens, the price area says prices are unavailable and offers Retry, Restore is present, and nothing crashes. **Fail if:** the row is missing, or the screen claims the road is unlocked, or the app hangs.

§L 原文 ▸ **Expect:** the row is there, the screen opens, the price area says prices are unavailable and offers Retry, Restore is present, and nothing crashes.

§L 原文 ▸ **Fail if:** the row is missing, or the screen claims the road is unlocked, or the app hangs.

> **关于 Expect 里 "prices are unavailable" 的一句提醒 —— 不预判。** 代码只要商品读取成功就显示带价格的按钮,不管登没登录;
> 只有商品列表为空或请求抛错时才显示"unavailable"。未登录时 StoreKit 会不会读出商品,这里没人验证过(可能照常读出)。
> 所以你可能看到的是价格,而不是 Expect 写的那句话。**本卡不判断这算 PASS 还是 FAIL。** 把等满 10 秒后价格区域显示的内容逐字记下来,判断留给你。
> 同理,〔Could not reach the App Store.〕和 "prices are unavailable" 字面不同,也逐字记下。

**截图清单:** `g1-00-appstore-signed-out.png` ·(如有)`g1-00b-launch-prompt.png` · `g1-01-settings-row.png` · `g1-02-road-after-10s.png` ·
`g1-03-restore-card.png` ·(可选)`g1-04-after-retry.png` · `g1-05-mac-state.txt`

**结果(你来填):** 日期时间(含时区)`____` · 设备 `Mac ____ / macOS ____` · app `1.32 (56)` · 退出登录的路径 `____` ·
设置行 `____` · 价格区域(10 秒后,逐字)`____` · Retry `有 / 无` · Restore `有 / 无` · 崩溃或卡死 `有 / 无` · 你的判断 `____`

---

## 步 3 · §K 已知阳性购买(Mac,生产环境,你自己的账号)

§K 原文 ▸ make one real ¥10 purchase on the owner's own Apple Account **in production** (sandbox never appears in `salesReports`), confirm the row appears and `--calibrate` still passes, then refund it.

§K 原文 ▸ *An agent cannot do this step and must not try.*

**前提,以及理由**

* **检查 1 已在这台 Mac 上做完,且 App Store 已用你自己的账号重新登录。** 理由:买完之后这台 Mac 会永远显示〔OPENED〕,再也做不了检查 1。
* **iPhone 上的 `s1-05-iphone-road-offer.png` 已经拍好。** 理由:它是检查 3 的阴性对照,买完就补不回来。
* 生产环境:`/Applications` 里的 App Store 二进制 + 你自己的 Apple 账号。不是 sandbox 测试账号。
* **为什么在 Mac 上买:** macOS 的"冷安装"不是冷的(拖进废纸篓后 `~/Library/Containers/com.jasonye.nihongoride` 还在,
  购买记录会从磁盘读回来,而不是从 StoreKit),所以冷安装只能在 iOS 上做,所以购买必须在 Mac 上;
  另外 Mac 购买会走 `FI1`,是 `PURCHASE` 集合里最没把握的那个代码。**局限,明说:** 它只证明一个平台的代码;`IA1` / `IA9` 仍然没被观察到。

**价格,明说,不替你判断:** §K 写的"¥10"是 SKU 的**基准地区 CHN** 价格(¥10.00,开发者收入 8.42)。你看到的价格取决于你账号的 storefront:
日本 storefront 显示 **¥150**(收入 128),美国 **$0.99**(收入 0.84)。注意 "¥" 本身分不出人民币还是日元,看数字(10 还是 150)和收据邮件上的国家/地区。
如果这一点让你有顾虑,那是你的决定。

**操作**

1. 终端里准备好时间命令(第 3 节)。
2. `open "/Applications/Nihongo Ride.app"` →〔Settings〕→〔THE ROAD〕→ 点行 → The Road。
3. 等价格按钮出现 → 截图 `k-01-offer-price.png`。**逐字抄下按钮右边的价格字符串。**
4. 点〔One-time purchase〕。Apple 的购买弹窗出现 —— 能截图就截 `k-02-apple-purchase-sheet.png`(里面有 Apple ID,只放证据文件夹)。
   用你自己的账号确认(密码 / Touch ID 由你输入)。
5. **确认后立刻**在终端跑时间命令,把输出存下来:

   ```bash
   python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))' | tee "$EV/k-07-purchase-time.txt"
   ```

6. 看页面:应变成〔OPENED〕→ 截图 `k-03-road-opened.png`。如果出现任何提示(例如〔Awaiting approval. The road opens by itself once it is approved.〕
   或〔The App Store could not verify that purchase, so nothing was opened. If you were charged, use Restore Purchases.〕,或一段错误文字),截图并逐字记下。
7. 〔Back〕回设置:行应为〔The Tōkaidō and the Road West〕→ 截图 `k-04-settings-row-owned.png`。
8. 存状态:

   ```bash
   python3 scripts/stage1_walk.py mac-state > "$EV/k-05-mac-state.txt" 2>&1; echo "exit=$?"
   ```

   应能看到 `lastVerifiedAt`、`verifiedTransactionID`,`isEntitled` true。
9. **storefront / 国家:** 记下账号的国家或地区(收据邮件上有;在 macOS 27 上账号设置里的路径没人核对过)。
   后面的命令要的是**两位**国家码,和报表里一样(`JP`、`CN`、`US`),**不是** `JPN` / `CHN`。
10. **要保留的:** Apple 的收据邮件(存成 `.eml` 或 PDF:`k-06-apple-receipt.eml`),里面有订单号。订单号只留在证据文件夹里,不进 git。

**太平洋日规则。** Apple 的日报按太平洋时间切日。夏令时期间(到 2026-11-01)JST = PDT + 16 小时,所以:
**JST 16:00 之前的购买,算在前一个太平洋日**;16:00 之后算同一天。例:2026-09-17 14:05 JST = 2026-09-16 22:05 PDT → 报表日 2026-09-16。
(2026-11-01 之后变成 JST 17:00。)`--confirm-known-positive --at` 会自己算这个日子;这条规则是给你手工核对用的。

**截图清单:** `k-01-offer-price.png` · `k-02-apple-purchase-sheet.png` · `k-03-road-opened.png` · `k-04-settings-row-owned.png` ·
`k-05-mac-state.txt` · `k-06-apple-receipt.eml` · `k-07-purchase-time.txt`

**结果(你来填):** 购买时刻(ISO-8601 含时区)`____` · 太平洋报表日 `____` · 价格字符串(逐字)`____` · storefront / 两位国家码 `____` ·
页面结果 `____` · 任何提示(逐字)`____` · 订单号存放文件 `____`

---

## 步 4 · §L 检查 3:跨平台恢复 + 冷安装(iPhone)

**前提,以及理由**

* 购买前的 OFFER 截图 `s1-05-iphone-road-offer.png` 已有。理由:没有它,"已拥有"证明不了什么。
* 步 3 的购买已在 Mac 上完成;iPhone 的 App Store 登录的是**同一个** Apple 账号。
* iPhone 上是 App Store 1.32 (57)(`s1-03-ios-state.txt`)。
* **还没有退款。** 理由:退款后看到"未拥有",分不清是恢复失败还是被撤销。
* 这台 iPhone 不是从一台已验证过的设备的备份恢复出来的。

**方向,明说:** §L 这道检查叫 macOS ↔ iOS,本卡只走 **macOS → iOS** 这个方向。反方向(iOS 买、Mac 上看)需要 Mac 冷安装,而 Mac 冷安装不是冷的。
这够不够,由你决定。

### A · 重新启动(不是冷安装)

1. 如果 app 在运行:强制退出。理由:app 只在启动时、`Transaction.updates` 或 Restore 时读 StoreKit,回到前台不读。
2. 从主屏幕启动,记下时刻。
3. 〔Settings〕→ 滚到〔THE ROAD〕→ 截图 `g3-01-settings-row.png`。这一行可能在启动后几秒才变,所以停在设置页等约 10 秒,再截 `g3-02-settings-row-10s.png`。
4. 点行 → The Road → 截图 `g3-03-road.png`。
5. **先不要点〔Restore Purchases〕。**
6. 如果**没有**显示已拥有:等约 2 分钟 → 强制退出 → 重新启动 → 再看一次 → 截图 `g3-04-road-after-2min-relaunch.png`。
   **只有**这时仍未拥有,才点〔Restore Purchases〕**一次**,等约 10 秒 → 截图 `g3-05-road-after-restore.png`。
   记住 Restore 没有反馈,唯一的结果是卡片翻转。每一步发生了什么都如实记下。

### B · 冷安装(只在 iOS 上做)

**为什么只在 iOS:** 在 iOS 上"删除 App"会删掉数据容器;在 macOS 上容器会在废纸篓之后留下来,购买记录会从磁盘回来而不是从 StoreKit。
"卸载 App"(Offload)在 iOS 上也会留下数据 —— 不要用。

1. (可选,删除会清掉计数器)先截关于页计数器 `g3-11-about-counters-before-delete.png`。
2. 长按图标 → 移除 App → **删除 App**。
3. App Store 重新安装,记下时刻(报表里可能是一次重新下载,也可能不是 —— 取决于账号的下载历史;登记表草稿要用)。
4. iPhone 解锁,在 Mac 上:

   ```bash
   python3 scripts/stage1_walk.py ios-state > "$EV/g3-12-ios-state.txt" 2>&1; echo "exit=$?"
   ```

5. 启动 → 引导页(英文)〔Skip〕→〔Settings〕→〔THE ROAD〕→ 截图 `g3-13-settings-row-cold.png`,等 10 秒 → `g3-14-settings-row-cold-10s.png` →
   点行 → The Road → `g3-15-road-cold.png`。
6. 同一条规则:未拥有 → 等约 2 分钟,强制退出,重新启动,再看(`g3-16-road-cold-after-2min-relaunch.png`)→ 仍未拥有才点一次 Restore(`g3-17-road-cold-after-restore.png`)。

**要观察并如实记下的**

* A 和 B 各自:启动后设置行的文字(刚进设置时一次、约 10 秒后一次);The Road 上是〔OPENED〕还是报价卡。
* 有没有等 2 分钟、有没有重启、有没有点 Restore;点了之后发生了什么(记住它没有反馈,只看卡片是否翻转)。
* 任何提示或弹窗,逐字。

**§L 原文**

§L 原文 ▸ Buy on one platform. On the other, signed into the same Apple Account, launch and open Settings → The Road. **Expect:** owned, without tapping Restore. Then try it from a cold install. **Fail if:** Restore is needed and does not work.

§L 原文 ▸ **Expect:** owned, without tapping Restore.

§L 原文 ▸ **Fail if:** Restore is needed and does not work.

> 字面上有一种情况两句都不命中:需要点 Restore、而且 Restore 起作用了。那种情况只如实记录,判断是你的。

**截图清单:** A:`g3-01-settings-row.png` · `g3-02-settings-row-10s.png` · `g3-03-road.png` ·(如有)`g3-04-road-after-2min-relaunch.png` ·(如有)`g3-05-road-after-restore.png`
B:(可选)`g3-11-about-counters-before-delete.png` · `g3-12-ios-state.txt` · `g3-13-settings-row-cold.png` · `g3-14-settings-row-cold-10s.png` · `g3-15-road-cold.png` ·
(如有)`g3-16-road-cold-after-2min-relaunch.png` ·(如有)`g3-17-road-cold-after-restore.png`

**结果(你来填):** 日期时间(含时区)`____` · 设备 `iPhone ____ / iOS ____` · app `1.32 (57)` ·
A 启动后 `已拥有 / 未拥有`,是否等了 2 分钟 `____`,是否点了 Restore 及之后 `____` ·
B 冷安装后 `已拥有 / 未拥有`,是否等了 2 分钟 `____`,是否点了 Restore 及之后 `____` · 你的判断 `____`

---

## 步 5 · §L 检查 2:家庭共享(家人**自己的**设备)

**前提,以及理由**

* **在购买之后、退款之前。** 理由:买之前或退款之后,本来就没有东西可继承,"没继承到"是空的。
* **家人自己的设备,登录的是家庭群组里的第二个 Apple 账号。** 不能用你的 Mac 或 iPhone 换账号来做:它们已经验证过,不管谁登录都显示〔OPENED〕(理由同检查 1)。
* 这台设备从未验证过这项购买,也不是从你设备的备份恢复的。
* 装的是 App Store 1.32,而且只从 App Store 装。这台设备如果没和你的 Mac 配对,`ios-state` 读不到它,build 号就没有工具能确认 —— 如实记下这一点。
* 购买项目 `familySharable` = false(2026-09-16 ASC 实测)。这道检查要验证的是:家人**不会**继承。

> ### ➕ 阳性对照 —— 由本卡添加,§L 的原文里没有
>
> **"购买项目共享"必须是开着的,并且能观察到:家人在自己设备的 App Store 里看得到你(组织者)的购买。**
> 没有这一条,"没继承到"也可能只是因为共享整个关着 —— 检查就会空洞地通过。
> 可能的路径(**iOS 26 上没人核对过**):组织者设备 设置 → 你的名字 → 家人共享 → 购买项目共享;家人设备 App Store → 账户 → 已购项目,能看到你的名字。
> 截图 `g2-01-purchase-sharing-control.png`(在家人设备上)。**这条对照是否算这道检查的必要条件,由你决定。**

**操作**

1. 家人设备:用家人自己的账号从 App Store 安装 Nihongo Ride,记下时刻(这可能是那个账号的一次首次下载 —— 算不算进 N 是 `DRAFTS` 里的问题)。
2. 启动 →〔Skip〕→〔Settings〕→〔THE ROAD〕→ 截图 `g2-02-settings-row.png`,等 10 秒 → `g2-03-settings-row-10s.png`。
3. 点行 → The Road → 等至少 10 秒 → 截图 `g2-04-road.png`。
4. 强制退出 → 重新启动 → 再走一遍到 The Road → 截图 `g2-05-road-after-relaunch.png`(排除"只是还没送达")。
5. **不要点〔One-time purchase〕**(那是家人账号上的一笔真实购买)。§L 的步骤里没有 Restore,本卡不要求点;如果你决定点,记为 §L 之外的附加观察。

**要观察的:** 看到的是报价卡〔OPEN THE ROAD WEST〕+ 价格,还是〔OPENED〕;设置行是〔The road past Kyōto〕还是〔The Tōkaidō and the Road West〕。

**§L 原文**

§L 原文 ▸ On a second Apple Account in the same family group, launch and open Settings → The Road. **Expect:** the offer, not the owned state.

§L 原文 ▸ **Expect:** the offer, not the owned state.

§L 这一行**没有写 Fail if**。

**截图清单:** `g2-01-purchase-sharing-control.png` · `g2-02-settings-row.png` · `g2-03-settings-row-10s.png` · `g2-04-road.png` · `g2-05-road-after-relaunch.png`

**结果(你来填):** 日期时间(含时区)`____` · 设备 `____ / 系统 ____` · app `1.32 (____)` · 阳性对照(购买项目共享可见)`是 / 否 / 未查` ·
The Road 显示 `报价 / 已拥有` · 重启后 `____` · 你的判断 `____`

---

## 证据哈希(步 5 之后,当天做)

```bash
python3 scripts/stage1_walk.py manifest "$EV" > "$EV.manifest.jsonl"; echo "exit=$?"
```

---

## 步 6 · D+1 / D+2:确认报表里出现了这一行

在购买的太平洋报表日 D 发布之后跑(没发布会得到 6,明天再跑即可)。这是新的一天、新的终端,先把目录和 `EV` 重新设好:

```bash
cd /Users/jason/Documents/typing_app
EV="$HOME/Documents/NihongoRide-Evidence/stage1-walk-<走查那天的 YYYY-MM-DD>"
```


```bash
python3 scripts/sales_report.py --confirm-known-positive --kind purchase --at <购买时刻,如 2026-09-17T14:05:09+09:00> --platform macOS --country <两位国家码,如 JP> > "$EV/k-08-confirm-purchase.txt" 2>&1; echo "exit=$?"; cat "$EV/k-08-confirm-purchase.txt"
```

它会算出 D,无缓存重新拉 D-1..D+1,列出这三天**所有**购买类行和**所有** UNCLASSIFIED 行,在 D 上按 kind / 平台 / 国家匹配,然后跑一次默认全窗口的校准。

| 退出码 | 意思 | 你接下来做什么 |
|---|---|---|
| **0** | D 上匹配到了,**并且**全窗口校准 OK。会打印一份**草稿**登记表条目和一句**草稿** §K 句子,都标着"未记录" | 读一遍。你同意的话,自己把条目贴进 `docs/measurements/stage1-known-positives.json`(没有任何工具会写它),`"evidence"` 用 manifest 的 sha256 填,§K 文字见 `DRAFTS`。然后才轮到步 7 |
| **4** | 校准失败 —— 仪器不可信 | 不要记录匹配,不要退款。把输出留在证据文件夹,先查仪器 |
| **6** | PENDING:太平洋日 D 的报表还没发布 | 什么都不用做,明天再跑 |
| **7** | 报表已经有了,但没有匹配的行 | **不要退款。** 看输出里列出的 D-1..D+1 购买类行和 UNCLASSIFIED 行;核对 `--at` / `--platform` / `--country` 有没有填错。其余原因这里没人观察过,由你判断 |
| 2 | 找不到 vendor number | 修好再跑;对这笔购买什么也没说明 |
| 3 | API 失败 | 过会儿再跑;同上 |

然后单独确认 §K 那句 "`--calibrate` still passes"(默认全窗口,**不带** `--since`):

```bash
python3 scripts/sales_report.py --calibrate > "$EV/k-09-calibrate.txt" 2>&1; echo "exit=$?"
```

应为 0。**不要**用 `--since 2026-09-09 --calibrate` 代替:那个窗口里没有任何 `RELEASE_DAYS` 里的日子,按设计退出 4
("no release days in window — cannot run the positive control"),2026-09-16 实测就是 4。

你把条目贴进登记表之后:

```bash
python3 scripts/sales_report.py --checkpoint > "$EV/k-10-checkpoint.txt" 2>&1; echo "exit=$?"
```

退出码:**0** 上界已打印,或零购买上界不适用 · **5** 上界被扣住(输出 `BOUND WITHHELD:` 和每一条原因,例如 `first_download`
条目存在而对应决定还是 null)· **4** 校准失败。

(可选)为首次下载条目找对应的报表日数据。报表行是汇总,**无法确定地把某一个单位归到某一次安装上**:

```bash
python3 scripts/sales_report.py --since <报表日 YYYY-MM-DD> --until <报表日 YYYY-MM-DD> --no-cache --json "$EV/sales-<报表日>.json"; echo "exit=$?"
```

---

## 步 7 · 退款(只在步 4、步 5 做完,且步 6 匹配上之后)

**前提,以及理由:** 检查 3 的 A 和 B、检查 2 都已做完;步 6 退出码 0。理由:先退款会让检查 2 变空、让检查 3 的"未拥有"无法解释。

1. 你本人:打开 reportaproblem.apple.com,找到 Nihongo Ride 这笔购买,申请退款。记下申请时刻(含时区),截图 `r-01-refund-request.png`。
2. 保存 Apple 的处理结果邮件 `r-02-refund-decision.eml`,记下批准时刻。如果 Apple 拒绝,如实记下(§K 没有这种情况的规则,见 `DRAFTS` 的问题清单)。
3. 退款行出现之后(可能要几天;销售脚本的注释说退款最多可在售出后约 90 天才出现),跑:

   ```bash
   python3 scripts/sales_report.py --confirm-known-positive --kind refund --at <退款批准时刻,ISO-8601 含时区> --platform macOS --country <两位国家码> > "$EV/r-03-confirm-refund.txt" 2>&1; echo "exit=$?"; cat "$EV/r-03-confirm-refund.txt"
   ```

   退出码同上表。**明说一个没被观察过的地方:** 退款行落在哪个太平洋日、和批准邮件的时间差多少,这里没人见过真实的退款行。
   命令只看 D-1..D+1,所以 7 也可能只是行落在别的日子 —— 不要据此下结论,把输出留下,由你判断是否换一个 `--at` 再跑。

---

## 可选 · 退款后观察撤销(**不属于 §K,也不属于 §L**)

任何一道检查都不依赖它。代码只有在 `Transaction.latest(for:)` 给出一个带撤销的交易时才会撤销。

* Mac:⌘Q → `open "/Applications/Nihongo Ride.app"` →〔Settings〕→〔THE ROAD〕→ 截图 `o-01-mac-road-after-refund.png`;
  `python3 scripts/stage1_walk.py mac-state > "$EV/o-02-mac-state-after-refund.txt" 2>&1; echo "exit=$?"`(看 `revokedAt`)。
* iPhone:强制退出 → 启动 →〔Settings〕→〔THE ROAD〕→ 截图 `o-03-iphone-road-after-refund.png`。
* 记下设置行是否变回〔The road past Kyōto〕。

---

## 一次做不完怎么办

**单独做也仍然有效的子集**

* **只做步 0–1**(安装 + iPhone 购买前 OFFER 截图):什么都没破坏。前提是之后购买确实发生在这张截图之后。
* **只做步 0–2**(Mac 上的检查 1),在购买前停下:有效,检查 1 不需要购买。
* **步 0–3 + 检查 3 的 A 一次做完,B 和检查 2 改天:** 有效,只要还没申请退款。
* **步 6** 在报表日 D 发布后的任何一天跑都行,不依赖步 4、5。
* 如果 `preflight` 显示 Mac 上 `NihongoRide.entitlement.v1` present:这台 Mac 做不了检查 1。换一台从未验证过的设备会偏离事先定好的顺序 —— 停下,由你决定。

**会毁掉证据、而且不能重来的顺序**

1. **在检查 2 和检查 3 之前退款。** 检查 2 变空(没有东西可继承);检查 3 看到"未拥有"时分不清是恢复失败还是被撤销。
2. **在一台曾经验证过的设备上做检查 1** —— 包括步 3 之后的这台 Mac、检查 3 之后的这台 iPhone。按设计它会永远显示〔OPENED〕→ 假 FAIL。
3. **在 iOS 上买,然后想在 Mac 上做冷安装。** Mac 的容器在废纸篓之后还在,"冷"不是冷的;而买过的 iPhone 也已经验证过。整个顺序就是为了避开这一条。
4. **在非 App Store 二进制上走**(Xcode Run、本地构建、TestFlight)。本地 `.storekit` 交易或 sandbox 交易不会进 `salesReports`;
   在 iPhone 上它还会覆盖掉 App Store 版本。走完什么都不证明,必须在 App Store 版本上重走;在 sandbox 里"买"的那一笔不算 §K 的购买。
5. **在拍 iPhone 购买前 OFFER 截图之前就购买。** 检查 3 就没有阴性对照,之后补不回来。
6. **检查 3 里没等 2 分钟、没重启就点了 Restore。** 那一次安装的"不点 Restore 就已拥有"这个观察就丢了,而且 `AppStore.sync()` 已经跑过,无法干净地重来。
7. **用"卸载 App"代替"删除 App"。** 数据留下,冷安装不冷。
