# App Store Connect — 上架元数据 / Metadata

> **这份文件不是单一事实来源,活着的 App Store Connect 才是。** 它曾经这样自称,然后陈旧了
> 二十二个版本:描述里停在 v1.28 之前的措辞、What's New 停在 v1.8.1、`ja` locale 从头到尾
> 没有出现过 —— 而这三样在线上都早已不同。一份声称自己是真相、实际落后于被描述系统的文档,
> 正是这个项目给自己命名过的缺陷:**「仓库里描述一件工作的产物,在待办和已办两种情况下长得
> 一模一样。」**
>
> 所以它现在的角色被写清楚:
>
> * **当前上架文案**(name / subtitle / keywords / description)—— 下面各 locale 段落保存
>   *撰写稿*,并注明最后一次与 ASC 对读的日期。改动之前请先 GET 一次线上文本再动手。
> * **每次发布的 What's New 与审核备注** —— **不在这里**。它们在那一次发布的
>   `scripts/submit_<version>.py` 里,由脚本 PATCH 后逐字节回读。下面 v1.8.1 及更早的段落
>   是历史记录,保留原样,不要改。
> * **价格、可售地区、内购** —— ASC 是唯一权威,下面只记不变的事实与 id。
>
> 最后一次与线上逐字节对读:**2026-08-31(v1.30 提交时)**,三个 locale 的 description
> 全部核过。字符数已核对在 App Store 限制内。

## 基本信息 / Core

| 字段 | 值 |
|---|---|
| App Name | **Nihongo Ride** |
| Bundle ID | `com.jasonye.nihongoride` (resource `W66A3AJT2D`) |
| SKU | `nihongoride-mac-2026` |
| Platform | macOS (14.0+) |
| Primary language | English (U.S.) |
| Primary category | Education |
| Secondary category | Reference |
| Age rating | 4+ (no objectionable content) |
| Price | **Free**,含一项非消耗型内购(见下方 In-App Purchase 段) |
| Copyright | © 2026 Yuhe Ye |
| Support URL | https://jasonyeyuhe.github.io/nihongo-ride/support.html |
| Marketing URL | https://jasonyeyuhe.github.io/nihongo-ride/ |
| Privacy Policy URL | https://jasonyeyuhe.github.io/nihongo-ride/privacy.html |

> **Corrected 2026-08-30 against the live record**, not from memory: this row said
> *"Games — Word (optional)"*. `GET /v1/appInfos/e66ae118-…?include=primaryCategory,secondaryCategory`
> returns `EDUCATION` / `REFERENCE`, with no Games classification at all.
>
> The staleness was not cosmetic. A Stage 1 reviewer read this line and raised mainland China's
> licence requirement (版号) for **games** offering in-app purchase as a possible hard block on
> the base territory — which is 48% of installs. It does not apply, and the five minutes that
> established that were spent because a document disagreed with the thing it describes.

App Privacy: **Data Not Collected**(离线可用、无开发者账号体系、无统计分析)。
v1.30 起 app 有一项可选内购,它由 App Store 通过用户自己的 Apple 账户完成 —— 这不改变 `Data Not Collected`(它禁止的是收集,不是购买),但**改变了 description 里那句
「无账号」能被怎么读**,所以 en-US 与 zh-Hans 的那一句在 v1.30 被限定过。见下。

---

## English (U.S.)

**Name** (≤30): `Nihongo Ride`

**Subtitle** (≤30): `Type your way across Japan`

**Keywords** (≤100): `japanese,typing,kana,hiragana,katakana,JLPT,vocabulary,romaji,learn,study,N5,furigana`

**Promotional text** (≤170): **线上未设置**(2026-08-31 GET 确认,三个 locale 都是 null)。
下面这句是 v1.7 时代的草稿,从未上线,且它引用的 183 篇文章早已是 233 篇 —— 保留仅作记录:
`Ride from Tokyo to Kyoto while you learn JLPT N5–N1 vocabulary. Now with 183 calm Practice passages and a BLIND typing challenge.`

**Description** (≤4000):
```
Nihongo Ride is a calm, focused typing-practice app that actually teaches you Japanese.

Most typing games test speed. Nihongo Ride teaches — kana, vocabulary, and real sentences — while you ride your way across Japan, from Tokyo to Kyoto. Type the correct reading and you move forward. Miss a word and it comes back later, exactly when you need it.

WHY IT'S DIFFERENT
• A built-in mini-IME. Type romaji on your normal keyboard — no system IME, no setup. It accepts every valid spelling (shi or si, tsu or tu, n or nn) and matches your keystrokes to kana in real time.
• Learn, don't just race. Every word shows its kana, an optional romaji hint, and its meaning in English and Chinese.
• Smart review. Words you mistype flow into a spaced-repetition queue (SM-2), so your practice targets your real weak spots.

THREE WAYS TO RIDE
• Journey — an immersive ride across Japan; type to keep moving and unlock famous stops.
• Time Attack — 60 seconds, as many words as you can.
• Practice — a quiet, distraction-free mode for word drills or long passages, with an optional BLIND challenge that hides all romaji hints.

CONTENT
• 7,000+ words across JLPT N5 to N1, with English and Chinese meanings.
• Example sentences and 233 reading passages — from everyday greetings to short literary paragraphs.
• Katakana loanwords supported, with foreign-sound digraphs.

PRIVATE BY DESIGN
• Works fully offline. No sign-up and no account with the developer, no ads, no tracking, and no analytics of any kind. The one optional in-app purchase is handled by the App Store, through your own Apple Account.
• Your progress stays on your device. Optional iCloud sync uses your own private iCloud database, which the developer cannot see inside, and the app is fully usable with it switched off.

Whether you're starting N5 or polishing N1, Nihongo Ride turns daily typing into real Japanese progress. Hop on and ride.
```

---

## 简体中文 (zh-Hans)

**Name** (≤30): `Nihongo Ride`

**Subtitle** (≤30): `打字环游日本 边骑边学`

**Keywords** (≤100): `日语,打字,假名,平假名,片假名,JLPT,单词,学日语,罗马音,N5,练习,日语学习`

**Promotional text** (≤170): **线上未设置**(同上)。以下为未上线的旧草稿:
`从东京骑到京都,一路学 JLPT N5–N1 单词。新增 183 篇禅意 Practice 文章与「盲打」挑战。`

**Description** (≤4000):
```
Nihongo Ride 是一款安静、专注的打字练习应用,真正帮你学会日语。

大多数打字游戏只考速度。Nihongo Ride 教你——假名、单词、真实句子——边骑车环游日本,从东京一路骑到京都。打对读音就前进;打错的词稍后会在你最需要时再次出现。

为什么不一样
• 内置迷你 IME。在普通键盘上敲罗马音即可,无需系统输入法、无需设置。逐键、多路径匹配,接受所有合法拼写(shi / si、tsu / tu、n / nn),实时转成假名。
• 不只是比速度,而是真学。每个词都显示假名、可关的罗马音提示,以及中英文词义。
• 智能复习。打错的词进入间隔复习队列(SM-2),让练习精准命中你的薄弱点。

三种骑行模式
• 环游(Journey)——沉浸式骑行环游日本,打字前进、解锁经典景点。
• 限时(Time Attack)——60 秒,尽可能多打。
• 练习(Practice)——安静无干扰,词流或长文章皆可,并有隐藏全部罗马音提示的「盲打」挑战。

内容
• JLPT N5 到 N1 共 7000+ 词,含中英文词义。
• 例句 + 233 篇阅读文章——从日常问候到短篇文学段落。
• 支持片假名外来词与外来音 digraph。

隐私至上
• 完全离线可用。无需注册,开发者这边也没有你的账号,无广告、无追踪,也没有任何统计分析。唯一的一项可选内购由 App Store 通过你自己的 Apple 账户完成。
• 学习进度留在你自己的设备上。iCloud 同步(可在设置里关闭)用的是你自己的私有 iCloud 数据库,开发者看不到里面的内容;关掉它,App 依然完整可用。

无论你是刚开始 N5,还是在打磨 N1,Nihongo Ride 把每天的打字变成真实的日语进步。上车,出发。
```

---

## 日本語 (ja)

> **2026-08-27 随 v1.28 上线,两个平台都有,并且是完整的**:name / subtitle / description /
> keywords / support URL / marketing URL / 本地化 release notes。
>
> 这一段之所以直到现在才出现在这份文件里,本身就是这个项目付过两次学费的那个形状:
> `docs/store/ja-listing.json`、`ja-listing-draft.md`、`scripts/add_locale.py` 这三个撰写产物,
> 在「待发」和「已发」两种情况下长得完全一样。2026-08-30 一次 Stage 1 评审据此建议「把日语
> 商店页做了吧」,而它三天前就已经在线上了。**能分辨的只有活系统或 `git log`** ——
> `git log --grep` 会给出 *"feat(v1.28): the ja storefront locale is live in ASC"*。
>
> **撰写稿在 `docs/store/ja-listing.json`,并且经过母语者审阅** —— 这是本 app 唯一经过母语
> 审阅的 locale,所以往里加未经审阅的日语是有代价的,不要为了「三个语言看起来一致」而改它。

**Name** (≤30): `Nihongo Ride`

**Keywords** (≤100): `日本語学習,JLPT,日本語能力試験,N5,N4,N3,N2,N1,単語,ひらがな,カタカナ,漢字,読み方,例文,読解,暗記,語彙力,かな入力`

**Description**:线上文本(2026-08-31 逐字节 GET,1177 字符)。撰写稿见
`docs/store/ja-listing.json`;改动前先 GET 一次。

> **v1.30 没有改这一段,而这是一个决定,不是遗漏。** en-US 的 `No account` 和 zh-Hans 的
> 「无账号」都是无限定的,在有内购之后会被读成「买东西也不需要账号」,所以两句都补了限定。
> 日语这句写的是 **`アカウント登録は不要`** —— **登録**,注册 —— 买家用的是自己**已有的**
> Apple 账户,不向开发者注册任何东西,所以它在 v1.30 之后仍然为真。
> 为了对齐而改它,等于把一句已经无歧义的话换成一句需要限定的话:看起来是统一,实际是放宽。

---

## In-App Purchase — Stage 1

> ASC 是唯一权威。这里只记不会变的事实和 id,不作为填写来源。

| 字段 | 值 |
|---|---|
| Reference name | `Nihongo Ride Scenery — the road west` |
| Product ID | `com.jasonye.nihongoride.scenery.lifetime` **(永久不可改)** |
| ASC id | `6806755720` |
| Type | `NON_CONSUMABLE` |
| Family Sharing | **off**(Apple 说明:打开之后无法撤销) |
| 基准价 | CHN ¥10.00,净 **¥8.42**(查自 ASC price points,不是按 15 percent 推的) |
| 等价地区 | 174 个自动等价;可售 **175** 个地区(含 CHN / JPN / USA) |
| 本地化 | en-US / ja / zh-Hans 三条 |
| 审核截图 | 1320×2868,`assetDeliveryState=COMPLETE` |
| 首次提交 | 随 **v1.30**(Apple 要求每种类型的第一个内购必须跟随一个新版本提交) |
| 提交端点 | `POST /v1/inAppPurchaseSubmissions`(**不是** `reviewSubmissionItems` —— 它不接受 IAP,已实测) |

三条本地化描述(2026-08-30 PATCH 后逐字节回读):

```
en-US    The Road West   / One-time. The road west: Kyoto to Nagasaki.
ja       西への道         / 買い切り。京都から長崎まで、西への道すべて。
zh-Hans  西行之路         / 一次性购买。京都到长崎,完整的西行之路。
```

**「永久」描述的是拥有的时长,不是无限的未来目录。** 卖的是京都→长崎这一条路和它的风景;
以后的新路线可以作为礼物送给已购买者,但不是承诺。买家实际读到的措辞在 `RoadView.boundary`,
由 `PurchasePromiseTests` 钉住 —— 不要照 product id 里的 `scenery` 反推卖了什么。

⚠️ **新建的内购不会继承 app 的地区可售性**:全新产品的 availability 资源**根本不存在**(404),
ASC 对此只字不提,而放着不管的产品在每一个地区都静默不可购买。这是必做的一步,不是一个检查项。

---

## 截图 / Screenshots (2880×1800)

Source: `NIHONGO_SHOT=/tmp/nihongo-store NIHONGO_SHOT_STORE=1 swift run NihongoRideApp`

**v1.1 macOS upload order(menu.png 已弃用 — ImageRenderer 黄占位条,2.3.3 风险):**
1. `game.png` — 骑行环游(主玩法)
2. `journal.png` — 骑行日志(1.1 新功能)
3. `practice.png` — Practice 长文章
4. `results.png` — 结算 + 评级
5. `practice-blind.png` — 盲打挑战
6. `game-mid.png` — 旅程中段(富士山)

**v1.1 iPhone (APP_IPHONE_67, 1320×2868) order**(真机截屏,
`TEST_RUNNER_NIHONGO_STORE_SHOTS=1 xcodebuild … -only-testing:…StoreScreenshotTests test` → `xcresulttool export attachments`):
1. `*-2-game.png` 2. `*-5-journal.png` 3. `*-1-menu.png`(真截屏,无占位问题) 4. `*-4-practice.png` 5. `*-3-results.png`

---

## v1.8.1 What's New / 新功能

> Ships: iCloud sync for the Conjugation Review (the v1.8 §C code, shipped gated off in 1.8,
> is now ON — AppModel.conjSRSSyncAvailable = true). The ConjugationSRSCard record type is
> deployed to CloudKit PRODUCTION (2026-07-05 via cktool + Console; also fixed the WordList
> gap so named-list sync works in Prod). No other user-facing change. Same copy both
> platforms. NOTE: no star glyph. Canonical copy → `scripts/submit_1_8_1.py`.

### English (≤4000)
```
• Conjugation Review now syncs across your devices via iCloud — the verb forms you're due to review follow you from Mac to iPhone to iPad, so you can pick up right where you left off.
• Sync reliability improvements.
```

### 简体中文
```
• 「变形复习」现在通过 iCloud 在你的设备间同步——到期要复习的动词变形会从 Mac 跟到 iPhone、iPad,让你随时接着上次的进度练。
• 同步稳定性改进。
```

### Review notes (both platforms)
v1.8.1 enables iCloud sync for the v1.8 verb-conjugation review — the SM-2 schedule for verb forms syncs across the user's own devices via their private CloudKit database (a SEPARATE store from the vocabulary review; no new data collected). iCloud optional; app fully usable without it. No other user-facing change.

---

## v1.8 What's New / 新功能

> Ships: Verb-Conjugation Review (spaced repetition for verb forms — local; the drill
> now remembers which forms you miss and brings them back on schedule, weighted toward
> your weak forms), more verbs to drill (the ずる verbs — 演ずる/感ずる… — are unlocked),
> and Kana Read-Aloud (opt-in offline Japanese text-to-speech button on the cards).
> iCloud sync of the conjugation review is built but GATED OFF this version (ships local
> only) — so do NOT mention cloud sync. Same copy for macOS and iOS. NOTE: What's New
> REJECTS the "★" glyph — no star glyph. Canonical copy → `scripts/submit_1_8.py`.

### English (≤4000)
```
• NEW: Conjugation Review — verb-conjugation practice now remembers the forms you get wrong and brings them back with spaced repetition, weighted toward your weakest forms. A "Review N due" button appears in the menu when forms are ready.
• More verbs to drill: the ずる verbs (演ずる, 感ずる, 信ずる, and more) are now conjugable, adding N1/N2 verbs to the pool.
• NEW: Read Aloud — turn on the speaker button (in Settings) to hear the kana spoken with an offline Japanese voice, on the word and conjugation cards.
• Polish and fixes throughout.
```

### 简体中文
```
• 新增「变形复习」：动词变形练习现在会记住你答错的变形，用间隔复习把它们按时带回来，并向你最薄弱的变形加权。有到期变形时，菜单会出现「复习 N 个」按钮。
• 更多可练动词：ずる 动词（演ずる、感ずる、信ずる 等）现已可变形，为词池加入 N1/N2 动词。
• 新增「假名朗读」：在设置里打开朗读按钮，即可在单词卡与变形卡上用离线日语语音听假名发音。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
v1.8 = Conjugation Review (local spaced repetition for verb forms, its own separate store — never touches vocabulary review) + ずる verbs unlocked (conjugation labels derived from EDRDG JMdict, CC BY-SA, credited in About) + opt-in offline kana Text-to-Speech (AVSpeechSynthesizer, ja-JP). All local + offline; no new data collected; iCloud not required (conjugation cloud sync is present but disabled this release).

---

## v1.7 What's New / 新功能

> Ships: Dynamic Type / "Larger Text" support across the whole app (accessibility;
> identical at the default size), a "Weak Words" cram (drills your hardest reviewed
> words, never writes SRS), and conjugation-form selection (pick which forms to drill).
> Same copy for macOS and iOS. NOTE: What's New REJECTS the "★" glyph — no star glyph.
> Canonical copy lives in `scripts/submit_1_7.py` (WHATS_NEW / REVIEW_NOTES).

### English (≤4000)
```
• Bigger text support: Nihongo Ride now follows your system "Larger Text" (Dynamic Type) setting across the whole app, so the menus, word cards, and stats scale up for easier reading.
• NEW: Weak Words — a focused cram of the words you struggle with most, drawn from your review history. It's pure practice: it never changes your spaced-repetition schedule.
• Verb Conjugation: choose exactly which forms to drill (te-form, past, negative, potential, volitional, and more) from the menu, instead of always getting every form.
• Polish and fixes throughout.
```

### 简体中文
```
• 更大字体支持：にほんご ライド 现在全 app 跟随系统「更大字体」（动态字体）设置，菜单、单词卡与统计都会随之放大，更易阅读。
• 新增「弱词练习」：从你的复习记录里挑出你最薄弱的词，集中强化。纯练习，绝不改动你的间隔复习计划。
• 动词变形：现在可在菜单里精选要练哪些变形（て形、过去、否定、可能、意志等），不必每次全练。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
v1.7 = Dynamic Type support (accessibility; unchanged at default size) + Weak Words practice (pure cram, no SRS write) + conjugation-form selection (local menu pref). All local + offline; no new data collected; iCloud not required.

---

## v1.5 What's New / 新功能

> Ships: Custom Word Lists (the v1.4 Saved deck generalizes into N named lists,
> synced privately via iCloud), a first-launch intro, and a VoiceOver pass.
> Same copy for macOS and iOS. NOTE: App Store What's New REJECTS the "★" glyph
> ("can't contain ★") — keep it as the word "star" / "星标".

### English (≤4000)
```
• NEW: Custom Word Lists — make as many named lists as you like. Tap the star to save a word to your favourites, or long-press it to file the word into any list. Practice any list on its own, right from the menu. Your lists sync privately across your devices via iCloud.
• NEW: A short, skippable intro on first launch — romaji spelling, the three modes, and saving words.
• Accessibility: VoiceOver now reads every screen — the HUD, score cards, ride log, settings, and your word lists.
• Polish and fixes throughout.
```

### 简体中文
```
• 新增「自定义词单」:想建几个就建几个。点星标把词加入收藏,长按可把它归入任意词单;在菜单里单独练习任何一个词单。你的词单通过 iCloud 在设备间私密同步。
• 新增首次启动的简短引导(可跳过):罗马音拼写、三种模式、收藏词。
• 无障碍:VoiceOver 现已朗读每一个界面——HUD、成绩卡、骑行日志、设置,以及你的词单。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
```
Nihongo Ride is a fully offline-capable typing-practice app for Japanese
learners. No account or login is required; the developer collects no data.

Version 1.5 adds Custom Word Lists. Lists (and the favourites/saved deck) are
the user's OWN content, stored locally and, when iCloud sync is on, in the
user's PRIVATE iCloud (CloudKit private database) — not accessible to the
developer. The app is fully usable without signing in to iCloud. The first-
launch intro does not request any permissions and can be skipped.
```

## v1.4 What's New / 新功能

> Ships: iCloud sync (SRS progress / ride log / saved words, private CloudKit) +
> the Saved Words deck. Same copy for macOS and iOS.

### English (≤4000)
```
• NEW: iCloud sync — your review progress, ride log, and saved words now follow you across all your devices, automatically and privately.
• NEW: Saved Words — tap the star to save any word (on the word card or the results screen), then drill your saved deck right from the menu.
• Polish and fixes throughout.
```

### 简体中文
```
• 新增 iCloud 同步:复习进度、骑行日志、收藏词单在你的设备间自动、私密地同步。
• 新增「收藏词单」:打字时或结算页点星标收藏任意词,在菜单里随时开练你的收藏。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
```
Nihongo Ride is a fully offline-capable typing-practice app for Japanese
learners. No account or login is required; the developer collects no data.

Version 1.4 adds iCloud sync and a Saved Words deck. iCloud sync stores the
user's own review progress / ride log / saved words in their PRIVATE iCloud
(CloudKit private database) — it is the user's own data, not accessible to the
developer, and can be turned off in Settings. The app is fully usable without
signing in to iCloud (everything is kept locally too).
```

## v1.3 What's New / 新功能

> Ships: Game Center (Time Attack leaderboard + 5 achievements). iCloud sync is
> built but deferred to v1.4 (needs the CloudKit container + a device schema run
> + 2-device verification). Same copy for macOS and iOS.

### English (≤4000)
```
• NEW: Game Center — climb the Time Attack leaderboard and earn achievements: First Ride, Century (100 words), Long Hauler (1,000 words), a Seven-Day Streak, and a Flawless Run.
• Polish and fixes throughout.
```

### 简体中文
```
• 新增 Game Center:登上「限时赛」排行榜,解锁成就——首次出发、百词、千里(1000 词)、七日连骑、完美一程。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
```
Nihongo Ride is a fully offline typing-practice app for Japanese learners. No
account or login is required; no data is collected.

Version 1.3 adds Game Center: a Time Attack leaderboard and five achievements.
Game Center is optional — the app is fully playable without signing in. On iOS
the on-screen keyboard appears automatically on the game screen (type the romaji
shown under each word); Pause and End run are touch buttons in the HUD.
```

## v1.2 What's New / 新功能

> Ships: persisted Settings screen + opt-in daily review reminders. (iCloud sync
> is built but deferred to a later version until the CloudKit container is set up.)
> Same copy for macOS and iOS — both platforms get the features.

### English (≤4000)
```
• NEW: Daily review reminders — turn them on in the new Settings screen and get a gentle nudge when words are due, counted accurately for each day ahead.
• NEW: Settings screen — your language, romaji hints, sound and reminder preferences now stay put between launches.
• Polish and fixes throughout.
```

### 简体中文
```
• 新增「每日复习提醒」:在新的「设置」页里开启,词到期时温柔提醒你,并按未来每天的实际到期数显示。
• 新增「设置」页:语言、罗马字提示、音效与提醒偏好现在会跨启动保存。
• 多处细节打磨与修复。
```

### Review notes (both platforms)
```
Nihongo Ride is a fully offline typing-practice app for Japanese learners. No
account or login is required. No data is collected.

Version 1.2 adds a Settings screen and an OPTIONAL daily "reviews due" reminder.
Notifications are OFF by default and strictly opt-in: the user enables them in
Settings → Review Reminder (and can turn them off there at any time). The app
requests notification permission only when the user flips that switch on.
```

## v1.1 What's New / 新功能

### macOS — English (≤4000)
```
• NEW: Ride Log — your typing travel diary. Daily streak, lifetime words and kilometres, a WPM trend drawn as the road you've ridden, upcoming reviews, and your last ten runs.
• 720 new example sentences across N3–N1, and 50 new literary practice passages (now 233).
• Polish and fixes throughout.
```

### macOS — 简体中文
```
• 新增「骑行日志」:连续天数、累计词数与里程、WPM 趋势(画成你骑过的那条路)、复习到期预报、最近十程列表。
• 新增 720 条 N3–N1 例句、50 篇文学风练习段落(现共 233 篇)。
• 多处细节打磨与修复。
```

### iOS — English (≤4000)
```
• NEW: iPhone support — the whole ride, redesigned for portrait. Everything fits neatly above the on-screen keyboard.
• NEW: Ride Log — your typing travel diary. Daily streak, lifetime words and kilometres, a WPM trend drawn as the road you've ridden, upcoming reviews, and your last ten runs.
• 720 new example sentences across N3–N1, and 50 new literary practice passages (now 233).
• The menu and results screens no longer pop up the keyboard — it appears only where you type.
```

### iOS — 简体中文
```
• 新增 iPhone 支持:整个骑行之旅为竖屏重新设计,所有内容都稳稳排布在屏幕键盘上方。
• 新增「骑行日志」:连续天数、累计词数与里程、WPM 趋势(画成你骑过的那条路)、复习到期预报、最近十程列表。
• 新增 720 条 N3–N1 例句、50 篇文学风练习段落(现共 233 篇)。
• 菜单与结算页不再弹出屏幕键盘——键盘只在需要打字的地方出现。
```

### iOS 1.1 审核备注 / Review notes
```
Nihongo Ride is a fully offline typing-practice app for Japanese learners.
No account or login is required. No data is collected.

On iPad and iPhone the on-screen keyboard appears automatically on the game
screen — type the romaji shown under each word to ride forward. Pause (⏸) and
End run are touch buttons in the HUD; Practice mode has touch Next/Done
buttons. Version 1.1 adds iPhone (portrait) support and a Ride Log progress
screen, reachable from the main menu.
```

## 审核备注 / Review notes — **v1.0 时代的记录,不是当前文案**

> 这一段原本没有版本标注,于是读起来像是「现在提交用的备注」,而它有两处已经是假的:
> **`No network connection is made`** 在 v1.28 就被更正过(`iCloudSyncEnabled` 默认为 true,
> app 默认就会通过 CloudKit 联网),而 app 也早已不是 macOS-only。
>
> **当前的审核备注在那一次发布的 `scripts/submit_<version>.py` 里**,由脚本 PATCH 后逐字节
> 回读 —— v1.30 的在 `scripts/submit_1_30.py: REVIEW_NOTES`。下面保留原文作为记录。

```
Nihongo Ride is a fully offline macOS typing-practice app for Japanese learners.
No account or login is required. No network connection is made. No data is collected.
To test: launch, press Start ride, and type the romaji shown under each word
(a physical keyboard is required). All three modes are reachable from the main menu.
```
