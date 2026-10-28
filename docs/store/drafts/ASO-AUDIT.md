# ASO audit: title, subtitle and keywords (PLAN-V1.37 P0-10)

*Read-only audit, 2026-10-28 (JST). Drafts for P1-13 only. Nothing here was uploaded, PATCHed or
proposed to the owner as a decision.* The live text is in `asc-baseline-2026-10-28.json` (ASC GET,
2026-10-28 01:04–01:14 UTC). The search reads are in `serp-2026-10-28.json`.

Each claim is marked:
* **measured**: read today from ASC, a public Apple page, the App Store web search, or the code at
  this clone's HEAD (`892ef68`);
* **judgement**: the agent's reading under the 2026-10-07 delegation, labelled as such.

---

## 1. Short version

* **Live text has not drifted from the repo.** All three descriptions and keyword fields are
  byte-identical on macOS 1.36 and iOS 1.36, and equal to `docs/ASC_METADATA.md` and
  `docs/store/ja-listing.json` (measured, baseline `repoAgreement`).
* **The app is invisible on almost every high-intent JP and CN query.** It is outside the returned
  results (about 12) for 26 of the 32 JP, CN and US queries tried (measured, §4). It ranks only where the query is close to
  its own subtitle: JP Mac `日本語 タイピング` #3, JP Mac `タイピング` #7, CN Mac `日语 打字 练习`
  #1 of 2, CN iPhone `日语 打字 练习` #12 (and, outside JP/CN, US Mac `learn japanese` #8).
* **One live keyword is aimed at a feature the app does not have.** `かな入力` in `ja` means typing
  on a kana keyboard layout. The app accepts romaji only (§5.3, measured).
* **The CN storefront probably does not read the `en-US` keyword field.** Apple lists China
  mainland's languages as Simplified Chinese and **English (U.K.)**, not English (U.S.) (measured,
  §3). So the zh-Hans field is the only one CN search reads. That makes zh-Hans duplicates expensive.
* **Candidate values are in §6**, each checked against the code in §7. None proposes a price.

---

## 2. Field limits, from Apple, read 2026-10-28

| field | limit | source |
|---|---|---|
| Name | 2–30 characters | `https://developer.apple.com/help/app-store-connect/reference/app-information/app-information` |
| Subtitle | 30 characters | same page; and `https://developer.apple.com/app-store/product-page/` |
| Keywords | "up to 100 bytes"; "each greater than two characters" | `https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information` |
| Keywords | "limited to 100 characters total, with terms separated by commas and no spaces" | `https://developer.apple.com/app-store/product-page/` |
| Promotional text | 170 characters; it "doesn't affect your app's search ranking" | both pages above |
| Description | 4000 characters | platform-version-information page |

**Bytes or characters: Apple's two pages disagree, and the live record settles it for one field.**
* The live `ja` keywords are **71 characters and 151 UTF-8 bytes**, and ASC holds them on both
  platforms (measured, baseline `keywordsMeasured`). The zh-Hans field is 43 characters, 95 bytes.
* So ASC enforces something other than 100 UTF-8 bytes. Characters is the reading that fits.
* This is one observation, not a rule. P1-13's byte-exact read-back (`docs/PLAN-V1.37.md:416`, V7)
  is what proves any new value was accepted whole.

**"Each greater than two characters"** is contradicted by the live fields too: `N5`, `N4`, `単語`
and `假名` are two characters each and are stored. Whether Apple *indexes* them is not stated
anywhere read today (not sourced).

**What metadata may not say** (App Review Guidelines 2.3.7, `https://developer.apple.com/app-store/review/guidelines/`,
read today): no trademarked terms or popular app names in keywords; subtitles must not "reference
other apps, or make unverifiable product claims"; screenshots and subtitles "should not include
prices". The product-page guide adds: no duplicate words, no category names, no competing app names.

---

## 3. Which keyword fields each storefront reads

From Apple's localization table, `https://developer.apple.com/help/app-store-connect/reference/app-store-localizations`,
read today (measured):

| storefront | languages Apple lists | this app's localizations that match |
|---|---|---|
| Japan | Japanese; English (U.S.) | `ja`, `en-US` |
| China mainland | Simplified Chinese; English (U.K.) | `zh-Hans` only |
| United States | English (U.S.) and nine others, incl. Simplified Chinese | `en-US`, `zh-Hans` |
| Vietnam, Hong Kong, Taiwan | English (U.K.) plus a local language | none exactly; `en-US` by fallback |

* Apple says localized keywords make an app searchable "in all countries or regions where the App
  Store supports" that language (`…/manage-app-information/localize-app-information`, read today).
* **Judgement:** Japan is served by two keyword fields (`ja` and `en-US`). China is served by one
  (`zh-Hans`). The `ja` draft's claim that the Japan storefront indexes `en-US` too
  (`docs/store/ja-listing-draft.md:35`) agrees with Apple's table. Apple does not say how indexing
  works, so this stays a reading of the table, not a measurement of search.
* **An option, not drafted as a default:** an `en-GB` localization would give CN (and HK, TW, VN) a
  second keyword field. It is a new locale, which changes which devices arrive (`docs/PLAN-WINDOW.md:39-40`).
  PLAN-V1.37 §K excludes zh-Hant and ko listings and is silent on en-GB. It needs an owner decision
  and a Window 2 registration. See "PLAN-V1.37 findings".

---

## 4. Where the app ranks today (measured)

**Instrument.** The public App Store web search, `https://apps.apple.com/<storefront>/<iphone|mac>/search?term=…`,
read 2026-10-28 between 01:09 and 01:11 UTC with plain GETs. The page carries an ordered result list
in its `serialized-server-data` JSON; the parser keeps the order. **Control:** the query
`Nihongo Ride` returns the app at #1 on JP iPhone, CN iPhone and JP Mac, so the parser finds the app
when it is there. Full lists: `serp-2026-10-28.json`.

**Limits of the instrument (judgement).**
* The web page returns at most about 12 results. "Not ranked" means "not in those 12".
* Web search may not equal the on-device App Store. Nothing read today says it does.
* One read, one moment, no personalisation control. Ranks move.
* There is no search-volume figure for any query. Apple's reports carry no search terms
  (`docs/measurements/v2-acquisition-funnel.md:121-125`). "High-intent" below is a judgement about
  what a learner types, not a measured volume.

| storefront · platform | query | Nihongo Ride | what ranks instead (top results, short) |
|---|---|---|---|
| JP · iPhone | ローマ字 入力 練習 | — | native typing games and children's romaji apps |
| JP · Mac | ローマ字 入力 練習 | — | native touch-typing trainers |
| JP · iPhone | タイピング 練習 日本語 | — | native flick and romaji speed apps |
| JP · Mac | タイピング 練習 日本語 | — | typing trainers, a Korean typing app |
| JP · iPhone / Mac | かな入力 | — | kana keyboards, a half-width kana converter, password managers (Mac) |
| JP · iPhone / Mac | 日本語学習 | — | JLPT and Japanese-course apps |
| JP · iPhone / Mac | JLPT | — | JLPT test-prep apps |
| JP · iPhone | 日本語能力試験 単語 | — | JLPT vocabulary books |
| JP · Mac | タイピング | **#7** | children's typing games, typing trainers |
| JP · Mac | 日本語 タイピング | **#3** | children's typing games, typing trainers |
| JP · Mac | japanese typing | **#5** | VPN, translators, kaomoji keyboards |
| CN · iPhone | 日语 打字 练习 | **#12** | multi-language typing, 日语打字通, Rail Typing (#3) |
| CN · Mac | 日语 打字 练习 | **#1 of 2** | — |
| CN · iPhone / Mac | 日语打字 | — | Rail Typing (#2 iPhone), 日语打字通, course apps |
| CN · iPhone / Mac | 日语五十音 | — | 五十音 chart apps with 1万–9.9万 ratings |
| CN · iPhone | 学日语 / 日语学习 / 日语单词 / JLPT | — | Duolingo, MOJi, course and vocabulary apps |
| CN · iPhone | 罗马音 / 假名 | — | converters, kana games, 五十音 apps |
| CN · iPhone | 日语 背单词 / 日语 离线 | — | vocabulary and dictionary apps |
| US · iPhone / Mac | japanese typing | — | Japanese keyboards and flick trainers; generic typing trainers |
| US · iPhone | learn hiragana | — | kana apps with up to 23K ratings |
| US · Mac | learn japanese | **#8** | grammar and reader apps |

**What this says (judgement).**
* Where the app appears, the subtitle carries the match. `タイピング` is in the `ja` subtitle and
  nowhere in the `ja` keywords, and JP Mac `タイピング` finds the app at #7. That is indirect
  evidence that the subtitle is indexed; Apple's pages read today do not say so (not sourced).
* JP's native-typing queries (`ローマ字 入力 練習`, `タイピング 練習 日本語`) are owned by speed-typing
  games for native speakers. The `ja` draft predicted this and chose not to chase it
  (`docs/store/ja-listing-draft.md:3-11`). The reads agree with that choice.
* **The Mac is where the app competes.** On Mac search the field is thin and the app ranks; on
  iPhone it does not. JP's downloads are 48 of 53 on the Mac, and CN's are 16 of 18 on iPhone or iPad
  (`docs/measurements/v137-funnel-post-day0.md:196-197`). CN's buyers are on the platform where the
  app ranks worst.

---

## 5. The fields, locale by locale

### 5.1 Title (all three: `Nihongo Ride`, 12 characters)

* 18 characters unused in every locale (measured).
* Apple's guide says "Choose a simple, memorable name … Avoid names that use generic terms"
  (product-page URL above). Industry practice puts descriptors in the title; that practice is not
  sourced here.
* **The agent's reading under the 2026-10-07 delegation:** leave the title alone in P1-13. A name
  change moves every locale's search row at once, cannot be separated from the rest of P1-13 in
  Window 2, and costs the exact-name searches that the control shows already work. If the owner wants
  it tried, §6.4 has the shape.

### 5.2 en-US

Live: subtitle `Type your way across Japan` (26); keywords
`japanese,typing,kana,hiragana,katakana,JLPT,vocabulary,romaji,learn,study,N5,furigana` (85).

* `learn` and `study` are generic. They buy nothing a learner would type alone (judgement).
* Only `N5` of the five JLPT levels is present (measured).
* Missing words for things the app has: `kanji`, `dictation`, verbs/conjugation, spaced repetition
  (§7 cites each).
* `en-US` is also Japan's second field (§3). English terms placed here also serve JP (judgement,
  from Apple's table).

### 5.3 ja

Live: subtitle `日本語学習者のためのローマ字タイピング` (19); keywords
`日本語学習,JLPT,日本語能力試験,N5,N4,N3,N2,N1,単語,ひらがな,カタカナ,漢字,読み方,例文,読解,暗記,語彙力,かな入力` (71).

* **`かな入力` is mis-targeted (measured on both sides).**
  * In the JP results it returns kana keyboards (JIS kana layout), a half-width kana converter, and on
    Mac password managers (§4).
  * The app accepts romaji only. The matcher consumes romaji keystrokes
    (`Sources/RomajiKana/KanaInputMatcher.swift:11-19`); a key is accepted only along a compiled
    romaji path (`:74-86`); the iOS key field is `.asciiCapable` (`Sources/NihongoRideApp/KeyCaptureView.swift:151`).
  * So the term aims at people who want a kana keyboard the app does not offer.
* The subtitle works where anything works (§4) and is the only native-reviewed field
  (`docs/ASC_METADATA.md`, ja section). **Judgement:** keep it.
* 29 characters of keywords unused, by Apple's character count (measured).

### 5.4 zh-Hans

Live: subtitle `打字环游日本 边骑边学` (11); keywords
`日语,打字,假名,平假名,片假名,JLPT,单词,学日语,罗马音,N5,练习,日语学习` (43).

* `日语` appears three times (`日语`, `学日语`, `日语学习`) and `打字` is in the subtitle too
  (measured). Apple's guide says to avoid duplicate words.
* Only `N5` of the five levels (measured).
* Since CN reads only this field (§3), every wasted term costs more here than anywhere else
  (judgement).
* The subtitle is a slogan. It says what the app feels like, not what a searcher types. CN iPhone
  `日语打字` does not find the app, and `日语 打字 练习` finds it at #12 (measured).
* **`五十音`.** The top CN query family is chart learning (`日语五十音`: chart apps with 1万–9.9万
  ratings, measured). The app has no kana chart or kana-drill mode: `GameMode` has six cases, none a
  kana drill (`Sources/GameCore/GameSession.swift:16-22`), and its levels are N5–N1 only
  (`Sources/VocabKit/VocabEntry.swift:5-6`). Kana practice exists only as all-kana Practice passages
  (`Sources/VocabKit/Passage.swift:9`). **The agent's reading:** `五十音` stays out of the subtitle;
  in keywords it is borderline under 2.3.7's "terms that are not relevant", so it is left out of the
  draft and named here for the owner.

---

## 6. Candidate values, for P1-13 only

**Status of every value below: a draft for P1-13. Not uploaded, not PATCHed, not an owner decision.**
P1-13 is a registered Window 2 co-intervention (`docs/PLAN-V1.37.md:244`). Each value is checked in §7.
Lengths are characters / UTF-8 bytes, measured with Python today.

### 6.1 en-US

| field | live | candidate | length |
|---|---|---|---|
| subtitle | `Type your way across Japan` | unchanged | 26 |
| keywords | (above) | `japanese,typing,kana,hiragana,katakana,kanji,JLPT,N5,N4,N3,romaji,furigana,vocab,dictation,verbs,SRS` | 100 / 100 |
| promotional text | null | `Ride the Tōkaidō from Nihonbashi to Kyōto for free, typing real Japanese as you go. Past Kyōto, the road west to Nagasaki is a one-time purchase.` | 145 |

Drops `learn`, `study`, `vocabulary` (→ `vocab`). Adds `kanji`, `N4`, `N3`, `dictation`, `verbs`,
`SRS`. `N2,N1` did not fit; the agent's choice put the modes ahead of the upper levels.

### 6.2 zh-Hans

| field | live | candidate | length |
|---|---|---|---|
| subtitle, option A | `打字环游日本 边骑边学` | `日语打字练习 罗马音输入 离线无广告` | 18 / 50 |
| subtitle, option B | | `日语打字练习 边骑边学环游日本` | 15 / 43 |
| keywords | (above) | `假名,平假名,片假名,JLPT,N5,N4,N3,N2,N1,单词,背单词,罗马字,罗马音,汉字,读音,例句,听写,动词变形,离线` | 64 / 128 |
| promotional text | null | `打字骑完东海道,从日本桥到京都,全程免费。京都之后,通往长崎的西行之路是一次性购买。` | 42 |

* Both subtitles lead with the literal query `日语打字练习` (judgement, from §4).
  Option A states facts a CN buyer can check (offline, no ads). Option B keeps the journey.
* The keyword field drops `日语`, `打字`, `练习` (now in the subtitle), and `学日语`, `日语学习`
  (duplicates). It adds the four missing levels and the modes the app has.
* PLAN-V1.37 §Q item 8 asks the zh copy to say what the app does that Rail Typing does not. Under
  2.3.7 a subtitle may not reference another app, so option A states the app's own facts and names
  no one. See the findings on "Mac".

### 6.3 ja

| field | live | candidate | length |
|---|---|---|---|
| subtitle | `日本語学習者のためのローマ字タイピング` | unchanged | 19 |
| keywords | (above) | `日本語学習,JLPT,日本語能力試験,N5,N4,N3,N2,N1,単語,ひらがな,カタカナ,漢字,読み方,例文,読解,暗記,語彙力,ふりがな,聞き取り,動詞活用,復習` | 84 / 184 |
| promotional text | null | `東海道（日本橋〜京都）は無料で、日本語を打ちながら走れます。京都から長崎までの「西への道」は買い切りです。` | 53 |

* Replaces `かな入力` (§5.3) and adds `ふりがな`, `聞き取り`, `動詞活用`, `復習` for features the app has.
* **Every added ja word is unreviewed.** The ja listing is the only native-reviewed locale
  (`docs/ASC_METADATA.md`, ja section). P1-13 uses P1-15's glossary and a native-level review before
  any of this goes near ASC (`docs/PLAN-V1.37.md:244`).
* At 184 UTF-8 bytes this is above the 151 bytes ASC has already accepted. P1-13's read-back decides
  whether it fits (§2).

### 6.4 If the owner wants a title test (not drafted as a default)

Shape only: `Nihongo Ride: Japanese Typing` (29), `Nihongo Ride - 日语打字练习` (19),
`Nihongo Ride - 日本語タイピング` (22). The objections are in §5.1.

---

## 7. Every claim in the candidates, checked against the code (V7)

| claim (where it appears) | true? | source at HEAD `892ef68` |
|---|---|---|
| typing / 打字 / タイピング: you type to play | yes | `Sources/GameCore/GameSession.swift:690-695` (`input(_:)` feeds each key to the matcher) |
| romaji / 罗马音 / 罗马字 / ローマ字 input | yes | `Sources/RomajiKana/KanaInputMatcher.swift:11-19`, `:74-86`; `Sources/RomajiKana/Resources/romaji-hiragana.tsv:65, 207` (shi / si) |
| 罗马音输入 needs no system IME | yes | `Sources/NihongoRideApp/KeyCaptureView.swift:28-31`; iOS `.asciiCapable` `:151` |
| kana, hiragana, katakana / 假名 平假名 片假名 / ひらがな カタカナ | yes, as typing targets and readings | `Sources/VocabKit/VocabEntry.swift:28-29` (reading in hiragana); katakana targets are typed through `Sources/RomajiKana/KanaScript.swift:3-11` |
| kanji / 汉字 / 漢字, readings / 读音 / 読み方 | yes: each word shows its surface and its kana | `Sources/NihongoRideApp/GameView.swift:1500` (surface), `:1747` (kana) |
| JLPT, N5 … N1 | yes | `Sources/VocabKit/VocabEntry.swift:5-6` |
| vocab / 单词 / 単語 | yes, 7,071 entries | `python3 scripts/release_numbers.py` today: `entries 7071` |
| furigana / ふりがな | yes, on example sentences, on by default | `Sources/SettingsKit/AppSettings.swift:76, 109`; `Sources/NihongoRideApp/GameView.swift:1553-1555` |
| 例句 / 例文 | yes, 6,738 entries carry an example | `release_numbers.py`: `withExample 6738` |
| dictation / 听写 / 聞き取り | yes, a mode | `Sources/GameCore/GameSession.swift:22`; offline ja-JP voice `Sources/SpeechKit/SpeechSynthesizer.swift:5, 44` |
| verbs / 动词变形 / 動詞活用 | yes, a mode | `Sources/GameCore/GameSession.swift:20` |
| SRS / 背单词 / 復習 | yes, SM-2 review | `Sources/ReviewKit/SRSCard.swift:23-28` |
| 离线 / offline | yes. No networking API in the app; iCloud sync is optional and on by default | `grep -rn "URLSession\|URLRequest" Sources` today: 0 hits; `Package.swift` declares no remote `.package(`; `Sources/SettingsKit/AppSettings.swift:40, 101` |
| 无广告 / no ads | yes, as absence | `grep` today for `GADMobileAds`, `AdMob`, `AppTrackingTransparency`, `FirebaseAnalytics` in `Sources`: 0 hits; no remote packages |
| "Ride the Tōkaidō from Nihonbashi to Kyōto" | yes, 8 stretches, 日本橋 at 0 m to 京都 at 25,000 m | `Sources/SceneryKit/RideRoute.swift:102-183` |
| "for free" / 全程免费 / 無料 | yes. The app is free and the Tōkaidō is never gated | ASC app price Free (`docs/ASC_METADATA.md`, Core); `Sources/NihongoRideApp/RoadView.swift:268-269`; `RideRoute.swift:323-325` (the west is appended, the Tōkaidō always present) |
| "typing real Japanese as you go" | yes, Journey mode | `GameSession.swift:17`; `GameMode.onboardingClause` `:54` |
| "the road west to Nagasaki" / 西行之路 / 西への道 | yes, 8 stretches, 大阪 28 km to 長崎 138 km | `RideRoute.swift:207-297`; IAP names, ASC GET today (baseline `inAppPurchase.localizations`) |
| "one-time purchase" / 一次性购买 / 買い切り | yes, `NON_CONSUMABLE` | ASC GET `/v2/inAppPurchases/6806755720` today; `RoadView.swift:176` |

**Not claimed anywhere above, on purpose:**
* a Japanese interface (there is none; the UI is `en` or `zh`, `Sources/NihongoRideApp/AppModel.swift:211`);
* a kana chart or `五十音` (§5.4);
* kana-keyboard input (§5.3);
* that one purchase opens the road on Mac and iPhone together. Cross-platform restore is one of §L's
  unwalked gates (`docs/PLAN-WINDOW.md:312-313`), and the walk is still a future owner card
  (`docs/PLAN-V1.37.md:97`, card C-1);
* anything about E3. If E3 ships with or before P1-13, every "free" above must be re-checked:
  candidate 1 makes N3–N1 paid (`docs/PLAN-V1.37.md:213`), so "JLPT N5–N1" and "for free" would need
  a paid label under 2.3.2.

---

## 8. What could not be sourced

* Whether the subtitle is indexed for search. Apple's pages read today do not say. §4 has indirect
  evidence only.
* Whether the web search ranks equal on-device ranks.
* Search volume for any query. None exists in Apple's reports.
* Whether `en-GB` keywords are indexed in the CN storefront.
* Whether two-character keywords (`N5`, `単語`, `假名`) are indexed.
* The native correctness of the added ja keywords and the ja promotional text.
* Whether ASC accepts the 184-byte ja field (above the 151 bytes measured).
