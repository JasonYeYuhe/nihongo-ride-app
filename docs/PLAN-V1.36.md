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

> ### 📌 REGISTERED <YYYY-MM-DD> (JST) under constraint 3, before v1.36 is submitted — readings on a word list's own rows, one star on the Saved row, and twenty-two example sentences' number + counter readings corrected (four of them leave the dictation pool)
>
> **What changed.**
> 1. On a list's screen, each word now shows its reading by the rule the search results on that screen
>    have used since v1.35, and a long gloss wraps. Display only: no word is added, removed or reordered.
> 2. The Saved list's row shows its star once. The stored name is unchanged.
> 3. [Twenty-two example sentences now teach the standard number + counter reading, per
>    `docs/measurements/v136-reading-manifest.json` (grammar and 2-of-2 refuters; exKana and one or two
>    tokens each): `n5-kazoku` 四人 よにん; 四月 しがつ (`n5-b303`, `n2-b942`); 九時 くじ (`n5-b071`,
>    `n4-g180`, `n3-b750`); 二十四時間 にじゅうよじかん (`n5-b018`); 四時間 よじかん (`n1-b615`); 四字熟語
>    よじじゅくご (`n2-b072`); 三千 さんぜん (`n1-b439`, `n3-b781`); 八十点 はちじゅってん (`n3-b678`); 三分
>    さんぷん (`n1-b1630`); 三十分 さんじゅっぷん (`n2-b449`); 五分 ごふん (`n1-b327`); 十分 'ten minutes'
>    じゅっぷん (`n1-b1147`, `n1-b1841`, `n2-b311`, `n3-b020`, `n4-b127`); 一軒 いっけん (`n2-b479`); 一階
>    いっかい (`n1-b957`).
>    **The dictation pool shrinks by 4, from 5,939 to 5,935** (`release_numbers`: withheldThisRelease 4).
>    Four of the corrected sentences were in it: `n1-b439`, `n3-b781`, `n3-b678` and `n3-b020`. Dictation
>    speaks the unchanged Japanese and grades what a rider types against the sentence's kana, so a
>    corrected sentence may stay only where the voice is proven to say the corrected reading. In
>    `n3-b020` the voice is proven to say the old じゅうぶん (instrument 1b), so grading it against
>    じゅっぷん would refuse a rider who types what they hear; in the other three it is not proven either
>    way (1b silent; `docs/measurements/v136-dictation-remeasure.json`). All four are withheld from
>    dictation, as v1.35 withheld `n5-g022`: they teach the right reading in Sentence mode, and dictation
>    is not graded where the voice may say something else. The other eighteen were withheld before and
>    stay withheld. Sweep: the calibrated tables cover the lexicalised counters, 何 + counter, 月 / 時 /
>    時間 / 字 after a last digit 4, 7 or 9, and the sound-changing counters 分 軒 階 回 歳 本 杯 匹 個 冊 点
>    泊 and 千 / 百 after a digit. Inside that scope no mismatch remains. Five tolerated readings are
>    left as they are (`n5-b334` 七時 ななじ, `n4-g171` 三階 さんかい, …じゅうさい in `n3-b123`, `n1-b311`
>    and `n1-b1450`). Outside that scope the sweep claims nothing.]
> 4. Nothing a rider sees: compiler warnings, the corpus writers' write path, CI's timeout.
>
> The offer screen, the Settings road card, the menu route strip, prices, About's counter text and the
> store metadata are unchanged. `SettingsView`, `MenuView`, `AboutView`, `OnboardingView`, `RoadView`,
> `RouteStore` and `EntitlementKit` are byte-identical to `fdb2b5f`.
>
> **Expected effect.**
> * The list rows: neutral to up on days-ridden; magnitude unmeasurable.
> * The star: neutral.
> * Eight of the twenty-two corrected sentences are one or two kana shorter, so each rides 10–20 m
>   less (`GameSession.swift:825`, 10 m per kana of the sentence's exKana): `n5-kazoku` 100 → 90 m,
>   `n5-b303` 240 → 230, `n2-b942` 280 → 270, `n5-b071` 210 → 190, `n4-g180` 180 → 160, `n3-b750`
>   170 → 150, `n5-b018` 180 → 170, `n2-b072` 280 → 270; `n1-b615` keeps its length (260 m). The
>   thirteen sound-change corrections swap kana one for one (さんせん → さんぜん, じゅうふん and
>   じゅうぶん → じゅっぷん, いち → いっ), so each keeps its length too: `n1-b439` 210 m, `n3-b781` 210,
>   `n3-b678` 250, `n1-b1630` 220, `n2-b449` 270, `n1-b327` 290, `n1-b1147` 210, `n1-b1841` 230,
>   `n2-b311` 290, `n4-b127` 200, `n2-b479` 220, `n1-b957` 190, `n3-b020` 180. The sentence's score
>   base and time baseline (`GameSession.swift:842`, `:847`) move with the same kana count, so only the
>   eight shorter ones change. Against 25,000 m to Kyōto: negligible.
> * Dictation: 4 of 5,939 pool sentences withheld (5,935 remain), all from N1 and N3. Neutral.
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

**2026-10-09 (JST), §I addendum 2: 12 sound-change corrections applied and declared, 1 upheld and held
back** (branch `feat/v136-corpus-3`, on the sweep commit `0a4e354`; `766c092` and `d806b0e`).
* **The corrections.** Each was upheld 2 of 2 by independent refuters at high confidence, and each was
  written through `CorpusFile`. Each changes exKana and the affected token readings only: 29 lines of
  n1–n4.json and no others. Where two forms are standard, the corpus takes the more common one:
  じゅっぷん, not じっぷん, and はちじゅってん, not はちじってん. `n1-b1516` keeps the じっぷん that v1.25 gave
  it, and the table accepts both.
  * `n1-b439` 会費は全員一律で三千円です。 and `n3-b781` 食事代の合計は三千円でした。: 三千 さんせん → さんぜん;
  * `n3-b678` このクラスのテストの平均点は八十点だ。: 八十点 はちじゅうてん → はちじゅってん (八十 → はちじゅっ);
  * `n1-b1630` カップ麺に熱湯を注いで三分待った。: 三分 さんふん → さんぷん (分 → ぷん);
  * `n2-b449` 今日以後は毎日三十分の運動を続ける。: 三十分 さんじゅうぶん → さんじゅっぷん (三十 → さんじゅっ,
    分 → ぷん);
  * `n1-b327` 彼女の勤め先は駅から歩いて五分のところにある。: 五分 ごぶん → ごふん (分 → ふん);
  * 十分 'ten minutes' じゅうふん → じゅっぷん (十 → じゅっ, 分 → ぷん), in `n1-b1147` 駅から会社まで徒歩十分弱だ。,
    `n1-b1841` ここから駅まで歩いて十分ぐらいかかる。, `n2-b311` 集合時間の前後十分は入口で待っています。 and
    `n4-b127` 駅から家まで十分ほど歩きます。;
  * `n2-b479` この近くに古い貸家が一軒建っている。: 一軒 いちけん → いっけん (一 → いっ);
  * `n1-b957` 受付は本館の一階にあります。: 一階 いちかい → いっかい (一 → いっ).
* **Held back: `n3-b020`** 駅からおよそ十分歩きました。, which teaches 十分 'ten minutes' as じゅうぶん. It was
  upheld 2 of 2, and it is in the dictation pool.
  * Calibrated instrument 1b proves the voice says じゅうぶん there: the span is byte-identical to the
    exJP audio, sha1 `cf14d6d9a386`. Instrument 1 agrees on the whole kana.
  * So じゅっぷん would refuse every rider who types what they hear, and withholding the sentence would
    shrink the pool, which the apply step forbids. It therefore stays as 1.35 shipped it.
  * Its votes and the evidence are in `v136-dictation-remeasure.json`. So is the alternative: correct it
    AND withhold it, taking the pool from 5,939 to 5,938, which was v1.35's precedent for `n5-g022`. That
    choice is the release owner's. *(Decided 2026-10-09: corrected and withheld; see "the dictation
    decisions" below.)*
* **The other three pool corrections** (`n1-b439`, `n3-b781`, `n3-b678`) were re-measured with 1b on
  the corrected tokens, the way v1.35 round 3 measured `n5-g022`: on a scratch copy, with 0 spurious
  matches in 8 decoys and 0 contradictions of instrument 1 in 39. 1b is silent on all three, so the voice
  is not proven to say the corrected reading.
  * Instrument 2 flags neither `n1-b439` nor `n3-b781` as corrected, and would have flagged each as
    1.35 shipped it, had さんぜん been one of its candidates. For `n3-b678` it is a tie, and it goes
    against the correction: with はちじっ a candidate, as it was when the shipped state was judged, it
    flags the corrected sentence (はちじっ 0.06541, はちじゅっ 0.06590, はちじゅう 0.06594). *(Corrected
    by the fix round below: this bullet first said instrument 2 flags none of the three, and gave the
    shipped state's distance as 0.0703, the は spelling alone, where `nearest()` takes the わ
    spelling's 0.06594.)*
  * The span comparatives, which are uncalibrated, favour the correction for `n3-b781` and are a
    three-way tie for `n3-b678`. For `n1-b439` they mostly favour it: only the さんぜん円 render points
    at さんせん (0.0120 against 0.0539), and that render is 0.24 s longer than the exJP audio.
  * They stay in the pool because the apply step requires it, against `n5-g022`'s precedent of
    withholding on silence. **`n3-b678` is the one for a person to look at** (DECISION NEEDED in the fix
    round below). This bullet first named `n1-b439`. *(Decided 2026-10-09: all three withheld; see "the
    dictation decisions" below.)*
* **Dictation:** the pool stays 5,939 and `dictation-exclusions.json` is untouched. The nine withheld
  rows' exKana follow the corpus, each according to what its complaint now says:
  * `n1-b327`, `n2-b479`, `n1-b957`: instrument 2 had named the corrected reading, so they take the
    n2-b304 shape, stale-after-correction;
  * `n2-b449`: the same, plus 三十, a token the flag did not name;
  * `n1-b1147` and `n1-b1630`: instrument 2 had named another reading (ぶん, わけ), so they take the
    n2-b072 shape;
  * `n1-b1841`, `n2-b311`, `n4-b127`: the voice is proven to say じゅうぶん, which the corrected
    じゅっぷん still is not, so they keep 'proven' with a note, as `n5-b018` did. `dictationProvenMisread`
    stays 239.
* **Declared** in `v136-reading-manifest.json`: 12 rows, with both votes verbatim except for paths.
  `correctedThisRelease` goes from 9 to 21.
  * `run_all_gates.sh --vocab-only` (local, `fdb2b5f` + the manifest) is green.
  * It goes red, naming only that id, when one declaration is dropped: the whole `n2-b479` entry,
    `n3-b678`'s exTokens alone, or `n1-b439`'s exKana alone.
  * Joined exTokens equal exKana on all 6,724 sentences.
* **Values:** `check_counter_readings.py --calibrate` on the corrected tree passes 82/82
  (`v136-counter-sweep-5.json`; 83/83 since the fix round below added (m0)).
  * The counter table finds 1 mismatch, `n3-b020`, which was held back, and 5 tolerated flag-only
    readings.
  * (i) flags all 13 of addendum 2's mismatches on `3d891b9` and on `fdb2b5f`, the corpus 1.35 shipped;
    `n3-b678`, which this table found itself, is now pinned.
  * (l) reads `3d891b9` with that tree's own exclusions.
  * (m), new, inspects each of the 12 on the working tree and passes it in both fields, taught exactly
    the corrected reading.
  * 9 mutants were run on scratch copies, each named for the check it must turn red, and all 9 were
    killed.
* **`swift test --filter 'VocabKit|CorpusEscapeResidue|ExampleSentence'`:** passed, 81 + 26 tests, in this
  worktree's own build root. Free disk was 17 GiB, under §B's 25 GiB floor; the apply step allowed this
  one SwiftPM build. `exclusionEvidenceIsCurrent` and "token readings reconstruct exKana" are among the
  passes.
* **Known and accepted (stumble chip)**, simulated on `StumbledWords.entryID` itself (ported to Python
  and run on both trees). *(Corrected by the fix round below: this was first simulated on `VocabStore`'s
  pair index alone, which skips entryID's bound-morpheme filter, and said `n1-b327`'s 分 now links to
  `n1-b655`.)*
  * `n1-b327`'s 分 (now ふん) and `n2-b449`'s 分 (now ぷん) lose their link to `n3-b389` 分 ぶん, whose
    glosses include "minute of time", and link to no card;
  * the other five 分 tokens (`n1-b1630` and the four 十分: ふん before, ぷん now) link to no card before
    or after. `n1-b655` 分 ふん 'minute' is a suffix (`n`, `suf`), and the chip never names one
    (`JapaneseParticles.boundPartsOfSpeech`);
  * the four 十 tokens (now じゅっ) no longer link to `n5-g010` 十 じゅう, and the two 一 tokens (now いっ)
    no longer link to `n5-g001` 一 いち;
  * 三千, 三十 and 八十 link to no card before or after.
* **Rider-visible:** none of the 12 changes its kana count, so none rides a different distance (§E lists
  each).
* **Source diff against `fdb2b5f`, now:** `ListsView.swift`, `GameView.swift`, `PracticeView.swift`, and
  n1–n5.json, 47 lines (n1.json 16, n2.json 12, n5.json 8, n3.json 6, n4.json 5). Every frozen source
  is still byte-identical.
* **Owed:** What's New, the review notes and `submit_1_36.py` must name this set: 21 corrected,
  `n3-b020` not among them.

**2026-10-09 (JST), fix round on addendum 2's record** (branch `feat/v136-corpus-3-fix`, on `a849909`).
The review of the apply step raised 7 findings, 2 SERIOUS and 5 MINOR. Each was re-measured here with
the repo's own instruments: the Kyoko compact voice, audio cached outside the repo, read-only on the
corpus. All 7 reproduce. **No corpus file changes:** the pool stays 5,939 and `correctedThisRelease`
stays 21. The entry above is corrected in place where it was wrong, each place marked.
* **`n3-b678` is the open pool sentence, not `n1-b439`** (SERIOUS). The re-measure misreported
  instrument 2, `check_dictation_readings.nearest()`, which takes the minimum over particle spellings:
  * as 1.35 shipped it, own はちじゅう is 0.06594 (the わ spelling). The 0.0703 recorded was the は
    spelling alone. はちじゅっ is nearer by 0.00004, not 0.0044, and はちじっ is nearer by 0.0005;
  * on the corrected tokens, with はちじっ and はちじゅう as candidates (the ones the re-measure declared
    for 1b and used to judge the shipped state), it FLAGS the sentence: はちじっ 0.06541 < はちじゅっ
    0.06590. It reported "not flagged" only because its own candidates for 八十 are やそ alone;
  * 1b is silent on 18 distinct span texts (八十, 八十点, 八十点だ, は八十点, 平均点は八十; hiragana and
    katakana), and instrument 1 on all six whole-kana spellings;
  * the uncalibrated leads disagree. Hiragana span: はちじゅう 0.0116, じゅっ 0.0122, じっ 0.0124.
    Katakana span: ハチジュッ 0.0057, with the exJP audio's own sample count but not its bytes.
    Isolated 八十点: じっ first; 八十点です。: う first;
  * on sentences 1b proves, each span lead misses once: the hiragana one in `n2-b277` (ろくじゅう 0.0140
    against the proven ろくじゅっ 0.0176), the katakana one in `n3-b020` (ジュップン against the proven
    じゅうぶん). Neither can settle a silent sentence.
  Corrected in `v136-dictation-remeasure.json` (the leads, the decision, a dated 'corrected' line, the
  new 'leadCheck'), in the manifest's `n3-b678` 'dictation' text, and in the entry above. The record's
  note no longer cites 0/494 false positives, which v1.25 §A withdrew as arithmetic. It cites the
  27/27 recall only.
* **`n1-b439`: the leads mostly favour the correction** (MINOR). Its one さんせん-leaning lead, the 1b
  span render さんぜん円, is 77,207 samples against the exJP audio's 71,831, 0.24 s longer, while every
  other substitution is within 0.035 s. The other variants all lean さんぜん: さんぜんえん / さんせんえん
  0.0088 / 0.0161, サンゼン / サンセン 0.0077 / 0.0131, サンゼンエン / サンセンエン 0.0048 / 0.0103. In
  isolation, 三千 and 三千円です。 render the same sample count as さんぜん and さんぜんえんです。. There is
  no byte identity anywhere. Recorded in the same two places.
* **DECISION NEEDED — `n3-b678`, the release owner's.** Both はちじゅってん and はちじってん are standard
  and were upheld 2 of 2 (NHK lists ジッ first). For a pool sentence, the condition that exKana match
  the voice outranks the more-common-form preference, and the voice is undetermined.
  * (a) Keep it as it is now: はちじゅってん, in the pool. Instrument 2 flags it.
  * (b) Teach はちじってん, in the pool. Instrument 2 does not flag it: own 0.06541, rivals at 0.06590 or
    more, a margin of 0.0005. The corpus then teaches the less common form. The 八十 token
    (はちじゅっ → はちじっ) and exKana change through `CorpusFile`, and `KNOWN_CORRECTED`, the manifest
    row and §E's "八十点 はちじゅってん" change with it.
  * (c) Correct it and withhold it, v1.35's `n5-g022` precedent. The pool goes from 5,939 to 5,938, and
    §E's "three stay in the pool" becomes two.
  * If the voice says はちじってん or はちじゅうてん, (a) refuses every rider who types what they hear,
    at ゅ or at っ.
  * Nothing is chosen here. (b) would rest on a margin of 0.0005 in the same instrument whose flag is
    the admission rule, which is a reason to put it to the owner, not a reason to apply it. *(Decided
    2026-10-09: (c), with `n1-b439`, `n3-b781` and `n3-b020` withheld too, so the pool goes to 5,935;
    see "the dictation decisions" below.)*
* **Stumble chip** (MINOR). The bullet above is rewritten on a port of `StumbledWords.entryID` run on
  both trees. `n1-b655` 分 ふん is a suffix, so the chip never names it, and the pair-index simulation
  missed that. Future chip trade-offs are simulated on `entryID`, not on the pair index alone.
* **(m0), `check_counter_readings.py`** (MINOR). `KNOWN_CORRECTED`'s ids are now held to the manifest:
  the manifest rows with disposition 'corrected' that are also (i)'s known hits must be exactly those
  ids. The values stay hand-written. Calibration is 83/83, and `v136-counter-sweep-5.json` was
  regenerated: the same corpus (`766c092`) and the same hits, plus the (m0) line. Mutants were run on
  scratch copies of the script, corpus and manifest, with git read from this worktree. The unmutated
  copy passes 83/83, and 5 of 5 mutants are killed by (m0):
  * X1: `KNOWN_CORRECTED` loses `n2-b311` (the review's X26, which (m) alone passed);
  * X2: the manifest drops `n2-b311`'s row;
  * X3: `n1-b957`'s disposition is no longer 'corrected';
  * X4: the manifest declares `n3-b020` corrected, with no check row;
  * X5: the manifest is absent.
  * A control, X6, makes the comparison vacuous (the set compared with itself) on X2's manifest. It
    passes 83/83, so the comparison is what catches X2.
* **Recorded for v1.37, not corrected.** Each is a new hit with no 2-of-2 votes, outside the calibrated
  table, and already wrong in 1.35. Each was re-read in the corpus here (exJP, the covering tokens,
  exEN and pool membership):
  * **`n2-b277`** この車は時速六十キロで安全に走っている。, 六十 taught ろくじゅう, **in the dictation pool**.
    1b proves the voice says ろくじゅっきろ: the span 六十キロ → ろくじゅっきろ renders byte-identical to the
    exJP audio (`5792f71c3229`), while ろくじっきろ, ろくじゅうきろ and 2 decoys do not. Controls in the same
    run: `n2-b1180` じゅっ, `n4-b186` and `n2-b034` ひと, and `n3-b020` じゅうぶん reproduced, and 4
    decoys gave 0 matches. Today a rider who types what they hear is refused at っ, as in 1.35.
    `COUNTER_RE` does not enumerate キロ. If two refuters uphold ろくじゅっ before submission, the
    correction agrees with the proven voice and the sentence stays in the pool. Otherwise it waits for
    v1.37. Recorded in `v136-dictation-remeasure.json` 'recordedNotCorrected'.
  * 一週間 taught いちしゅうかん (いっしゅうかん): `n2-b511` (in the pool), `n3-b310`, `n4-g189`.
  * 第一章 だいいちしょう (だいいっしょう): `n1-b1418` (in the pool).
  * 一等 いちとう (いっとう): `n2-g285`.
  * 一晩 いちばん (ひとばん): `n4-b186`. 一晩中 いちばんちゅう (ひとばんじゅう): `n2-b034`. v1.29 proved the
    voice says ひと in both.
  * …じゅう before a loanword counter (standard じゅっ / じっ): `n5-b105` 二十センチ and `n4-b104` 五十ページ,
    both in the pool; `n2-b1180` 十センチ (voice proven じゅっ), `n3-k061` 十パーセント and `n5-g010`
    十ページ.
  * Each needs a calibrated table row first (週 / 週間, 章, 等, a loanword counter after 十, and 一晩 in
    the lexicalised table), then 2-of-2 refuters.
  * For the pool sentences, the voice is measured before any correction. For `n2-b511` and `n1-b1418`,
    the review's leads favour the taught いち: correct Japanese the voice may not say, as in `n3-b020`.
  * §E's "Outside that scope the sweep claims nothing" stays accurate.
* **Proof on this tree:** `run_all_gates.sh --vocab-only` is green, and red with `n3-b678`'s exTokens
  declaration dropped ("exTokens OVERWRITTEN", naming only that id). `test_check_vocab_diff.py` passes.
  Joined exTokens equal exKana on all 6,724 sentences. `release_numbers`: correctedThisRelease 21,
  pool 5,939 → 5,939.
* **Not run:** `swift test`. No Swift source, corpus file or test-read resource changed (the diff is
  this file, the two records' text, `check_counter_readings.py` and the regenerated sweep), so the
  apply step's pass stands.
* **Noted, not fixed:** the docstring of `scripts/check_dictation_readings.py` still states the
  withdrawn 0/494.

**2026-10-09 (JST), the dictation decisions** (branch `feat/v136-dictation-decisions`, on `7cc56d2`;
`24f90eb`, `20658f1` and this record). The orchestrator made these decisions under the owner's
delegation; they are recorded here as made, not re-argued.
1. **`n3-b020`** 駅からおよそ十分歩きました。 ('about ten minutes'): upheld 2 of 2, and instrument 1b
   proves the pool voice says じゅうぶん. **Correct it** (十分 → じゅっぷん in exKana and the token reading)
   **and withhold it from dictation**, as v1.35 withheld corrected sentences whose voice disagrees:
   teach the right reading, and do not test dictation where the voice says something else.
2. **`n1-b439`, `n3-b781`** (三千円 さんぜん) and **`n3-b678`** (八十点 はちじゅってん): corrected, in the
   pool, 1b silent. Follow the v1.35 precedent (`n5-g022`): **withhold them from dictation**, with the
   evidence recorded: 1b silent, instrument 2's leads as re-measured, and `n3-b678`'s tie stated as a
   tie. For `n3-b678` this is option (c) of the DECISION NEEDED above.
3. **`n2-b277`** (六十キロ) and the 12 out-of-table sentences stay unchanged, recorded for v1.37 as
   listed above.

The apply step's rule that the pool must not shrink is set aside for these four.
* **The correction.** `n3-b020`: exKana えきからおよそじゅうぶんあるきました → えきからおよそじゅっぷんあるきました,
  and its one 十分 token じゅうぶん → じゅっぷん, written through `CorpusFile`. 2 lines of n3.json (:22111,
  :22127) and no others. The corpus teaches じゅっぷん, as in the other four 十分 'ten minutes'
  corrections; the table accepts じっぷん too. The sentence keeps its 18 kana, so it still rides 180 m.
  Joined exTokens equal exKana on all 6,724 sentences.
* **Declared** in `v136-reading-manifest.json` as a 22nd row. The hit and both votes are copied
  verbatim from `v136-dictation-remeasure.json` 'upheldNotApplied', and the 1b evidence is in its
  'dictation'. Also updated in the manifest:
  * the reason gains (4), and the method states the rule;
  * `counts`: 22 corrected, 4 withheldFromDictation;
  * the note;
  * the rows of `n1-b439`, `n3-b781` and `n3-b678` say withheld, and keep their measurements.
  The re-measure record gains 'decided' and the applied 'decision'. Its first decision is kept as
  'decisionBefore', and its pool reads 5,939 → 5,935.
* **Dictation.** The 4 ids are in `dictation-exclusions.json`, sorted, so excludedCount goes from 785
  to 789. Each also has an evidence row in `dictation-reading-mismatches.json`, and each file's note
  gains one sentence. Both files were written through `CorpusFile`, and each round-trips at indent=1.
  * `n3-b020`'s row is 'proven' (v1.36, 1b), with the complaint 十分 じゅっぷん -> じゅうぶん. It takes the
    shape of `n2-b311` and `n4-b127`, where the same voice is proven to say じゅうぶん for 十分 'ten
    minutes'. **So `dictationProvenMisread` goes from 239 to 240.** The review notes must quote the
    new figure.
  * The other three are 'undecided', in `n5-g022`'s shape: the complaint names the old reading and the
    corrected one, annotated "no instrument heard this". The evidence is 1b's silence with its hashes,
    and the leads labelled as leads. For `n3-b678` that means instrument 2 flags the corrected sentence
    once はちじっ is a candidate, and the span comparatives disagree, which is a tie.
  * A Python replica of `exclusionEvidenceIsCurrent` reads 789 of 789 rows, 0 stale; the two files
    name the same 789 ids.
* **`release_numbers`**, read from its output:
  * correctedThisRelease: 22;
  * dictationExcluded: 785 → 789;
  * dictationPool: 5,939 → 5,935;
  * withheldThisRelease: 4;
  * releasedThisRelease: 0;
  * dictationProvenMisread: 240.
* **The sweep.** `check_counter_readings.py`: `KNOWN_CORRECTED` gains `n3-b020` 十分 じゅっぷん, so
  (m0) holds 13 rows to the manifest's 13. The working-tree half of (l) now reads the two hits still
  there, `n4-g171` (in the pool) and `n5-b334` (withheld): one of each, so the lookup is still proven
  both ways. The docstrings follow.
  * `--calibrate` passes 83/83 (`v136-counter-sweep-6.json`, corpus `24f90eb`; 85/85 since the fix
    round below added (m1) and (m2), and sweep-6 is regenerated with them).
  * The counter table finds 0 mismatches and the 5 tolerated flag-only readings.
  * `v136-counter-sweep-5.json` is kept as it is. It records `766c092`, where `n3-b020` was the one
    remaining mismatch.
* **Mutants**, run on scratch copies of the script, corpus and manifest, with git read from this
  worktree. The control passes 83/83, and 5 of 5 mutants fail exactly the check named:
  * `n3-b020`'s exKana alone reverted: (m);
  * its token alone reverted: (m);
  * the manifest row dropped: (m0);
  * the `KNOWN_CORRECTED` row dropped: (m0);
  * `n4-g171` withheld on the working tree: (l).
* **Stumble chip**, simulated on a port of `StumbledWords.entryID` on both trees. Before the
  correction, `n3-b020`'s 十分 token linked to `n4-g178` 十分 じゅうぶん 'enough, sufficient', the wrong
  sense. Now it links to no card, because no entry is 十分 / じゅっぷん (`n1-b1516` is じっぷん).
* **Proof on this tree:**
  * `run_all_gates.sh --vocab-only` (local, `fdb2b5f` + the manifest) is green.
  * It is red, naming only `n3-b020`, with that row's exTokens declaration dropped (1 problem) and with
    the whole row dropped (exKana and exTokens).
  * All 11 `scripts/test_*.py` pass. `test_check_vocab_diff.py`'s release-manifest probes include
    `n3-b020`'s three.
  * `swift test --filter 'VocabKit|CorpusEscapeResidue|ExampleSentence|Dictation'` passes 81 + 26
    tests, with 0 failures and no warnings, in this worktree's own build root. Free disk was 16 GiB,
    under §B's 25 GiB floor; the task allowed this one SwiftPM build, and its root went to the Trash
    afterwards. `exclusionEvidenceIsCurrent`, `exclusionsAndEvidenceAgree`,
    `dictationExclusionsResolve` and "token readings reconstruct exKana" are among the passes.
* **Rider-visible:**
  * Sentence mode teaches `n3-b020` as じゅっぷん.
  * Dictation draws from 5,935 sentences, 4 fewer. One N1 and three N3 sentences leave the pool.
  * No sentence rides a different distance.
* **Source diff against `fdb2b5f`, now:** `ListsView.swift`, `GameView.swift` and `PracticeView.swift`;
  n1–n5.json, 49 lines (n3.json now 8); and, for the first time this release,
  `dictation-exclusions.json`. Since `7cc56d2`, no frozen file has changed.
* **Owed before submission:**
  * What's New and the review notes must name 22 corrections (`n3-b020` among them), the pool at
    5,935 and dictationProvenMisread at 240. §F's drafts still name nine.
  * `submit_1_36.py` is frozen for this branch and was not touched. Its NAMED_IDS guard keeps refusing
    until it is rewritten for this set.

**2026-10-09 (JST), fix round of the dictation decisions** (branch `feat/v136-dictation-decisions-fix`,
on `8324943`). The review found two MINOR defects. Both were reproduced, and both are fixed.
1. **The pool history was wrong.** The new evidence rows of `n1-b439` and `n3-b781` said each sentence
   "had been in the dictation pool since 1.35 shipped". It had been there since v1.21, when dictation
   shipped (`60c73a3`):
   * both sentences were already in the corpus with さんせん by then (`n1-b439` from `8823a3a`, `n3-b781`
     from `76408cc`; each is in the corpus at `60c73a3`);
   * neither id was in `dictation-exclusions.json` before `24f90eb`.
   Both rows now say "since v1.21, when dictation shipped", as `n5-g022`'s row dates its own. The fix
   is 2 lines, written through `CorpusFile`, which round-trips the file at indent=1. A Python replica
   of `exclusionEvidenceIsCurrent` and `exclusionsAndEvidenceAgree` then reads 789 of 789 rows with 0
   stale. The two files name the same 789 ids, 240 rows are proven, and the floor holds at 789 ≥ 240.
2. **Nothing pinned the four withholdings.** (l) reads only hits, and a corrected sentence is no longer
   a hit. So after `n3-b020` was corrected, nothing held its new withheld state; the decisions rested
   only on the two exclusion files agreeing with each other.
   * Reproduced with `8324943`'s script on a scratch copy: `n3-b020` deleted from both files, with
     their counts fixed. `--calibrate` passed 83/83 and exited 0. Only `release_numbers` moved, to a
     pool of 5,936 and withheldThisRelease 3, and it is not a gate.
   * Fixed with two `--calibrate` checks next to (m).
     * (m1): every row the manifest declares 'corrected' is withheld in the working tree's
       `dictation-exclusions.json`. That is all 22 rows, not only (m)'s 13. The one exception is a row
       that `v136-dictation-remeasure.json` gives a 1b 'RELEASE' verdict, which is the method's rule.
       The 'dictation' prose is not parsed: at `7cc56d2` three rows began "IN the dictation pool" and
       named 1b (silent there), so a text test would have passed them.
     * (m2): the manifest's counts are held to the files. withheldFromDictation must equal the number
       of corrected rows withheld now and not in 1.35's list (`fdb2b5f`), and releasedToDictation the
       reverse. Their difference must equal `release_numbers`' withheldThisRelease, which is imported,
       not re-derived. That last comparison is made only while `release_numbers` measures this manifest
       from `fdb2b5f`; once either moves on, the check's detail says it was not made.
   * `--calibrate` now passes 85/85. `v136-counter-sweep-6.json` is regenerated: the two lines are
     added, the hits are unchanged, and the corpus is still `24f90eb`.
   * **Mutants**, run on scratch copies of Sources, scripts and docs, with git read from this
     worktree's gitdir and no index written. All 7 behave as expected:
     * the control passes 85/85;
     * `n3-b020` back in the pool (both files, counts fixed) fails (m1) and (m2). The `8324943` script
       passes the same copy 83/83;
     * `n3-b678` back in the pool fails (m1) and (m2);
     * `n3-b020` back in the pool, with withheldFromDictation lowered to 3 to match, fails (m1) alone;
     * withheldFromDictation lowered from 4 to 3, with nothing else changed, fails (m2) alone;
     * an unrelated pool sentence (`n4-g001`) withheld in `dictation-exclusions.json` alone fails (m2)
       alone, with withheldThisRelease at 5;
     * `n3-b678` back in the pool with a 1b 'RELEASE' verdict and withheldFromDictation 3 passes 85/85.
       So the exception is live, and the check is not one that can only answer "withheld".
   * (m1) and (m2) check v1.36's working tree, as (l) and (m) do.
* **`release_numbers`**, read from its output: correctedThisRelease 22, dictationExcluded 789,
  dictationPool 5,939 → 5,935, withheldThisRelease 4, releasedThisRelease 0, dictationProvenMisread 240.
* **Proof on this tree:**
  * `run_all_gates.sh --vocab-only` is green.
  * It is red with `n3-b020`'s exTokens declaration dropped, naming only that id ("exTokens
    OVERWRITTEN", 1 problem). The manifest was restored afterwards.
  * All 11 `scripts/test_*.py` pass.
  * `swift test --filter 'VocabKit|CorpusEscapeResidue|ExampleSentence|Dictation'` passes 81 + 26
    tests, with 0 failures and no warnings. It was run because the edited evidence record is read by
    `exclusionEvidenceIsCurrent` and `exclusionsAndEvidenceAgree`, and both pass. It was this round's
    one SwiftPM build, in this worktree's own build root (708 MB), which went to the Trash afterwards.
    Free disk was 15 GiB.
* **Diff since `8324943`:** `dictation-reading-mismatches.json` (2 lines), `check_counter_readings.py`,
  `v136-counter-sweep-6.json` (2 lines) and this file. No corpus file and no frozen file changed.

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

