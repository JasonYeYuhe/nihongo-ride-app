# App Store Connect — 上架元数据 / Metadata

> 单一事实来源。Chrome/API 填写时从这里复制。字符数已核对在 App Store 限制内。

## 基本信息 / Core

| 字段 | 值 |
|---|---|
| App Name | **Nihongo Ride** |
| Bundle ID | `com.jasonye.nihongoride` (resource `W66A3AJT2D`) |
| SKU | `nihongoride-mac-2026` |
| Platform | macOS (14.0+) |
| Primary language | English (U.S.) |
| Primary category | Education |
| Secondary category | Games — Word (optional) |
| Age rating | 4+ (no objectionable content) |
| Price | **Free** |
| Copyright | © 2026 Yuhe Ye |
| Support URL | https://jasonyeyuhe.github.io/nihongo-ride/support.html |
| Marketing URL | https://jasonyeyuhe.github.io/nihongo-ride/ |
| Privacy Policy URL | https://jasonyeyuhe.github.io/nihongo-ride/privacy.html |

App Privacy: **Data Not Collected** (fully offline, no account, no analytics).

---

## English (U.S.)

**Name** (≤30): `Nihongo Ride`

**Subtitle** (≤30): `Type your way across Japan`

**Keywords** (≤100): `japanese,typing,kana,hiragana,katakana,JLPT,vocabulary,romaji,learn,study,N5,furigana`

**Promotional text** (≤170):
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
• Example sentences and 183 reading passages — from everyday greetings to short literary paragraphs.
• Katakana loanwords supported, with foreign-sound digraphs.

PRIVATE BY DESIGN
• Fully offline. No account, no network, no tracking, no ads.
• Your progress stays on your Mac.

Whether you're starting N5 or polishing N1, Nihongo Ride turns daily typing into real Japanese progress. Hop on and ride.
```

---

## 简体中文 (zh-Hans)

**Name** (≤30): `Nihongo Ride`

**Subtitle** (≤30): `打字环游日本 边骑边学`

**Keywords** (≤100): `日语,打字,假名,平假名,片假名,JLPT,单词,学日语,罗马音,N5,练习,日语学习`

**Promotional text** (≤170):
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
• 例句 + 183 篇阅读文章——从日常问候到短篇文学段落。
• 支持片假名外来词与外来音 digraph。

隐私至上
• 完全离线。无账号、不联网、无追踪、无广告。
• 学习进度只留在你的 Mac 上。

无论你是刚开始 N5,还是在打磨 N1,Nihongo Ride 把每天的打字变成真实的日语进步。上车,出发。
```

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

## 审核备注 / Review notes (App Review)
```
Nihongo Ride is a fully offline macOS typing-practice app for Japanese learners.
No account or login is required. No network connection is made. No data is collected.
To test: launch, press Start ride, and type the romaji shown under each word
(a physical keyboard is required). All three modes are reachable from the main menu.
```
