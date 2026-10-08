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

> ### 📌 REGISTERED <YYYY-MM-DD> (JST) under constraint 3, before v1.36 is submitted — readings on a word list's own rows, one star on the Saved row, and nine example sentences' number + counter readings corrected
>
> **What changed.**
> 1. On a list's screen, each word now shows its reading by the rule the search results on that screen
>    have used since v1.35, and a long gloss wraps. Display only: no word is added, removed or reordered.
> 2. The Saved list's row shows its star once. The stored name is unchanged.
> 3. [Nine example sentences now teach the standard number + counter reading, per
>    `docs/measurements/v136-reading-manifest.json` (grammar and 2-of-2 refuters; exKana and one token
>    each): `n5-kazoku` 四人 よにん; 四月 しがつ (`n5-b303`, `n2-b942`); 九時 くじ (`n5-b071`, `n4-g180`,
>    `n3-b750`); 二十四時間 にじゅうよじかん (`n5-b018`); 四時間 よじかん (`n1-b615`); 四字熟語 よじじゅくご
>    (`n2-b072`). All nine stay withheld from dictation. Sweep: the calibrated tables cover the
>    lexicalised counters, 何 + counter, and 月 / 時 / 時間 / 字 after a last digit 4, 7 or 9; inside that
>    scope 0 mismatches remain and one tolerated reading is left as it is (`n5-b334` 七時 ななじ). Outside
>    it, sentences with the same kind of defect are recorded by id in PLAN-V1.36 §I and not corrected.]
> 4. Nothing a rider sees: compiler warnings, the corpus writers' write path, CI's timeout.
>
> The offer screen, the Settings road card, the menu route strip, prices, About's counter text and the
> store metadata are unchanged. `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`,
> `RouteStore` and `EntitlementKit` are byte-identical to `fdb2b5f`.
>
> **Expected effect.**
> * The list rows: neutral to up on days-ridden; magnitude unmeasurable.
> * The star: neutral.
> * Eight of the nine corrected sentences are one or two kana shorter, so each rides 10–20 m less
>   (`GameSession.swift:825`, 10 m per kana of the sentence's exKana): `n5-kazoku` 100 → 90 m,
>   `n5-b303` 240 → 230, `n2-b942` 280 → 270, `n5-b071` 210 → 190, `n4-g180` 180 → 160, `n3-b750`
>   170 → 150, `n5-b018` 180 → 170, `n2-b072` 280 → 270; `n1-b615` keeps its length (260 m). The
>   sentence's score base and time baseline (`GameSession.swift:842`, `:847`) move with the same kana
>   count. Against 25,000 m to Kyōto: negligible.
> * Cadence: the first release in about five weeks. Its release days raise first-time downloads; the
>   longer gap lowers the weekly rate. A fraction of one day's installs either way.
>
> **How to read a checkpoint against it.** `3/N` does not move. Near a threshold, split the cohort at
> v1.36's `FIRM_RELEASE_DATES_PT` entries.

## §F What's New (drafts; each sentence is re-checked against the merged code; no ★)

* en: "Word Lists: on a list's page, the list's words now show their reading underneath, as the
  dictionary search results there already do, and a long meaning wraps instead of being cut off." /
  "Word Lists: the Saved list's row shows its star once instead of twice." / [the corrections sentence]
* zh-Hans: "单词表:在词单页面里,词单中的词下方现在会显示读音,与该页面词库搜索结果的显示方式相同;较长的释义会换行显示,不再被截断。"
  / "单词表:「收藏」词单那一行的星标现在只显示一次。" / [corrections]
* ja: "単語リスト:リストのページで、単語の下に読みが表示されるようになりました(辞書検索の結果と同じ表示です)。長い意味は省略されず、折り返して表示されます。"
  / "単語リスト:「Saved」リストの行の星が1つだけになりました。" / [corrections]
* The corrections sentence, drafted 2026-10-09 for the nine entries the manifest declares (one sentence
  for all nine; the copy must name exactly what the manifest declares):
  * en: "Corrected the reading of a number with its counter in nine example sentences: for example,
    四月 is now read しがつ, 九時 くじ and 四人 よにん, the standard readings, instead of よんがつ, きゅうじ
    and よんにん."
  * zh-Hans: "更正了九条例句中数字与量词的读音:例如「四月」现在读作标准读音 しがつ,「九時」读作 くじ,「四人」读作
    よにん,不再是 よんがつ、きゅうじ、よんにん。"
  * ja: "9 つの例文で、数字と助数詞の読みを訂正しました(例:「四月」は よんがつ ではなく しがつ、「九時」は きゅうじ
    ではなく くじ、「四人」は よんにん ではなく よにん)。"
  * `scripts/submit_1_36.py` still carries the one-correction copy. It refuses to run on this tree
    (`correctedThisRelease` 9 ≠ 1), which is its guard working. Its copy, review note 3 ("one example
    sentence's reading was corrected") and guard are rewritten for the nine after `fix/v136-r1-ui`
    (`7adb59e`), which replaces that same guard with a named-entry check, is merged — not here, where the
    two edits would conflict.

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

**2026-10-09 (JST), §I's 8 counter corrections applied and declared** (R1 step 3 and its fix round,
branch `feat/v136-corpus-2-fix`; `db467aa`, `069d34d` and the record commit after them).
* **The corrections**, each upheld 2 of 2 by independent refuters at high confidence, written through
  `CorpusFile`: one token's reading and the matching stretch of exKana per sentence, 16 lines of
  n1–n5.json and no others.
  * `n5-b303` 四月一日から新しい学校に行きます。 四月 よんがつ → しがつ (四 よん → し);
  * `n2-b942` 兄は今年の四月に貿易会社に入社した。 四月 よんがつ → しがつ (四 よん → し);
  * `n5-b071` 明日の午前九時に病院へ行きます。, `n4-g180` 電車は九時に出発します。 and `n3-b750`
    午前九時に試合を開始する。: 九時 きゅうじ → くじ (九 きゅう → く);
  * `n5-b018` 一日は二十四時間あります。 二十四時間 にじゅうよんじかん → にじゅうよじかん (二十四 にじゅうよん →
    にじゅうよ);
  * `n1-b615` 会議は三時間乃至四時間ほどかかる予定です。 四時間 しじかん → よじかん (四 し → よ);
  * `n2-b072` 漢字のテストに向けて、四字熟語をたくさん暗記した。 四字熟語 よんじじゅくご → よじじゅくご
    (四 よん → よ).
  * Not changed: `n5-b334` 七時 ななじ, tolerated usage, flag-only.
* **Declared** in `v136-reading-manifest.json`: 9 entries, each with its exact before and after;
  `correctedThisRelease` 1 → 9. `run_all_gates.sh --vocab-only` (local, `BASELINE_REF` fdb2b5f) is
  green; removing any one of the 27 declarations (an entry, or its exKana or exTokens) turns
  `check_vocab_diff.py` red naming only that id. `check_vocab_diff` checks that a declared field moved,
  not what it moved to. The value-level proof is `check_counter_readings.py --calibrate` on `069d34d`
  (`v136-counter-sweep-3.json`): 42/42 calibration checks, 0 mismatches, `n5-b334` flag-only. The same
  table flags all 8 on fdb2b5f.
* **Calibration strengthened first** (`db467aa`): 七月 / 九月 / 四時 / 九時間 / 四字 logic checks, and (h),
  a planted tree with a wrong reading in every file and kind of field for each table. All 18 mutants
  are killed. 16 of them were also run on the previous version, and 12 of those passed its 34 checks.
* **Dictation:** all nine stay withheld. `dictation-exclusions.json` is byte-identical to fdb2b5f; 785
  excluded, pool 5,939. The 8 evidence rows' exKana follow the corpus, each according to what its
  complaint now says. Six were instrument 2's own complaint (四 よん → し, 九 きゅう → く, 四 し → よ),
  so they take n2-b304's v1.31 shape: complaint kept with "the corpus has since been corrected to …",
  evidence `stale-after-correction (v1.36)`. Instrument 2 having named the corrected reading is
  corroboration (67% measured agreement), not proof. For `n2-b072`, instrument 2 named よう, not the
  corrected よ, and the row says so. `n5-b018` keeps `proven`: its complaint is the 一日 span, which did
  not move.
* **Known and accepted (stumble chip)**, simulated on `VocabStore`'s pair index (surface + reading,
  ambiguous keys dropped); no test pins these ids:
  * the three 九 tokens (`n5-b071`, `n4-g180`, `n3-b750`) now link to `n5-b057` 九 く "nine", a card with
    no example sentence, instead of `n5-g009` 九 きゅう;
  * the 四 tokens of `n5-b303`, `n2-b942` (now し) and `n2-b072` (now よ) no longer link to `n5-g004`
    四 よん, the same trade-off as `n5-kazoku`;
  * `n1-b615` (四 し → よ) and `n5-b018` (二十四) link to no card before or after.
* **Rider-visible:** eight of the nine sentences ride 10–20 m less (§E lists each).
* **Source diff against `fdb2b5f`, now:** `ListsView.swift`, `GameView.swift`, `PracticeView.swift`,
  and n1–n5.json, 18 lines (n5.json 8, n2.json 4, n1, n3 and n4.json 2 each). Every frozen source is
  still byte-identical.
* **Not run:** `swift test --filter 'VocabKit|CorpusEscapeResidue|ExampleSentence'`. Free disk was
  23.4 GiB at the start of this round and 20.7 GiB at its end, under §B's 25 GiB floor for any build.
  Owner-gated: only the owner empties the Trash. A Python replica of
  `ExampleSentenceTests.exclusionEvidenceIsCurrent` reads 785/785 rows with 0 stale; on the previous
  evidence file it reports the 8.
* **Owed before submission:** `submit_1_36.py`'s copy and guard for the nine (§F), after
  `fix/v136-r1-ui` merges.

## §I Scope addendum, 2026-10-09 (JST) — before the N = 100 reading

The whole-release review, round 1, found 8 shipped sentences whose taught number + counter readings
item 4's tables cannot see. It ran over `fdb2b5f..ba77c13`: five lenses, with two refuters for every
non-NIT finding; the record is in `~/Library/Caches/NihongoRide-v136-work/review-r1.json`.
* 四月 taught よんがつ, in `n5-b303` and `n2-b942`;
* 九時 taught きゅうじ, in `n5-b071`, `n4-g180` and `n3-b750`;
* 二十四時間 taught にじゅうよんじかん (`n5-b018`), 四時間 taught しじかん (`n1-b615`), and 四字熟語 taught
  よんじじゅくご (`n2-b072`);
* 七時 taught ななじ (`n5-b334`), which is tolerated usage.

All 8 are already withheld from dictation. **Item 4 is extended, not replaced,** to month, hour,
duration and 字 counters, under the same rules:
* a calibrated table first, which must flag these on the current tree;
* each hit upheld 2 of 2 by independent refuters, or left unchanged;
* every write through `CorpusFile`, declared in the v1.36 manifest.

A tolerated reading such as ななじ is flagged for a person, not corrected. The release date and the
cut rules do not change. This is recorded today, before the N = 100 reading (projected 10-19..29), so
no checkpoint figure chose it.

The same round's other findings are fixed in this release:
* the scaled list-row text gets an 11 pt floor below the default size;
* the Saved row's star icon is pinned by a test;
* a removed word's Remove label no longer reads its internal id;
* `submit_1_36.py` checks which entries it names, not how many;
* the sweep's population floor is applied to the right table;
* the zh What's New calls the screen 词单, as the app does;
* the §E registration lists every rider-visible change.

Recorded for v1.37, not done here: nothing yet beyond the round's NITs.

**Found 2026-10-09 by the fix review of the 8 corrections, and recorded by id, not corrected.** These
have the same kind of defect: a number + counter reading without its sound change. They sit outside
the table above, which enumerates only 月 / 時 / 時間 / 字. Nothing here changes them. The 2-of-2 rule
applies, and no calibrated table sees them yet. Each was re-read in the corpus on 2026-10-09 (exJP,
the covering tokens and exEN):
* 三千円 taught さんせんえん (standard さんぜん): `n1-b439` and `n3-b781`, **both in the dictation pool**.
  If the voice says さんぜん (plausible, not measured), a rider typing what they hear is refused at ぜ.
* 十分 meaning "ten minutes" (by exEN) taught じゅうぶん: `n3-b020` 駅からおよそ十分歩きました。, **in the
  dictation pool**. This round's own scan found it; the review did not list it.
* 分 without its sound change: `n1-b1630` 三分 さんふん (さんぷん); `n2-b449` 三十分 さんじゅうぶん; 十分
  "ten minutes" taught じゅうふん in `n1-b1147`, `n1-b1841`, `n2-b311` and `n4-b127` (v1.25 corrected
  `n1-b1516` to じっぷん); `n1-b327` 五分 (a five-minute walk) ごぶん.
* っ missing: `n2-b479` 一軒 いちけん (いっけん); `n1-b957` 一階 いちかい (いっかい).
* For a person to judge, as tolerated-class candidates: `n4-g171` 三階 さんかい (in the pool; さんがい is
  the traditional form), and 三十歳 / 八十歳 taught …じゅうさい (`n3-b123`, `n1-b311`, `n1-b1450`).

Either an addendum made before the N = 100 reading extends the counter table under the same
calibrate-then-2-of-2 rules (分 ぷん / ふん, 軒 and 階 with っ, 三千 ぜん), or these go to v1.37 as listed.
The three pool sentences (`n1-b439`, `n3-b781`, `n3-b020`) come first either way. Until then, §E's
sweep line states the table's scope, not "none found".

### §I addendum 2, 2026-10-09 (JST), later the same day — still before the N = 100 reading

The data-lens review of the §I corrections scanned every numeral token followed by a counter, and found
more sentences with the same defect, a number + counter sound change taught wrong:
* 三千円 taught さんせんえん, in `n1-b439` and `n3-b781`. **Both are in the dictation pool**, so a rider
  who types what the voice says is marked wrong;
* 三分 さんふん (`n1-b1630`), 三十分 さんじゅうぶん (`n2-b449`), and 五分 ごぶん (`n1-b327`);
* 十分 meaning "ten minutes", taught じゅうふん, in `n1-b1147`, `n1-b1841`, `n2-b311` and `n4-b127`;
* 一軒 いちけん (`n2-b479`) and 一階 いちかい (`n1-b957`).

Some are tolerated readings and are flagged, never corrected: 三階 さんかい, and 三十歳 / 八十歳 read with
じゅうさい.

**Item 4 is extended a second time** to the sound-changing counters: 分, 千, 百, 軒, 階, 回, 歳, 本, 杯,
匹, 個, 冊, 点 and 泊. The rules are the same: a calibrated table that must flag the sentences above; each hit
upheld 2 of 2, or left unchanged; writes through `CorpusFile`; everything declared in the v1.36 manifest.

The release date and the cut rules do not change. What's New and the review notes are rewritten once the
set is final, and `submit_1_36.py` refuses to run until they name it.

