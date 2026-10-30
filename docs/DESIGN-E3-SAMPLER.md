# DESIGN-E3-SAMPLER: a complete free sampler, one one-time depth unlock, every existing install kept whole

*Design document, 2026-10-27 (JST). PLAN-V1.37 §C item P0-13. Written on branch `docs/v137-e3-design` from repo HEAD `9c09ab7`; revised the same day after independent red-line reviews (rounds 1 and 2, §12), and again on 2026-10-30 on branch `docs/e3-r3` from `main` @ a34769c (round 3, §12). Design only: no code, no IAP, no App Store Connect write. Every claim cites a file:line, an ASC GET with its date, or a URL read on the date given.*

*Where citations point (round-3 finding r3-N5).* Code outside the marker is cited at `main` (9c09ab7 then, a34769c now; the cited lines are the same). **The v1.37 marker exists only on `release/v1.37`**, merged at **25a472e**; `main` does not have it yet. Marker citations are by symbol name, with the line at 25a472e and the tag **[25a472e]**. Round 1 and 2 cited `v137-marker` @ 56a2ebc / 8b06f79; those line numbers have moved, and every behaviour they described holds at 25a472e.

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

Counts are read 2026-10-30 from the corpus v1.37 ships, at **[25a472e]** (`Sources/VocabKit/Resources/n5.json … n1.json`, `passages.json`, `dictation-exclusions.json`). "Sentences" = entries with both `exJP` and `exKana` (`VocabEntry.isTypeableSentence`, `Sources/VocabKit/VocabEntry.swift:62-66`). "Dictation" = typeable sentences minus the 796 excluded ids (`DictationSafety`). "Verbs" = entries with a `vc` class (`ConjugationSession.swift:18`, `:434-436`).

The dictation column is round 3's refresh (r3-N5). P0-2 withheld seven sentences from dictation, so the pool fell from 5,935 to 5,928 (PLAN-V1.37 dated corrections, `docs/PLAN-V1.37.md:622-623`). One was in N4 and six in N2 and N1. `main` @ a34769c still has the earlier corpus: 789 exclusions and 5,935. Words, sentences and verbs did not change.

| level | words | sentences | dictation sentences | verbs |
|---|---|---|---|---|
| N5 | 646 | 616 | 518 | 95 |
| N4 | 642 | 627 | 554 | 211 |
| N3 | 1,450 | 1,411 | 1,228 | 427 |
| N2 | 1,747 | 1,695 | 1,509 | 588 |
| N1 | 2,586 | 2,375 | 2,119 | 996 |
| **total** | **7,071** | **6,724** | **5,928** | **2,317** |

Practice passages are **not** JLPT-tagged. They carry `easy` / `med` / `hard` (`Sources/VocabKit/Passage.swift:24`): 51 / 75 / 107, 233 in all. They stay free under both candidates.

| | **Candidate 1 (default)** | **Candidate 2 (the owner's alternative at C-2(d))** |
|---|---|---|
| Free levels | N5, N4 | N5 |
| Free words · sentences · dictation · verbs | 1,288 · 1,243 · 1,072 · 306 | 646 · 616 · 518 · 95 |
| Paid levels | N3, N2, N1 | N4, N3, N2, N1 |
| Paid words · sentences · dictation · verbs | 5,783 · 5,481 · 4,856 · 2,011 | 6,425 · 6,108 · 5,410 · 2,222 |
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
  * **It may grow and never shrink.** A later corpus edit that moves an id from N4 to N3 leaves the id free.
  * **Every id whose `jlpt` is a free level is in it** (round-2 finding MINOR-6): a new N5 or N4 entry, **and an existing entry moved down into N5 or N4**, is added in the same commit. Otherwise "N4 stays free" would be false for that word. One test asserts both directions: every free-level id is in the set, and every id ever in the set still is.
  * **The comparison copy cannot be edited in the same commit** (round-2 finding NIT-3). The test reads the first gated release's list with `git show <first-gated-tag>:<path>`, and the release record carries its hash, so one commit cannot change the list and its reference together.
  * **Why not `jlpt`.** The corpus is corrected most releases (v1.37's own P0-2 re-reads sentences). Defined by the `jlpt` field, the free tier would shrink every time a correction moved a word up a level, and every sampler would lose that word and its SRS card. Sampler installs are existing installs once E3 ships.
  * **What it does not override:** if the corpus withdraws an entry for every install (an existing practice for bad entries, `VocabStore.swift:172-180`), it is withdrawn for samplers too. That is the corpus's rule, applied to every install alike, and not the gate's.
    * **A withdrawn id stays in `DepthFreeSet`** (round-3 finding r3-N2). The commit that removes the entry from the corpus also appends its id to a recorded list of withdrawals, `DepthFreeSet.withdrawn`. That list is grow-only too. The repo has no such list today: withdrawals are handled at read time by `resolvesID` (`Sources/VocabKit/VocabStore.swift:172-185`). So the golden test says "every id resolves in the catalog **or** is a recorded withdrawal" (§9.3). Without that, the first withdrawal would turn the test red, and the obvious repair, removing the id from the set, would break "never shrinks".
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
1. **The P0-12 marker exists** with a first-seen build from before E3's build on that platform, compared as integers, per platform. For scale: the highest released builds are macOS 61 and iOS 62 (ASC GET 2026-10-30, below). v1.37's own builds are macOS 62 and iOS 63 (`project.yml:136, 275` **[25a472e]**). `main` still reads 61 / 62, because the bump lives on the release branch.
2. **The marker is written at E3's first launch with `priorDataPresent`**: the install predates E3.
3. **A verified `AppTransaction` in the production environment** has `originalAppVersion` below E3's, parsed as integers. Apple, read today: the value is "the original value of the `CFBundleShortVersionString` for apps running in macOS, and the original value of the `CFBundleVersion` for apps running on all other platforms"; it "remains constant and doesn't change when the customer upgrades the app"; and "In the sandbox testing environment, the `originalAppVersion` value is always `1.0`" (https://developer.apple.com/documentation/storekit/apptransaction/originalappversion, read via its documentation JSON 2026-10-27).

And:
* **Sandbox** (App Review, TestFlight): rule 3 is ignored; only rules 1–2 apply. A reviewer's fresh install sees the offer. **A reused review device does not**: rules 1–2 still grant it. §7.4 has the plan for that (round-3 finding r3-M4).
* **Unreadable**: `AppTransaction` throws and rules 1–2 do not grant → **session-only grace**: the depth is open for this process, nothing is persisted, and the check runs again next launch.
* **Order**: the check reads the marker **as it stood before this launch's write**.
* The offline-reinstall row: no prior data, no pre-launch marker, `AppTransaction` throws → session grace, nothing persisted.

Why `AppTransaction` cannot be the first line: it "throws an error if the `AppTransaction` isn't available or if the user isn't authenticated with the App Store. Getting an `AppTransaction` may require network connectivity" (https://developer.apple.com/documentation/storekit/apptransaction/shared, read 2026-10-27). PLAN-STAGE1 measured it throwing `networkError(-1009)` offline, with its cache scoped per app version (`docs/PLAN-STAGE1.md:281-284`). So an install that auto-updated to E3 overnight and opens on a plane would throw. Rules 1–2 exist so that this rider never needs the network.

This design keeps all of that and adds five protections found in review round 1 (§12): a threshold defined by what customers received (§5.2), a grant written by every build with the gate off (§5.2), rule 3 read by the value's shape (§5.3), a defined pending state with a timeout (§5.6), and a free set frozen by id (§2.2).

### 5.2 The threshold: above every build ever uploaded without the gate

**Definition** *(agent's choice, 2026-10-07 delegation, replacing round 0's "first E3 build of any channel", which review finding B1 showed un-grandfathers people)*:
* `T_build[p]`, per platform: **one more than the highest `CFBundleVersion` of any build without the gate ever uploaded to App Store Connect on platform p**, released or not. Round 1 said "released to App Store customers"; round-2 finding MINOR-1 showed that an ungated TestFlight upload above every release would leave its testers' markers at or above `T`, and sandbox ignores rule 3, so they would get **N**. Counting uploads only grandfathers more TestFlight installs.
* `T_version`: the marketing version of the gated release. It must be **strictly above every marketing version ever released without the gate, on either platform.**
* Both are compiled into the gated binary before its first upload, from an ASC read made then. Both are re-checked before submit (below).
* **They may rise and never fall.** Raising grants more; lowering would un-grandfather any install whose grant was not yet written.

**Why "released to customers", not "first upload".** Builds come from one counter per target, bumped by one each release (`scripts/check_versions.py:78`; history 1…63 through v1.37's iOS build at 25a472e, all single integers). Say a gated build 66 is uploaded, and then a 1.38.1 hotfix (67) or a v1.39 without E3 reaches customers. Under round 0's definition a fresh install of 67 would fail rule 1 (67 ≥ 66), rule 2 (no prior data) and, on iOS, rule 3 ("67" ≥ 66): permanent **N** for someone who installed when every level was free. Under this definition the gated build must be rebuilt with `T_build` above 67 before it can be submitted.

**Today's values, for scale** (ASC GET 2026-10-30, `/v1/apps/6777469778/appStoreVersions?include=build&limit=200`; unchanged since the 2026-10-27 read): 76 released versions; macOS 37, highest build 61; iOS 39, highest build 62; every build one integer; every version two or three components. No 1.37 version record exists yet. Uploaded builds (ASC GET 2026-10-30, `/v1/builds?filter[app]=6777469778&include=preReleaseVersion&limit=200`): 46 listed per platform, highest 61 (macOS) and 62 (iOS), all digits. So no 1.37 build has been uploaded yet, and no unreleased upload sits above a release. ASC lists fewer builds than were ever made (46 against 63 in git), so the script also takes the highest build number in the repo's git history of `project.yml` and uses the larger of the two. v1.37 and v1.38 ship ungated first, so the real thresholds are fixed only at the gated upload.

**TestFlight.** A gated build is uploaded after every ungated upload before it, so its number is at or above `T_build`, and a fresh TestFlight install of it is a sampler, which is what testing needs. If an ungated upload later overtakes it, its TestFlight installs become grandfathered: generous and harmless. No low threshold is needed for testing.

**The release-script check, before every `--submit`** (ASC GET only, the read `asc_release.py` already makes per build at `find_build`, `scripts/asc_release.py:520-536`, plus the endpoint above):
1. Read every uploaded build per platform (`/v1/builds` with `preReleaseVersion`), every released version with its build (`appStoreVersions?include=build`), and the highest `CURRENT_PROJECT_VERSION` in git history.
2. **Which builds carried the gate is read from the binaries, not from a list the script keeps** (round-2 finding MINOR-7). The gated build's `Info.plist` carries one key emitted from the gate constant (for example `NRDepthGate = 1` with its thresholds). The script reads it out of the `.xcarchive` it uploads and records it with the build number. **A build with no record counts as ungated**, the direction that raises `T`, which covers every pre-E3 build. The registry is evidence of what was read, never an input that can lower anything.
3. **Gated submit:** stop unless all of these hold.
   * `T_build[p]` > every ungated build uploaded on p.
   * `T_version` > every ungated released version.
   * Both are ≥ the previous gated release's values.
   * **Each platform's own gated build ≥ max(`T_build[macOS]`, `T_build[iOS]`)** (round-2 finding MINOR-5). §5.3 compares a one-component value with that maximum, so an iOS gated build numbered below the macOS threshold would read its own fresh installs as "below" and leave the gate dead on iOS. If a counter lags, bump it before upload.
4. **Ungated submit at or above the current `T_build`** (an ungated release after E3 exists): stop unless the build carries the ungated grant writer (next paragraph). The next gated submit then fails step 3 until its thresholds are raised above this build.
5. **Again at release** (round-2 finding NIT-1). Steps 1–3 run again at the manual or phased release of a gated version, because an ungated release on the other platform could land between submit and release. While a gated version is waiting on either platform, the script refuses to release an ungated version on the other.
6. Print the thresholds and the ASC values in the release record.

**A cost the threshold carries** (round-2 finding NIT-2, stated): **any ungated release after E3 has shipped forces the next gated release's threshold above it.** Every sampler installed before that point then sits below `T` and gets a rule-1 grant, whether or not it ever launched the ungated build. That is safe for the red line and costs revenue and Window 2's denominator. So the cheapest way to keep the gate meaningful is never to ship an ungated build once E3 is live; a rollback is better done as a gated build with a fix.

**The ungated grant writer** (review finding S1, accepted). In any build where the gate is off (a rollback, a kill switch, E3 code present but disabled), `depthIsOpen` is true **and the grant is written** with `Reason.ungatedBuild`, on every launch. "Everything free" becomes a grant in its own right, so turning the gate back on later cannot close it.
* **Which release must carry it, and why:** the **first gated release (v1.39)**. Every later build is cut from `main` after E3's merge, so every rollback or kill-switch build inherits it. That covers S1 fully.
* **What it does not cover:** a hotfix built from a branch cut before E3 (a 1.38.x from the v1.38 tag). That hotfix has no E3 code, so it cannot write anything. The release-script check covers it instead, by forcing the next gated build's threshold above it (step 3).
* **Shipping it earlier, in v1.38,** would make every v1.38-or-later launch a grant before E3 exists, closing that hotfix case too. But it is E3 code shipping before the owner's box. **So it is a design note only, and needs the owner** (Q6). Default on silence: not in v1.38. The release-script check is sufficient without it.

### 5.3 Rule 3 by the value's shape, not the running platform

Round 0 compared `originalAppVersion` with the running platform's meaning: a marketing version on macOS, a build on iOS. On a universal purchase that is wrong if Apple reports the account's **first** platform's value, which is unmeasured (§5.10). Review finding S3: an iPhone-first account reinstalling on a Mac would read "40" as version [40], above [1, 39], and get **N**.

**Evidence that the shapes are disjoint:**
* Every `CFBundleVersion` this app ever released is one integer: 37 macOS and 39 iOS releases, all one component (ASC GET above). In git, `CURRENT_PROJECT_VERSION` was always a quoted integer, 1…63 (`git log -p 25a472e -- project.yml`, read 2026-10-30). The marker refuses any build that is not all digits (`InstallCohort.Running.init?(marketingVersion:build:platform:)`, `Sources/SettingsKit/InstallCohort.swift:141-146` **[25a472e]**).
* Every marketing version has two or three components: "1.0" … "1.36", plus "1.4.1" and "1.8.1" (git history of `MARKETING_VERSION`; ASC: 72 two-component and 4 three-component versions).

**The rule** *(agent's choice, 2026-10-07 delegation)*:
* **One component** → it is a build. Below E3 if it is below **max**(`T_build[macOS]`, `T_build[iOS]`), whatever platform is running.
* **Two or more components** → it is a marketing version. Below E3 if it is below `T_version`.
* Anything else (empty, non-numeric) → `unavailable`.
* Two pins keep the shapes disjoint: a test over `project.yml` that every build is one integer and every marketing version has at least two components, and the same assertion in `check_versions.py`'s bump (`:65-90`).

**`originalPlatform`, where the OS has it** (round-3 finding r3-M3, accepted with one refinement) *(agent's choice, 2026-10-07 delegation)*.
* **What Apple says, read 2026-10-30.** `AppTransaction.originalPlatform` is "The platform on which the customer originally purchased the app", of type `AppStore.Platform`, available from iOS 18.4 and macOS 15.4 (https://developer.apple.com/documentation/storekit/apptransaction/originalplatform, read via its documentation JSON). `AppStore.Platform`'s values are `iOS`, `macOS`, `tvOS` and `visionOS` (https://developer.apple.com/documentation/storekit/appstore/platform, same date).
* **What it does not say.** It names where the purchase happened. It does not say which numbering `originalAppVersion` uses on the other platform. Apple's `originalAppVersion` page ties the numbering to the platform the app is **running** on ("for apps running in macOS" … "for apps running on all other platforms", read 2026-10-30). So the review's "the app can know which numbering the value uses" is an inference, not something Apple's page states. What `originalPlatform` gives for certain is a way to **detect** that a reading crosses platforms.
* **The deployment targets are macOS 14.0 and iOS 17.0** (`project.yml:20-22`). Below 18.4 / 15.4 the field does not exist, and the shape rule above decides alone.
* **The rule, when the field is present:**
  * Map it: `macOS` → the value should be a **version**; any other platform → the value should be a **build** (Apple: CFBundleVersion "on all other platforms").
  * **Platform and shape agree** → compare exactly as the shape rule does. Nothing changes.
  * **They disagree, and the value is below by its shape** → **G**, as the shape rule alone would give. *This is the refinement.* The review proposed `unavailable` for every disagreement. But a value that is below by its own shape can only come from a pre-E3 build: the shapes are disjoint, every legacy value compares below in its own frame (§5.3 above), and every gated build is ≥ max(`T_build`) (§5.2 step 3). Turning that G into S would be a regression from round 2.
  * **They disagree, and the value is not below** → `unavailable` → **S**. **Never N on a disagreement.**
* **The invariant, pinned by one test:** for every reading, the decision with `originalPlatform` present is never more closed than the decision without it. `originalPlatform` can only turn an N into an S.
* **The cost, said plainly.** If Apple numbers a universal purchase by the running platform, which is what its page says, every account that first got the app on iOS reads a **version** on its first Mac install. Their platform says "build", so the reading disagrees. For a pre-E3 iPhone-first account, that is S on the Mac, which is the point of the change. For an **E3-era** iPhone-first account, it is also S, on every Mac launch, never persisted. The Mac gate is then open for every iPhone-first account, and the same holds the other way round. That costs revenue and Window 2's Mac denominator. It is the cost of "never N on a disagreement". §10 Q7 asks the owner whether to settle disagreements by `originalPurchaseDate` instead. Default on silence: S, as above.

Side effect: the mirror case also goes the right way. An E3-era Mac-first account reports "1.39"; on iOS round 0 read that as [1, 39] < [63] and granted it. By shape it is a version, not below `T_version`: **N**. That keeps Window 2's denominator cleaner.

### 5.4 The pure function

It lives beside `EntitlementRecord`, takes plain values (the house rule that keeps GameCore free of ConjugationReviewKit, `GameSession.swift:305-309`), and imports neither StoreKit nor SettingsKit. It **copies** the marker's integer-version rules rather than importing SettingsKit ("1.36" == "1.36.0", `InstallCohort.Version`'s `<` and `==`, `InstallCohort.swift:93-103` **[25a472e]**), and one table test feeds the same strings to both types and asserts they agree (round-2 finding NIT-8: round 1 said both "imports neither SettingsKit" and "can reuse the marker's `Version`").

```swift
public enum DepthGrandfather {
    public enum Platform: String, Codable, Sendable { case macOS, iOS }
    public struct Version: Comparable, Sendable { let components: [Int] }   // never strings

    /// §5.2. Rises, never falls; a test pins the literals and the release script checks them.
    public struct Threshold: Equatable, Codable, Sendable {
        let buildMacOS: Int, buildIOS: Int   // T_build per platform
        let version: Version                 // T_version
    }

    /// What E3 reads from P0-12 (§5.9). Every case that can grant from PD carries the PD the
    /// gated build computed this launch, before the marker call (§5.9 item 1).
    public enum Cohort: Sendable {
        case present(firstSeenBuild: Int, platform: Platform, priorDataPresent: Bool)
        case absent(priorDataPresent: Bool)       // PD as the gated build computed it this launch
        case unreadable(priorDataPresent: Bool)   // corrupt bytes, not Data, a schema this build
                                                  // cannot read, or another platform's marker (r3-S1)
        case notRecorded                          // no marker step ran (isolation, nil): never
                                                  // grants offline, never writes (r3-S1)
    }

    public enum StoredGrant: Sendable { case absent, present }   // presence of either copy IS the grant

    /// Where the purchase was made, from `AppTransaction.originalPlatform` (iOS 18.4 / macOS 15.4).
    /// Nil below those versions; then the value's shape decides alone (§5.3, r3-M3).
    public enum OriginalPlatform: Sendable { case macOS, other }

    public enum AppTransactionReading: Sendable {
        case production(originalAppVersion: String, originalPlatform: OriginalPlatform?)  // verified, .production
        case nonProduction                            // verified, sandbox or xcode
        case unavailable                              // threw, unverified, unparseable, or timed out
    }

    public enum Reason: String, Codable, Sendable {
        case ungatedBuild, markerBeforeE3, priorDataAtFirstMarker,
             priorDataUnreadableMarker,              // row 4a (r3-S1)
             originalAppVersionBeforeE3
    }

    public enum Decision: Equatable, Sendable {
        case alreadyGranted
        case grant(Reason)        // open; persist the grant now
        case needsAppTransaction  // pending: open until the reading or the timeout (§5.6)
        case sessionGrace         // open for this process only; never persisted
        case notGrandfathered     // closed unless purchased; writes NOTHING (no negative state exists)
    }

    /// Everything except AppTransaction. Never touches the network.
    public static func offlineDecision(gateEnabled: Bool, storesReadable: Bool,
                                       stored: StoredGrant, cohort: Cohort,
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
| 0a | this launch's own stores are unreadable: one of the six store loads returns `.unreadable`, or the settings key reads nil while `supportStoresPresent` is true (both defined exactly in §5.10) | — | **S**; neither the marker nor a grant is written | §5.10, round-1 M3, round-2 MINOR-2, round-3 r3-N1 |
| 1 | a stored grant, either copy | — | open (`alreadyGranted`) | stored; no re-evaluation, ever |
| 2 | marker present, this platform, build < T | — | **G** `markerBeforeE3` | 1 |
| 3 | marker present, this platform, build ≥ T, PD true | — | **G** `priorDataAtFirstMarker` | 2 |
| 4 | marker absent before this launch, and the PD this gated build computed and **kept** this launch is true, **whether or not this launch wrote a marker** (`Running` nil or `encoded()` nil write nothing) | — | **G** `priorDataAtFirstMarker` | 2 (a legacy install that skipped 1.37 and 1.38; offline; r3-M1) |
| 4a | marker **unreadable** before this launch (corrupt bytes, not `Data`, a schema this build cannot read, or another platform's marker), and the kept PD is true | — | **G** `priorDataUnreadableMarker` | 2 (the evidence row 4 accepts; offline; r3-S1) |
| 5 | marker present, build ≥ T, PD false; or marker absent and the kept PD false | production, below E3 (§5.3, by shape, and by `originalPlatform` where present) | **G** `originalAppVersionBeforeE3` | 3 (a legacy reinstall, online) |
| 6 | as 5 | production, not below (and platform and shape agree, §5.3) | **N**, nothing written | a fresh E3-era install |
| 7 | as 5 | nonProduction | **N**, nothing written | sandbox rule |
| 8 | as 5 | unavailable (including a platform–shape disagreement that is not below, §5.3), or no answer by the timeout | **S** | unreadable |
| 9 | as 5 | still pending | **P** | §5.6 |
| 10 | marker unreadable and the kept PD false; or no marker step ran (`notRecorded`, isolation) | production, below E3 (§5.3) | **G** `originalAppVersionBeforeE3` | 3 |
| 11 | as 10 | production, not below (platform and shape agree) | **N**, nothing written | — |
| 12 | as 10 | nonProduction | **N** | sandbox rule |
| 13 | as 10 | unavailable, or timeout | **S** | unreadable |
| 14 | as 10 | still pending | **P** | §5.6 |

* **The offline-reinstall row is row 8** (pre-launch marker absent, this launch's PD false, AppTransaction throws → S, nothing persisted). Round 0 numbered it 12.
* Rows 0–4a never read the network, so a legacy rider on a plane is decided by rows 1–4a.
* **Row 4a closes the unreadable-marker gap** (round-3 finding r3-S1, SERIOUS, accepted). Before it, a pre-E3 rider whose marker bytes went bad had only rule 3. Signed in to a non-legacy App Store account, that rider got row 11 **N** on every online launch. The marker is write-once, so that state never healed. The same install with **no** marker got row 4 **G**. That made grandfathering depend on the network, which PLAN-V1.37 §K forbids (`docs/PLAN-V1.37.md:438`). An unreadable marker now carries the same evidence row 4 accepts. Round 2 left this as a "should, before E3 ships" in prose (§5.9 item 4). It is now a row, a test and a mutation (§9).
  * **Another platform's marker goes with the unreadable bytes, not with isolation** *(agent's choice, 2026-10-07 delegation)*. The review put it with isolation, under `notRecorded`. But it is write-once and never heals, exactly like corrupt bytes, so S1's argument applies to it word for word. Carrying PD into it only ever adds a G.
  * **Isolation stays unable to grant offline or to write.** `notRecorded` carries no PD, because an isolated launch does not read the user's stores.
  * **The generous error, stated.** A sampler whose marker went bad after it had ridden also gets 4a **G**. That is the same generous error row 3 and row 4 already accept (round-2 NIT-8). Reaching it takes corrupt bytes or a non-`Data` value under a key only P0-12 writes.
* **No row writes access state on N.** There is no stored negative state, so nothing local can stand between a later launch and rows 5 and 10 (round-2 finding S-new-1; round 1's latch is removed, §5.6). The one display-only key, the grace notice of §5.10, is not access state: no decision reads it (round-3 finding r3-M2).
* Row 1 means a grant, once written, decides every later launch with no other input.

**Readings this table makes, labelled:**
* **`unavailable` includes `.unverified`, an unparseable value and the timeout**, not only a throw *(agent's reading, 2026-10-07 delegation)*. §E names only the throw. Each is "no information", and treating it as such keeps a legacy rider on the safe side of the red line.
* **PD on a present marker counts** (row 3). A marker first written at an E3-era launch with PD true means the install had data before that marker existed. Round 1 said only a pre-marker install can have that; round-2 finding NIT-8 is right that it is false. A sampler whose defaults plist was lost while `odometer.json` survived also qualifies, and so does a macOS sampler who deletes the marker key by hand (then row 4). **Both errors are generous**, and the row is kept for the legacy rider it exists for.
* **Another platform's marker is unreadable** (row 4a with PD true, row 10 with PD false) *(agent's choice, 2026-10-07 delegation)*; the marker's own `firstSeenBuild(isBefore:on:)` returns nil for it (`InstallCohort.swift:202-205` **[25a472e]**).

### 5.6 While the check is pending, and the timeout

Review finding S2 (round 1), accepted: a captive-portal network can leave `AppTransaction.shared` neither returning nor throwing, and round 0 said nothing about that time.

* **Pending is open.** From `needsAppTransaction` until a reading or the timeout, `depthIsOpen` is true, as for grace. This is §E's own condition: "the failure must be 'assume entitled' when the transaction cannot be read, never 'assume not entitled'" (`PLAN-V2-PRODUCT.md:393-397`).
* **The timeout is 5 seconds** from the start of the read *(agent's choice, 2026-10-07 delegation; not measured, a parameter pinned by a test)*. No reading by then → **S** for the rest of the process.
* **After the timeout a late reading may only upgrade.** A late "production, below" → **G**, persisted. A late "not below" or "nonProduction" does not close a session already in grace.
* **Before the timeout, only rows 6, 7, 11 and 12 close**, and only at a moment no run is in progress. A run started while pending finishes on the store it was built with; the close takes effect when the rider is back on the menu.
* **Widget and reminders** are refreshed again once the decision settles, after the launch's synchronous refresh (`AppModel.swift:717-718`). The widget may show open counts for up to five seconds, which is the safe direction.
* **A fresh install's first launch shows onboarding** (`AppModel.swift:698-704`), so its pending window normally passes on a screen with no level content.

**Round 1's latch is removed** (round-2 finding S-new-1, SERIOUS, accepted) *(agent's choice, 2026-10-07 delegation)*.
* **What it was.** After a verified production "not below" reading, a local key let later launches decide **N** without reading `AppTransaction`.
* **Why it breached §E.** `originalAppVersion` belongs to an Apple Account; the latch lived in the container. A container outlives its account in ordinary ways: a deleted sandboxed Mac app keeps `~/Library/Containers/<id>`; an offloaded iOS app keeps its data and re-downloads under whichever account is signed in; a restore from another device's backup carries everything. A legacy rider whose first reading on that container came from a second account would have been refused rule 3 for good after switching back. §E rule 3 grants that rider.
* **Why not keep the review's repaired form** ("start closed, still read in the background, grant on any 'below'"). It closes the permanent breach, but under it a latched container that is offline starts **closed** where §E says unreadable means grace. Nothing persisted would be taken, but it is still a second rule that §E does not have, kept to save a few seconds of open depth.
* **Why the latch is not worth that.** What it saved is small. `AppTransaction`'s cache is scoped per app version and the App Store server is asked "if one has not been cached yet" (the SDK doc comment quoted at `PLAN-STAGE1.md:281-283`). So once an install has read it for the running version, later launches normally answer from the cache: pending lasts as long as a local read, and offline grace falls mainly on the first offline launch after each update. *The speed and offline behaviour of a cached read are not measured here;* if a cached read turns out slow, the cost is a longer open window, which is the safe direction.
* **So nothing is written on N.** The only persisted access state is the grant (§5.7), which can only open. A source scan pins that E3 writes exactly two keys and one file: the grant's two copies (§5.7) and the display-only grace-notice key `NihongoRide.depthGraceNotice.v1` (§5.10), allowed **by name**. The scan also asserts that `DepthGrandfather` and `depthIsOpen` never read the notice key (round-3 finding r3-M2; §9.3).

### 5.7 What is persisted, where, and why a grant is never revoked

| what | where | written by | content | synced? |
|---|---|---|---|---|
| install-cohort marker `NihongoRide.installCohort.v1` | settings `UserDefaults` | P0-12, once, if absent (`InstallCohort.decide`, `InstallCohort.swift:305-316` **[25a472e]**) | first-seen version, build, platform, PD | never |
| grant, copy 1: a new key, proposed `NihongoRide.depthGrant.v1` | settings `UserDefaults` | E3, on any `grant(_)`, and on `alreadyGranted` when this copy is missing; never over a present copy | the `Reason`, the version and build that wrote it, the thresholds | never |
| grant, copy 2: a small file beside the other stores, proposed `depth-grant.json` | Application Support, through `supportFileURL` (`AppModel.swift:530-532`) | the same, under the same rule | the same | never |
| the depth purchase's `EntitlementRecord`, its own key and quarantine key (P1-5) | settings `UserDefaults` | the depth store | as the road's record (`Entitlement.swift:79-127`) | never |
| the grace notice, proposed `NihongoRide.depthGraceNotice.v1` (round-3 r3-M2) | settings `UserDefaults` | E3's depth-card code only, at the two moments §5.10 names | two flags: "a session was in grace", "the notice was shown" | never |
| pending, session grace | memory | — | — | — |

* **Presence of either grant copy is the grant** *(agent's choice, 2026-10-07 delegation)*. Only a grant writes either copy, so any bytes there, readable or not, mean a grant happened.
  * **Stated as the product choice it is** (round-2 finding NIT-8): on macOS this puts the depth one `defaults write` away. That is not a red-line issue. Requiring readable bytes instead would turn a corrupt plist into lost depth for a grandfathered rider, which is the worse error for this app.
* **The grant key is its own quarantine** (review finding M5, accepted). It is never overwritten, so unreadable bytes stay as they are and no copy is made. P0-12 uses the same rule for the marker. Round 0 pointed at `EntitlementLedger`'s quarantine helper, whose `quarantineKey` ignores its `key` parameter (`Entitlement.swift:222`) and would have written into the road's quarantine key.
* **Two copies, repaired** (round-1 M3, partial; round-2 MINOR-3, accepted). If an OS event drops the defaults plist, the file still holds the grant, and the reverse. **On every `alreadyGranted` launch, a missing copy is recreated** from the surviving bytes, copied verbatim, and a present copy is never overwritten, readable or not. So the grant survives any sequence of single losses, not just one. Both live in the app container, so deleting the app on iOS removes both, and rule 3 is then the only way back (§5.10).
  * **One grant-writing function** (round-3 finding r3-M2). Every write of either copy goes through one function, `writeGrantCopies(_:)`, which writes a copy only where none is present. `grant(_)` calls it with fresh bytes. The copy repair calls it with the surviving copy's bytes. Nothing removes either copy. §9.3's scan pins exactly that: one writing function, two call sites, no remove. Round 2's wording, "the grant key appears in one write", would have forbidden the repair round 2 itself added.
* **Never revoked, in code, four ways.** (1) No type has a "revoked" or "false" value to write. (2) No code path removes either copy; a source scan pins that (§9). (3) Row 1 comes before every input that could change (rows 0 and 0a are above it, and both can only open). (4) The thresholds may only rise (§5.2).
* **What a grant covers** (review finding N5, accepted): everything the N3–N1 pools contained when the grant was written, and every later addition to those pools. If a later pack (E4) is ever carved out of today's N1 words, those words stay open for every grant.
* **Never synced, never sent.** None of these is a CloudKit record type (`CloudKitSyncController.swift:63`). `PrivacyClaimTests` stay green; Data Not Collected stays true. The privacy page's on-device storage list (`site/privacy.html:34-35`, which P0-6 extends for the marker) gains one sentence for the grant, the grace notice and the second purchase record, for the owner to push.

### 5.8 The order rule, and what it actually protects

The check reads P0-12's **pre-launch observation**, never the defaults after this launch's write. When that observation is `.absent`, PD comes from the gated build's own computation this launch (§5.9), not from the key.

**PLAN-V1.37 §E's stated reason does not hold under its own definitions.** It says that reading the fresh marker would make an offline legacy reinstall "fail rules 1–3, and get neither a grant nor grace". But a fresh marker has build ≥ T and PD false, so rules 1–2 do not grant, and with `AppTransaction` throwing, §E's own unreadable rule gives grace. That is row 8 either way. **No row changes with the order**, given that the marker stores PD.

The rule is still kept, because it protects against a likely bug: a decision that reads "present marker, build ≥ T" as a final verdict and skips `AppTransaction`. The mutation in §9 targets it.

**A fresh marker over unreadable bytes** would not hurt a legacy rider (review finding N1, accepted: round 0 overstated this). A legacy rider has a settings blob, so the fresh marker's PD would be true, and that is row 3, **G**. P0-12 still leaves unreadable bytes alone, which is right for its own reasons.

### 5.9 What E3 reads from the v1.37 marker, as built

The marker shipped in v1.37: it is on `release/v1.37`, merged at **25a472e** (round 1 and 2 read it on `v137-marker` @ 56a2ebc / 8b06f79). Read 2026-10-30 at 25a472e, by symbol:
* `InstallCohort.Observation` is `.absent` / `.present(Marker)` / `.unreadable`, and **`.absent` carries no PD** (`Sources/SettingsKit/InstallCohort.swift:243-281`). `.unreadable` covers corrupt bytes, a value that is not `Data` (`Stored.notData`, `:225`), and a schema or platform value a later build wrote (`:247-248`). Its comment says the gap round 3 closes, and says closing it is E3's job (`:263-274`).
* `InstallCohort.decide` writes the marker only on `.absent`, and only when `running` is not nil and `encoded()` is not nil (`:305-316`, `:210-214`). `recordLaunch` returns the **pre-launch** observation (`:352-359`).
* `AppModel` calls it once in `init`, before the settings save, with PD = "settings blob present or odometer not missing", passed inline (`InstallCohort.priorDataPresent(settingsStored:odometerStored:)`, `InstallCohort.swift:343-345`). It keeps only the observation, as `installCohortAtLaunch` (`AppModel.swift:424`, call at `:627-648`, save at `:754`, all **[25a472e]**). It is `nil` on a launch that touches nothing of the user's.

**What E3 reads, exactly** (round 2 corrects round 1's step 3, review finding NIT-4; round 3 corrects items 1, 4 and 5, findings r3-S1, r3-M1 and r3-N1):
1. **The gated build computes PD itself**, into a local, **before** the marker call: `priorDataPresent = settings key present || supportStoresPresent`, with `supportStoresPresent` defined in §5.10. That is broader than v1.37's expression (v1.37 review round 1, finding marker-1), which counts only the settings blob and `odometer.json`. The gated build passes the local to `recordLaunch` **and keeps it** beside `installCohortAtLaunch`. Every `Cohort` case that can grant from PD reads **the kept local**, never the key after the write. This is a change to the call site in the gated build's `AppModel`, not to v1.37.
   * **What the broader expression buys, corrected** (round-3 finding r3-N1). Round 2 said that with v1.37's expression, a 1.1 rider who upgrades straight to E3 offline would land on row 8 instead of row 4. That does not happen. A 1.0 or 1.1 install has support stores and no settings key, so row 0a catches its first gated launch: **S**, nothing written by E3. The end-of-`init` settings save, which is outside E3, then writes the key (`AppModel.swift:754` **[25a472e]**). Launch 2 has the key, so either expression gives PD true, and the rider gets row 4 **G**, offline. Because 0a's clause and the broad PD share one `supportStoresPresent`, the two expressions agree on every launch that gets past 0a. The broad one is kept anyway, as defence in depth if 0a ever changes. §9.1 pins the two-launch sequence.
2. `.present(m)` on this platform → `Cohort.present(firstSeenBuild: m.firstSeenBuild, platform: m.platform, priorDataPresent: m.priorDataPresent)`. Another platform's marker → `Cohort.unreadable(priorDataPresent: <the kept local>)` (§5.5, row 4a).
3. **`.absent`** → `Cohort.absent(priorDataPresent: <the kept local>)`. Row 4 then works on the first E3 launch, offline, with nothing re-read. **That includes a launch that wrote no marker** (round-3 finding r3-M1): `Running` nil or `encoded()` nil makes `decide` write nothing, and the kept local still says what this install had. Round 1 re-read this launch's write instead, and treated a failed write as "PD false". For a pre-E3 rider who skipped 1.37 and 1.38, that gave S offline, and N online under a non-legacy account, on every launch, because with `Running` nil the write never happens. That workaround is gone, and round 3 removes the last places in §9 and §11 that still described it.
4. **`.unreadable`** → `Cohort.unreadable(priorDataPresent: <the kept local>)` (round-3 finding r3-S1, SERIOUS). With PD true, row 4a grants offline, on the same evidence row 4 accepts. With PD false, rows 10–14 apply. Round 2 left this as "should, before E3 ships"; it is now a row (§5.5), a test (§9.1) and a mutation (§9.2). An unreadable marker is no longer worse off than no marker.
5. **`nil`** (the isolation case, round-1 N4) → `Cohort.notRecorded`. It carries no PD, so it never grants offline, and nothing is persisted, because in that case the stores are handed no defaults (`AppModel.swift:605-606`; `:615-616` **[25a472e]**). Pinned at 25a472e by `InstallCohortWiringTests.isolatedLaunchHasNoMarker`.
6. E3's decision runs in `init` after the marker step. **The marker call and every grant write sit behind one predicate**: row 0a's "stores readable" (round-2 finding MINOR-2). A source scan pins both the order and the shared predicate.

**What E3 needs from markers v1.37 and v1.38 wrote is only firstSeenBuild and platform.** Any such marker is below `T`, so rule 1 grants whatever its PD says, including a wrong PD.

**No change to the v1.37 marker is needed.** Round 1 said a PD-keeping change "would have to land before v1.37 ships". It would not: row 4 is the case where no marker existed before the gated launch, so the PD it needs is computed by the gated build (step 1).

**What must never change after v1.37 ships** (round-2 finding NIT-6):
* The `InstallCohort.Marker` decoder, `Marker.init(from:)`, strict schema 1 with every field required (`InstallCohort.swift:181-196` **[25a472e]**).
* The golden bytes its tests pin: `InstallCohortTests.markerJSON137` (macOS build 62) and `markerJSON137iOS` (iOS build 63), cited by name because line numbers move (v1.37 review round 2, marker-r2-5). Since round 1's marker-5 fix they are exactly what 1.37 writes.
* If an E3-era edit made v1.37's bytes undecodable, every legacy install would drop from row 2 to row 4a or rows 10–14: offline protection only through this launch's PD, otherwise rule 3 only. A new field goes in a schema-2 marker under a new key, never in an edit of schema 1.

**Hardening applied by the orchestrator at `v137-marker` 8b06f79 and shipped at 25a472e** (round-2 finding NIT-5, which the review called optional). Recorded here as read, not done by this document:
* `Marker.encoded()` now returns `nil` on failure, and `decide` then writes nothing, so the next launch tries again (`InstallCohort.swift:207-214` **[25a472e]**). Before, an encoding failure would have stored empty bytes that read `.unreadable` forever. The test `writtenBytesReadBack` (`InstallCohortTests.swift:352-353` **[25a472e]**) holds that every write reads back as present with the running build. That launch writes no marker, and row 4 still reads the kept PD (item 3).
* The test `noLaunchBeforeFirstUnlock` (`InstallCohortTests.swift:388-389` **[25a472e]**) pins that `project.yml`, comments stripped, sets no `UIBackgroundModes`, no `aps-environment` and no `BGTaskSchedulerPermittedIdentifiers`. At a34769c and at 25a472e the only match is a comment (`project.yml:77`).
* **What that pin is and is not.** "With no background mode, no push and no BGTask, nothing launches the app before the first unlock" is an **inference about OS behaviour, not a measurement**. In particular, it does not measure iOS prewarming. What makes it safe is the pinned precondition: adding any of those keys turns the test red and reopens the question. Row 0a stays in the gated build as the second line, defined by evidence `init` already has rather than by `UIApplication`, which may not exist yet when `@State private var model = AppModel()` runs (`NihongoRideApp.swift:16`).

### 5.10 Costs this rule accepts, said plainly

* **A legacy account's first install on its second platform.** The app is one ASC record with macOS and iOS versions (ASC GET 2026-10-27, `/v1/apps/6777469778/appStoreVersions`: `MAC_OS` and `IOS`, both 1.36 `READY_FOR_SALE`) and one bundle id (`project.yml:133, 272`). Whether that first install reads a pre-E3 `originalAppVersion` is unmeasured and cannot be tested in the sandbox ("1.0"). If it does, §5.3's shape rule grants it. If it does not, then on iOS 18.4 / macOS 15.4 and later `originalPlatform` shows the reading crosses platforms, and the result is **S**, never N (§5.3, round-3 r3-M3). Below those versions the device is a sampler. That install never had anything, so this is not a loss; the synced content is kept and shown (§4.4). Round 0's sentence "either answer keeps the red line" was too broad: it did not cover a **reinstall** on the second platform, which §5.3 now handles.
* **Reinstalling under a different Apple Account** (review finding M4, accepted). After a delete, the grant copies are gone (iOS) and rule 3 reads the new account's value. If that account first got the app after E3, the result is **N**. This is a new acquisition by a different account, and it is accepted as such.
* **Switching Apple Accounts in either direction** (round-1 M4, round-2 S-new-1). Each launch reads the signed-in account's `originalAppVersion` (rows 5–14). Switching *to* an account that first got the app after E3 gives **N** on a container that was never granted; that is a new acquisition by a different account, accepted. Switching *back* to a legacy account gives **G** at the next online launch, because nothing local remembers the other account's answer.
* **A fresh install that is never online, or whose reading stays unavailable,** gets grace on every launch where the read fails (rows 8, 13). It cannot buy anyway: a purchase needs the network. With `AppTransaction` cached per app version, this falls mainly on the first offline launch after each update (§5.6).
* **Long grace that ends in N** (round-2 finding MINOR-4, option (a) chosen) *(agent's choice, 2026-10-07 delegation)*. An E3-era install that is offline, signed out of the App Store or on a wrong clock for weeks rides N3–N1 in grace, makes N3 SRS cards and lists, and then one launch reads "not below" and closes.
  * **Accepted, because grace is by definition not a grant.** §E says it is temporary and never persisted, and a wall-clock cap would put a clock into a path that today reads none.
  * **What the rider keeps:** every card, list and history entry made in grace, kept and synced, rideable again on purchase (§4.1).
  * **Copy at the transition.** The first time the depth card shows after a session that was in grace, it says so: "N3–N1 were open while the App Store couldn't be reached. Everything you saved is kept." / "无法连接 App Store 时，N3–N1 曾暂时开放。你保存的内容都还在。" A test pins that the line shows exactly once.
  * **Where "once" is kept** (round-3 finding r3-M2, accepted). "After a session that was in grace" and "exactly once" both span processes, so they must be stored. Round 2 also said a scan pins that no other E3 key is written. As written, the tests forbade the feature. So there is **one display-only key**, `NihongoRide.depthGraceNotice.v1`, in settings `UserDefaults`, never synced, holding two flags:
    * `graceSeen`: set when a launch's decision ends in **S** at rows 8 or 13, or at the timeout. Pending alone does not set it. Row 0a does not either, because nothing is written on a 0a launch.
    * `shown`: set when the depth card renders the line, which it does only while `graceSeen && !shown`.
    * **It is not access state.** No decision reads it. The source scan allows exactly this key, by name, and asserts that `DepthGrandfather` and `depthIsOpen` never mention it (§9.3). It can never close anything, so it is not the stored negative state that round-2 S-new-1 removed.
    * Its writes sit behind the same predicate as the marker call and the grant writes (row 0a and isolation). Unreadable bytes mean "shown": the line is not shown and the bytes are left alone. The cost of that error is one missing sentence.
* **The 5-second timeout is a guess.** Too short gives grace to slow networks (safe); too long holds the depth open longer at launch (also safe).
* **Launches before first unlock** (row 0a). Today no background mode, push entitlement or BGTask identifier exists, pinned by `noLaunchBeforeFirstUnlock` (§5.9), so the path is believed unreachable. That belief is an unmeasured inference about the OS. Row 0a is defined by what `init` can see: a store whose file exists but loads `.unreadable` (`PersistKit/LossyLoad.swift:64-70`), or the settings key reading nil while support stores exist. On such a launch the depth is open for the session and neither the marker nor the grant is written. The settings save at `AppModel.swift:715` (`:754` **[25a472e]**) is outside E3 and unchanged.
* **Row 0a's file set, exactly** (round-3 finding r3-N1). Round 2 said "support files" and did not list them. The list matters, because the scope of that set decides which legacy installs get S. One function, `supportStoresPresent`, feeds both row 0a and §5.9's broad PD, so the two cannot drift apart:
  * **The six stores `init` loads through `LossyLoad`** before the marker step: `review.json`, `conjugation-review.json`, `history.json`, `odometer.json`, `custom-texts.json`, `stumble-ledger.json` (`AppModel.swift:540-547, 551-568`, listed as `persistLoadOutcomes` at `:576-582`, **[25a472e]**). Clause 1 of row 0a: any of the six returns `.unreadable`. `supportStoresPresent` counts any of the six whose outcome is not `.missing`, so `.undecodable` counts as present.
  * **`word-lists.json` and `saved-words.json`, by existence.** Their load runs later in `init` (`WordListStore.loadOrMigrate`, `AppModel.swift:708` **[25a472e]**), so the marker step can only see whether the files exist.
  * **Not counted:** the `NihongoRide` directory itself. `supportFileURL` creates it as a side effect on every launch (`AppModel.swift:2894-2895` **[25a472e]**), so counting it would make every fresh install look like a 1.x install: S on launch 1, then a row-4 **G** on launch 2, for everyone. Also not counted: `cksync-state.json` (sync state, not the rider's data) and `.corrupt` siblings (their original file is counted).
  * Clause 2 of row 0a: the settings key reads nil **and** `supportStoresPresent` is true.
  * **Who lands there, besides a launch before first unlock:** an install last opened on 1.0 or 1.1, and a macOS rider who deleted the settings key by hand. Each gets one **S** launch with nothing written, then row 4 **G** on the next, offline (§5.9 item 1).

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
1. **A locked level in the menu picker** (row 1). Selecting it shows the depth card in place of the start button. After a purchase the start button returns and that level rides **at once**. This answers the condition PLAN-V1.37 §K sets on any entrance: no entrance "to a purchase that shows nothing on purchase". It is at 0 km. **That a 0 km entrance is allowed here is the agent's reading of §K, not §K's text** *(agent's reading, 2026-10-07 delegation; round-3 finding r3-N3)*. §K's line is "A 0 km entrance (P1-9), or any entrance to a purchase that shows nothing on purchase" (`docs/PLAN-V1.37.md:434`). The reading takes "(P1-9)" to name the 0 km entrance it bans: the cut P1-9, a 0 km entrance to scenery first seen at 28 km (PLAN-V1.37 §D P1-9). This entrance opens something on the next tap. The stricter reading bans any 0 km entrance. That would put both E3 entrances, the Settings row included, behind a distance, because a sampler can open Settings at 0 km. §K is the owner's, and agent-authored meaning is not added to it (`docs/PLAN-V1.37.md:430`), so the choice is §10 Q9.
2. **One Settings row** beside the road card (`SettingsView.swift:174-206`), opening the same card. It is where Restore lives for a sampler whose menu is on an open level, and where App Review is pointed.

Not entrances: search, list rows and About carry a level tag or a line of text, never a buy button. No onboarding page, no badge, no modal, no post-ride prompt (PLAN-V1.37 §K bans the Kyōto-arrival kinds of these). Grandfathered installs see neither entrance.

### 7.2 The depth card

* What it opens, with counts **computed as catalog minus `DepthFreeSet`**, never by `jlpt` and never typed (round-2 finding MINOR-6), pinned by a test: for candidate 1 at today's corpus, N3, N2, N1: 5,783 words and 5,481 sentences, in every mode.
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
> Users who installed the app before this version keep every level for free. This is decided on the device. **If this device had an earlier version of Nihongo Ride installed, every level is already open and the purchase is not shown.** On iPhone or iPad, delete the app and install fresh to see it. **On a Mac, deleting the app keeps its data, so use a new macOS user account** (round-2 finding NIT-8). In the sandbox a fresh install always sees the purchase.
>
> The road west ("The Road West") is a separate, existing purchase and is unchanged.

* The IAP's own review note and screenshot show the depth card. The road IAP's note is P1-14's.
* Family Sharing stays off: it is irreversible (PLAN-V1.37 §K; `HANDOFF-STAGE1-GATES-PROMPT.md:218`).
* **The depth IAP is never promoted** (round-3 finding r3-N4). A promoted IAP on the product page could be bought by a grandfathered rider for content they already have. It would also arrive as a `PurchaseIntent` that nothing handles, which PLAN-V1.37 §K bans without handling and tests (`docs/PLAN-V1.37.md:436`). Before submit, the release script reads back (GET) `/v1/apps/6777469778/promotedPurchases` and stops if any entry names the depth product. Today the list is empty (ASC GET 2026-10-30: `total 0`).

**The App Review plan for a reused review device** (round-3 finding r3-M4, accepted). The note above *asks* for a fresh install. It cannot *make* one.
* **The risk.** Any review iPhone or Mac that ran a reviewed 1.37 or 1.38 build has a marker below `T`, so it gets row 2 **G**: no lock in the menu, no Settings row. The Mac app has been reviewed 37 times under this bundle id (ASC GET 2026-10-30, §5.2). A sandboxed Mac container survives deletion (`project.yml:74`, `com.apple.security.app-sandbox: true`). The likely result is a guideline 2.1 rejection, "could not locate the In-App Purchase", of the first build that carries the new IAP. That IAP must be reviewed together with the binary. Guideline 2.1(b), read 2026-10-30 (https://developer.apple.com/app-store/review/guidelines/), asks that in-app purchases be "visible to the reviewer", and says that if one "cannot be found or reviewed in your app, explain the reason in your review notes". The note above does that; the rest of this plan makes it hard to miss.
* **What goes with the submission:**
  1. **A screen recording** of the sampler flow on a fresh install of the gated build: a locked level in the picker → the depth card → the purchase sheet → the level rides. It is attached to the version's App Review information as an attachment. The endpoint exists for this app (ASC GET 2026-10-30, `/v1/appStoreReviewDetails/{id}/appStoreReviewAttachments` on 1.36's Mac review detail: 0 attachments today). **The recording is the owner's to make.** It contains a purchase, and PLAN-V1.37 §K forbids "any purchase by an agent in any environment" (`docs/PLAN-V1.37.md:431`). The agent can script the steps and write the caption.
  2. **The IAP's review screenshot** shows the depth card, not a store sheet. Each IAP has one review screenshot (ASC GET 2026-10-30, `/v2/inAppPurchases/{id}/appStoreReviewScreenshot` on the road IAP returns an `inAppPurchaseAppStoreReviewScreenshots` record).
  3. **The review note above**, with its "if this device had an earlier version" paragraph, and one line pointing at the attachment: "A screen recording of this flow on a fresh install is attached."
* **The reply, drafted now** for a 2.1 "could not locate the In-App Purchase" message. It is posted in App Review's reply only if that rejection comes, and only after the owner reads it:

  > Thank you for reviewing Nihongo Ride. The In-App Purchase "N3–N1 Levels" is offered only on installs made with this version or later. People who installed an earlier version keep every level free, and the app decides this on the device. Your review device appears to have had an earlier version of Nihongo Ride installed, so every level is already open there and the purchase is not shown.
  >
  > To see it: on iPhone or iPad, delete Nihongo Ride and install this build. On a Mac, deleting the app keeps its data, so please use a macOS user account that has never opened Nihongo Ride. Then, on the main menu, choose N3, N2 or N1 in the level picker. The purchase card replaces the Start button. It is also in Settings, under the road card, with Restore Purchases.
  >
  > The attached screen recording shows the whole flow on a fresh install of this build: a locked level, the purchase card, the purchase sheet, and the level opening after purchase.

* **What the plan does not do.** It adds no hidden reviewer path and no build-time switch: those would be a hidden feature (guideline 2.5.19, "Don't include any hidden, dormant, or undocumented features", same page and date), and a switch is exactly the gate-off build that §5.2 turns into grants. The one mechanism that would show a reused device the product is a read-only line in Settings for grandfathered installs. It breaks "existing riders' UI byte-identical to v1.38" (§8, §9.4 V2), so it is the owner's choice: §10 Q8, default not shown.
* Submission: E3 is the app's **second** non-consumable, so `POST /v1/inAppPurchaseSubmissions` (`scripts/submit_1_30.py:28-31`; `scripts/asc_release.py:611-614`). Neither path is measured for a second IAP; the script stops on any answer other than success (PLAN-V1.37 §E rank 1).
* **Whether App Review's environment is the sandbox** is PLAN-V1.37's claim (§E), not re-verified today. Apple's page read today says only what the sandbox value is.

---

## 8. What existing installs keep: everything, forever

An existing install is one that the rule grants: rows 0, 2, 3, 4, 4a, 5 and 10 of §5.5 (review finding N2: round 0's list missed the other-platform case, now row 4a or 10; round 3 added 4a, r3-S1). From then on `depthIsOpen` is true on every launch, from the grant alone (row 1), offline or online. Until a grant is written, rows 8–9 and 13–14 keep it open for the session.

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
| Settings (24) | No new row. (A read-only "included" line is the owner's option, §10 Q8; default not shown.) |
| The road and the road west (25) | Unchanged. The road west stays a separate purchase, still for sale. |
| On a plane, after an overnight update | Rule 1 or 2, offline (rows 2–4a), including a rider whose marker became unreadable. |
| After a downgrade, an upgrade, a restore, a refund of anything, a sign-out | The grant decides (row 1). Nothing reads anything else. |
| A hotfix, a rollback or a kill switch that turns the gate off, then a release that turns it back on | Every launch with the gate off wrote a grant (row 0). A pre-E3-branch hotfix is covered by the threshold, which the release script forces above it (§5.2). |

**The verification that matters most:** for a grandfathered install, every pool count and every run builder must return exactly what v1.38 returns. §9 pins that with a golden fixture produced from v1.38's own code, the method `PurchasePromiseTests` uses for the road (`Tests/SceneryKitTests/RideRouteFreezeTests.swift:1-20, 309`).

---

## 9. Tests to write, and the verification it needs

### 9.1 Pure table tests (`DepthGrandfather`)

* **Every row of §5.5**, one test each, including row 8 by name ("offline reinstall, no prior data, no pre-launch marker, AppTransaction throws → session grace, nothing persisted").
* **Rule 3 by shape** (§5.3): "40" on macOS is a build and below a threshold of 65 → G; "1.39" on iOS is a version and not below `T_version` 1.39 → N; "1.20" on iOS → G; "" and "1.x" → unavailable.
* **Rule 3 with `originalPlatform`** (§5.3, r3-M3), one table, each value with platform nil, `macOS` and `other`:
  * agreement decides as shape does: "1.20" + `macOS` → G; "1.40" + `macOS` → N; "40" + `other` → G; "66" + `other` → N (thresholds 65 / 1.39);
  * disagreement and below by shape → G: "40" + `macOS` → G; "1.20" + `other` → G;
  * disagreement and not below → S, never N: "1.40" + `other` → S; "66" + `macOS` → S;
  * the invariant over the whole table: with the platform present, the decision is never more closed than with it nil.
* **Pending and timeout** (§5.6): pending is open; no answer at 5 s → S; a late "below" after the timeout → G; a late "not below" after the timeout leaves this session open and writes nothing; a close before the timeout waits for a run to end.
* **Nothing on N** (§5.5): rows 6, 7, 11, 12 write no key and no file; the next launch with a legacy account's reading grants (the account-switch-back case, round-2 S-new-1).
* **Grant copies** (§5.7): copy 1 absent and copy 2 present → copy 1 recreated from copy 2's bytes, and the reverse; neither present copy is ever overwritten, readable or not. Both writes go through `writeGrantCopies(_:)` (r3-M2).
* **The two `Version` types agree** on the same strings (§5.4).
* **The marker read** (§5.9, r3-M1): pre-launch `.absent` plus the **kept** PD true → row 4 G, **including when this launch wrote no marker** (`Running` nil; `encoded()` nil). `.absent` with kept PD false → rows 5–9. `nil` → `notRecorded`: never G offline, nothing persisted.
* **The unreadable marker** (§5.5 row 4a, r3-S1): corrupt marker bytes + settings blob present, `AppTransaction` production and not below → **G** `priorDataUnreadableMarker`, decided offline, with `AppTransaction` never consulted. The same with a non-`Data` value, and with another platform's marker. Corrupt bytes + kept PD false → rows 10–14. `notRecorded` + any PD → never row 4a.
* **The 1.1 rider, two launches** (§5.9 item 1, §5.10, r3-N1): launch 1 has `review.json` and `history.json`, no settings key, no marker → row 0a **S**, no marker and no grant written, settings saved at the end of `init`. Launch 2, offline → row 4 **G**. A fresh install, where only the `NihongoRide` directory exists → not row 0a.
* **The grace notice** (§5.10, r3-M2): a session that ends in S sets `graceSeen`; the next depth card shows the line and sets `shown`; the card after that does not show it; pending alone sets nothing; unreadable bytes → not shown, not overwritten; no decision changes when the key is present, absent or unreadable.
* **Version parsing**: "1.4" < "1.36" < "1.40"; "1.9" < "1.10"; "1.36" == "1.36.0"; "1.4.1" between "1.4" and "1.5"; iOS "9" < "62"; "1.0" (sandbox-shaped) parses; "" and "abc" → unavailable.
* **Per platform**: a macOS marker at build 61 against an iOS threshold is never compared (row 4a with kept PD true, row 10 with it false).
* **Decision → persistence**: `grant` writes both copies once; `alreadyGranted` writes only a missing copy; `sessionGrace` and `notGrandfathered` write no access state (the grace notice's flag is display-only, §5.10).
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
| Derive row 4's PD from the key after this launch's write instead of the kept local (r3-M1) | "`.absent` + kept PD true + `Running` nil → row 4 G", and the same with `encoded()` nil: both red when the write is suppressed |
| **Drop row 4a** (r3-S1) | "corrupt marker bytes + settings blob present, production not below → G offline" |
| Map unreadable bytes, a non-`Data` value or another platform's marker to `notRecorded` (r3-S1) | the same test, and its non-`Data` and other-platform variants |
| Let `notRecorded` (isolation) grant from PD, or write anything | "`nil` → never G offline, nothing persisted" |
| Return N on a platform–shape disagreement (r3-M3) | "1.40" + `other` → S; "66" + `macOS` → S; the never-more-closed invariant |
| Return S on a disagreement that is below by shape (r3-M3) | "40" + `macOS` → G; "1.20" + `other` → G |
| Count the `NihongoRide` directory, or `cksync-state.json`, in `supportStoresPresent` (r3-N1) | "a fresh install is not row 0a" |
| Let any access decision read the grace-notice key (r3-M2) | the source scan: `DepthGrandfather` and `depthIsOpen` never mention it |
| Write a second grant-writing site, or any remove of either copy (r3-M2) | the source scan: one writing function, two callers, no remove |
| **Threshold set at the first upload instead of above every ungated release** (B1) | "an ungated release after the first gated upload, installed fresh, then the gated build → G" |
| Lower a threshold literal | the literal pin, and the release-script check's fixture |
| **Drop the ungated grant writer** (S1) | "gate off → grant written", and "gate off, then on → still open" |
| **Treat pending as closed** (S2) | "pending → open", and the hanging-reading fixture: no answer for 30 s → open throughout, S at 5 s |
| Close mid-run | "a close before the timeout waits for the run to end" |
| **Read rule 3 by the running platform** (S3) | "40" on macOS → must be G |
| **Persist any negative state** (a key or file written on N; round 1's latch) | the source scan of E3's writes, and "N on a second account, then a legacy account's reading → G" |
| Skip the background read on any launch that reached rows 5–14 | the same account-switch-back test |
| Never recreate a missing grant copy | "defaults lost, then file lost → still granted" |
| Count an ungated **upload** as nothing because it was never released (round-2 MINOR-1) | the release-check fixture: an unreleased ungated TestFlight build above every release must raise `T` |
| Let a platform's gated build sit below max(`T_build`) (MINOR-5) | the release-check fixture |
| Read "gated" from the registry instead of the archive, or treat an unrecorded build as gated (MINOR-7) | the release-check fixture: a build missing from the registry raises `T` |
| Count the depth card from `jlpt` (MINOR-6) | a fixture corpus with one id moved N3 → N4: the id joins the free set and the card's count drops by one |
| Write the marker or the grant on a launch whose stores are unreadable (MINOR-2) | row 0a, and the shared-predicate scan |
| Edit the schema-1 marker decoder or its golden bytes | `InstallCohortTests.markerJSON137` and `markerJSON137iOS` (`InstallCohortTests.swift:19, 23` **[25a472e]**) |
| **Filter the free tier by `jlpt`** (S4) | a fixture corpus that moves one free id to N3 → the id must stay rideable |
| Remove an id from `DepthFreeSet` | the frozen-copy comparison |
| Remove a withdrawn id from `DepthFreeSet` along with its corpus entry (r3-N2) | the frozen-copy comparison. The id must stay; the golden test accepts it because it is a recorded withdrawal |
| **Compute the unplayable hint or `.removed` from the rideable store** (S5) | a sampler list of N3 ids shows neither "aren't available" nor "you can remove it" |
| Write anything at a launch before first unlock | row 0a |

### 9.2.1 The release-script check

* A table test of the check's pure core, fed recorded ASC responses: a gated submit with `T_build` at or below an ungated release → stop; an ungated submit above `T_build` without the writer → stop; a threshold below the previous gated release's → stop; the clean case → proceed.
* A dry run against ASC (GET only) before the first gated submit, its output in the release record.

### 9.3 App-layer tests

* **Golden grandfathered sweep.** A fixture produced by **compiling v1.38's own code**: for each mode × level × "All", the pool size and the id set each builder can draw, plus every count in §2.1, for a fixed fixture review store and lists. E3 with `depthIsOpen = true` must reproduce it byte for byte. This is the red-line test; the shape is `PurchasePromiseTests`' v1.29 sweep.
* **Sampler sweep.** The same table with `depthIsOpen = false`: every id drawn is N5 or N4; every count equals the run it promises (the house "count and run from one predicate" rule).
* **Store split, by source scan** (the `CallSiteScanner` in `Tests/NihongoRideAppTests/CallSiteScanner.swift`): every `GameSession.make*` and `ConjugationSession.make*` call in `NihongoRideApp` passes `vocab:` explicitly (the defaults are `.shared`, the full store, e.g. `GameSession.swift:419`); `catalog` never reaches a builder or a `resolves:` argument. **E3's writes** (round-3 finding r3-M2): both grant copies are written by one function, `writeGrantCopies(_:)`, called from `grant(_)` and from the copy repair and nowhere else, and nothing removes either copy; the only other E3 key written is `NihongoRide.depthGraceNotice.v1`, allowed by name; `DepthGrandfather` and `depthIsOpen` never mention that key.
* **Locked level**: start with a locked level selected builds nothing and sets no empty-pool notice (§4.5, `MenuView.swift:477-482`).
* **Free set golden**: `DepthFreeSet.ids` ⊇ the first gated release's list, read with `git show`; every free-level id is in it; every id in it resolves in the catalog **or is in `DepthFreeSet.withdrawn`**, the grow-only record of corpus withdrawals (§2.2, round-3 finding r3-N2). A withdrawn id stays in the set.
* **Release check against real responses**: the pure core of §5.2's check is fed recorded ASC responses (`/v1/builds`, `appStoreVersions?include=build`) and an archive `Info.plist` with and without the gate key.
* **Order in `init`**: the E3 decision runs after the marker step (source scan, §5.9).
* **Access swap**: a purchase while on the menu swaps `vocab`, refreshes the widget and reminders, and the next start rides N3.
* **Sync safety**: a synced N3 SRS card and list id on a sampler survive a save and a re-sync unchanged.
* **Copy pins**: the card's counts equal the catalog's; one name per product per language; `PrivacyClaimTests`, `PurchasePromiseTests`, `PaidRouteRowTests` and `OneBranchRuleTests` change in the same commit as what they pin (PLAN-V1.37 §J V7). `stage1_walk.py`'s constants as PLAN-V1.37 §E lists.

### 9.4 The §J verification E3 needs

* **V1** gates green at the then-current floor; `HorizontalTextFitTests.accepted` only lowered.
* **V2** headless renders en/zh/ja for two named states: **grandfathered** (the menu, lists, search, About and Settings **byte-identical to v1.38**, a frozen-surface check that the red line holds on screen) and **sampler** (intended differences named in advance: the locked picker, the depth card, the Settings row, list and search tags, About's line). The capture harness needs a sampler seam to render the second (§6.2 item 3). If the owner chooses §10 Q8, the grandfathered Settings render gains that one line, named in advance, and is otherwise still byte-identical.
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
| Q4 | **Any stored negative state** (round 1's latch, §5.6). It would shorten the open window at launch and remove offline grace for samplers, at the cost of a container-scoped fact standing in for an account-scoped one. | **Removed in round 2: no latch, §E exactly.** Nothing is written on N. The owner can ask for the review's repaired form ("start closed, still read, grant on any 'below'"), knowing it starts latched containers closed offline where §E gives grace. |
| Q6 | **The ungated grant writer in v1.38** (§5.2). It would make every v1.38-or-later launch a grant before E3 exists, covering a hotfix built from a pre-E3 branch. It is E3 code shipping before the owner's box, so it needs the owner's word. | Not in v1.38. The writer ships with E3 (v1.39), and the release-script check covers pre-E3-branch hotfixes. |
| Q5 | **Search for samplers**: keep all levels searchable and addable (as shipped since v1.35), or show only open levels? | All levels, tagged. |
| Q7 | **A reading whose `originalPlatform` disagrees with its shape** (§5.3, round-3 r3-M3). As designed, a disagreement that is not below gives **S** on every launch and is never persisted. If Apple numbers a universal purchase by the running platform, as its page says, that holds the gate open on the other platform for **every** account, E3-era ones included. The alternative is a fourth rule §E does not have: settle a disagreement by `AppTransaction.originalPurchaseDate` ("The date the customer originally purchased the app from the App Store", https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate, read 2026-10-30). Before the first gated release → **G**, persisted, which would grant a legacy account's first install on its other platform. On or after it → **N**. The date is signed by Apple, not read from the device clock (contrast Q3). | **§E's rules as written: no date rule.** A disagreement gives S, never N, and nothing is persisted. |
| Q8 | **A read-only line in Settings for grandfathered installs** (§7.4, round-3 r3-M4): "N3–N1 Levels: included with your install" / "N3–N1 等级：随安装附带", with no buy button and no Restore. A reviewer on a reused device could then see that the product exists. It **breaks "existing riders' UI byte-identical to v1.38"** (§8; §9.4 V2's grandfathered Settings render), which is why it is the owner's call and not the agent's. | **Not shown.** The review note, the attached recording and the drafted 2.1 reply only (§7.4). |
| Q9 | **What §K's "A 0 km entrance (P1-9)" bans** (§7.1, round-3 r3-N3). The agent's reading: P1-9's entrance, plus any entrance to a purchase that shows nothing on purchase. Under it, E3's locked level and Settings row are allowed at 0 km, because the purchase opens a level on the next tap. The stricter reading bans every 0 km entrance. Both E3 entrances, the Settings row included, would then have to wait for a distance, and a reviewer would need to ride before finding the IAP. | **The agent's reading, labelled as such:** both entrances as drafted. The owner's word at C-2 replaces it either way. Nothing ships before the C-2 box. |

---

## 11. Where PLAN-V1.37 and the code disagree, and what this document could not verify

**PLAN-V1.37 against the code or its own definitions:**
1. **§E's reason for the order rule** does not hold: under §E's own "unreadable" rule the offline reinstall gets grace whichever marker is read (§5.8). The rule is kept as defence in depth.
2. **P0-13's "kana … in every mode"**: no kana mode exists (`GameSession.swift:16-22`). Kana practice is the passages and the coach drills, both free (§1).
3. **P0-13's "everything that already ships free"** includes the N3–N1 pools if read literally. Read here as every feature and mechanic (§1).
4. **P1-5's scope misses three things** a second SKU needs: routing `Transaction.updates` (`RouteStore.swift:395-404`), the product request (`:169`), and the DEBUG seam (`:122-142`) (§6.2).
5. **§E's "a clean denominator"** ("Purchases come only from new installs"): a grandfathered account's first install on its other platform is not grandfathered by rules 1–2 and can buy. Whether App Store reports count it as a first-time download under universal purchase is unverified, so the denominator may not be exactly "new installs".
6. **§E rule 1 and the marker**: a marker for another platform and an unverified `AppTransaction` (§5.5) are not covered by §E's text. This design treats both as unreadable, labelled. An unreadable marker carries this launch's PD (row 4a with it true, row 10 with it false; round-3 r3-S1).
7. **§E says rule 3 compares "`CFBundleShortVersionString` on macOS, `CFBundleVersion` on iOS".** On a universal purchase that is unsafe if Apple reports the first platform's value; §5.3 reads the value by shape instead.
8. **§E's "before E3's build" is ambiguous**, and the natural reading (the first E3 build) un-grandfathers installs of any ungated build released after it (§5.2, review finding B1).
9. **§E's "a constant flip"** (Sequence) implies a gate that can be flipped back. Flipping it back off and on again would un-grandfather installs made in between, unless the gate-off build writes the grant (§5.2, review finding S1).
10. **The v1.37 marker drops PD on `.absent`** (`InstallCohort.Observation.absent`, `InstallCohort.swift:245`; the call at `AppModel.swift:627-648`; both **[25a472e]**). E3 computes PD itself, before the marker call, **keeps it in a local**, and reads that local for `.absent` and `.unreadable` alike, whether or not this launch wrote a marker (§5.9 items 1, 3 and 4). It never reads PD back from this launch's write. Round 1 did, and round 2 removed that, but this item still described it until round 3 (r3-M1). No v1.37 change is needed.

**Not verified today:**
* `originalAppVersion` on a universal purchase's second platform (§5.10). §5.3 makes either answer safe. `originalPlatform` (iOS 18.4 / macOS 15.4, read 2026-10-30) says where the purchase was made. It does not say which numbering the value uses (§5.3, r3-M3).
* How often a real reading's `originalPlatform` disagrees with its shape, and so how much §10 Q7's default costs. Nothing on the device reports it, by design (Data Not Collected).
* How long `AppTransaction.shared` can hang, and whether 5 s is the right timeout (§5.6).
* How fast a **cached** `AppTransaction` read is, and whether it answers offline (§5.6). The latch's removal leans on the SDK comment that the cache is per app version, not on a measurement.
* Whether iOS prewarming can run `AppModel.init` before the first unlock. `noLaunchBeforeFirstUnlock` pins the absence of background modes, push and BGTask, not prewarming (§5.9).
* Whether an iOS launch before first unlock happens for this app, and what `UserDefaults` does then (§5.10).
* Whether App Review runs in the sandbox environment (§7.4).
* Whether App Review's devices are fresh. The plan in §7.4 assumes they may not be.
* Whether a freshly downloaded build's `AppTransaction` is readable offline on its first launch. PLAN-STAGE1's measurement (`PLAN-STAGE1.md:281-284`) was of an update; the table gives grace either way.
* Either IAP submission path for a second IAP (PLAN-V1.37 §A).

**State read 2026-10-30:** one IAP exists, `com.jasonye.nihongoride.scenery.lifetime`, `NON_CONSUMABLE`, `APPROVED`, `familySharable` false (ASC GET 2026-10-30, `/v1/apps/6777469778/inAppPurchasesV2`; unchanged since 2026-10-27). No promoted purchase exists (`/v1/apps/6777469778/promotedPurchases`, `total 0`). No depth IAP exists, and none is created by this document.

---

## 12. Review round 1

An independent red-line review of round 0 (`31b9487`) is at `~/Library/Caches/NihongoRide-v137-work/review-e3-design.md` (outside the repo). It found 1 BLOCKER, 5 SERIOUS, 5 MINOR and 5 NIT. Each was checked against the code before a decision.

| # | sev | finding | checked against | decision | where it changed |
|---|---|---|---|---|---|
| B1 | BLOCKER | A threshold at "the first E3 build of any channel" un-grandfathers fresh installs of any ungated build released after that upload. | Builds come from one counter bumped by one (`check_versions.py:78`); every released build is one integer, max 61 / 62 (ASC GET 2026-10-27). The scenario holds. | **ACCEPT** | §5.2: a threshold above every build released without the gate, rising only; the release-script check before every submit; §9.2 and §9.2.1. |
| S1 | SERIOUS | A rollback or kill switch after E3 un-grandfathers installs made while the gate was off. | §E's "a constant flip" implies the gate can be flipped back; round 0's table could not see a gate-off build. Holds. | **ACCEPT** | §5.2: every gate-off build writes the grant (`ungatedBuild`, row 0). It ships with E3 (v1.39). Shipping it in v1.38 needs the owner (Q6, default no); the release-script check covers pre-E3-branch hotfixes. |
| S2 | SERIOUS | A hanging `AppTransaction` has no timeout and no defined pending state. | Round 0 defined only throw → grace; the launch refreshes the widget and reminders before any async read (`AppModel.swift:717-718`). Holds. | **ACCEPT** | §5.6: pending is open; 5 s timeout → S; a late reading only upgrades; a close waits for a run to end; refresh after settling. Round 1 also added a latch; round 2 removed it (S-new-1). |
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

**One point where round 1 went further than the review, and one where it differs:**
* **Further, and withdrawn in round 2:** the latch (§5.6). Round 1 argued that the review's pending fix alone would open the depth for up to five seconds at every sampler launch. Round 2's review showed the latch was a breach (S-new-1), and it is removed.
* **Differs:** the review says TestFlight sampler testing must go through the DEBUG seam. TestFlight builds are Release builds, and the seam is `#if DEBUG` (`RouteStore.swift:122-142`), so it is not available there. It is also not needed: a gated build's number is above every earlier ungated release, so a fresh TestFlight install of it is a sampler under §5.2's threshold.

### Review round 2

The round-2 red-line review of `a6a6f26` is at `~/Library/Caches/NihongoRide-v137-work/review-e3-design-r2.md` (outside the repo): 0 BLOCKER, 1 SERIOUS, 7 MINOR, 8 NIT. Each finding was checked against the code, or against `v137-marker` @ 56a2ebc / 8b06f79 where marked, before a decision.

| # | sev | finding | checked against | decision | where it changed |
|---|---|---|---|---|---|
| S-new-1 | SERIOUS | Round 1's latch stored an account-level fact (`originalAppVersion` "not below") in a container that can outlive the account, so a rider switching back to a legacy account was refused rule 3 for good. | Apple: the value is per purchase and "remains constant" (doc JSON read 2026-10-27); the latch was in `UserDefaults` (round-1 §5.7). Holds. | **ACCEPT, stronger than proposed: the latch is removed** | §5.6 (why removed, and why not the review's repaired form), §5.5 ("no row writes anything on N"), §5.10 (account switch in both directions), §9.2 (mutations), Q4. |
| MINOR-1 | MINOR | `T_build` over released builds misses an ungated TestFlight upload above every release. | `/v1/builds` lists uploads separately (ASC GET 2026-10-27: 46 per platform, highest 61 / 62). Holds. | **ACCEPT** | §5.2: `T_build` over every ungated upload, plus git history because ASC lists fewer builds than were made. |
| MINOR-2 | MINOR | Row 0a promised "nothing written", but the marker write in the same `init` is unguarded, and `UIApplication` may not exist there. | `AppModel.swift:625-636` [marker]; `NihongoRideApp.swift:16`. Holds. | **ACCEPT** | Row 0a is now defined by `init`'s own evidence; the marker call and grant writes share one predicate in the gated build (§5.5, §5.9 item 6, §5.10). The 8b06f79 pin is recorded as an inference made safe by a precondition (§5.9). |
| MINOR-3 | MINOR | The two grant copies were never repaired. | Round-1 §5.7 wrote copies only on `grant(_)`. Holds. | **ACCEPT** | §5.7: a missing copy is recreated verbatim on `alreadyGranted`; a present copy is never overwritten; §9.1 test, §9.2 mutation. |
| MINOR-4 | MINOR | Long grace that ends in N was not addressed. | Grace is unbounded in time by design. Holds. | **ACCEPT, option (a)** | §5.10: accepted; what the rider keeps; one-time transition copy, pinned. No wall-clock cap, to keep clocks out of the path. |
| MINOR-5 | MINOR | An iOS gated build below max(`T_build`) would grant every fresh iOS install online. | Counters are per target (`check_versions.py:78`); §5.3 compares with the max. Holds (revenue, not red line). | **ACCEPT** | §5.2 step 3: each platform's gated build ≥ max(`T_build`), bumping a lagging counter. |
| MINOR-6 | MINOR | The free set grew only by new entries, so an id moved down to N4 would not be free, and a `jlpt` count would drift. | Round-1 §2.2. Holds. | **ACCEPT** | §2.2: every free-level id is in the set; §7.2: counts = catalog minus the free set; one test both ways. |
| MINOR-7 | MINOR | The registry of gated builds was written by the script that checks it. | Round-1 §5.2 step 2. Holds. | **ACCEPT** | §5.2 step 2: "gated" read from the archived `Info.plist`; an unrecorded build counts as ungated. |
| NIT-1 | NIT | Thresholds checked at submit can go stale before release. | Versions are per platform in ASC. Holds. | **ACCEPT** | §5.2 step 5: re-run at release; no ungated release on the other platform while a gated one waits. |
| NIT-2 | NIT | The cost of any ungated release after E3 was unstated. | — | **ACCEPT** | §5.2: stated. Any ungated release after E3 forces the next threshold up and grandfathers every sampler installed before it. |
| NIT-3 | NIT | The free set's frozen copy could be edited in the same commit. | — | **ACCEPT** | §2.2: `git show <first-gated-tag>` and a hash in the release record. |
| NIT-4 | NIT | §5.9 step 3's re-read was unnecessary; the gated build can compute PD itself. | `AppModel.swift:633-635` [marker] passes PD inline. Holds. | **ACCEPT** | §5.9 items 1 and 3; round 1's "would have to land before v1.37" corrected. |
| NIT-5 | NIT | `encoded()` could store empty bytes forever. | Fixed by the orchestrator at 8b06f79 (`InstallCohort.swift:198-205`; `writtenBytesReadBack`). | **ACCEPT, already applied** | §5.9: recorded as read, not done by this document. |
| NIT-6 | NIT | The marker's decoder and golden bytes must be declared frozen. | `InstallCohort.swift:172-187`; `InstallCohortTests.swift:18, 242`. | **ACCEPT** | §5.9: frozen after v1.37 ships; schema 2 under a new key if ever needed; §9.2 mutation. |
| NIT-7 | NIT | Latch spec gaps (unreadable latch bytes; a contradiction with the re-read fallback). | — | **MOOT** | The latch and the re-read are both removed. |
| NIT-8 | NIT | Row 3's justification is false; "presence is a grant" is one `defaults write` away on macOS; the Mac review note; the two `Version` types. | Holds on all four. | **ACCEPT** | §5.5 row 3 (both errors generous); §5.7 (stated as a product choice); §7.4 (a new macOS user account); §5.4 and §9.1 (copied rules, agreement test). |

**After round 2,** no local state written by E3 can stand between an install and a grant. The only persisted access state is the grant, which only opens. Every N decision writes nothing. Every threshold only rises.

### Review round 3

The round-3 red-line review read this document at `release/v1.37` @ 25a472e (identical to `main` @ a34769c for this file): 0 BLOCKER, 1 SERIOUS, 4 MINOR, 5 NIT. Its findings are copied byte for byte into `docs/evidence/v137-e3-design/review-round3-findings.json`. The disposition of each finding, with what was checked, is in `docs/evidence/v137-e3-design/review-round3.md`. Each one was checked against this document and against `Sources/` at 25a472e, because `main` does not have the marker yet.

| # | sev | finding | checked against | decision | where it changed |
|---|---|---|---|---|---|
| r3-S1 | SERIOUS | An unreadable marker had no offline route to a grant: rule 3 only, so N online under a non-legacy account, forever (write-once). No marker at all got row 4 G. | `InstallCohort.swift:263-274, 305-316` **[25a472e]**; this doc's rows 10–14, §5.9 item 4, §9.1. Holds. | **ACCEPT**, with one change to the proposed split: another platform's marker carries PD too, because it is write-once like corrupt bytes. Only isolation is `notRecorded`. | §5.4 (`Cohort.unreadable(priorDataPresent:)`, `.notRecorded`, `Reason.priorDataUnreadableMarker`); §5.5 row 4a and rows 10–14; §5.9 items 2, 4, 5; §8; §9.1 test; §9.2 mutations; §11 item 6. |
| r3-M1 | MINOR | §9.1, §9.2 and §11 item 10 still specified round 1's re-read of this launch's write, which round 2 had removed. | This doc's §9.1 marker-read bullet, §9.2 row-4 mutation, §11 item 10; `InstallCohort.swift:305-311, 210-214` **[25a472e]**. Holds. | **ACCEPT** | §5.5 row 4 (whether or not a marker was written); §5.9 item 3; §9.1; §9.2 (kept local vs key-after-write); §11 item 10. |
| r3-M2 | MINOR | "Exactly once" needs persisted state, but the scans forbade any other E3 key and any second grant write, including the copy repair. | This doc's §5.10, §5.6, §5.7, §9.3. Holds. | **ACCEPT** | §5.6 (what the scan allows); §5.7 table (the notice key) and one `writeGrantCopies(_:)`; §5.5 ("no access state on N"); §5.10 (the key's two flags, writes, unreadable bytes); §9.1; §9.2; §9.3. |
| r3-M3 | MINOR | `AppTransaction.originalPlatform` exists (iOS 18.4 / macOS 15.4); use it, with shape below those versions. | Apple's documentation JSON for `originalPlatform`, `AppStore.Platform` and `originalAppVersion`, read 2026-10-30; `project.yml:20-22`. The API exists as stated. The claim that it tells which numbering the value uses is not in Apple's text. | **ACCEPT, one refinement:** a disagreement that is below by shape stays **G**; one that is not below is **S**; never N. The cost (S on every launch for cross-platform accounts, E3-era ones included) is stated, and §10 Q7 asks about a date rule. | §5.3 (the rule, its invariant and its cost); §5.4 (`OriginalPlatform`); §5.5 rows 5, 6, 8, 11; §5.10; §9.1; §9.2; §10 Q7; §11. |
| r3-M4 | MINOR | A reused review device is grandfathered and never sees the IAP; "use a new macOS user account" is a request, not a mechanism. | This doc's §7.4, §5.2 (37 Mac releases, ASC GET 2026-10-30); `project.yml:74`; guideline 2.1(b) read 2026-10-30. Holds. | **ACCEPT** | §5.1; §7.4 (recording made by the owner, IAP review screenshot, note line, the drafted 2.1 reply, what the plan does not do); §10 Q8 (the read-only line, default not shown); §8; §9.4 V2. |
| r3-N1 | NIT | Row 0a pre-empts the broader PD, so round 2's "1.1 rider goes to row 4 instead of row 8" never happens; "support files" was undefined. | `AppModel.swift:540-582, 708, 754, 2894-2895` **[25a472e]**. Holds. | **ACCEPT**, the second of the review's two options: 0a's clause is kept, the false claim dropped, and the set defined exactly. | §5.5 row 0a; §5.9 item 1; §5.10 (`supportStoresPresent`, the directory excluded); §9.1 two-launch test; §9.2. |
| r3-N2 | NIT | "Every id resolves in the catalog" conflicts with corpus withdrawals and with "never shrinks". | `VocabStore.swift:172-185`; no recorded withdrawal list exists in the repo (grep, 2026-10-30). Holds. | **ACCEPT** | §2.2 (`DepthFreeSet.withdrawn`); §9.3; §9.2. |
| r3-N3 | NIT | §7.1's reading of §K's 0 km line was not labelled as the agent's. | `docs/PLAN-V1.37.md:430, 434`. Holds. | **ACCEPT** | §7.1 (labelled); §10 Q9. |
| r3-N4 | NIT | Nothing said the depth IAP is never promoted. | `grep -n "promot\|PurchaseIntent"` over this doc: no match before round 3; `docs/PLAN-V1.37.md:436`; ASC GET 2026-10-30 `promotedPurchases` `total 0`. Holds. | **ACCEPT** | §7.4 (not promoted; release-script read-back); §11. |
| r3-N5 | NIT | Marker citations and some "today" numbers were stale at 25a472e. | Every marker behaviour holds at 25a472e. The dictation pool is 5,928 at 25a472e (recounted 2026-10-30). Released builds are still 61 / 62 (ASC GET 2026-10-30); 62 / 63 are v1.37's own builds, on the release branch only. | **ACCEPT, in part:** re-cited by symbol at 25a472e; dictation refreshed. "61 and 62" is kept as the highest **released** builds, which is still true today, and 62 / 63 are added as v1.37's builds. | Header; §1; §5.1; §5.2; §5.3; §5.4; §5.7; §5.9; §9.2; §11. |

**After round 3,** a pre-E3 install is granted offline whatever state its marker is in: present and below `T` (row 2), absent with this launch's data visible (row 4), or unreadable with this launch's data visible (row 4a). A launch that row 0a catches is open for that session (S), and the first launch 0a does not catch is decided by those rows. `originalPlatform` can only turn an N into an S. E3 writes three things: two grant copies through one function, and one display-only key that no decision reads.
