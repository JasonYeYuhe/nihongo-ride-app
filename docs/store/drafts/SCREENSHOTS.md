# Screenshot sets and the CN search-result creative (PLAN-V1.37 P0-10)

*Design spec, 2026-10-28 (JST). Nothing was rendered for this file, the app was not run, and
nothing was uploaded.* It says, for each frame: the screen and state, how it can be captured, and
the caption in each language. It is for P1-13 (`docs/PLAN-V1.37.md:244`), which may stagger the
screenshots to a later version.

Marks as in `ASO-AUDIT.md`: **measured** (ASC GET, a public page, or the code at HEAD `892ef68`) or
**judgement** (the agent's reading under the 2026-10-07 delegation).

---

## 1. What is live (measured, `asc-baseline-2026-10-28.json`)

| set | en-US | zh-Hans | ja |
|---|---|---|---|
| Mac `APP_DESKTOP` 2880×1800 | game, journal, practice, results, practice-blind, game-mid | the same six, zh renders | **none** |
| iPhone `APP_IPHONE_67` 1320×2868 | en-1-menu, en-2-game, en-3-results, en-4-practice, en-5-journal | zh-1 … zh-5, same order | **none** |
| iPad `APP_IPAD_PRO_3GEN_129` 2752×2064 (landscape) | the Mac six | the Mac six, zh | **none** |
| app previews | none | none | none |

* en and zh files differ (different `sourceFileChecksum`s), so the zh sets are localized (measured).
* **ja has no screenshot set on either platform**, and the JP storefront shows the English ones.
  The public JP page `https://apps.apple.com/jp/app/id6777469778?platform=iphone`, read today,
  references `en-1-menu.png` … `en-5-journal.png`. The CN page references `zh-1-menu.png` … (measured).
* **No live frame shows the road, the road west, or the offer.** The first iPhone frame is the menu.
* `docs/ASC_METADATA.md:205-215` records a v1.1 upload order that differs from the live iPhone order
  (live: menu first). The doc is stale on this point; the live order is in the baseline.

---

## 2. Where the traffic is (measured, 2026-09-20 .. 10-25)

* JP: 3,049 impressions, 53 first-time downloads. CN: 2,651 impressions, 18 downloads
  (`docs/measurements/v137-funnel-post-day0.md:167-168`).
* JP downloads are 48 of 53 on the Mac. CN downloads are 16 of 18 on iPhone or iPad (`:196-197`).
* Impression → page view: JP 139 / 3,049 = 4.6%, CN 65 / 2,651 = 2.5% (computed from `:167-168`).
  CN users still open the page about half as often from search, as before day 0
  (`docs/measurements/v2-acquisition-funnel.md:113-126`).
* That file also says the gap cannot be told apart from the app being shown for queries it does not
  answer (`:112-124`). So the creative and the zh keywords are one confounded lever. P1-13 ships them
  together, which is why `ASO-AUDIT.md` §6.2 and this file are one draft.

**So two first impressions matter most (judgement):**
1. **CN, iPhone, the first three portrait frames.** Apple: "Depending on the orientation of your
   screenshots, the first one to three images will appear in search results when no app preview is
   available" (`https://developer.apple.com/app-store/product-page/`, read today). The live iPhone
   set is portrait, so the agent's reading is three. Apple does not state the count per orientation.
2. **JP, Mac, the first landscape frame.** How many landscape frames a Mac search row shows is not
   stated by Apple (not sourced). The agent designs as if it were one.

---

## 3. Rules every frame obeys

* **Show the app in use** (Guideline 2.3.3). Captions and overlays are allowed.
* **Label what is paid** (2.3.2): "screenshots … clearly indicate whether any featured items, levels
  … require additional purchases". Every frame that shows the road west carries a paid label **on
  the frame itself**, not only in the caption.
* **No price in any frame** (2.3.7: screenshots "should not include prices"). The offer frame is cut
  above the buy row. The price shown in the app comes from the App Store (`RoadView.swift:179`),
  so it also varies by storefront.
* **No other app is named** (2.3.7).
* **No Japanese UI is shown or implied** unless E5 (P1-15) ships in the same binary. Today the UI is
  `en` or `zh` (`Sources/NihongoRideApp/AppModel.swift:211`). The ja set uses the English UI with
  Japanese captions, and says so once (F2).
* **No cross-device purchase claim.** Cross-platform restore is one of §L's unwalked gates
  (`docs/PLAN-WINDOW.md:312-313`).
* **No E3 claim.** If E3 ships first, F2's "N5–N1" needs a paid label (`docs/PLAN-V1.37.md:213`).
* **The frozen screens stay byte-identical.** `road.png`, `road-iap-review.png` and `menu.png` are
  gated (`docs/PLAN-V1.37.md:202`). New captures are added beside them, in separate processes where an
  environment seam is used, never by changing them.
* Sizes, from Apple's spec page read today
  (`https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications`):
  iPhone 1320×2868 portrait (the live size), iPad 13" 2752×2064 landscape (live) or 2064×2752,
  Mac 2880×1800. Up to 10 per size.

---

## 4. The frames

**How the app can be captured today (measured from the code):**
* **iPhone (and iPad portrait):** the XCUITest walk, `Tests/NihongoRideiOSUITests/StoreScreenshotTests.swift`.
  It snaps `menu`, `game`, `results`, `practice`, `journal` in en and zh (`:59, 68, 76, 102, 119`). It
  does **not** visit the road. P1-13 extends it: Settings → `roadRow`
  (`Sources/NihongoRideApp/SettingsView.swift:188-201`).
* **Owned and far-along states:** two DEBUG-only seams. `NIHONGO_FAKE_ENTITLEMENT=verified`
  (`Sources/NihongoRideApp/RouteStore.swift:128-141`) and `NIHONGO_FAKE_LIFETIME_METRES`, honoured only
  under an isolation that touches nothing of the user's (`Sources/NihongoRideApp/AppModel.swift:1683-1698`).
* **Mac:** the headless renderer, `NIHONGO_SHOT=<dir> NIHONGO_SHOT_STORE=1`
  (`Sources/NihongoRideApp/Screenshot.swift:13-14, 135`). It cannot draw native controls: pickers come
  out as yellow placeholder bars, so the Mac menu is unusable (`docs/ASC_METADATA.md:205`). The
  entitlement seam is read once per process, so owned frames need their own run
  (`Screenshot.swift:272-276`).
* **Not to be used:** the stage contact sheet (`NIHONGO_SHOT_STAGES=1`). Its own comment calls it
  "a developer contact sheet, not the app" (`Screenshot.swift:311-316`).

**Caption format (judgement):** a headline of at most about 12 CJK characters or 32 Latin characters,
so it reads at search-row thumbnail size, plus one optional smaller line. Large type on a dark band at
the top; the app's own colours (`Theme`, inside `Sources/NihongoRideApp/NihongoRideApp.swift`).

### F1 · Type it

* **Screen:** Journey, mid-word, romaji hint showing. iPhone: keyboard up.
* **Capture:** iPhone `*-2-game` (`StoreScreenshotTests.swift:62-68`). Mac `game.png`
  (`Screenshot.swift:203`). Existing renders to judge by:
  `~/Library/Caches/NihongoRide-v137-work/renders-v137-final/head/en/game.png` and `…/head/zh/game.png`
  (referenced, not copied).

| | headline | second line |
|---|---|---|
| en | Type romaji. Learn Japanese. | Every word: kanji, kana and meaning |
| zh | 敲罗马音,学日语 | 每个词都有汉字、假名和中文释义 |
| ja | ローマ字で打って、日本語を覚える | 単語ごとに漢字・読み・意味（英語／中国語） |

### F2 · What is inside

* **Screen:** the menu with the six mode capsules and the JLPT picker. **iPhone and iPad only**
  (the Mac render has placeholder bars). On Mac, F2 is the Practice passage instead
  (`Screenshot.swift:413`).
* **Capture:** iPhone `*-1-menu` (`StoreScreenshotTests.swift:59`).

| | headline | second line |
|---|---|---|
| en | JLPT N5–N1 · 7,000+ words | 6 ways to practise |
| zh | JLPT N5–N1 · 7000+ 词 | 6 种练习模式 |
| ja | JLPT N5〜N1・7,000語以上 | 6つのモード　※画面表示は英語・中国語 |

The ja note is dropped only if E5 ships in the same binary.

### F3 · The road, free

* **Screen:** the Road screen's top: the header and the Tōkaidō card, 日本橋 and 川崎 reached, the
  "km still to Kyōto" line. The road-west card may show below it, locked.
* **Capture:** iPhone: the extended walk, Settings → The Road. Mac: `road.png` already exists at a
  tall size (`Screenshot.swift:291-295`); a store-size crop of its top is composited on a 2880×1800
  canvas. Renders to judge by: `…/renders-v137-final/head/en/road-iap-review.png`, `…/head/zh/road-iap-review.png`.

| | headline | second line |
|---|---|---|
| en | The Tōkaidō, Nihonbashi → Kyōto | Free, and complete |
| zh | 东海道:日本桥 → 京都 | 免费,而且完整 |
| ja | 東海道：日本橋 → 京都 | 無料で、最後まで走れます |

### F4 · A paid stretch, labelled as paid

* **Screen:** Journey, riding the 広島 stretch (starts at 60,000 m, `RideRoute.swift:254-256`), on an
  owned device. The HUD's route bar shows the west.
* **On-frame label** (top corner, filled badge): en `PAID · The Road West`, zh `付费 · 西行之路`,
  ja `有料・西への道`.
* **Capture:** iPhone: a second walk with `NIHONGO_FAKE_ENTITLEMENT=verified` and
  `NIHONGO_FAKE_LIFETIME_METRES=61000`. Mac: a separate render process with the same two variables.
  Whether the headless renderer's fixed-odometer machinery (`Screenshot.swift:175-183`) leaves the
  lifetime seam in charge is read from comments only; P1-13 checks the render before using it.
* **Choice of stretch (judgement):** 広島 is late gold over the sea (`RideRoute.swift:257`), the
  clearest contrast with the Tōkaidō's palettes. 姫路 (`:232-241`, the palest sky) is the alternative.

| | headline | second line |
|---|---|---|
| en | Past Kyōto: the Road West | Paid add-on · one-time purchase |
| zh | 京都之后:西行之路,直到长崎 | 付费内容 · 一次性购买 |
| ja | 京都の先へ：長崎までの西への道 | 有料・買い切り |

### F5 · The offer

* **Screen:** the Road screen scrolled to the road-west card (eight locked stretches, 大阪 28 km to
  長崎 138 km) and the "Open the Road West" card's blurb. **Cut above the buy row**, so no price
  appears (§3). The blurb's distance sentence reads the device's own odometer
  (`RoadView.swift:266-269`); use the capture's fixed 700 m ("24.3 km", `Screenshot.swift:283-285`).
* **Capture:** iPhone: the extended walk, scrolled. Mac: the middle of `road.png`. Both composited
  onto a store-size canvas with the caption band.

| | headline | second line |
|---|---|---|
| en | Buy it once. It stays open. | The Tōkaidō stays free and complete |
| zh | 一次购买,永久开启 | 东海道依然免费、完整 |
| ja | 一度の購入で、ずっと開いたまま | 東海道は無料のまま、最後まで走れます |

### F6 · Private

* **Screen:** the Ride Log (iPhone `*-5-journal`, `StoreScreenshotTests.swift:119`; Mac `journal.png`,
  `Screenshot.swift:485`) or the Practice passage.

| | headline | second line |
|---|---|---|
| en | Works offline. No ads. | No sign-up |
| zh | 离线可用 · 无广告 | 无需注册 |
| ja | オフラインで使える・広告なし | アカウント登録は不要 |

The ja second line reuses the live, native-reviewed phrase `アカウント登録は不要`
(`docs/store/ja-listing.json`, description), which `docs/ASC_METADATA.md` (ja section) explains is still
true after the IAP.

---

## 5. The sets, per locale and device

| position | iPhone (en / zh / ja) | iPad (en / zh / ja) | Mac (en / zh / ja) |
|---|---|---|---|
| 1 | F1 Type it | F1 | **F1** (JP's first impression) |
| 2 | F2 What is inside | F2 | F3 The road, free |
| 3 | F3 The road, free | F3 | F4 Paid stretch |
| 4 | F4 Paid stretch | F4 | F5 The offer |
| 5 | F5 The offer | F5 | F2-Mac (Practice) |
| 6 | F6 Private | F6 | F6 Private |
| 7 (optional) | live `*-3-results` | live `results.png` | live `practice-blind.png` |

**Why the paid frames are not in the first three (judgement).** The search row is the product's
first sentence. A searcher for `日语打字` should see the typing, the content, and the free road. The
road west is the thing sold; it is shown, labelled, from position 4 (Mac: 3, because only the first
frame is likely to show in a Mac search row).

**The ja set is new**, not a replacement. Today JP sees the English set (§1). Shipping a ja set
changes what JP searchers see, so it is part of P1-13's registered co-intervention, not a free
extra.

---

## 6. The CN search-result creative, as a searcher sees it

Three portrait frames, side by side in the result row, under the icon, `Nihongo Ride` and the
subtitle (zh option A or B, `ASO-AUDIT.md` §6.2).

| slot | today (measured) | proposed | what the searcher should take from it (judgement) |
|---|---|---|---|
| 1 | `zh-1-menu.png` | **F1** 敲罗马音,学日语 | "this is a typing app for Japanese" |
| 2 | `zh-2-game.png` | **F2** JLPT N5–N1 · 7000+ 词 | "it has real content, at my level" |
| 3 | `zh-3-results.png` | **F3** 东海道:日本桥 → 京都 · 免费,而且完整 | "a journey, and free" |

* Each headline is at most 13 characters, so it stays legible at a third of the row's width
  (judgement; no Apple size rule was found).
* The zh UI mixes names: the road-west card is titled `西の道` (`RoadView.swift:93`), while the IAP and
  the boundary sentence say `西行之路` (ASC GET today; `RoadView.swift:314`). Captions use `西行之路`,
  the name on the payment sheet. `RoadView` is frozen, so the mix stays until after the N = 200 record.

---

## 7. Every caption sentence, checked against the code (V7)

| caption claim | frames | source at HEAD `892ef68` |
|---|---|---|
| you type romaji | F1 | `Sources/RomajiKana/KanaInputMatcher.swift:11-19, 74-86`; iOS `.asciiCapable`, `KeyCaptureView.swift:151` |
| each word shows kanji, kana and meaning | F1 | surface `GameView.swift:1500`; gloss `:1535` via `GameSession.swift:666`; kana `GameView.swift:1747` |
| meaning in English or Chinese | F1 | `VocabEntry.swift:40, 115-116`; UI language `en`/`zh`, `AppModel.swift:211` |
| JLPT N5–N1 | F2 | `Sources/VocabKit/VocabEntry.swift:5-6`; level picker `MenuView.swift:206-210` |
| 7,000+ words | F2 | `python3 scripts/release_numbers.py` today: `entries 7071` |
| 6 modes | F2 | `Sources/GameCore/GameSession.swift:16-22` |
| UI is English and Chinese (ja note) | F2 | `AppModel.swift:211`; menu language picker `MenuView.swift:193-196` |
| Tōkaidō, Nihonbashi → Kyōto | F3 | `Sources/SceneryKit/RideRoute.swift:102-183`; card title `RoadView.swift:74` |
| free, and complete | F3, F5 | `RoadView.swift:268-269` ("that road is free, and it is complete"); arrival line `:80` |
| the Road West, to Nagasaki | F4, F5 | `RideRoute.swift:207-297`; card title `RoadView.swift:93` |
| paid · one-time purchase | F4 | IAP `NON_CONSUMABLE`, ASC GET today; button label `RoadView.swift:176` |
| it stays open / 永久开启 / ずっと開いたまま | F5 | `RoadView.swift:218-219` ("it stays open"), `:313-315` ("permanently opens") |
| works offline | F6 | `grep -rn "URLSession\|URLRequest" Sources`: 0 hits; no remote `.package(` in `Package.swift`; iCloud sync optional, `AppSettings.swift:40, 101` |
| no ads | F6 | no ad or tracking SDK (`grep` today: 0 hits); no remote packages |
| no sign-up | F6 | no developer account in the app; the IAP uses the buyer's own Apple Account (`docs/ASC_METADATA.md`, App Privacy note) |

---

## 8. Open items for P1-13

* **Apple's required iPhone size moved.** The spec page read today says the required iPhone set is
  "iPhone with Dynamic Island (medium display)" (1206×2622 or 1179×2556), with the large set
  (1320×2868) optional. The live sets are 1320×2868 only, and v1.36 passed review with them on
  2026-10-26. Whether the next upload needs a medium set is not known (not sourced). P1-13 checks
  before it starts the screenshot work.
* **ja captions are unreviewed.** They go through P1-15's glossary and a native-level review.
* **F4 and F5 need code the release does not have yet:** the walk's road visit, the owned-state run,
  and the composite step. None of it touches the frozen list.
* **The live iPad set is landscape Mac renders at 2752×2064**, while the walk's header says it
  captures the 13" iPad in portrait (`StoreScreenshotTests.swift:7`). P1-13 picks one.
