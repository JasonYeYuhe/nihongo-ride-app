# DESIGN-E3-SAMPLER: a complete free sampler, one one-time depth unlock, every existing install kept whole

*Design document, 2026-10-27 (JST). PLAN-V1.37 §C item P0-13. Written on branch `docs/v137-e3-design` from repo HEAD `9c09ab7`. Design only: no code, no IAP, no App Store Connect write. Every claim cites a file:line at that HEAD, an ASC GET with its date, or a URL read today.*

> **Nothing in this document ships before the owner's C-2 box (PLAN-V1.37 Appendix A-1).** No IAP is created, no price is set and no product id is registered before that box exists. With no box, E3 stays on its branch and nothing here reaches a rider (PLAN-V1.37 §I, v1.39 row; §1 C-2 default).
>
> **No price appears here, and no price placeholder.** "An agent invents no prices" (`docs/PLAN-V1.34.md:729`). The buy button shows StoreKit's `product.displayPrice`, as the road's does (`Sources/NihongoRideApp/RoadView.swift:179`).
>
> **Labels.** Anything marked *(agent's choice, 2026-10-07 delegation)* or *(agent's reading, 2026-10-07 delegation)* is the agent's, under the owner's 2026-10-07 delegation. It is not an owner decision. The owner can change any of them at C-2(d) or by saying so.

---

## 0. The design in one screen

* **What is sold.** One non-consumable that opens the N3, N2 and N1 pools in every mode. Nothing else.
* **What stays free (candidate 1, the default).** N5 and N4 in every mode, all 233 Practice passages, the learner's own texts, the Tōkaidō road, search, lists, saving, sync, the coach, the widget and Game Center. *(The boundary is the agent's design choice under the 2026-10-07 delegation; PLAN-V1.37 §C P0-13 names it the default, and C-2(d) can change it.)*
* **Who can buy it.** Only installs that are not grandfathered. Every install that existed before E3's first build keeps everything, forever, through a persisted, never-revoked grant (§5).
* **How it is built.** One predicate decides what is open. `AppModel` holds two vocabulary stores: the full **catalog** for reading (search, list rows, About), and a **rideable** store for building runs and counting them. Every run builder and every count already reads the model's one injected store (`AppModel.swift:199-201, 528-529`), so swapping that store for a filtered one closes every mode at once (§2).
* **What has to exist first.** P1-5 (per-SKU keys, a product list, `MultiSKU.enabled`) and P1-11 (ledger v2 with a product dimension) in v1.38, and P0-12's install-cohort marker in v1.37 (§6).

---

## 1. The boundary, with the counts the code ships

Counts are read today from the bundled corpus (`Sources/VocabKit/Resources/n5.json … n1.json`, `passages.json`, `dictation-exclusions.json`). "Sentences" = entries with both `exJP` and `exKana` (`VocabEntry.isTypeableSentence`, `Sources/VocabKit/VocabEntry.swift:62-66`). "Dictation" = typeable sentences minus the 789 excluded ids (`DictationSafety`). "Verbs" = entries with a `vc` class (`ConjugationSession.swift:18`, `:434-436`).

| level | words | sentences | dictation sentences | verbs |
|---|---|---|---|---|
| N5 | 646 | 616 | 518 | 95 |
| N4 | 642 | 627 | 555 | 211 |
| N3 | 1,450 | 1,411 | 1,228 | 427 |
| N2 | 1,747 | 1,695 | 1,513 | 588 |
| N1 | 2,586 | 2,375 | 2,121 | 996 |
| **total** | **7,071** | **6,724** | **5,935** | **2,317** |

Practice passages are **not** JLPT-tagged. They carry `easy` / `med` / `hard` (`Sources/VocabKit/Passage.swift:24`): 51 / 75 / 107, 233 in all. They stay free under both candidates.

| | **Candidate 1 (default)** | **Candidate 2 (the owner's alternative at C-2(d))** |
|---|---|---|
| Free levels | N5, N4 | N5 |
| Free words · sentences · dictation · verbs | 1,288 · 1,243 · 1,073 · 306 | 646 · 616 · 518 · 95 |
| Paid levels | N3, N2, N1 | N4, N3, N2, N1 |
| Paid words · sentences · dictation · verbs | 5,783 · 5,481 · 4,862 · 2,011 | 6,425 · 6,108 · 5,417 · 2,222 |
| Free in both | all 233 passages; the learner's own texts; the Tōkaidō; every mode; search, lists, saving, sync, coach, widget, Game Center | same |
| Against the fork's sampler sketch ("all six mechanics, 1,000–1,500 high-frequency words with their sentences, ~20 passages, one route", `docs/PLAN-V2-PRODUCT.md:412-415`) | inside the word range; far more passages; one route | below the word range |

**Why candidate 1 is the default** *(agent's choice, 2026-10-07 delegation)*:
* "A generous free tier is still the funnel" (`PLAN-V2-PRODUCT.md:398-399`). With 0 JP ratings and about 2.6 installs a day (PLAN-V1.37 §A), a sampler that feels crippled costs reviews the app does not have.
* It is the only candidate inside the fork's own sketch of a "bounded but complete sampler".
* It still leaves 82% of the words (5,783 / 7,071) on the paid side, so the purchase buys real depth.

**What "everything that already ships free" means** *(agent's reading, 2026-10-07 delegation)*. Read literally, the N3–N1 pools ship free today, so the phrase would contradict the boundary. It is read as **every feature and mechanic**: every mode, the road, search, lists, saving, custom text, sync, coach, widget, Game Center. The paid unit is **riding** a word or sentence whose entry is N3, N2 or N1 (candidate 2: N4 too). Seeing, searching, saving and listing any word stays free.

**"Kana" in the boundary.** There is no kana-drill mode in the code. `GameMode` has six cases: journey, timeAttack, practice, conjugation, sentence, dictation (`Sources/GameCore/GameSession.swift:16-22`). Kana practice lives in Practice passages (all-kana text, `Passage.swift:9-10`) and the coach's pattern drills (`Sources/DiagnosticsKit/CoachContent.swift:116-118`). Both stay free.

**One-time goods must be finished** (`PLAN-V2-PRODUCT.md:306-310`). The N3–N1 pools are finished: they are bundled, offline files. The copy sells them **as they are in the app**, with counts computed from the catalog, and promises no future content (§7.3).

---

## 2. The mechanism: one predicate, two stores

### 2.1 Why a filtered store and not a filter at each call site

* **Every builder already takes the model's store.** `AppModel` holds one injected `vocab` (`AppModel.swift:199-201`, `init(vocab:)` at `:528-529`). Every run builder in the model passes it: `GameSession.make` (`:2158`), `makeSentence` (`:2145, 1984, 2003`), `makeDictation` (`:2143, 1782, 1801`), `makeSaved` (`:1386, 1965`), `makeWeak` (`:2258, 2299`), `ConjugationSession.make` (`:2341`), `makeReview` (`:2415`).
* **Two builders reach the whole corpus on their own.** `makeSentence` falls back to `vocab.ordered()` when the level pool is empty (`GameSession.swift:403-404`). Conjugation review pads with fresh prompts from `pool(vocab:, level: nil)`, the whole corpus, because the model sets `config.level = nil` for review (`ConjugationSession.swift:529-532`; `AppModel.swift:2412`). A per-call-site filter would miss both. A filtered store closes both without touching GameCore.
* **Every count already asks the same store.** Due counts, the widget, reminders, the forecast, weak words and the conjugation queue all pass `vocab.resolvesID` or `conjugationRideable` (`AppModel.swift:746, 799-802, 1300, 1545-1558, 1593, 1659, 1959, 2198, 2240, 2279, 2367-2374, 2379, 2393`; `JournalView.swift:194`). A filtered store makes "the number shown" and "the run produced" agree by construction, which is the house rule (`Sources/EntitlementKit/Entitlement.swift:116-119`).
* **Nothing deletes an id that does not resolve.** No store prunes unresolvable ids: `grep -i "prune\|orphan"` over `Sources` finds only comments, corpus text and the romaji matcher's own `pruneDeadEnds` (`RomajiKana/KanaInputMatcher.swift:181`). ReviewKit, WordListsKit, ConjugationReviewKit and SyncKit never import VocabKit; they take a `resolves:` closure (`Sources/ReviewKit/ReviewStore.swift:46-64`). So an N3 card or list entry that the rideable store cannot see is **kept**, synced and untouched. It is not ridden.

### 2.2 The shape

* `let catalog: VocabStore`: the full store, injected as today. **Read-only uses only**: search, list rows, About's counts, stumbled-word chips' display.
* `private(set) var vocab: VocabStore`: the **rideable** store. It equals `catalog` when depth is open. Otherwise it is `VocabStore(entries: catalog.entries.filter { freeLevels.contains($0.jlpt) })`, built once and cached. Every builder and every count keeps reading `vocab`, as today.
* `depthIsOpen: Bool`: the one predicate. True when **any** of: a persisted grandfather grant; the depth purchase's `EntitlementRecord.isEntitled` (its own key, P1-5); this session's grace (§5). Nothing else may decide it.
* `levelIsOpen(_ level: JLPTLevel) -> Bool`: `depthIsOpen || freeLevels.contains(level)`.
* When `depthIsOpen` changes (a purchase, a restore, a grace that becomes a grant), `vocab` is swapped, then `refreshWidgetSnapshot()` and `refreshReminders()` run, as they do after any due-count change (`AppModel.swift:717-718`). A run already in progress is not touched; it was built from the store it started with.
* `freeLevels` is one constant: `[.n5, .n4]` for candidate 1, `[.n5]` for candidate 2. The owner's C-2(d) answer changes this one line.

### 2.3 What may read which store

| reads `catalog` (display only) | reads `vocab` (rides and counts) |
|---|---|
| Search: `ListsView.swift:421`, and its prebuilt index `:580-581` | Every builder and count listed in §2.1 |
| List word rows: `ListsView.swift:871-876` (today an unresolved id renders as `.removed`, which would be false for an N3 word) | `playableCount(in:)`, `sentenceCount(in:)`, `dictationCount(in:)` (`AppModel.swift:1762-1764, 1770-1772, 1811`) |
| About's word count: `AboutView.swift:257-264` | `wordsAvailableAtLevel`, `dictationPoolCount`, `conjugationPoolCount` (`AppModel.swift:1670-1673, 2024-2029, 2307-2309`) |
| Stumbled-word chips' display: `ResultsView.swift:353` | The ride button under those chips: `rideableStumbles` (`AppModel.swift:2278-2280`), already computed separately from the displayed slice (`ResultsView.swift:357-358`) |

A source-scan test pins this split (§9).

---

## 3. Inventory: every surface where level content reaches a rider

"Sampler" = an install where `depthIsOpen` is false. "Paid level" = N3–N1 (candidate 1). Each row ends with what an existing (grandfathered) install sees; §8 collects them.

| # | Surface | Where level content enters (file:line) | What the boundary means there for a sampler | Edge cases | Existing installs |
|---|---|---|---|---|---|
| 1 | **Level picker** (menu) | `MenuView.swift:201-216` (N5…N1 + All); `AppModel.selectedLevel` `:236-237`, persisted as `AppSettings.selectedLevel` (`AppSettings.swift:24, 97`, default N5) | All five levels still shown. A paid level shows a lock and, when selected, the **depth card** replaces the start button (§7). "All" means **all open levels** and is labelled "Mix" / 混合 (today en "All", `MenuView.swift:210`; `AppModel.swift:1677-1679`) *(agent's choice, 2026-10-07 delegation)*. | A stored N2 on a sampler (§4.5). The empty-pool notice must not fire for a locked level: today it says "Nothing due at this level today" (`MenuView.swift:477-482`), which would be false. | Identical to v1.38: no lock, "All" keeps its label. |
| 2 | **Journey** | `startGame` → `GameSession.make` (`AppModel.swift:2102-2108, 2158`); due words from **every** level plus new words at the level (`GameSession.swift:605-622`) | New words only from open levels. Due cards whose word is paid are not mixed in. | An N3 SRS card on a sampler (§4.1). | Unchanged. |
| 3 | **Time Attack** | Same builder, `newWordCount = 300`, no reviews (`AppModel.swift:2111-2114`) | Open levels only. A sampler who has seen every N5 word gets the existing empty-pool notice, as any rider does today (`AppModel.swift:2167-2179`). | — | Unchanged. |
| 4 | **Practice: passages** | `makePractice(level: practicePassageLevel)` (`AppModel.swift:2156`; `GameSession.swift:361-386`) | **Free, all 233.** No JLPT tag exists to gate. | The coach's particle drill draws passages by content across all lengths (`AppModel.swift:1374-1382`): free. | Unchanged. |
| 5 | **Practice: words** | `GameSession.make` with the level (`AppModel.swift:2115-2117, 2158`) | Open levels only, like Journey. | — | Unchanged. |
| 6 | **Practice: My text** (custom text) | `makeCustomText` (`AppModel.swift:2147-2154`; `GameSession.swift:322-354`). CustomTextKit depends only on PersistKit (`Package.swift:72`): it never touches the corpus. | **Free, whatever words the text contains.** The level picker is hidden for it (`AppModel.swift:276-278`). It writes no SRS (`GameSession.swift:311-316`). | A pasted text full of N3 words: free, because the learner supplied it. The road purchase's boundary already says importing your own Japanese is a separate thing (`RoadView.swift:314-316`); E3 does not sell it either. | Unchanged. |
| 7 | **Sentence** | `makeSentence(vocab:config:)` (`AppModel.swift:2145`); falls back to the whole corpus when the level pool is empty (`GameSession.swift:402-404`) | Open levels only. The fallback, through the rideable store, can only reach open levels. | A locked level never reaches the builder: the depth card replaces start (row 1). | Unchanged. |
| 8 | **Listen** (dictation) | `makeDictation(vocab:config:)` (`AppModel.swift:2143`; `GameSession.swift:494-506`), no fallback | Open levels only. `dictationPoolCount` (`AppModel.swift:2024-2029`) counts the rideable store, so "no sentences at this level" (`MenuView.swift:464-470`) stays true. | Same as row 7. | Unchanged. |
| 9 | **Verbs** (conjugation drill) | `ConjugationSession.make` with `selectedLevel` (`AppModel.swift:2333-2341`; `ConjugationSession.swift:447-463`) | Open levels only: 306 verbs for candidate 1. | — | Unchanged. |
| 10 | **Verbs: due review** | `makeReview` pads from the **whole** pool (`ConjugationSession.swift:529-532`; `AppModel.swift:2412`) | Due cards for paid verbs are not rideable (`conjugationRideable`, `AppModel.swift:2367-2374`, uses the model's store); padding draws only open verbs. The menu count (`:2378-2379`) agrees. | Paid-verb cards synced from another device: kept, not counted, not ridden. | Unchanged. |
| 11 | **Reviews / SRS queue** (badge, Due line, Sentence-due, Listen-due) | `dueReviewCount` (`AppModel.swift:1658-1660`); `startSentenceDue` (`:1997-2006`), `startDictationDue` (`:1794-1801`); Due line `MenuView.swift:724-731` | Only cards whose word is open are counted or ridden. | §4.1. | Unchanged. |
| 12 | **Weak words** cram | `weakWordsRunIDs` / `startWeakWords` (`AppModel.swift:2238-2264`) | Only open words. The button's count and the run agree because both read one function (`:2232-2241`). | — | Unchanged. |
| 13 | **Stumbled words** (after a sentence or Listen run) | Chips: `StumbledWords.from(vocab:)` (`ResultsView.swift:353`). Ride: `rideableStumbles` → `makeWeak` (`AppModel.swift:2278-2303`) | A token inside an N5 sentence may be an N3 word. Its chip displays from the catalog and can be starred; the ride button rides only open words. | The button says the number it rides, as today (`ResultsView.swift:355-358`). | Unchanged. |
| 14 | **Word Lists** (play, Sentence, Listen from a list) | `startListGame` (`AppModel.swift:1957-1972`), `startSentenceList` (`:1977-1987`), `startDictationList` (`:1775-1787`); counts `:1762-1772, 1811` | Paid words stay in the list and show with a level tag ("N3 · in the N3–N1 levels") and no ride. The list's play counts count open words only. A list whose words are all paid shows the existing zero-playable state, plus one line naming why. | A list synced from a grandfathered device (§4.4). The 500-word cap (`WordListStore.swift:16`) counts every id, paid or not, as today. | Unchanged. |
| 15 | **Saved words** (★, the default list) | `isSaved` / `toggleSaved` (`AppModel.swift:1754, 1818`); the ★ is a list (`:1740-1747`) | Saving any word is free. Riding it follows row 14. | §4.1. | Unchanged. |
| 16 | **Dictionary search** | `model.vocab.search` (`ListsView.swift:421`) over the whole corpus since v1.35 | **Reads the catalog: every level stays searchable and addable** (it ships free today). A paid result shows its level tag; no buy button in search *(agent's choice, 2026-10-07 delegation)*. | §4.2. | Unchanged. |
| 17 | **Coach** drills | Word drills from **reviewed** ids (`AppModel.swift:1295-1306, 1384-1386`); particle drills from passages (`:1374-1382`) | Word drills draw only open reviewed words (rideable store). Passage drills free. The drill count (`:1311-1317`) agrees. | — | Unchanged. |
| 18 | **Widgets** | `refreshWidgetSnapshot` writes due **counts** only (`AppModel.swift:785-805`; fields `Sources/WidgetSharedKit/WidgetSnapshot.swift:16-37`) | Counts of open cards only. No word ever reaches the widget. | After a purchase the counts rise at the next refresh, which the access swap triggers (§2.2). | Unchanged. |
| 19 | **Reminders** | `refreshReminders` captures `vocab.resolvesID` (`AppModel.swift:740-757`); `DueReminderPlanner.swift:84` | Counts of open cards only. | Same. | Unchanged. |
| 20 | **Game Center** | One leaderboard, `ta_score` (`GameCenterManager.swift:23`), Time Attack only (`:73-75`); score per word from kana length and combo, not level (`GameSession.swift:846-851`); achievements from lifetime words, streak, runs, grade (`GameCenterManager.swift:77-85`) | No change to the board. A sampler posts from N5/N4 runs. Today's riders already post from any level. | None new. | Unchanged. |
| 21 | **Onboarding** | Shown only to a fresh install (`AppModel.swift:698-704`); lists the six modes (`GameSession.swift:45-60`) | **Unchanged, and it never mentions the purchase** *(agent's choice, 2026-10-07 delegation)*: an onboarding page would be a new entrance before the rider has typed anything. | Fresh installs are exactly the sampler population. | Never shown again to them (`AppModel.swift:703`). |
| 22 | **Stats and Ride Log** | Ride history labels its level (`JournalKit/RideRecord.swift:12-14`; `JournalView.swift:535-543`); the forecast card counts due cards (`JournalView.swift:192-194`) | History is shown as it is, including N3 rides synced from another device. The forecast counts open cards. `StatsView.swift` reads no level content (grep finds none). | — | Unchanged. |
| 23 | **About** | Word count from the store, passages, "Levels N5–N1" (`AboutView.swift:257-264`) | Reads the catalog (7,071). For a sampler one line is added: "N3–N1 with the one-time unlock". | Without the catalog split this would silently show 1,288. | Unchanged. |
| 24 | **Settings** | The road card (`SettingsView.swift:174-206`) | One new row, for samplers only: the depth unlock and its Restore (§7.1). | — | No new row. |
| 25 | **The road (Tōkaidō and the road west)** | `RideRoute`, `RouteStore` | **Untouched.** Distance still accrues from every mode as today. The road west stays its own purchase. | A sampler who bought the road west has the road west, not the depth. | Unchanged. |

**Sync, for every row.** CloudKit syncs SRS cards, ride records, the odometer, the legacy saved deck, word lists and conjugation cards (`CloudKitSyncController.swift:63`). It does **not** sync settings, custom texts, the entitlement, the install-cohort marker or the grant (none is a record type there). So access is decided per device; content arrives from other devices and is kept.

---

## 4. The named edge cases

1. **An SRS card or a saved/listed word from N3 on a sampler.** It can arrive by sync from another device, or be left by a session-grace launch (§5). It is **kept** on disk and in CloudKit (no pruning, §2.1). It is not counted in the badge, the Due line, the widget, reminders or the forecast, and it is never ridden, so no count promises a card the run cannot hand over. A saved N3 word stays starred and listed, with its level tag. On purchase it rides at once, its schedule intact.
2. **Search results from N3 for a sampler.** Shown, with a level tag, and addable to a list (search over the whole corpus ships free today, `ListsView.swift:319-322`). No buy button inside search. One caption under the first paid result per query: "N3–N1 words can be saved now and ridden with the N3–N1 levels."
3. **A custom text containing N3 words.** Free. It is the learner's own material, typed in Practice, never resolved against the corpus (row 6).
4. **A word list synced from a grandfathered device to a fresh one on the same iCloud account.** The fresh device is a new install and is not grandfathered by rules 1–2, which are local (§5). Rule 3 may grant it; whether `originalAppVersion` on a universal purchase reports the account's first platform is **unmeasured** (§5.6). If not granted: the list arrives whole, shows every word, tags the paid ones, and its play count is the open words. **Nothing is removed on either device.** The grandfathered device keeps riding all of it. A depth purchase on either device opens both, through StoreKit.
5. **A level setting persisted at N2 on a device that turns out not to be grandfathered.** This happens after a session-grace launch where the rider picked N2, or after a restore of a refunded purchase. The stored value is **never rewritten by the gate**, so a later purchase finds the rider where they left off. The menu shows N2 selected and locked, with the depth card in place of the start button. The rider picks an open level or buys. Nothing silently rides N4 under an N2 label *(agent's choice, 2026-10-07 delegation)*.
6. **"All" on a sampler.** Mixes open levels only. Its footer reads "Mix deck: 1,288 words" from the rideable store (`MenuView.swift:726-727`; `AppModel.swift:1670-1673`).
7. **A purchase mid-run.** The run keeps the store it started with. The next run sees the new store.
8. **A refund of the depth purchase.** The purchase record closes on the store's `revoked` signal only (`Entitlement.swift:143-148`). Content the rider made stays and is no longer ridden. A grandfather grant is a separate key and a refund cannot touch it.

---

## 5. The grandfather rule

### 5.1 As §E states it

From PLAN-V1.37 §E ("E3's grandfather rule"). An install is grandfathered, and the grant is **persisted**, if any of these holds:
1. **The P0-12 marker exists** with a first-seen build from before E3's build on that platform, compared as integers, per platform (macOS 61 and iOS 62 today, `project.yml:136, 275`).
2. **The marker is written at E3's first launch with `priorDataPresent`**: the install predates E3.
3. **A verified `AppTransaction` in the production environment** has `originalAppVersion` below E3's, parsed as integers. Apple, read today: the value is "the original value of the `CFBundleShortVersionString` for apps running in macOS, and the original value of the `CFBundleVersion` for apps running on all other platforms", and "In the sandbox testing environment, the `originalAppVersion` value is always `1.0`" (https://developer.apple.com/documentation/storekit/apptransaction/originalappversion, read via its documentation JSON 2026-10-27).

And:
* **Sandbox** (App Review, TestFlight): rule 3 is ignored; only rules 1–2 apply. A reviewer's fresh install sees the offer.
* **Unreadable**: `AppTransaction` throws and rules 1–2 do not grant → **session-only grace**: the depth is open for this process, nothing is persisted, and the check runs again next launch.
* **Order**: the check reads the marker **as it stood before this launch's write**.
* The offline-reinstall row: no prior data, no pre-launch marker, `AppTransaction` throws → session grace, nothing persisted.

Why `AppTransaction` cannot be the first line: it "throws an error if the `AppTransaction` isn't available or if the user isn't authenticated with the App Store. Getting an `AppTransaction` may require network connectivity" (https://developer.apple.com/documentation/storekit/apptransaction/shared, read 2026-10-27). PLAN-STAGE1 measured it throwing `networkError(-1009)` offline, with its cache scoped per app version (`docs/PLAN-STAGE1.md:281-284`). So an install that auto-updated to E3 overnight and opens on a plane would throw. Rules 1–2 exist so that this rider never needs the network.

### 5.2 The pure function

It lives beside `EntitlementRecord`, takes plain values (the house rule that keeps GameCore free of ConjugationReviewKit, `GameSession.swift:305-309`), and imports neither StoreKit nor SettingsKit.

```swift
public enum DepthGrandfather {
    public enum Platform: String, Codable, Sendable { case macOS, iOS }

    /// Integer components, never strings. "1.4" < "1.36" < "1.40"; "1.36" == "1.36.0";
    /// iOS builds are one component: "9" < "62". Unparseable → nil.
    public struct Version: Comparable, Sendable { let components: [Int] }

    /// E3's first build, per platform, fixed before the first E3 upload of any kind and never lowered.
    public struct Threshold: Sendable {
        let macOSFirstBuild: Int        // marker rule 1 on macOS
        let iOSFirstBuild: Int          // marker rule 1 on iOS, and rule 3 on iOS (CFBundleVersion)
        let macOSFirstVersion: Version  // rule 3 on macOS (CFBundleShortVersionString)
    }

    /// The marker as it stood BEFORE this launch wrote anything (P0-12's observation).
    public enum CohortBeforeLaunch: Sendable {
        case absent(priorDataPresent: Bool)   // priorDataPresent as P0-12 computed it this launch
        case present(firstSeenVersion: Version, firstSeenBuild: Int, platform: Platform, priorDataPresent: Bool)
        case unreadable
    }

    /// Presence of the grant key IS the grant (§5.4). Its bytes are diagnostic only.
    public enum StoredGrant: Sendable { case absent, present }

    public enum AppTransactionReading: Sendable {
        case production(originalAppVersion: String)  // verified, environment == .production
        case nonProduction                            // verified, sandbox or xcode
        case unavailable                              // threw, unverified, or unparseable
    }

    public enum Reason: String, Codable, Sendable {
        case markerBeforeE3, priorDataAtFirstMarker, originalAppVersionBeforeE3
    }

    public enum Decision: Equatable, Sendable {
        case alreadyGranted                 // stored grant: open, nothing to write
        case grant(Reason)                  // open, and persist the grant now
        case sessionGrace                   // open for this process only; never persisted
        case notGrandfathered               // closed unless purchased
    }

    /// Rules 1–2 and the stored grant, offline. nil = rule 3 is needed.
    public static func offlineDecision(stored: StoredGrant, cohort: CohortBeforeLaunch,
                                       platform: Platform, threshold: Threshold) -> Decision?

    /// The full rule. The caller reads AppTransaction only when offlineDecision returned nil.
    public static func decide(stored: StoredGrant, cohort: CohortBeforeLaunch,
                              appTransaction: AppTransactionReading,
                              platform: Platform, threshold: Threshold) -> Decision
}
```

Rule 3 compares on macOS `Version(originalAppVersion) < threshold.macOSFirstVersion`, and on iOS `Version(originalAppVersion) < Version([threshold.iOSFirstBuild])`. A production value that does not parse is `unavailable`, not "below" and not "above".

### 5.3 The truth table

"E3" = the threshold on this device's platform. "PD" = `priorDataPresent`. **G** = grant, persisted. **S** = session grace. **N** = not grandfathered (the offer shows). "—" = not consulted.

| # | stored grant | marker before this launch | PD | AppTransaction | result | rule |
|---|---|---|---|---|---|---|
| 1 | present | any | any | — | open (`alreadyGranted`) | stored; no re-evaluation, ever |
| 2 | absent | present, this platform, build < E3 | any | — | **G** `markerBeforeE3` | 1 |
| 3 | absent | present, this platform, build ≥ E3, PD true | true | — | **G** `priorDataAtFirstMarker` | 2 (marker first written at an E3-or-later launch of an install that already had data) |
| 4 | absent | absent | true | — | **G** `priorDataAtFirstMarker` | 2 (a legacy install that skipped 1.37 and 1.38; works offline) |
| 5 | absent | present, build ≥ E3, PD false | — | production, below E3 | **G** `originalAppVersionBeforeE3` | 3 (a legacy rider who deleted and reinstalled, online) |
| 6 | absent | present, build ≥ E3, PD false | — | production, E3 or later | **N** | a fresh E3-era install |
| 7 | absent | present, build ≥ E3, PD false | — | nonProduction | **N** | sandbox rule |
| 8 | absent | present, build ≥ E3, PD false | — | unavailable | **S** | unreadable |
| 9 | absent | absent | false | production, below E3 | **G** `originalAppVersionBeforeE3` | 3 (legacy reinstall, online, first launch) |
| 10 | absent | absent | false | production, E3 or later | **N** | a fresh install |
| 11 | absent | absent | false | nonProduction | **N** | sandbox: App Review's fresh install sees the offer |
| 12 | absent | absent | false | unavailable | **S** | **the offline-reinstall row** |
| 13 | absent | unreadable | — | production, below E3 | **G** `originalAppVersionBeforeE3` | 3 |
| 14 | absent | unreadable | — | production, E3 or later | **N** | — |
| 15 | absent | unreadable | — | nonProduction | **N** | sandbox rule |
| 16 | absent | unreadable | — | unavailable | **S** | unreadable |
| 17 | absent | present, **other** platform | — | as 13–16 | as 13–16 | a marker for another platform is treated as unreadable *(agent's choice, 2026-10-07 delegation)* |

Rules 1–2 never read the network, so rows 2–4 hold on a plane. Row 1 means a grant, once written, decides every later launch with no other input.

**Two readings this table makes, labelled:**
* **`unavailable` includes `.unverified` and an unparseable production value**, not only a throw *(agent's reading, 2026-10-07 delegation)*. §E names only the throw. Treating an unverified transaction as "no information" keeps a legacy rider on the safe side of the red line. The cost is that a device that can force `.unverified` gets grace each launch, which a forced offline launch already gets (§5.7).
* **PD on a present marker counts** (row 3). The marker stores PD; a marker first written at an E3-era launch with PD true means the install had data before any marker existed, which only a pre-marker install can have.

### 5.4 What is persisted, where, and why a grant is never revoked

| key (local `UserDefaults`, the settings store) | written by | content | synced? |
|---|---|---|---|
| `NihongoRide.installCohort.v1` | P0-12, once, if absent | first-seen version, build, platform, PD | never |
| a new grant key, proposed `NihongoRide.depthGrant.v1` | E3, on any `grant(_)` decision, once | the `Reason`, the version and build that wrote it, the platform | never |
| the depth purchase's `EntitlementRecord`, under its own key and its own quarantine key (P1-5) | the depth store | as the road's record (`Entitlement.swift:79-127`) | never |
| session grace | nobody | lives in memory only | — |

* **The grant key's presence is the grant** *(agent's choice, 2026-10-07 delegation)*. Only a grant ever writes it, so any bytes there, readable or not, mean a grant happened. Unreadable bytes are honoured as a grant and copied once to `<key>.unreadable`, the house quarantine pattern (`Entitlement.swift:215-238`). This differs on purpose from `EntitlementLedger.load`, which fails toward "never established" (`:204-211`) because its key can also hold a never-verified record. The grant key cannot.
* **Never revoked, in code, three ways.** (1) The type has no "revoked" or "false" value to write. (2) No code path removes the key; a source scan pins that (§9). (3) Row 1 returns before any other input is read, so no later signal (a new `AppTransaction`, a refund, a downgrade, a marker change) can reach a decision.
* **Why.** "No existing install loses anything, ever — enforced in code" (`PLAN-V2-PRODUCT.md:387-389`). A grant that a later reading could close would turn a flaky network or an Apple-side value change into lost depth for someone who never paid for it and was promised it.
* **Never synced, never sent.** None of these is a CloudKit record type (`CloudKitSyncController.swift:63`). `PrivacyClaimTests` stay green; Data Not Collected stays true. The privacy page's on-device storage list (`site/privacy.html:34-35`, which P0-6 extends for the marker) gains one sentence for the grant and the second purchase record, for the owner to push.

### 5.5 The order rule, and what it actually protects

The check reads P0-12's **pre-launch observation**, never the defaults after this launch's write.

**PLAN-V1.37 §E's stated reason does not hold under its own definitions.** It says that reading the fresh marker would make an offline legacy reinstall "fail rules 1–3, and get neither a grant nor grace". But a fresh marker has build = E3 and PD false, so rules 1–2 do not grant, and with `AppTransaction` throwing, §E's own unreadable rule gives grace: row 8, the same S as row 12. **No row of the table changes with the order**, given that the marker stores PD.

The rule is still kept, because it protects against a likely bug: a decision that reads "present marker, build ≥ E3" as a final verdict and skips `AppTransaction`. With the pre-launch observation, the offline reinstall reaches row 12 (S) even under that bug; with the post-write marker it would get N. So the order is defence in depth, and the mutation in §9 targets that bug.

### 5.6 The interface E3 needs from P0-12

P0-12 is being built on `feat/v137-install-cohort`; E3 assumes nothing beyond these:
1. **A launch-scoped, pre-write observation**: absent (with this launch's PD) / present (first-seen version components, first-seen build, platform, PD) / unreadable. Readable after the marker step and before anything else touches the key.
2. **PD computed before this launch writes anything that PD looks at.** The settings blob is saved on every launch (`AppModel.swift:715`) and sync starts at `:719`. If PD reads the settings blob or the odometer, it must be computed before `:715` and before sync can fill local stores from the cloud, or every reinstall would read as "prior data".
3. **Integer version and build types** that E3 can reuse, so the comparison is written once.
4. **Write-once, and unreadable bytes never replaced.** A fresh marker over unreadable bytes would turn row 16 (S, then G once online) into rows 6–8 for a legacy rider.
5. **A platform value** that matches E3's `Platform`.

If v1.37 slips and P0-12 rides v1.38 (PLAN-V1.37 §I, v1.37 row), nothing here changes: rule 2 (row 4) covers every install that skipped the marker releases.

### 5.7 Costs this rule accepts, said plainly

* **A fresh E3-era install that stays offline gets grace on every offline launch** (rows 8, 12, 16). It gains nothing permanent. Because the `AppTransaction` cache is per app version (`PLAN-STAGE1.md:281-283`), even a once-online install can throw again after an update. A rider who wants the depth free can keep the device offline. That rider cannot buy anyway: a purchase needs the network. Closing this hole is open question Q4.
* **Universal purchase across platforms is unmeasured.** The app is one ASC record with macOS and iOS versions (ASC GET 2026-10-27, `/v1/apps/6777469778/appStoreVersions`: `MAC_OS` and `IOS`, both 1.36 `READY_FOR_SALE`) and one bundle id (`project.yml:133, 272`). Whether a legacy Mac rider's **first** iPhone install reads a pre-E3 `originalAppVersion` is not documented and cannot be tested in the sandbox, where the value is always "1.0". Either answer keeps the red line, because that iPhone is a new install that had nothing. It decides only whether a legacy account's second device gets the depth (Q3).
* **The threshold is a hand-set constant.** It must be the first E3 build of any channel, TestFlight included, on each platform. Lowering it later would un-grandfather installs whose grant was not yet written; a test pins its literal value once set (§9).

---

## 6. The multi-SKU dependency: what P1-5 and P1-11 must provide first

E3 cannot share a release with the ledger split: "Split the counter before adding an offer, never in the same release" (`PLAN-STAGE1.md:1374-1381`). So P1-5 and P1-11 ship in v1.38 and E3 in v1.39 (PLAN-V1.37 §E "Sequence").

### 6.1 What blocks a second SKU today

| blocker | where | what P1-5 / P1-11 must do |
|---|---|---|
| One static product id | `RouteStore.swift:69` | A product list; the road's id unchanged. |
| The ledger is loaded for that one id | `RouteStore.swift:117-120` | One ledger per SKU, each on its own key. |
| A record under a different `productID` is discarded, quarantined and later overwritten | `Entitlement.swift:224-242` | Never share a key: two SKUs on `NihongoRide.entitlement.v1` would quarantine and overwrite each other's record on every load, and lock buyers out offline. |
| The quarantine key ignores the `key` parameter | `Entitlement.swift:222` (`defaultsKey + ".unreadable"`), used at `:236-238` | A quarantine key derived from each SKU's own key. |
| `refresh()` reads the store for one id | `RouteStore.swift:179-180` (and `readStore`, `:208-241`, filtering `productID` at `:214, 233`) | A refresh per SKU, each with its own `revokedAt`. |
| The purchase applies its plan to the one ledger | `RouteStore.swift:364-365` | The plan applied to the SKU that was bought. |
| The ledger counts have no product dimension | `UnlockOfferLedger.swift:127` (one key), `:135` (`[event: [bucket]]`) | Ledger v2 keyed by product: v1 decodes by padding, never truncating; existing counts migrate under the road's id; a quarantine key per ledger key (PLAN-V1.37 §D P1-11). |
| Buckets are the Tōkaidō's distance | `UnlockOfferLedger.swift:52-56` | E3's events use the same distance buckets. No level dimension is added: the ledger records "no vocabulary" (`:41`) and a level picked is close to that line *(agent's choice, 2026-10-07 delegation)*. |

### 6.2 Gaps in P1-5's stated scope (found in code, not listed in PLAN-V1.37 §D P1-5)

1. **`Transaction.updates` refreshes only the road.** The listener finishes every verified update, of any product, then calls the road's `refresh()` (`RouteStore.swift:395-404`). An approved Ask-to-Buy or a refund of the depth would be finished there and never reach the depth's ledger until the next launch. P1-5 must route each update to every SKU's refresh, or to the matching one.
2. **`Product.products(for:)` asks for one id** (`RouteStore.swift:169`). It must ask for the list. It "silently drops the rest" when an id is missing (`:81-84`), so a depth id missing in some storefront must leave the road's row working.
3. **The DEBUG seam fakes one entitlement** (`RouteStore.swift:122-142`, `NIHONGO_FAKE_ENTITLEMENT`). UI tests need the sampler, grandfathered, bought and grace states for the depth separately. Any new seam stays inside `#if DEBUG`, which `EntitlementSeamTests` enforces by reading the file.
4. **A new IAP has no availability record and is silently unbuyable until one is set** (PLAN-V1.37 §A, citing `docs/ASC_METADATA.md:196-197`). E3's release script must set and read back availability before submit.

### 6.3 What P1-12 must provide for E3 to be measured

`sales_report.py` classifies by type code only (`scripts/sales_report.py:215-229`). Window 2 needs P1-12(a): a SKU column, the depth SKU registered, an unknown SKU failing calibration, two SKUs never pooled. Not a code dependency of E3; a dependency of reading it.

---

## 7. What the rider sees

### 7.1 Entrances

Two, both for samplers only *(agent's choice, 2026-10-07 delegation)*:
1. **A locked level in the menu picker** (row 1). Selecting it shows the depth card in place of the start button. After a purchase the start button returns and that level rides **at once**. This answers the condition PLAN-V1.37 §K sets on any entrance: no entrance "to a purchase that shows nothing on purchase". It is at 0 km, which is allowed for this one because the purchase opens something on the next tap; the cut P1-9 was a 0 km entrance to scenery first seen at 28 km (PLAN-V1.37 §D P1-9).
2. **One Settings row** beside the road card (`SettingsView.swift:174-206`), opening the same card. It is where Restore lives for a sampler whose menu is on an open level, and where App Review is pointed.

Not entrances: search, list rows and About carry a level tag or a line of text, never a buy button. No onboarding page, no badge, no modal, no post-ride prompt (PLAN-V1.37 §K bans the Kyōto-arrival kinds of these). Grandfathered installs see neither entrance.

### 7.2 The depth card

* What it opens, with counts **computed from the catalog** and pinned by a test, never typed: for candidate 1, N3, N2, N1: 5,783 words and 5,481 sentences, in every mode.
* What stays free: N5, N4, every mode, the passages, the road.
* What it is not: the road west, which is its own purchase.
* The buy button with `product.displayPrice`; a progress state; Restore with an outcome (P1-3's `restorePlan` shape, reused).
* Drafts, for the owner to change *(agent's draft, 2026-10-07 delegation)*:
  * en: "N3, N2 and N1: 5,783 more words and 5,481 sentences, in every mode. One purchase, yours to keep. N5, N4, every mode and the road stay free. The road west is a separate purchase."
  * zh: "N3、N2、N1：再加 5,783 个词和 5,481 个例句，所有模式都能用。一次购买，永久拥有。N5、N4、所有模式和这条路都免费。西行之路是另一项购买。"
  * ja: written with P1-15's glossary, not drafted here.

### 7.3 Copy constraints

* **One name per product per language**, pinned by a test like `PurchasePromiseTests` (P1-2 does this for the road: one zh name, 西行之路). Proposed name *(agent's draft, 2026-10-07 delegation)*: en "N3–N1 Levels", zh "N3–N1 等级", ja via P1-15. The road keeps "The Road West" / 西行之路 / 西への道.
* **No promise the code does not keep.** No "all future content", no "every level" for the free tier, no count that is not computed. "Yours to keep" / "永久拥有" describe the duration of ownership, the reading `RoadView.boundary` already uses (`RoadView.swift:308-311`).
* **"All" becomes "Mix" for samplers** (row 1), so the picker does not say "All" over two levels.
* **The store must say what needs a purchase.** Guideline 2.3.2: "make sure your app description, screenshots, and previews clearly indicate whether any featured items, levels, subscriptions, etc. require additional purchases" (https://developer.apple.com/app-store/review/guidelines/, read 2026-10-27). Today the en description says "7,000+ words across JLPT N5 to N1" and the zh "JLPT N5 到 N1 共 7000+ 词" (`docs/ASC_METADATA.md:83, 124`); the subtitles and keywords name N5–N1 (`:60-64, 102-105, 153`). At the E3 release these say that N3–N1 need a one-time purchase, in en, zh and ja, read back byte-exact (PLAN-V1.37 §J V7). The site's "7,000+ words" (`site/index.html:43`) and "JLPT N5–N1" lines (`site/index.html:7, 34`; `site/support.html:24`) need the same qualifier, pushed by the owner.
* **The road's boundary sentence stays true.** It says the road purchase does not cover content packs (`RoadView.swift:314-316`). E3 is sold separately, so nothing there changes.

### 7.4 App Review notes it will need (draft; written into ASC only at the E3 release, after the C-2 box)

> The app is free. N5 and N4 vocabulary, every mode, all Practice passages and the Tōkaidō road are free. A one-time non-consumable, "N3–N1 Levels", opens the N3, N2 and N1 vocabulary in every mode, immediately after purchase. To see it: on the main menu choose N3, N2 or N1 in the level picker; the purchase card replaces the Start button. It is also in Settings, under the road card, with Restore Purchases.
>
> Users who installed the app before this version keep every level for free. This is decided on the device. **If this device had an earlier version of Nihongo Ride installed, every level is already open and the purchase is not shown; delete the app and install fresh to see it.** In the sandbox a fresh install always sees the purchase.
>
> The road west ("The Road West") is a separate, existing purchase and is unchanged.

* The IAP's own review note and screenshot show the depth card. The road IAP's note is P1-14's.
* Family Sharing stays off: it is irreversible (PLAN-V1.37 §K; `HANDOFF-STAGE1-GATES-PROMPT.md:218`).
* Submission: E3 is the app's **second** non-consumable, so `POST /v1/inAppPurchaseSubmissions` (`scripts/submit_1_30.py:28-31`; `scripts/asc_release.py:611-614`). Neither path is measured for a second IAP; the script stops on any answer other than success (PLAN-V1.37 §E rank 1).
* **Whether App Review's environment is the sandbox** is PLAN-V1.37's claim (§E), not re-verified today. Apple's page read today says only what the sandbox value is.

---

## 8. What existing installs keep: everything, forever

An existing install is one that `decide` grants (rows 1–5, 9, 13). For it `depthIsOpen` is true on every launch, from the grant key alone (row 1), offline or online.

| surface (§3 row) | what it sees |
|---|---|
| Level picker (1) | All five levels and "All", exactly as v1.38. No lock. |
| Journey, Time Attack, Practice words (2, 3, 5) | Every level, new and due. |
| Passages, My text (4, 6) | Unchanged. |
| Sentence, Listen, Verbs, Verbs review (7–10) | Every level. |
| Reviews, badge, widget, reminders, forecast (11, 18, 19, 22) | Every card counted and ridden, as today. |
| Weak words, stumbled words, coach (12, 13, 17) | Every word. |
| Lists, saved words, search (14–16) | Every word rides. No tags. |
| Game Center, onboarding, stats, About (20–23) | Unchanged. Onboarding is never shown again. |
| Settings (24) | No new row. |
| The road and the road west (25) | Unchanged. The road west stays a separate purchase, still for sale. |
| On a plane, after an overnight update | Rule 1 or 2, offline (rows 2–4). |
| After a downgrade, an upgrade, a restore, a refund of anything, a sign-out | The grant key decides (row 1). Nothing reads anything else. |

**The verification that matters most:** for a grandfathered install, every pool count and every run builder must return exactly what v1.38 returns. §9 pins that with a golden fixture produced from v1.38's own code, the method `PurchasePromiseTests` uses for the road (`Tests/SceneryKitTests/RideRouteFreezeTests.swift:1-20, 309`).

---

## 9. Tests to write, and the verification it needs

### 9.1 Pure table tests (`DepthGrandfather`)

* **Every row of §5.3**, one test each, including row 12 by name ("offline reinstall, no prior data, no pre-launch marker, AppTransaction throws → session grace, nothing persisted").
* **Version parsing**: "1.4" < "1.36" < "1.40"; "1.9" < "1.10"; "1.36" == "1.36.0"; "1.4.1" between "1.4" and "1.5"; iOS "9" < "62"; "1.0" (sandbox-shaped) parses; "" and "abc" → unavailable.
* **Per platform**: a macOS marker at build 61 against an iOS threshold is never compared (row 17).
* **Decision → persistence**: `grant` writes the key once; `alreadyGranted` writes nothing; `sessionGrace` and `notGrandfathered` write nothing.
* **Unreadable grant bytes** are honoured and quarantined once, never overwritten.

### 9.2 Mutations that must go red (revert each, paste the red line, PLAN-V1.37 §J V8)

| mutation | must turn red |
|---|---|
| Persist the grace (write the grant key on `sessionGrace`) | rows 8, 12, 16: "nothing persisted" |
| Compare versions as strings | "1.4" vs "1.36" (string order puts "1.4" above), iOS "9" vs "62" |
| Accept sandbox for rule 3 (treat `nonProduction` "1.0" as below E3) | rows 7, 11, 15 |
| Revoke a grant (any path that removes or overwrites the grant key, or returns `notGrandfathered` with a stored grant) | row 1, and the source scan below |
| Read the marker after this launch's write, combined with treating "present, build ≥ E3" as final | row 12 |
| Treat `unavailable` as `notGrandfathered` | rows 8, 12, 16 |
| Drop the PD check on a present marker | row 3 |
| Lower the threshold constant | the literal pin |

### 9.3 App-layer tests

* **Golden grandfathered sweep.** A fixture produced by **compiling v1.38's own code**: for each mode × level × "All", the pool size and the id set each builder can draw, plus every count in §2.1, for a fixed fixture review store and lists. E3 with `depthIsOpen = true` must reproduce it byte for byte. This is the red-line test; the shape is `PurchasePromiseTests`' v1.29 sweep.
* **Sampler sweep.** The same table with `depthIsOpen = false`: every id drawn is N5 or N4; every count equals the run it promises (the house "count and run from one predicate" rule).
* **Store split, by source scan** (the `CallSiteScanner` in `Tests/NihongoRideAppTests/CallSiteScanner.swift`): every `GameSession.make*` and `ConjugationSession.make*` call in `NihongoRideApp` passes `vocab:` explicitly (the defaults are `.shared`, the full store, e.g. `GameSession.swift:419`); `catalog` never reaches a builder or a `resolves:` argument; the grant key appears in one write and no remove.
* **Locked level**: start with a locked level selected builds nothing and sets no empty-pool notice (§4.5, `MenuView.swift:477-482`).
* **Access swap**: a purchase while on the menu swaps `vocab`, refreshes the widget and reminders, and the next start rides N3.
* **Sync safety**: a synced N3 SRS card and list id on a sampler survive a save and a re-sync unchanged.
* **Copy pins**: the card's counts equal the catalog's; one name per product per language; `PrivacyClaimTests`, `PurchasePromiseTests`, `PaidRouteRowTests` and `OneBranchRuleTests` change in the same commit as what they pin (PLAN-V1.37 §J V7). `stage1_walk.py`'s constants as PLAN-V1.37 §E lists.

### 9.4 The §J verification E3 needs

* **V1** gates green at the then-current floor; `HorizontalTextFitTests.accepted` only lowered.
* **V2** headless renders en/zh/ja for two named states: **grandfathered** (the menu, lists, search, About and Settings **byte-identical to v1.38**, a frozen-surface check that the red line holds on screen) and **sampler** (intended differences named in advance: the locked picker, the depth card, the Settings row, list and search tags, About's line). The capture harness needs a sampler seam to render the second (§6.2 item 3).
* **V3** AX5 on the depth card and the locked picker, en/zh/ja; contrast measured on rendered pixels.
* **V4** `run_ios_placement_tests.sh`: the depth card's placement, absent when open.
* **V5** store gates stay at exit 3 until P0-9; the depth SKU joins them when P0-9 runs.
* **V6** the pre-submission review adds the **red-line lens on the grandfather rule** (PLAN-V1.37 §J V6), with independent refuters, reading this table against the code.
* **V7** store copy and review notes read back byte-exact; the site diff for the owner.
* **V8** every mutation in §9.2 reverted and seen red.

---

## 10. Open questions for the owner (each has a default on silence)

| # | question | default on silence |
|---|---|---|
| Q1 | **The boundary (C-2(d)):** candidate 1 (N5+N4 free) or candidate 2 (N5 free)? | Candidate 1. |
| Q2 | **The product's name** in en/zh (ja with E5), and its product id, which Apple never lets be edited (`RouteStore.swift:66-69`). Draft: "N3–N1 Levels" / "N3–N1 等级"; an id naming the boundary, like the road's names its capability set (`RouteStore.swift:52-57`). | The draft name; the id chosen at the E3 release to name the chosen boundary, recorded in the release record. |
| Q3 | **A legacy account's second device.** Rule 3 may or may not grant it (§5.7). Should a pre-E3 ride record arriving by sync also grant? It needs no new record type (ride records carry a date, `JournalKit/RideRecord.swift`), but a device clock can be set back, and it is a fourth rule §E does not have. | No. §E's three rules only; the synced content is kept and shown. |
| Q4 | **The offline-grace hole** (§5.7). Latch a verified production "E3 or later" reading locally, so a once-verified fresh install gets no grace later? It never blocks a grant, but it is not in §E. | No latch: §E exactly, the hole accepted. |
| Q5 | **Search for samplers**: keep all levels searchable and addable (as shipped since v1.35), or show only open levels? | All levels, tagged. |

---

## 11. Where PLAN-V1.37 and the code disagree, and what this document could not verify

**PLAN-V1.37 against the code or its own definitions:**
1. **§E's reason for the order rule** does not hold: under §E's own "unreadable" rule the offline reinstall gets grace whichever marker is read (§5.5). The rule is kept as defence in depth.
2. **P0-13's "kana … in every mode"**: no kana mode exists (`GameSession.swift:16-22`). Kana practice is the passages and the coach drills, both free (§1).
3. **P0-13's "everything that already ships free"** includes the N3–N1 pools if read literally. Read here as every feature and mechanic (§1).
4. **P1-5's scope misses three things** a second SKU needs: routing `Transaction.updates` (`RouteStore.swift:395-404`), the product request (`:169`), and the DEBUG seam (`:122-142`) (§6.2).
5. **§E's "a clean denominator"** ("Purchases come only from new installs"): a grandfathered account's first install on its other platform is not grandfathered by rules 1–2 and can buy. Whether App Store reports count it as a first-time download under universal purchase is unverified, so the denominator may not be exactly "new installs".
6. **§E rule 1 and the marker**: a marker for another platform (row 17) and an unverified `AppTransaction` (§5.3) are not covered by §E's text. This design treats both as unreadable, labelled.

**Not verified today:**
* `originalAppVersion` on a universal purchase's second platform (§5.7).
* Whether App Review runs in the sandbox environment (§7.4).
* Whether a freshly downloaded build's `AppTransaction` is readable offline on its first launch. PLAN-STAGE1's measurement (`PLAN-STAGE1.md:281-284`) was of an update; the table gives grace either way.
* Either IAP submission path for a second IAP (PLAN-V1.37 §A).

**State read today:** one IAP exists, `com.jasonye.nihongoride.scenery.lifetime`, `NON_CONSUMABLE`, `APPROVED`, `familySharable` false (ASC GET 2026-10-27, `/v1/apps/6777469778/inAppPurchasesV2`). No depth IAP exists, and none is created by this document.
