# PLAN-V1.36 — readings on your lists, and 四人 taught as よにん

Written 2026-10-07 (JST). **The scope was fixed today, before the N = 100 reading** (projected
2026-10-19..29). No checkpoint figure chose it, and none may change it. The owner delegated the release
("你全权负责", and on 2026-10-07 "没办法再找我"). Method: a read-only understand-and-design workflow
(four lenses, three proposals from different angles, two judges, a synthesis). Its full output is outside
the repo, in `~/Library/Caches/NihongoRide-v136-work/design-result.json`. Every citation below was
re-read before this file was written.

## §A Why this, and not what PLAN-V1.34 §F listed

PLAN-V1.34 §F gave v1.36 four things:
* D3, documents written after moderated sessions. The sessions never ran, and they are owner-gated.
* D5, after the walk. Blocked.
* Session-driven fixes. There are none.
* D4, optional and never uploaded.

None of these is visible to a rider. "A release that carries nothing a rider can see is not shipped"
(PLAN-V1.34 §F). So v1.36 takes the open-surface defects that were recorded and never scheduled, plus
one corpus correction and the banked code-health work.

**Frozen, byte-identical to 1.35's build commit `fdb2b5f`:**
* the sources `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`, `RouteStore`,
  `EntitlementKit`, `Theme` and `ScaledFont`, and `xcode/NihongoRide.storekit`;
* the price and the IAP;
* all store metadata and screenshots.

Word Lists is not on the walk, so the walk card's "1.35 changes no screen the walk visits" carries over
to 1.36 unchanged.

## §B Precondition: disk

On 2026-10-07 the data volume had 1.0 GiB free and the Trash held 85 GB. That covers other sessions'
build output and this session's investigation copies. Moving things to the Trash frees nothing, because
it is the same volume, and only the owner empties the Trash. **No clone, build, render or archive starts
below 25 GiB free.** Check `df -h /System/Volumes/Data` before the first build and again before the
archive.

## §C The items, in order

**0. Code health, one reviewed merge before the rider items** (~0.9 day). Each fix gets a mutation shown
red.
* The three Swift 6.4 warnings that `swift build` reports:
  * `searchAnnouncement` needs to be `nonisolated static` (`ListsView.swift`);
  * `import Combine` is missing for `Timer` in `GameView.swift` and `PracticeView.swift`.
  The result must be zero `warning:` lines from `swift build` and `swift build --build-tests`. At archive
  time, grep the xcodebuild logs too.
* The corpus writers go through `corpus_io.CorpusFile`. Three scripts still rewrite whole files today:
  * `gen_examples.py`, at indent=2 with no final newline, against the shipped indent=1 plus a newline;
  * `enrich_verb_classes.py`;
  * `normalize_pos_tags.py`, whose comment claims "byte-for-byte the shipped layout".
  Tests go in the existing self-tests, so the gate count stays 17.
* `corpus_io` must refuse a CRLF file it cannot reproduce, rather than rewriting it as LF.
* CI: the gates job's `timeout-minutes` goes from 30 to 45. It has measured 13.5–21.8 minutes. A timeout
  is not a gate.

**1. Word Lists: a list's own words show their reading, and a long meaning wraps** (~0.6 day).
* `ListDetailView.wordRow` (`ListsView.swift`) draws only the surface and a one-line gloss.
  `.lineLimit(1)` cuts the gloss.
* The search results right above it draw surface / reading / gloss (`ListsView.swift:488-500`), with
  the rule `entry.surface == entry.kana ? nil : entry.kana`.
* Recorded as a defect in `PLAN-V1.33.md:86` ("list-detail rows without a reading") and never scheduled.
* The fix:
  * one shared helper for the reading rule, used by both call sites;
  * a reading line under the surface;
  * the gloss wraps;
  * the text column becomes a struct that takes `scale`, following `WordSearchResultRow`;
  * VoiceOver reads the word as one element (word, reading, gloss);
  * Remove stays its own button, keeping `removeWord-<id>`.
* No stored data, sync, order or list rule changes.
* Proof:
  * a hosted layout sweep at the default size and the five accessibility sizes, en and zh, kept to
    30 s or less of local runtime;
  * a value test of the helper;
  * the contrast table extended;
  * a mutation for each property;
  * `HorizontalTextFitTests.accepted` stays at 26 or lower;
  * `run_ios_placement_tests.sh` 13/13 before the merge, because `WordListSearchFlowTests` drives this
    screen;
  * the simulator pass.

**2. Word Lists: the Saved row draws its star once** (~0.15 day). The row's gold `star.fill` icon plus
the stored name "★ Saved" / "★ 收藏" show two stars (`PLAN-V1.33.md:86`). Only the row's display name
drops the leading "★ ". The stored name, the detail header and the add-to-list sheet keep it, because
they draw no icon. In the headless renders, `lists.png` is the one screen expected to differ, which
makes it v1.36's positive control.

**3. Corpus: `n5-kazoku` teaches 四人 as よにん** (~0.25 day).
* 家族は四人です。 is taught as かぞくはよんにんです (`n5.json`, exKana and the 四 token).
* The repo's own counter table says 四人 is よにん (`check_counter_readings.py`).
* In v1.35 it was left alone only because the audio arbiter was inconclusive (`PLAN-ITERATION.md`
  §D). v1.35 since set a standard for corrections the audio does not decide: grammar, plus two
  independent refuters, and "a tolerated casual pronunciation is not a reading to teach".
* **Upheld only 2 of 2.** Otherwise nothing changes, and it leaves What's New and the registration.
* The change: よん → よ in the 四 token and in exKana; 人 stays にん; token boundaries, the id and the
  headword are unchanged.
* It goes through `CorpusFile`, is declared in `docs/measurements/v136-reading-manifest.json`, and
  `release_numbers.CORPUS_MANIFEST` points to that manifest.

**4. Measure first: 何 + counter readings** (time-boxed at 0.5 day).
* Extend `check_counter_readings.py` with interrogatives (何時 なんじ, 何人 なんにん, 何回 なんかい, …). It
  is a sweep, not a gate.
* Calibration first:
  * it flags `n5-g022` on the pre-v1.35 tree `281fc45`;
  * it does not flag it on HEAD;
  * the population is at least 6,000 entries.
* Any hit that is not upheld 2 of 2 is recorded and left unchanged. "0 found, calibrated" is a valid
  result.

**5. Release mechanics** (~0.35 day).
* `check_versions.py --bump 1.36` gives macOS 61 / iOS 62.
* `scripts/submit_1_36.py` is config-only: `iap=None`, `DESCRIPTION_EDITS = {}`.
* `release_numbers.BASELINE_REF` moves from `281fc45` to `fdb2b5f`.
* The §K box (§E) is appended before `--submit`.

**6. §G proof, review, submit** (~2 days), as PLAN-V1.34 §G:
* first, the signing probe (console lock, keychain, the `/tmp/sigtest` codesign);
* `run_all_gates.sh` at FLOOR 17 on the final commit, before `--submit`;
* headless renders, en and zh, three runs each, against a same-day render of `fdb2b5f`. The intended
  difference is named per screen before the comparison is read. `road.png`, `road-iap-review.png` and
  `menu.png` must be identical;
* the simulator pass at default size and AX5, en and zh, on the 402pt iPhone and the iPad mini;
* the placement tests 13/13;
* two adversarial review rounds, with a frozen-surface lens (`git diff fdb2b5f`), a copy-versus-code
  lens and a mutation lens, plus a third round if round 2 finds a SERIOUS;
* `launch_gate.sh`, a curl of the live pages, a byte-exact read-back of every ASC write, and
  `ListAgents` before every write.

**7. Release day** (~0.25 day), per platform's Pacific date: `FIRM_RELEASE_DATES_PT` (one line per
platform if the dates differ), `stage1_walk` `EXPECTED_*` and fixtures, the walk card and drafts, the
cadence row, STATE, memory, and `review_watch` the same day.

**Total:** about 5 agent-days.
* Code health merged by ~10-16.
* Items 1–4 by ~10-28.
* §G and the reviews 10-28 .. 11-03.
* **Target submit: 2026-11-05 JST**, in PLAN-V1.34 §F's slot, both platforms together, not before 11-02.

## §D Cut rules

* **If item 1 has not passed §G and review by 2026-11-02, v1.36 is not submitted.** The star alone does
  not justify a release, and neither does one corpus sentence. Items 0 and 2–4 stay merged on main for
  the next release.
* Items 3 and 4 are each cut on their own evidence rule, independently of the release.
* A frozen-surface diff found in review is reverted, never argued away.
* The N = 100 reading, which will probably land mid-build, does not change scope and adds no §K rule.
  Rule 4 is applied before it is run.

## §E The §K registration (draft, appended to PLAN-STAGE1 §K before `--submit`; bracketed lines follow what shipped)

> ### 📌 REGISTERED <YYYY-MM-DD> (JST) under constraint 3, before v1.36 is submitted — readings on a word list's own rows, one star on the Saved row, and 四人 taught as よにん
>
> **What changed.**
> 1. On a list's screen, each word now shows its reading by the rule the search results on that screen
>    have used since v1.35, and a long gloss wraps. Display only: no word is added, removed or reordered.
> 2. The Saved list's row shows its star once. The stored name is unchanged.
> 3. [`n5-kazoku`'s 四人 now reads よにん, per `docs/measurements/v136-reading-manifest.json` (grammar and
>    2-of-2 refuters). It stays withheld from dictation. Sweep: <n corrections / none found>.]
> 4. Nothing a rider sees: compiler warnings, the corpus writers' write path, CI's timeout.
>
> The offer screen, the Settings road card, the menu route strip, prices, About's counter text and the
> store metadata are unchanged. `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`,
> `RouteStore` and `EntitlementKit` are byte-identical to `fdb2b5f`.
>
> **Expected effect.**
> * The list rows: neutral to up on days-ridden; magnitude unmeasurable.
> * The star: neutral.
> * The corrected sentence is one kana shorter: 90 m instead of 100 m when ridden
>   (`GameSession.swift:825`), against 25,000 m to Kyōto. Negligible.
> * Cadence: the first release in about five weeks. Its release days raise first-time downloads; the
>   longer gap lowers the weekly rate. A fraction of one day's installs either way.
>
> **How to read a checkpoint against it.** `3/N` does not move. Near a threshold, split the cohort at
> v1.36's `FIRM_RELEASE_DATES_PT` entries.

## §F What's New (drafts; each sentence is re-checked against the merged code; no ★)

* en: "Word Lists: on a list's page, the list's words now show their reading underneath, as the
  dictionary search results there already do, and a long meaning wraps instead of being cut off." /
  "Word Lists: the Saved list's row shows its star once instead of twice." / [the 四人 sentence]
* zh-Hans: "单词表:在词单页面里,词单中的词下方现在会显示读音,与该页面词库搜索结果的显示方式相同;较长的释义会换行显示,不再被截断。"
  / "单词表:「收藏」词单那一行的星标现在只显示一次。" / [四人]
* ja: "単語リスト:リストのページで、単語の下に読みが表示されるようになりました(辞書検索の結果と同じ表示です)。長い意味は省略されず、折り返して表示されます。"
  / "単語リスト:「Saved」リストの行の星が1つだけになりました。" / [四人]

## §G Not in v1.36, with the reason

* **The denied-reminder notice.** It is a modal on the Settings screen, which carries entrance #1, and
  PLAN-V1.34 §I deferred it by name.
* **About copy, the Settings sync caption, a device-language default, a Japanese UI.** All are frozen or
  walk-visited surfaces, or they change which presentation of the offer a territory sees (constraint 1).
  They go on the day-91 list.
* **The Verbs HUD narrow-iPad sweep, the AX1 drill card, and the keyboard-down ★ overlap.** The first two
  are unmeasured, and the third has a measured cost. They go to v1.37, measured first.
* **Sharding `swift test`, a faster vocab self-test, `check_vocab_diff` reading `passages.json`.** These
  are gate-runner changes. They come after a release, not inside one.
* **`n5-kuru`, `n3-b653`, `n2-k006`, `n1-b1232`.** These need a human, or they change a headword's
  identity.
* **B2's improvements.** There is still no evidence that anyone pastes.
* **D3, D4, D5, §E, and session-driven fixes.** These are owner-gated.
* **The privacy page's local-storage list.** It is prepared in `site/` only. Pushing it to the live site
  is the owner's call, and the release does not wait on it.
* **Anything on the frozen list, TestFlight, telemetry, a second SKU, acquisition work.**

## §H Record

**Items 0–4 merged on 2026-10-07 (JST).**
* **Item 0, code health.**
  * The Swift warnings are fixed in `da462c4`. `swift build` and `swift build --build-tests` print none.
  * The corpus writers, the CRLF refusal and the CI timeout are merged in `a6f2bfe`. That merge
    includes `gen_passages.py`, which a review found also wrote whole files.
  * On `a6f2bfe`, `run_all_gates.sh` ran 17 gates with 0 failures.
* **Items 1–2, Word Lists**, merged in `022f94a`. Three review lenses ran, and the fix round landed
  in `a2b5836`. It changed three things beyond the plan's text:
  * at the accessibility sizes, Remove now stacks under the word, as the search row's button does.
    The fixer counted 1,476 English glosses (the review: 1,469) that broke mid-word beside the button at AX5 on a
    320pt phone. 46 single words wider than the whole line remain, all at AX4–AX5 on the 320pt
    phone.
  * the gloss and the removed-word note now scale with body text. On iOS they are slightly smaller
    than the old `.caption` / `.caption2` above the default size. On the Mac the gloss is 2pt larger.
  * `HorizontalTextFitTests.accepted` went from 26 to 25.
* **Items 3–4, corpus**, merged in `de1e3b9`.
  * 四人 → よにん was upheld 2 of 2, both votes at high confidence.
  * The sweep is calibrated on `n5-g022` against a population of 6,724. Its only other hit is
    `n2-b937` 何分, which is the adverb なにぶん; both refuters rejected it, so nothing changed.
  * `BASELINE_REF` moved to `fdb2b5f` in this merge rather than in item 5.
  * `v136-counter-sweep.json` records the tree before the correction (`fae6b8e`), so it still lists
    `n5-kazoku`.
  * Known and accepted: in this one sentence, the 四 token (now よ) no longer links to the 四 (よん)
    card in the stumble chip, because that card's reading is not the one taught here.
* **Source diff against `fdb2b5f`:** `ListsView.swift`, `GameView.swift` and `PracticeView.swift`
  (one import each), and `n5.json` (two lines). Every frozen source is byte-identical.
* **Still owed:** item 5 (bump, submit script, registration), item 6 (`run_ios_placement_tests.sh`,
  the simulator pass, the headless renders, two whole-release review rounds) and item 7.

