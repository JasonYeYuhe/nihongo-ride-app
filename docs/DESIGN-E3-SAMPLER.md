# DESIGN-E3-SAMPLER: a complete free sampler, one one-time depth unlock, every existing install kept whole

*Design document, 2026-10-27 (JST). PLAN-V1.37 §C item P0-13. Written on branch `docs/v137-e3-design` from repo HEAD `9c09ab7`; revised the same day after an independent red-line review (round 1, §12). Marker-branch citations are to `v137-marker` @ 56a2ebc and say so. Design only: no code, no IAP, no App Store Connect write. Every claim cites a file:line at that HEAD, an ASC GET with its date, or a URL read today.*

> **Nothing in this document ships before the owner's C-2 box (PLAN-V1.37 Appendix A-1).** No IAP is created, no price is set and no product id is registered before that box exists. With no box, E3 stays on its branch and nothing here reaches a rider (PLAN-V1.37 §I, v1.39 row; §1 C-2 default).
>
> **No price appears here, and no price placeholder.** "An agent invents no prices" (`docs/PLAN-V1.34.md:729`). The buy button shows StoreKit's `product.displayPrice`, as the road's does (`Sources/NihongoRideApp/RoadView.swift:179`).
>
> **Labels.** Anything marked *(agent's choice, 2026-10-07 delegation)* or *(agent's reading, 2026-10-07 delegation)* is the agent's, under the owner's 2026-10-07 delegation. It is not an owner decision. The owner can change any of them at C-2(d) or by saying so.

---

## 0. The design in one screen

* **What is sold.** One non-consumable that opens the N3, N2 and N1 pools in every mode. Nothing else.
* **What stays free (candidate 1, the default).** N5 and N4 in every mode, all 233 Practice passages, the learner's own texts, the Tōkaidō road, search, lists, saving, sync, the coach, the widget and Game Center. *(The boundary is the agent's design choice under the 2026-10-07 delegation; PLAN-V1.37 §C P0-13 names it the default, and C-2(d) can change it.)*
* **Who can buy it.** Only installs that are not grandfathered. Every install made from a build that customers received without the gate keeps everything, forever, through a persisted, never-revoked grant (§5). The threshold that decides this sits above every such build, and may only rise (§5.2).
* **How it is built.** One predicate decides what is open. `AppModel` holds two vocabulary stores: the full **catalog** for reading (search, list rows, About), and a **rideable** store for building runs and counting them. Every run builder and every count already reads the model's one injected store (`AppModel.swift:199-201, 528-529`), so swapping that store for a filtered one closes every mode at once (§2). The free side is a list of word ids frozen at the first gated release, which may grow and never shrink (§2.2).
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

**The choice is made once.** After the first gated release, sampler installs are existing installs too, and the red line protects them. So C-2(d) is a one-time choice before that release: the free set may grow later, and never shrink (§2.2; review finding S4).

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
* `private(set) var vocab: VocabStore`: the **rideable** store. It equals `catalog` when depth is open. Otherwise it is `VocabStore(entries: catalog.entries.filter { DepthFreeSet.ids.contains($0.id) })`, built once and cached. Every builder and every count keeps reading `vocab`, as today.
* `depthIsOpen: Bool`: the one predicate. True when **any** of: the gate is off in this build; a persisted grandfather grant; the depth purchase's `EntitlementRecord.isEntitled` (its own key, P1-5); the grandfather check still pending; this session's grace (§5). Nothing else may decide it.
* `levelIsOpen(_ level: JLPTLevel) -> Bool`: `depthIsOpen || freeLevels.contains(level)`.
* When `depthIsOpen` changes (a purchase, a restore, a grace that becomes a grant), `vocab` is swapped, then `refreshWidgetSnapshot()` and `refreshReminders()` run, as they do after any due-count change (`AppModel.swift:717-718`). A run already in progress is not touched; it was built from the store it started with.
* **`DepthFreeSet.ids` is a list of word ids, not a level filter** (review finding S4, accepted). It is generated once, at the first gated release, from the chosen boundary: N5 + N4 for candidate 1 (1,288 ids), N5 for candidate 2 (646). It is committed as a golden file and pinned by a test.
  * **It may grow and never shrink.** A later corpus edit that moves an id from N4 to N3 leaves the id free. A new N5 or N4 entry is added to the list in the same commit that adds the entry. A test compares the list with a frozen copy of the first gated release's list and fails if any id is missing.
  * **Why not `jlpt`.** The corpus is corrected most releases (v1.37's own P0-2 re-reads sentences). Defined by the `jlpt` field, the free tier would shrink every time a correction moved a word up a level, and every sampler would lose that word and its SRS card. Sampler installs are existing installs once E3 ships.
  * **What it does not override:** if the corpus withdraws an entry for every install (an existing practice for bad entries, `VocabStore.swift:172-180`), it is withdrawn for samplers too. That is the corpus's rule, applied to every install alike, and not the gate's.
  * **C-2(d) is one-time.** The owner's answer chooses which levels seed the list. After the first gated release, a boundary change may only add ids.

### 2.3 What may read which store

| reads `catalog` (display only) | reads `vocab` (rides and counts) |
|---|---|
| Search: `ListsView.swift:421`, and its prebuilt index `:580-581` | Every builder and count listed in §2.1 |
| List word rows: `ListsView.swift:871-876` (today an unresolved id renders as `.removed`, which would be false for an N3 word) | `playableCount(in:)`, `sentenceCount(in:)`, `dictationCount(in:)` (`AppModel.swift:1762-1764, 1770-1772, 1811`) |
| About's word count: `AboutView.swift:257-264` | `wordsAvailableAtLevel`, `dictationPoolCount`, `conjugationPoolCount` (`AppModel.swift:1670-1673, 2024-2029, 2307-2309`) |
| Stumbled-word chips' display: `ResultsView.swift:353` | The ride button under those chips: `rideableStumbles` (`AppModel.swift:2278-2280`), already computed separately from the displayed slice (`ResultsView.swift:357-358`) |
| The coach headline's example romaji: `CoachView.swift:171` (review finding M1) | The coach's drill entries: `AppModel.swift:1300-1305` (a builder; review finding M1) |
| A list row's `.removed` state and its "No longer in the dictionary — you can remove it" note (`ListsView.swift:871-876, 1243-1245`), and the list's unplayable hint (`:390-391, 844-849`): computed from the catalog only (review finding S5) | — |

**The scan covers every reader, not only builders** (review finding M1): every `model.vocab` and `vocab.` use in `NihongoRideApp` is classified as one of the two columns, and a new unclassified use fails the test.

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
| 14 | **Word Lists** (play, Sentence, Listen from a list) | `startListGame` (`AppModel.swift:1957-1972`), `startSentenceList` (`:1977-1987`), `startDictationList` (`:1775-1787`); counts `:1762-1772, 1811` | Paid words stay in the list and show with a level tag ("N3 · in the N3–N1 levels") and no ride. The list's play counts count open words only. **On a sampler, a list whose words are all paid does not show today's hint**, "These words aren't available on this device (they may come from a newer vocabulary)" (`ListsView.swift:844-849`, shown when `playableCount` is 0, `:390-391`). That hint would be false, and its sibling, the `.removed` row's "you can remove it" (`:1243-1245`), invites removals that sync as tombstones (`WordListStore.swift:183-191`, merged at `AppModel.swift:1424-1430`) and delete the words on the grandfathered device. The sampler sees instead: "N3–N1 words ride with the N3–N1 levels. They stay in this list." (review finding S5). | A list synced from a grandfathered device (§4.4). The 500-word cap (`WordListStore.swift:16`) counts every id, paid or not, as today. | Unchanged. |
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
4. **A word list synced from a grandfathered device to a fresh one on the same iCloud account.** The fresh device is a new install and is not grandfathered by rules 1–2, which are local (§5). Rule 3 may grant it; whether `originalAppVersion` on a universal purchase reports the account's first platform is **unmeasured**, and §5.3 reads it by shape so either answer is handled (§5.10). If not granted: the list arrives whole, shows every word, tags the paid ones, and its play count is the open words. **Nothing is removed on either device**, and nothing on the sampler invites a removal (row 14). The grandfathered device keeps riding all of it. A depth purchase on either device opens both, through StoreKit.
5. **A level setting persisted at N2 on a device that turns out not to be grandfathered.** This happens after a session-grace or pending launch where the rider picked N2, or after a refund of a purchase made while N2 was selected (review finding N3: round 0 said "a restore of a refunded purchase", which restores nothing). The stored value is **never rewritten by the gate**, so a later purchase finds the rider where they left off. The menu shows N2 selected and locked, with the depth card in place of the start button. The rider picks an open level or buys. Nothing silently rides N4 under an N2 label *(agent's choice, 2026-10-07 delegation)*.
6. **"All" on a sampler.** Mixes open levels only. Its footer reads "Mix deck: 1,288 words" from the rideable store (`MenuView.swift:726-727`; `AppModel.swift:1670-1673`).
7. **A purchase mid-run.** The run keeps the store it started with. The next run sees the new store.
8. **A refund of the depth purchase.** The purchase record closes on the store's `revoked` signal only (`Entitlement.swift:143-148`). Content the rider made stays and is no longer ridden. A grandfather grant is a separate key and a refund cannot touch it.

---

## 5. The grandfather rule

### 5.1 As §E states it

From PLAN-V1.37 §E ("E3's grandfather rule"). An install is grandfathered, and the grant is **persisted**, if any of these holds:
1. **The P0-12 marker exists** with a first-seen build from before E3's build on that platform, compared as integers, per platform (macOS 61 and iOS 62 today, `project.yml:136, 275`).
2. **The marker is written at E3's first launch with `priorDataPresent`**: the install predates E3.
3. **A verified `AppTransaction` in the production environment** has `originalAppVersion` below E3's, parsed as integers. Apple, read today: the value is "the original value of the `CFBundleShortVersionString` for apps running in macOS, and the original value of the `CFBundleVersion` for apps running on all other platforms"; it "remains constant and doesn't change when the customer upgrades the app"; and "In the sandbox testing environment, the `originalAppVersion` value is always `1.0`" (https://developer.apple.com/documentation/storekit/apptransaction/originalappversion, read via its documentation JSON 2026-10-27).

And:
* **Sandbox** (App Review, TestFlight): rule 3 is ignored; only rules 1–2 apply. A reviewer's fresh install sees the offer.
* **Unreadable**: `AppTransaction` throws and rules 1–2 do not grant → **session-only grace**: the depth is open for this process, nothing is persisted, and the check runs again next launch.
* **Order**: the check reads the marker **as it stood before this launch's write**.
* The offline-reinstall row: no prior data, no pre-launch marker, `AppTransaction` throws → session grace, nothing persisted.

Why `AppTransaction` cannot be the first line: it "throws an error if the `AppTransaction` isn't available or if the user isn't authenticated with the App Store. Getting an `AppTransaction` may require network connectivity" (https://developer.apple.com/documentation/storekit/apptransaction/shared, read 2026-10-27). PLAN-STAGE1 measured it throwing `networkError(-1009)` offline, with its cache scoped per app version (`docs/PLAN-STAGE1.md:281-284`). So an install that auto-updated to E3 overnight and opens on a plane would throw. Rules 1–2 exist so that this rider never needs the network.

This design keeps all of that and adds five protections found in review round 1 (§12): a threshold defined by what customers received (§5.2), a grant written by every build with the gate off (§5.2), rule 3 read by the value's shape (§5.3), a defined pending state with a timeout (§5.6), and a free set frozen by id (§2.2).

### 5.2 The threshold: above everything customers ever got without the gate

**Definition** *(agent's choice, 2026-10-07 delegation, replacing round 0's "first E3 build of any channel", which review finding B1 showed un-grandfathers people)*:
* `T_build[p]`, per platform: **one more than the highest `CFBundleVersion` ever released to App Store customers on platform p by a build without the gate.**
* `T_version`: the marketing version of the gated release. It must be **strictly above every marketing version ever released without the gate, on either platform.**
* Both are compiled into the gated binary before its first upload, from an ASC read made then. Both are re-checked before submit (below).
* **They may rise and never fall.** Raising grants more; lowering would un-grandfather any install whose grant was not yet written.

**Why "released to customers", not "first upload".** Builds come from one counter per target, bumped by one each release (`scripts/check_versions.py:78`; history 1…62, all single integers). Say a gated build 66 is uploaded, and then a 1.38.1 hotfix (67) or a v1.39 without E3 reaches customers. Under round 0's definition a fresh install of 67 would fail rule 1 (67 ≥ 66), rule 2 (no prior data) and, on iOS, rule 3 ("67" ≥ 66): permanent **N** for someone who installed when every level was free. Under this definition the gated build must be rebuilt with `T_build` above 67 before it can be submitted.

**Today's values, for scale** (ASC GET 2026-10-27, `/v1/apps/6777469778/appStoreVersions?include=build&limit=200`): 76 released versions; macOS 37, highest build 61; iOS 39, highest build 62; every build one integer; every version two or three components. v1.37 and v1.38 ship ungated first, so the real thresholds are fixed only at the gated upload.

**TestFlight.** A gated build is uploaded after every ungated release before it, so its number is at or above `T_build`, and a fresh TestFlight install of it is a sampler, which is what testing needs. If an ungated release later overtakes it, its TestFlight installs become grandfathered: generous and harmless. No low threshold is needed for testing.

**The release-script check, before every `--submit`** (ASC GET only, the read `asc_release.py` already makes per build at `find_build`, `scripts/asc_release.py:520-536`, plus the endpoint above):
1. Read every released version and its build, per platform.
2. Read the repo's registry of which released builds carried the gate. A new file, appended by the release script at each submit, the shape of the `FIRM_RELEASE_DATES_PT` registry.
3. **Gated submit:** stop unless `T_build[p]` > every ungated released build on p, `T_version` > every ungated released version, and both are ≥ the previous gated release's values.
4. **Ungated submit at or above the current `T_build`** (an ungated release after E3 exists): stop unless the build carries the ungated grant writer (next paragraph). The next gated submit then fails step 3 until its thresholds are raised above this build.
5. Print the thresholds and the ASC values in the release record.

**The ungated grant writer** (review finding S1, accepted). In any build where the gate is off (a rollback, a kill switch, E3 code present but disabled), `depthIsOpen` is true **and the grant is written** with `Reason.ungatedBuild`, on every launch. "Everything free" becomes a grant in its own right, so turning the gate back on later cannot close it.
* **Which release must carry it, and why:** the **first gated release (v1.39)**. Every later build is cut from `main` after E3's merge, so every rollback or kill-switch build inherits it. That covers S1 fully.
* **What it does not cover:** a hotfix built from a branch cut before E3 (a 1.38.x from the v1.38 tag). That hotfix has no E3 code, so it cannot write anything. The release-script check covers it instead, by forcing the next gated build's threshold above it (step 3).
* **Shipping it earlier, in v1.38,** would make every v1.38-or-later launch a grant before E3 exists, closing that hotfix case too. But it is E3 code shipping before the owner's box. **So it is a design note only, and needs the owner** (Q6). Default on silence: not in v1.38. The release-script check is sufficient without it.

### 5.3 Rule 3 by the value's shape, not the running platform

Round 0 compared `originalAppVersion` with the running platform's meaning: a marketing version on macOS, a build on iOS. On a universal purchase that is wrong if Apple reports the account's **first** platform's value, which is unmeasured (§5.10). Review finding S3: an iPhone-first account reinstalling on a Mac would read "40" as version [40], above [1, 39], and get **N**.

**Evidence that the shapes are disjoint:**
* Every `CFBundleVersion` this app ever released is one integer: 37 macOS and 39 iOS releases, all one component (ASC GET above). In git, `CURRENT_PROJECT_VERSION` was always a quoted integer, 1…62 (`git log -p -- project.yml`). The marker refuses any build that is not all digits (`Sources/SettingsKit/InstallCohort.swift:134-138` on `v137-marker` @ 56a2ebc).
* Every marketing version has two or three components: "1.0" … "1.36", plus "1.4.1" and "1.8.1" (git history of `MARKETING_VERSION`; ASC: 72 two-component and 4 three-component versions).

**The rule** *(agent's choice, 2026-10-07 delegation)*:
* **One component** → it is a build. Below E3 if it is below **max**(`T_build[macOS]`, `T_build[iOS]`), whatever platform is running.
* **Two or more components** → it is a marketing version. Below E3 if it is below `T_version`.
* Anything else (empty, non-numeric) → `unavailable`.
* Two pins keep the shapes disjoint: a test over `project.yml` that every build is one integer and every marketing version has at least two components, and the same assertion in `check_versions.py`'s bump (`:65-90`).

Side effect: the mirror case also goes the right way. An E3-era Mac-first account reports "1.39"; on iOS round 0 read that as [1, 39] < [63] and granted it. By shape it is a version, not below `T_version`: **N**. That keeps Window 2's denominator cleaner.

### 5.4 The pure function

It lives beside `EntitlementRecord`, takes plain values (the house rule that keeps GameCore free of ConjugationReviewKit, `GameSession.swift:305-309`), and imports neither StoreKit nor SettingsKit. It can reuse the marker's integer `Version` type, or copy its rules exactly ("1.36" == "1.36.0", `InstallCohort.swift:86-96` on the marker branch).

```swift
public enum DepthGrandfather {
    public enum Platform: String, Codable, Sendable { case macOS, iOS }
    public struct Version: Comparable, Sendable { let components: [Int] }   // never strings

    /// §5.2. Rises, never falls; a test pins the literals and the release script checks them.
    public struct Threshold: Equatable, Codable, Sendable {
        let buildMacOS: Int, buildIOS: Int   // T_build per platform
        let version: Version                 // T_version
    }

    /// What E3 reads from P0-12 (§5.9).
    public enum Cohort: Sendable {
        case present(firstSeenBuild: Int, platform: Platform, priorDataPresent: Bool)
        case unreadable          // unreadable bytes, another platform's marker, or no marker step ran
    }

    public enum StoredGrant: Sendable { case absent, present }   // presence of either copy IS the grant
    public enum Latch: Sendable { case absent, present(threshold: Threshold) }   // §5.6

    public enum AppTransactionReading: Sendable {
        case production(originalAppVersion: String)  // verified, environment == .production
        case nonProduction                            // verified, sandbox or xcode
        case unavailable                              // threw, unverified, unparseable, or timed out
    }

    public enum Reason: String, Codable, Sendable {
        case ungatedBuild, markerBeforeE3, priorDataAtFirstMarker, originalAppVersionBeforeE3
    }

    public enum Decision: Equatable, Sendable {
        case alreadyGranted
        case grant(Reason)        // open; persist the grant now
        case needsAppTransaction  // open while pending (§5.6)
        case sessionGrace         // open for this process only; never persisted
        case notGrandfathered(writeLatch: Bool)   // closed unless purchased
    }

    /// Everything except AppTransaction. Never touches the network.
    public static func offlineDecision(gateEnabled: Bool, protectedDataAvailable: Bool,
                                       stored: StoredGrant, cohort: Cohort, latch: Latch,
                                       platform: Platform, threshold: Threshold) -> Decision

    /// Called only after .needsAppTransaction, with the reading or .unavailable at the timeout.
    public static func decide(cohort: Cohort, reading: AppTransactionReading,
                              threshold: Threshold) -> Decision
}
```

### 5.5 The truth table

"T" = this platform's `T_build`. "PD" = `priorDataPresent`. **G** = grant, persisted. **S** = session grace. **N** = not grandfathered (the offer shows). **P** = pending: open until the reading or the timeout (§5.6). "—" = not consulted. Rows are evaluated top to bottom; the first match decides.

| # | condition | AppTransaction | result | rule |
|---|---|---|---|---|
| 0 | the gate is off in this build | — | **G** `ungatedBuild` (open; the write waits if row 0a's condition holds) | §5.2, S1 |
| 0a | iOS, protected data not yet available (a launch before first unlock) | — | **S**, nothing written | §5.7, M3 |
| 1 | a stored grant, either copy | — | open (`alreadyGranted`) | stored; no re-evaluation, ever |
| 2 | marker present, this platform, build < T | — | **G** `markerBeforeE3` | 1 |
| 3 | marker present, this platform, build ≥ T, PD true | — | **G** `priorDataAtFirstMarker` | 2 |
| 4 | marker absent before this launch; the marker this launch wrote has PD true | — | **G** `priorDataAtFirstMarker` | 2 (a legacy install that skipped 1.37 and 1.38; offline) |
| L | marker present, build ≥ T, PD false, latch present and its threshold equals the current one | — | **N**, no AppTransaction read | §5.6 latch |
| 5 | marker present, build ≥ T, PD false (or row 4's marker with PD false), no valid latch | production, below E3 by shape | **G** `originalAppVersionBeforeE3` | 3 (a legacy reinstall, online) |
| 6 | as 5 | production, not below | **N**, write latch | a fresh E3-era install |
| 7 | as 5 | nonProduction | **N**, no latch | sandbox rule |
| 8 | as 5 | unavailable, or no answer by the timeout | **S** | unreadable |
| 9 | as 5 | still pending | **P** | §5.6 |
| 10 | marker unreadable, or another platform's, or no marker step ran | production, below by shape | **G** `originalAppVersionBeforeE3` | 3 |
| 11 | as 10 | production, not below | **N**, no latch | latch only over a readable marker |
| 12 | as 10 | nonProduction | **N** | sandbox rule |
| 13 | as 10 | unavailable, or timeout | **S** | unreadable |
| 14 | as 10 | still pending | **P** | §5.6 |

* **The offline-reinstall row is row 8** (pre-launch marker absent, this launch's marker PD false, AppTransaction throws → S, nothing persisted). Round 0 numbered it 12.
* Rows 0–4 and L never read the network, so a legacy rider on a plane is decided by rows 1–4.
* Row 1 means a grant, once written, decides every later launch with no other input.

**Readings this table makes, labelled:**
* **`unavailable` includes `.unverified`, an unparseable value and the timeout**, not only a throw *(agent's reading, 2026-10-07 delegation)*. §E names only the throw. Each is "no information", and treating it as such keeps a legacy rider on the safe side of the red line.
* **PD on a present marker counts** (row 3). A marker first written at an E3-era launch with PD true means the install had data before any marker existed, which only a pre-marker install can have.
* **Another platform's marker is unreadable** (row 10) *(agent's choice, 2026-10-07 delegation)*; the marker's own `firstSeenBuild(isBefore:on:)` returns nil for it (`InstallCohort.swift:193-196`, marker branch).

### 5.6 While the check is pending, and the timeout

Review finding S2, accepted: a captive-portal network can leave `AppTransaction.shared` neither returning nor throwing, and round 0 said nothing about that time.

* **Pending is open.** From `needsAppTransaction` until a reading or the timeout, `depthIsOpen` is true, as for grace. This is §E's own condition: "the failure must be 'assume entitled' when the transaction cannot be read, never 'assume not entitled'" (`PLAN-V2-PRODUCT.md:393-397`).
* **The timeout is 5 seconds** from the start of the read *(agent's choice, 2026-10-07 delegation; not measured, a parameter pinned by a test)*. No reading by then → **S** for the rest of the process.
* **After the timeout a late reading may only upgrade.** A late "production, below" → **G**, persisted. A late "not below" or "nonProduction" does not close a session already in grace; it writes the latch for next launch (row 6 only).
* **Before the timeout, only rows 6, 7, 11 and 12 close**, and only at a moment no run is in progress. A run started while pending finishes on the store it was built with; the close takes effect when the rider is back on the menu.
* **Widget and reminders** are refreshed again once the decision settles, after the launch's synchronous refresh (`AppModel.swift:717-718`). The widget may show open counts for up to five seconds, which is the safe direction.
* **A fresh install's first launch shows onboarding** (`AppModel.swift:698-704`), so its pending window normally passes on a screen with no level content.

**The latch** *(agent's choice, 2026-10-07 delegation; round 0 Q4's default changed from "no" to "yes")*. After a verified production reading "not below" (row 6), a local key records the threshold it was judged against, and later launches decide by row L without reading `AppTransaction`. Why it is safe:
* `originalAppVersion` "remains constant" across upgrades (Apple, §5.1), so the reading cannot become "below" later for this account.
* It is written only over a **present, readable** marker with build ≥ T and PD false, an install that rows 2–4 already showed is new. Never after rows 10–14.
* It is ignored as soon as the threshold rises (row L requires equality), so a raised threshold re-runs rule 3.
* It never blocks a grant: rows 0–4 come before it.

Without the latch, every sampler launch would pass through pending, so the depth would be open for up to five seconds at every launch, and open for whole sessions whenever offline (round 0's §5.7 hole). With it, a sampler that was online once has no pending window and no offline grace. The owner can still choose §E's exact behaviour instead (Q4).

### 5.7 What is persisted, where, and why a grant is never revoked

| what | where | written by | content | synced? |
|---|---|---|---|---|
| install-cohort marker `NihongoRide.installCohort.v1` | settings `UserDefaults` | P0-12, once, if absent (`InstallCohort.swift:278-289`, marker branch) | first-seen version, build, platform, PD | never |
| grant, copy 1: a new key, proposed `NihongoRide.depthGrant.v1` | settings `UserDefaults` | E3, on any `grant(_)`, if absent | the `Reason`, the version and build that wrote it, the thresholds | never |
| grant, copy 2: a small file beside the other stores, proposed `depth-grant.json` | Application Support, through `supportFileURL` (`AppModel.swift:530-532`) | the same write, if absent | the same | never |
| latch, proposed `NihongoRide.depthVerifiedNew.v1` | settings `UserDefaults` | row 6 only | the threshold it was judged against | never |
| the depth purchase's `EntitlementRecord`, its own key and quarantine key (P1-5) | settings `UserDefaults` | the depth store | as the road's record (`Entitlement.swift:79-127`) | never |
| pending, session grace | memory | — | — | — |

* **Presence of either grant copy is the grant** *(agent's choice, 2026-10-07 delegation)*. Only a grant writes either copy, so any bytes there, readable or not, mean a grant happened.
* **The grant key is its own quarantine** (review finding M5, accepted). It is never overwritten, so unreadable bytes stay as they are and no copy is made. P0-12 uses the same rule for the marker. Round 0 pointed at `EntitlementLedger`'s quarantine helper, whose `quarantineKey` ignores its `key` parameter (`Entitlement.swift:222`) and would have written into the road's quarantine key.
* **Two copies** (review finding M3, partial). If an OS event drops the defaults plist, the file still holds the grant, and the reverse. Both live in the app container, so deleting the app on iOS removes both, and rule 3 is then the only way back (§5.10).
* **Never revoked, in code, four ways.** (1) No type has a "revoked" or "false" value to write. (2) No code path removes either copy; a source scan pins that (§9). (3) Row 1 comes before every input that could change (rows 0 and 0a are above it, and both can only open). (4) The thresholds may only rise (§5.2).
* **What a grant covers** (review finding N5, accepted): everything the N3–N1 pools contained when the grant was written, and every later addition to those pools. If a later pack (E4) is ever carved out of today's N1 words, those words stay open for every grant.
* **Never synced, never sent.** None of these is a CloudKit record type (`CloudKitSyncController.swift:63`). `PrivacyClaimTests` stay green; Data Not Collected stays true. The privacy page's on-device storage list (`site/privacy.html:34-35`, which P0-6 extends for the marker) gains one sentence for the grant, the latch and the second purchase record, for the owner to push.

### 5.8 The order rule, and what it actually protects

The check reads P0-12's **pre-launch observation**, never the defaults after this launch's write. The one exception is reading PD from this launch's own write, when the pre-launch observation is `.absent` (§5.9).

**PLAN-V1.37 §E's stated reason does not hold under its own definitions.** It says that reading the fresh marker would make an offline legacy reinstall "fail rules 1–3, and get neither a grant nor grace". But a fresh marker has build ≥ T and PD false, so rules 1–2 do not grant, and with `AppTransaction` throwing, §E's own unreadable rule gives grace. That is row 8 either way. **No row changes with the order**, given that the marker stores PD.

The rule is still kept, because it protects against a likely bug: a decision that reads "present marker, build ≥ T" as a final verdict and skips `AppTransaction`. The latch makes that bug easier to write, because row L is exactly such a verdict; the mutation in §9 targets it.

**A fresh marker over unreadable bytes** would not hurt a legacy rider (review finding N1, accepted: round 0 overstated this). A legacy rider has a settings blob, so the fresh marker's PD would be true, and that is row 3, **G**. P0-12 still leaves unreadable bytes alone, which is right for its own reasons.

### 5.9 What E3 reads from the v1.37 marker, as built

The marker is on `feat/v137-install-cohort` @ 56a2ebc in `v137-marker`. Read today:
* `InstallCohort.Observation` is `.absent` / `.present(Marker)` / `.unreadable`, and **`.absent` carries no PD** (`Sources/SettingsKit/InstallCohort.swift:225-254`).
* `recordLaunch` decides, writes the marker if the key was absent, and returns the **pre-launch** observation (`:308-316`). The marker it writes carries the PD computed this launch (`:278-289`).
* `AppModel` calls it once in `init`, before the settings save, with PD = "settings blob present or odometer not missing", and keeps only the observation, as `installCohortAtLaunch` (`AppModel.swift:420-428, 625-636` on the marker branch). The PD value is not kept. It is `nil` on a launch that touches nothing of the user's.

**What E3 reads, exactly:**
1. `installCohortAtLaunch`.
2. `.present(m)` → `Cohort.present(firstSeenBuild: m.firstSeenBuild, platform: m.platform, priorDataPresent: m.priorDataPresent)`. Another platform's marker → `.unreadable`.
3. **`.absent`** → E3 reads the key once more, through the marker's own `InstallCohort.observe(InstallCohort.Stored.read(from:))` (`:215-264`). It accepts the result only if it is `.present(m)` with `m.firstSeenBuild` equal to the running build and `m.platform` equal to the running platform, which proves it is the marker this launch just wrote. Its PD is the PD computed before this launch wrote anything, so row 4 works on the first E3 launch, offline. If the result is anything else (the write did not happen, for example `Running` failed to parse), PD is treated as false and the decision falls to rows 5–9. That costs nothing offline (S), and an online legacy rider still gets G from rule 3.
4. `.unreadable` → `Cohort.unreadable`.
5. **`nil`** (the isolation case, review finding N4, accepted) → `Cohort.unreadable`. Nothing is persisted, because in that case the stores are handed no defaults (`AppModel.swift:605-606`).
6. E3's decision runs in `init` after the marker step, so the order is fixed by one line of control flow. A source-scan test pins it.

**No change to the v1.37 marker is needed.** Review finding M2 is accepted as an interface gap and closed on E3's side, by step 3. A one-line change that kept PD beside the observation would be cleaner, but it is not required, and it would have to land before v1.37 ships, in a release already reviewed. So it is not proposed.

### 5.10 Costs this rule accepts, said plainly

* **A legacy account's first install on its second platform.** The app is one ASC record with macOS and iOS versions (ASC GET 2026-10-27, `/v1/apps/6777469778/appStoreVersions`: `MAC_OS` and `IOS`, both 1.36 `READY_FOR_SALE`) and one bundle id (`project.yml:133, 272`). Whether that first install reads a pre-E3 `originalAppVersion` is unmeasured and cannot be tested in the sandbox ("1.0"). If it does, §5.3's shape rule grants it. If it does not, the device is a sampler. That install never had anything, so this is not a loss; the synced content is kept and shown (§4.4). Round 0's sentence "either answer keeps the red line" was too broad: it did not cover a **reinstall** on the second platform, which §5.3 now handles.
* **Reinstalling under a different Apple Account** (review finding M4, accepted). After a delete, the grant copies are gone (iOS) and rule 3 reads the new account's value. If that account first got the app after E3, the result is **N**. This is a new acquisition by a different account, and it is accepted as such.
* **A fresh install that is never online** gets grace on every launch (rows 8, 13). It cannot buy anyway: a purchase needs the network. The latch (§5.6) closes this for any install that was online once.
* **The 5-second timeout is a guess.** Too short gives grace to slow networks (safe); too long holds the depth open longer at launch (also safe).
* **Launches before first unlock** (row 0a) are handled by not writing, which rests on `isProtectedDataAvailable` (iOS) reporting the state truthfully. This is not measured on this app.

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

An existing install is one that the rule grants: rows 0, 2, 3, 4, 5 and 10 of §5.5 (review finding N2: round 0's list missed the other-platform case, now row 10). From then on `depthIsOpen` is true on every launch, from the grant alone (row 1), offline or online. Until a grant is written, rows 8–9 and 13–14 keep it open for the session.

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
| After a downgrade, an upgrade, a restore, a refund of anything, a sign-out | The grant decides (row 1). Nothing reads anything else. |
| A hotfix, a rollback or a kill switch that turns the gate off, then a release that turns it back on | Every launch with the gate off wrote a grant (row 0). A pre-E3-branch hotfix is covered by the threshold, which the release script forces above it (§5.2). |

**The verification that matters most:** for a grandfathered install, every pool count and every run builder must return exactly what v1.38 returns. §9 pins that with a golden fixture produced from v1.38's own code, the method `PurchasePromiseTests` uses for the road (`Tests/SceneryKitTests/RideRouteFreezeTests.swift:1-20, 309`).

---

## 9. Tests to write, and the verification it needs

### 9.1 Pure table tests (`DepthGrandfather`)

* **Every row of §5.5**, one test each, including row 8 by name ("offline reinstall, no prior data, no pre-launch marker, AppTransaction throws → session grace, nothing persisted").
* **Rule 3 by shape** (§5.3): "40" on macOS is a build and below a threshold of 65 → G; "1.39" on iOS is a version and not below `T_version` 1.39 → N; "1.20" on iOS → G; "" and "1.x" → unavailable.
* **Pending and timeout** (§5.6): pending is open; no answer at 5 s → S; a late "below" after the timeout → G; a late "not below" after the timeout leaves this session open and writes the latch; a close before the timeout waits for a run to end.
* **The latch**: honoured only at an equal threshold; ignored after a rise; never written over an unreadable marker.
* **The marker read** (§5.9): pre-launch `.absent` plus this launch's marker with PD true → row 4 G; `.absent` with no readable write → rows 5–9; `nil` → unreadable, nothing persisted.
* **Version parsing**: "1.4" < "1.36" < "1.40"; "1.9" < "1.10"; "1.36" == "1.36.0"; "1.4.1" between "1.4" and "1.5"; iOS "9" < "62"; "1.0" (sandbox-shaped) parses; "" and "abc" → unavailable.
* **Per platform**: a macOS marker at build 61 against an iOS threshold is never compared (row 10).
* **Decision → persistence**: `grant` writes the key once; `alreadyGranted` writes nothing; `sessionGrace` and `notGrandfathered` write nothing.
* **Unreadable grant bytes** are honoured and never overwritten; no copy is made (§5.7). Either grant copy alone is a grant.

### 9.2 Mutations that must go red (revert each, paste the red line, PLAN-V1.37 §J V8)

| mutation | must turn red |
|---|---|
| Persist the grace (write a grant on `sessionGrace`) | rows 8, 13: "nothing persisted" |
| Compare versions as strings | "1.4" vs "1.36" (string order puts "1.4" above), iOS "9" vs "62" |
| Accept sandbox for rule 3 (treat `nonProduction` "1.0" as below E3) | rows 7, 12 |
| Revoke a grant (any path that removes or overwrites either copy, or decides from anything but row 1 when a grant is stored) | row 1, and the source scan |
| Read the marker after this launch's write, combined with treating "present, build ≥ T" as final | row 8 |
| Treat `unavailable` or the timeout as `notGrandfathered` | rows 8, 13 |
| Drop the PD check on a present marker | row 3 |
| Drop the row-4 read of this launch's own marker | row 4 |
| **Threshold set at the first upload instead of above every ungated release** (B1) | "an ungated release after the first gated upload, installed fresh, then the gated build → G" |
| Lower a threshold literal | the literal pin, and the release-script check's fixture |
| **Drop the ungated grant writer** (S1) | "gate off → grant written", and "gate off, then on → still open" |
| **Treat pending as closed** (S2) | "pending → open", and the hanging-reading fixture: no answer for 30 s → open throughout, S at 5 s |
| Close mid-run | "a close before the timeout waits for the run to end" |
| **Read rule 3 by the running platform** (S3) | "40" on macOS → must be G |
| Honour a latch after the threshold rose | row L with a raised threshold must re-read |
| **Filter the free tier by `jlpt`** (S4) | a fixture corpus that moves one free id to N3 → the id must stay rideable |
| Remove an id from `DepthFreeSet` | the frozen-copy comparison |
| **Compute the unplayable hint or `.removed` from the rideable store** (S5) | a sampler list of N3 ids shows neither "aren't available" nor "you can remove it" |
| Write anything at a launch before first unlock | row 0a |

### 9.2.1 The release-script check

* A table test of the check's pure core, fed recorded ASC responses: a gated submit with `T_build` at or below an ungated release → stop; an ungated submit above `T_build` without the writer → stop; a threshold below the previous gated release's → stop; the clean case → proceed.
* A dry run against ASC (GET only) before the first gated submit, its output in the release record.

### 9.3 App-layer tests

* **Golden grandfathered sweep.** A fixture produced by **compiling v1.38's own code**: for each mode × level × "All", the pool size and the id set each builder can draw, plus every count in §2.1, for a fixed fixture review store and lists. E3 with `depthIsOpen = true` must reproduce it byte for byte. This is the red-line test; the shape is `PurchasePromiseTests`' v1.29 sweep.
* **Sampler sweep.** The same table with `depthIsOpen = false`: every id drawn is N5 or N4; every count equals the run it promises (the house "count and run from one predicate" rule).
* **Store split, by source scan** (the `CallSiteScanner` in `Tests/NihongoRideAppTests/CallSiteScanner.swift`): every `GameSession.make*` and `ConjugationSession.make*` call in `NihongoRideApp` passes `vocab:` explicitly (the defaults are `.shared`, the full store, e.g. `GameSession.swift:419`); `catalog` never reaches a builder or a `resolves:` argument; the grant key appears in one write and no remove.
* **Locked level**: start with a locked level selected builds nothing and sets no empty-pool notice (§4.5, `MenuView.swift:477-482`).
* **Free set golden**: `DepthFreeSet.ids` equals the first gated release's frozen copy plus additions; every id in it resolves in the catalog.
* **Order in `init`**: the E3 decision runs after the marker step (source scan, §5.9).
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
| Q1 | **The boundary (C-2(d)):** candidate 1 (N5+N4 free) or candidate 2 (N5 free)? **One-time:** after the first gated release the free set may only grow (§2.2). | Candidate 1. |
| Q2 | **The product's name** in en/zh (ja with E5), and its product id, which Apple never lets be edited (`RouteStore.swift:66-69`). Draft: "N3–N1 Levels" / "N3–N1 等级"; an id naming the boundary, like the road's names its capability set (`RouteStore.swift:52-57`). | The draft name; the id chosen at the E3 release to name the chosen boundary, recorded in the release record. |
| Q3 | **A legacy account's second device.** Rule 3 may or may not grant it (§5.10). Should a pre-E3 ride record arriving by sync also grant? It needs no new record type (ride records carry a date, `JournalKit/RideRecord.swift`), but a device clock can be set back, and it is a fourth rule §E does not have. | No. §E's three rules only; the synced content is kept and shown. |
| Q4 | **The latch** (§5.6). It records a verified production "not below" reading, so a sampler that was online once has no pending window and no offline grace. It never blocks a grant and is dropped when the threshold rises, but it is not in §E. | **Changed in round 1: latch on** *(agent's choice, 2026-10-07 delegation)*, because pending is now open (S2) and without the latch every sampler launch would open the depth for up to five seconds. The owner can say "§E exactly" to remove it. |
| Q6 | **The ungated grant writer in v1.38** (§5.2). It would make every v1.38-or-later launch a grant before E3 exists, covering a hotfix built from a pre-E3 branch. It is E3 code shipping before the owner's box, so it needs the owner's word. | Not in v1.38. The writer ships with E3 (v1.39), and the release-script check covers pre-E3-branch hotfixes. |
| Q5 | **Search for samplers**: keep all levels searchable and addable (as shipped since v1.35), or show only open levels? | All levels, tagged. |

---

## 11. Where PLAN-V1.37 and the code disagree, and what this document could not verify

**PLAN-V1.37 against the code or its own definitions:**
1. **§E's reason for the order rule** does not hold: under §E's own "unreadable" rule the offline reinstall gets grace whichever marker is read (§5.8). The rule is kept as defence in depth.
2. **P0-13's "kana … in every mode"**: no kana mode exists (`GameSession.swift:16-22`). Kana practice is the passages and the coach drills, both free (§1).
3. **P0-13's "everything that already ships free"** includes the N3–N1 pools if read literally. Read here as every feature and mechanic (§1).
4. **P1-5's scope misses three things** a second SKU needs: routing `Transaction.updates` (`RouteStore.swift:395-404`), the product request (`:169`), and the DEBUG seam (`:122-142`) (§6.2).
5. **§E's "a clean denominator"** ("Purchases come only from new installs"): a grandfathered account's first install on its other platform is not grandfathered by rules 1–2 and can buy. Whether App Store reports count it as a first-time download under universal purchase is unverified, so the denominator may not be exactly "new installs".
6. **§E rule 1 and the marker**: a marker for another platform (row 10) and an unverified `AppTransaction` (§5.5) are not covered by §E's text. This design treats both as unreadable, labelled.
7. **§E says rule 3 compares "`CFBundleShortVersionString` on macOS, `CFBundleVersion` on iOS".** On a universal purchase that is unsafe if Apple reports the first platform's value; §5.3 reads the value by shape instead.
8. **§E's "before E3's build" is ambiguous**, and the natural reading (the first E3 build) un-grandfathers installs of any ungated build released after it (§5.2, review finding B1).
9. **§E's "a constant flip"** (Sequence) implies a gate that can be flipped back. Flipping it back off and on again would un-grandfather installs made in between, unless the gate-off build writes the grant (§5.2, review finding S1).
10. **The v1.37 marker drops PD on `.absent`** (`InstallCohort.swift:227`, `AppModel.swift:625-636` on `v137-marker` @ 56a2ebc). E3 reads PD from this launch's own write instead (§5.9). No v1.37 change is needed.

**Not verified today:**
* `originalAppVersion` on a universal purchase's second platform (§5.10). §5.3 makes either answer safe.
* How long `AppTransaction.shared` can hang, and whether 5 s is the right timeout (§5.6).
* Whether an iOS launch before first unlock happens for this app, and what `UserDefaults` does then (§5.10).
* Whether App Review runs in the sandbox environment (§7.4).
* Whether a freshly downloaded build's `AppTransaction` is readable offline on its first launch. PLAN-STAGE1's measurement (`PLAN-STAGE1.md:281-284`) was of an update; the table gives grace either way.
* Either IAP submission path for a second IAP (PLAN-V1.37 §A).

**State read today:** one IAP exists, `com.jasonye.nihongoride.scenery.lifetime`, `NON_CONSUMABLE`, `APPROVED`, `familySharable` false (ASC GET 2026-10-27, `/v1/apps/6777469778/inAppPurchasesV2`). No depth IAP exists, and none is created by this document.

---

## 12. Review round 1

An independent red-line review of round 0 (`31b9487`) is at `~/Library/Caches/NihongoRide-v137-work/review-e3-design.md` (outside the repo). It found 1 BLOCKER, 5 SERIOUS, 5 MINOR and 5 NIT. Each was checked against the code before a decision.

| # | sev | finding | checked against | decision | where it changed |
|---|---|---|---|---|---|
| B1 | BLOCKER | A threshold at "the first E3 build of any channel" un-grandfathers fresh installs of any ungated build released after that upload. | Builds come from one counter bumped by one (`check_versions.py:78`); every released build is one integer, max 61 / 62 (ASC GET 2026-10-27). The scenario holds. | **ACCEPT** | §5.2: a threshold above every build released without the gate, rising only; the release-script check before every submit; §9.2 and §9.2.1. |
| S1 | SERIOUS | A rollback or kill switch after E3 un-grandfathers installs made while the gate was off. | §E's "a constant flip" implies the gate can be flipped back; round 0's table could not see a gate-off build. Holds. | **ACCEPT** | §5.2: every gate-off build writes the grant (`ungatedBuild`, row 0). It ships with E3 (v1.39). Shipping it in v1.38 needs the owner (Q6, default no); the release-script check covers pre-E3-branch hotfixes. |
| S2 | SERIOUS | A hanging `AppTransaction` has no timeout and no defined pending state. | Round 0 defined only throw → grace; the launch refreshes the widget and reminders before any async read (`AppModel.swift:717-718`). Holds. | **ACCEPT** | §5.6: pending is open; 5 s timeout → S; a late reading only upgrades; a close waits for a run to end; refresh after settling. The latch (Q4 default changed) keeps samplers out of pending. |
| S3 | SERIOUS | Rule 3 read by the running platform can give N to a reinstall on the second platform. | Every released build is one component and every version two or three (ASC GET; git history of `project.yml`; marker refuses non-digit builds, `InstallCohort.swift:134-138`). Holds. | **ACCEPT** | §5.3: rule 3 by shape; two pins keep the shapes disjoint; §5.10 drops "either answer keeps the red line". |
| S4 | SERIOUS | A free tier defined by `jlpt` loses words to corpus edits or a boundary change. | The corpus is corrected most releases (PLAN-V1.37 P0-2); round 0's `freeLevels` was "one line". Holds once samplers exist. | **ACCEPT** | §2.2: `DepthFreeSet.ids`, frozen by id at the first gated release, grow-only; §1 and Q1: C-2(d) is one-time. Corpus-wide withdrawals stay the corpus's rule. |
| S5 | SERIOUS | On a sampler, existing copy ("aren't available on this device", "you can remove it") invites removals that sync to the grandfathered device. | `ListsView.swift:390-391, 844-849, 1243-1245`; tombstones `WordListStore.swift:183-191`; merge `AppModel.swift:1424-1430`. Holds. | **ACCEPT** | §3 row 14: the true line replaces the hint; §2.3: `.removed` and the hint are computed from the catalog; §9.2 mutation. |
| M1 | MINOR | §2.3 misses `CoachView.swift:171` and the coach drill entries. | Both read `model.vocab` / `vocab`. Holds. | **ACCEPT** | §2.3 rows; the scan covers every reader. |
| M2 | MINOR | P0-12 as built has no PD on `.absent`. | `InstallCohort.swift:227`; `AppModel.swift:625-636` keeps only the observation (marker branch @ 56a2ebc). Holds. | **ACCEPT, closed on E3's side** | §5.9: on `.absent`, E3 reads PD from this launch's own marker, accepted only if it matches the running build and platform. No v1.37 change. |
| M3 | MINOR | An iOS launch before first unlock may read empty defaults. | Not measured; the OS behaviour cannot be checked from the repo. | **PARTIAL** | Row 0a (no writes, grace) and a second grant copy in Application Support (§5.7). Recorded as unverified (§5.10, §11). |
| M4 | MINOR | Reinstall under a different Apple Account → N. | Rule 3 reads the account's value. Holds. | **ACCEPT** as an accepted cost | §5.10. |
| M5 | MINOR | The house quarantine helper would write into the road's quarantine key. | `Entitlement.swift:222` ignores `key`. Holds. | **ACCEPT** | §5.7: the grant key is its own quarantine; no copy. |
| N1 | NIT | A fresh marker over unreadable bytes would give a legacy rider row 3 (G), not rows 6–8. | PD is true when a settings blob exists (`AppModel.swift:625-636`, marker branch). Holds. | **ACCEPT** | §5.8. |
| N2 | NIT | §8's grant rows missed the other-platform case. | Holds. | **ACCEPT** | §8. |
| N3 | NIT | "A restore of a refunded purchase" restores nothing. | Holds. | **ACCEPT** | §4.5. |
| N4 | NIT | `installCohortAtLaunch == nil` was unspecified. | `nil` on isolation launches (marker branch `AppModel.swift:420-424`). Holds. | **ACCEPT** | §5.9 item 5: unreadable, nothing persisted. |
| N5 | NIT | Name the grant's scope so a later pack carved from N1 stays covered. | — | **ACCEPT** | §5.7. |

**One point where this design goes further than the review, and one where it differs:**
* **Further:** the latch (§5.6). The review's pending fix alone would open the depth for up to five seconds at every sampler launch. The latch is a persisted *negative* from a *readable* production value, which §E does not forbid; it is labelled and the owner can remove it (Q4).
* **Differs:** the review says TestFlight sampler testing must go through the DEBUG seam. TestFlight builds are Release builds, and the seam is `#if DEBUG` (`RouteStore.swift:122-142`), so it is not available there. It is also not needed: a gated build's number is above every earlier ungated release, so a fresh TestFlight install of it is a sampler under §5.2's threshold.

