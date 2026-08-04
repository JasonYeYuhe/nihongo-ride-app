# v1.16 — One assistance policy, N3 content, and the debts v1.15 left

Status: revised after Codex and Gemini review. Both rejected the first draft's
headline feature; §A is its replacement. Review notes in §5.

---

## 1. The measurement that shapes this release

Jason asked for a big change with more AI in it. Before designing anything I re-ran every
on-device probe from v1.15, because that file says to. macOS went 26.5 → 26.6 and **all
three capabilities got worse** (`docs/ai-probes/RERUN-2026-08-03.md`):

- **Authoring Japanese**: still 5 of 5 defective, plus a new failure — the kana field came
  back containing **romaji** (「しかし、watashi wa ima, benkyo wo shiteimasu.」). Kana is the
  string the learner is graded against.
- **Constrained classification**: 2/4 → **1/4**. Sokuon and small-ya both classified as
  kunrei-shiki. The advice was nonsense even when the label was right.
- **Grounded explanation** — the one task that measured usable in v1.15, and the one thing
  the v1.15 plan kept in reserve: now returns two identical fields and **invents incorrect
  Japanese** (「この商品は披露します」, which wants を) in a task whose whole premise was that
  it never has to produce Japanese.

So the honest answer to "how do we get more AI in" is not a new on-device surface. It is
the AI that has already been measured to work: **a large model, offline, behind the
deterministic gates and the human read that shipped 779 sentences in v1.15.**

**Scope of that claim, corrected after review.** Codex was right that "there is no on-device
surface worth building, not 'not yet'" overreaches what n=5/4/1 with one prompt style, no
few-shot, the default model and no `useCase` can support. What the probes establish is that
this design, as probed, fails badly enough to reject **for v1.16** — not that no prompting
or decoding setup could do better. Reopening it needs a pre-registered benchmark rather than
prompt-tweaking against these same items: ≥100 authoring words stratified by level/POS/
ambiguity plus ≥20 adversarial inputs, ≥30 matcher-derived traces per pattern, ≥100 entries
for explanation with two independent readers, run English and Chinese, cold and warm, on an
eligible iPhone, iPad and Mac. Pass means zero wrong learner-visible Japanese. Until someone
runs that, the answer is "rejected for v1.16", and the phrasing layer is rejected with it.

The v1.15 constraint therefore hardens: *the app authors every Japanese character; the model
never does, at runtime or otherwise, without a gate and a reader between it and a learner.*

## 2. The update

### §A — One assistance policy (the headline; deterministic)

The plan's first draft proposed a "Live Coach" that showed a correction inline on the second
refusal. **Both reviewers rejected it independently, and the code says they are right:**

- The ride screen **already** displays the full canonical romaji and every currently accepted
  next key (`GameView.swift:495-524`), and `showRomajiHint` defaults ON — so inline coaching
  is redundant in the default experience, and when the learner has turned hints OFF it
  overrides an explicit choice to practise blind.
- It would corrupt scoring. `revealHint()` marks the word revealed, forces a minimal score
  and records an SRS lapse (`GameSession.swift:293-299, 333-356`). An automatic correction
  after two refusals hands over the same information for free, so a learner could take the
  answer and still receive an unhinted SRS outcome — the distinction between recall and
  assisted completion stops meaning anything.
- Pedagogically it rewards "try twice, then wait", which is the opposite of retrieval
  practice in an app whose whole engine is spaced repetition.

What the app actually has is **two hint systems that do not know about each other**: an
always-on romaji display, and a manual reveal that costs a lapse — except that the reveal is
reachable from **nowhere**. `revealHint()` is fully written, scored and tested, and no view
has ever called it (checked across the whole app target: the only non-test references are
`ConjugationSession`'s own copy). So this section is not re-timing an existing control; it is
building the control that the engine has been waiting for. Two further facts found while
implementing, both fixed here:

- `revealHint()` set `showRomajiHint = true` **session-wide** — one reveal would have put the
  answer on screen for every remaining word of the run. Harmless while unreachable, a bug the
  moment the offer makes it reachable. Reveal is now per-word (`romajiVisible`).
- Holding a key is worth **2** distinct attempts, not 1: macOS delays the first repeat by
  375 ms (default, and only longer on slower settings), which is past any sane
  autorepeat-detection gap; every later repeat is filtered. Only the initial delay can exceed
  the gap, so 2 is a hard bound — which is what makes the threshold of 3 safe, and is pinned
  by a test so nobody lowers it to 2.

v1.16 replaces both systems with one setting the learner can reason about:

| assistance | during a word | cost |
|---|---|---|
| **Always show** | full romaji visible, as today with hints on | none — this is study mode |
| **Offer after struggle** (new default for new installs) | nothing shown; after repeated refusal at the SAME matcher state, a reveal control appears | using it marks the word assisted: `usedHint`, minimal score, SRS lapse — the existing path |
| **Off** | nothing, ever | none; the learner chose blind practice and is left alone |

Three things this gets right that the first draft did not: the answer is never injected, only
OFFERED; taking it costs exactly what taking it costs today; and "Off" means off.

Definitions the reviewers asked for, because "second refusal at the same kana" was too vague
to implement:

- **Same state** = (queue index, kana index, accepted romaji prefix). Not "the same
  character value" — that conflates two unrelated attempts at the same kana in different
  words. The queue index stands in for the entry-or-passage id: it is unique within a run and
  identical in both session types, and a word repeated later in the same run is a genuinely
  new attempt, so identity is the wrong grain anyway. Reset on accepted progress, word change,
  pause, or backgrounding.
- **Distinct attempts, not repeats.** The trace already documents that a held key produces
  hundreds of refusals (`MistakeEvent.swift:60-78`). The offer requires distinct physical
  attempts. **Threshold: 3**, derived rather than picked — it is the smallest value strictly
  above the 2-attempt ceiling a held key can reach, so no amount of leaning on one key can
  produce an offer, and a learner who genuinely tries three different wrong keys at one
  position gets one.
- Time Attack keeps its exclusion: the timer runs every 0.1 s regardless
  (`GameView.swift:108-113`), so any reading costs competitive time.
- Refusals already reset the combo. The offer adds no second penalty.

### §B — N3 example sentences (the AI, where it is measured to work)

2,898 of 7,074 words have an example. N5 and N4 are covered. **N3 has 872 without one** and
is the level where learners live longest.

Same pipeline as v1.15 §I, with the gates it grew: shape, no-latin, no-duplicate,
morphological target presence, reading alignment via Sudachi, level ceiling. Then generation
in batches, then the two-lens agent review, then my adjudication, then merge with per-example
provenance (`exMeta`) so a batch stays rollback-able.

**N3 is harder than N5/N4 and the gates must be re-measured, not assumed.** Three gate
changes land BEFORE the pilot, all of them because a reviewer pointed at the code:

1. **Require the morphological match.** `pilot_gate.py:108-110` currently accepts a Sudachi
   target token **or** the older substring/stem fallback, so the weaker check still decides
   the cases the stronger one cannot resolve. At N3 that is exactly the polysemous vocabulary
   where it matters. Tokenizer uncertainty becomes rejection: false negatives cost coverage,
   false positives teach the wrong word.
2. **Close the level gate's hole.** It rejects known vocabulary above the ceiling but lets
   **unknown** tokens through, and N3 permits one level harder — so an N3 sentence can be
   built out of N2 words and compounds absent from the dictionary. Unknown content words are
   counted and capped.
3. **Transitivity.** The first draft anticipated 上がる/上げる failures and then shipped no
   check for them; `VocabEntry` carries POS strings and a conjugation class but no
   transitive/intransitive role. Either add authoritative transitivity metadata and a
   conservative particle-frame gate, or quarantine transitivity-pair verbs into their own
   reviewed stratum. Not "expect it and hope the reader catches it".

**What the measurement did to these three.** Calibrated against the 779 sentences that
already shipped — every one past the gate, two-lens review and adjudication, so a rule that
rejects many of them is not stricter but wrong (`scripts/gate_calibration.py`):

1. **Landed, after the matcher was fixed first.** Dropping the fallback naively rejected 63
   of the 779 (8.1%), and all 63 were good: the matcher could not see a target finer than
   Sudachi's C-mode split (時代 inside 学生時代, 都 inside 東京都) or one spanning tokens
   (ご主人 → ご|主人, ごらんになる → ごらん|に|なり). Teaching it A-mode splits and contiguous
   token runs took that to 2 (0.3%) — both compounds Sudachi never splits — so the fallback
   was paying for imprecision it no longer prevents, and is gone.
2. **Landed, cap = 2, after fixing the counter.** The first counter called the いる of
   ～ています an unknown content word, i.e. it measured its own tokenizer exactly as the first
   level gate did with た and で. Excluding 非自立 tokens, the reviewed corpus runs
   542 / 209 / 26 / 2 sentences at 0 / 1 / 2 / 3 unknowns, so the cap is read off the data.
3. **Killed — replaced by a review flag.** Both drafted forms failed measurement.
   *Metadata gate:* only 38 of 2126 verbs carry a vt/vi tag, and of the 184 verbs awaiting an
   N3 example, **zero** do — it would have reported a clean sweep while checking nothing.
   *Quarantine:* it blocks 73 of the 779 reviewed sentences; reading all 73, every one uses
   the right verb with the right particle, so it would cost 51 of the 872 N3 words to prevent
   a defect class with no observed occurrence. *The を particle-frame rule is itself wrong
   Japanese:* 「橋を渡る」, 「階段を上がる」, 「この道を通る」 are all shipped and all correct — を
   marks the path traversed. What ships instead is a `reviewFlag` on pair-verb items, telling
   the review stage to check particles on a verb whose partner is one character away. The
   check goes where the demonstrated capability is; 73 out of 73 says that is the reviewer.

Full new gate against the reviewed corpus: **4 rejections in 779 (0.5%)**.

### §B pilot 1 — the stop rule fired

245 words, stratified (pair verbs / other verbs / ambiguous surfaces / single kanji /
register-sensitive / random), seed recorded. 208 survived the gate (85%). Two-lens agent
review across eight agents flagged 55 (26.4%), against v1.15's 7.0%.

Adjudicating: **all 13 "wrong" verdicts are real**, and roughly 15–18 of the 42 lesser ones
are too — call it 13–15%. **Both stop conditions fired**: over 10%, and false-reading and
false-meaning defects that no deterministic gate can catch.

- **False reading (2).** 年月 is taught as としつき, but 「長い年月をかけて」 is normally read
  ねんげつ; 日本 is taught as にっぽん, but 「サッカーの日本代表」 is read にほん. The sentence is
  correct Japanese and teaches the wrong answer to type.
- **False meaning (6).** The word is present, correctly read, in a real sense — that the
  displayed gloss does not include. 針 glossed "needle, pin" as a clock hand; 単位 "unit" as an
  academic credit; 面 "face, surface" as the suffix -面 "aspect"; 切れる "to break" as a battery
  running out; 殺す "to kill" only inside 息を殺す; 通す "to let pass" as threading a needle.
  **This is what N3 being harder actually looks like**: N3 vocabulary is polysemous and the
  app shows one narrow gloss.
- **Grammar and translation (5).** 倒す transitive with no possible agent; a doubled
  connective で; Chinese that is not grammatical Chinese (我打了扫).

**Three more candidate gates were killed by calibration**, on top of the two §B already
killed — the pattern is consistent enough to be worth naming: rules that feel obviously right
keep turning out to measure their own tokenizer rather than the sentences.

- *Compound adjacency* ("reject when the target is glued to a neighbouring noun") rejects
  9.6% of the reviewed corpus, and reading them they are good: 校長 in 校長先生, 時代 in
  学生時代, 世界 in 世界中. It measures compounding, not defectiveness — 面 in 安全面 and 通行 in
  通行止め are structurally identical to those. **No deterministic gate separates them.**
- *Suffix POS* does not fire: Sudachi tags the 面 of 安全面 普通名詞, not 接尾辞.
- *Whole-surface kanji match* rejects 19.5% — verbs conjugate, so 比べる never appears in
  比べます. Per-kanji costs 0.6% and catches the real defect (是非 written ぜひ, 後 written のち),
  so **that** one landed.

What did NOT change: the pipeline writes good Japanese. The defects concentrate in
gloss-versus-sense, which is a generation-time constraint, not a gate. Pilot 2 tests exactly
that: same 245 words, same gate, a prompt that pins the sense to the displayed gloss, forbids
burying the word in a compound or idiom, requires the given spelling, requires the context to
force the reading, names the Chinese false friends, and lets the model return an empty
sentence rather than a wrong one. If pilot 2 does not clear the same bar, **N3 does not ship
in v1.16** and the release is §A, §C and §D.

### §B pilot 2 — better, and still stopped. N3 is deferred.

Same 245 words, same gate, revised prompt. 208 survivors again (85%), and the model **used
the refusal option on 6 words** — including 日本/にっぽん, one of pilot 1's false readings. The
new per-kanji gate caught 後 written のち.

|  | pilot 1 | pilot 2 |
|---|---|---|
| flagged | 55 (26.4%) | 53 (25.5%) |
| severity "wrong" | 13 | 8 |
| false readings among "wrong" | 2 | 0 |
| gloss-mismatch among "wrong" | 6 | 0 |

The severe end moved a lot. What is left at "wrong" is five Chinese-translation defects
(捉迷藏 for 鬼ごっこ, 打折 for breaking a bone, 大众 for 方々, 代表 copied for 党の代表) and two
register/grammar ones — no false reading, no gloss mismatch.

**But the gloss-mismatch class did not disappear; it was demoted.** 通す is still threading a
needle against "to let pass"; 見舞い is an ordinary sick-visit against "enquiry"; the English
for 場 still says "opportunity"; the English for 姿 and 境 drops the target word entirely. The
stop rule says *any* false-meaning defect no deterministic gate can catch — it does not say
"any severe one". Condition two fires again, and the adjudicated total lands around 11–13%,
still over the 10% ceiling.

**So N3 does not ship in v1.16.** The release is §A, §C and §D.

**The residual blocker is now identified precisely, and it is not the model.** 18 of 59 flags
are gloss-versus-sense and 21 are Chinese translation. The Japanese itself is fine: three of
four correctness reviewers found zero "wrong" items. N3 vocabulary is polysemous and the app
shows **one narrow gloss per entry**, so a sentence using any other real sense is a defect no
prompt can prevent — the model would have to guess which of several correct senses the app
happens to display. That is a data-model problem: either the entry carries the sense the
example teaches (an `exSense` alongside `exJP`), or the app displays the gloss that matches
its own example. Either fixes the class at the root, and neither is a v1.16 patch.

Kept from this work regardless: a much stronger gate (morphological match required, matcher
taught mode-A splits and multi-token runs, unknown-content-word cap, per-kanji spelling check
— 1.2% against the reviewed corpus), a prompt that pins sense and permits refusal, and
`scripts/gate_calibration.py`, which killed five of eight candidate rules before they could
ship.

**The stop rule, defined before any results are seen.** The metric is the **adjudicated
defect rate among gate survivors, counted before flagged items are removed** — the v1.15
comparable is 59/838 ≈ 7.0% reviewer-flagged, of which the small pilot's hand-read gave
2/55 ≈ 3.6% genuinely wrong. The pilot uses **≥200 gate survivors**, stratified across verbs,
ambiguous surfaces, single-kanji words and register-sensitive terms. **The batch stops if the
adjudicated defect rate exceeds 10%, or if any false-reading or false-meaning defect appears
that no deterministic gate can catch.** Numbers chosen now, recorded here, not after seeing
the data.

### §C — The two data-loss debts v1.15 found and did not fix

Both were confirmed still present in the code today.

**An unreadable word-list file gets overwritten.** `WordListStore.loadOrMigrate` carefully
returns `.unreadableDeferred` so a file it could not READ is left alone — and `AppModel`
discards the outcome (zero references). The session runs on an empty store and the next ★
tap saves it over the good file. The loader's whole reason for distinguishing "unreadable"
from "corrupt" is undone by the first write.

Gating disk writes is necessary and **not sufficient** — Codex again. Protection has to cover
user mutations, local persistence, sync-merge persistence AND outbound CloudKit records, or
an empty stand-in becomes visible sync state even though the file on disk survived. Note that
list persistence currently records local CloudKit changes after attempting the save *even
when the save failed* (`AppModel.swift:951-963`). And "tell the user" is not recovery: there
is a retry-read action, list controls stay disabled until it succeeds, and a persistent I/O
or permission failure gets a non-destructive next step rather than stranding the learner
until they think to relaunch.

**The v1.4 favorites migration silently drops everything past the 500th.**
`seedDefaultIDs` does `prefix(maxWordsPerList)`. v1.4 had no cap, so a user with 620 saved
words loses 120 — and then `enqueueAllLocal` pushes the truncated deck over the cloud copy.

**The spill fix I proposed is wrong, and Codex showed why with three code references.** The
★ glyph asks only whether the DEFAULT list contains the word (`WordListStore.swift:62-67`),
so a favorite moved to "★ 2" renders unstarred and tapping ★ tries to re-add it to a list
that is already full. Only the default list has a constant cross-device identity
(`WordList.swift:25-38`); auto-created lists get UUIDs, sync unions by id and never enforces
the 50-list cap after merging, so two upgrading peers each mint their own "★ 2". And the
legacy v1.4 cloud mirror carries default-list ids only, so spilled favorites vanish from
older peers entirely. Spill preserves the bytes and destroys the meaning of "favorite".

**Grandfather instead.** Keep every deduplicated legacy id in the default list, let that one
list exceed 500 as a migrated exception, and keep the 500 cap for NEW additions until the
count falls back under it. ★ semantics, sync identity and the cap all survive. Raising the
cap generally is a separate question that needs the worst-case encoded `ids + wordMeta +
CKRecord` size measured first — the source's own estimate (~350 KB for all 7,074) omits
fields and encoding overhead, so "just raise it" is not yet proven safe.

### §D — The accessibility debt, led by the worst case in the app

At AX5 in Practice, **the characters the learner has to type are behind an ellipsis**.
`PracticeView` has no `dynamicTypeSize` cap and the passage `Group` has no ScrollView, so the
target text truncates. A typing app that hides the typing target is broken, not merely
inconvenient.

**Do not fix it by copying the ride screen's cap.** GameView caps at accessibility1 because
its HUD is a fixed layout that cannot reflow; Practice is a column of text that can. Capping
would deny AX5 users the size they asked for in order to solve a problem reflow solves
properly. The acceptance contract: full AX5 preserved, the passage scrolls, the caret stays
visible above the software keyboard, and short/medium/long passages are each verified with
VoiceOver on a device.

Plus the rest of the v1.15 §F batch, which is the same shape as the §C work already
reviewed and shipped: fixed frames on the Time Attack countdown ("3…" reads as 3 seconds
when 35 remain), ListsView row heights, JournalView date/stat columns, StatsView chart
heights, and three VoiceOver honesty fixes (a "—" placeholder announced as "no rides yet",
a best-WPM badge that is on screen but unreachable, `Int(best)` truncating where the badge
rounds).

## 3. What I am NOT building, and why

- **Any new on-device AI surface.** §1. Three capabilities, all worse in one point release,
  and the only usable one now fabricates Japanese.
- **The optional AI phrasing layer** the v1.15 plan reserved. Abandoned, not deferred: at
  1/4 classification and misleading prose it would make a correct diagnosis worse.
- **N2/N1 sentences.** After N3 reports its numbers, not before.
- **A cloud model.** Still ends "Data Not Collected" for a job the pipeline does offline.

## 4. Sequencing

§C first (data loss), then §D (a learner who cannot see the target cannot practise at all),
then §A, then §B's gates → pilot → decision. §B ships only if its own numbers clear the bar
in §2; the release does not wait for it.

## 5. What the reviews changed

Codex and Gemini reviewed the first draft independently and agreed on the headline.

**Killed §A as drafted.** Gemini: showing a correction mid-word converts recall into visual
pattern-matching and breeds hint dependency, and it "directly violates user intent when
Romaji Hint is disabled". Codex found the code: the ride screen already shows the full romaji
and every accepted next key, `showRomajiHint` defaults on, and `revealHint()` already charges
an SRS lapse that an automatic correction would let a learner dodge. Two independent routes
to the same verdict. The replacement — one assistance policy, offer-don't-inject — is Codex's
suggestion and it is better than what I wrote.

**Killed the favorites spill**, with the ★-semantics and sync-identity reasoning above.

**Corrected my overclaim** about on-device AI being categorically not worth building.

**Tightened §B**: require the morphological match rather than falling back to substrings,
close the unknown-token hole in the level gate, gate transitivity instead of merely
predicting it, and fix the stop rule's metric and threshold in advance.

**One reviewer claim I checked and rejected.** Gemini warned that N3 grammar might fall
outside the romaji engine's coverage (`ざるを得ない`, `っけ`, `っちゃ`, `っこない`). Measured
against the real matcher: every one is typeable. The single failure was `zaruoenai` — typing
`o` for を — which is not an engine gap but exactly the particle pattern the v1.15 Coach
already diagnoses and teaches.

**Carried, not built:** per-word confusion notes and pre-computed drill sets (both need the
N3 batch to exist first), pitch-accent metadata (a content problem), and the IME/batched-input
question Codex raised for macOS marked text and iOS `UIKeyInput` — worth its own measurement
pass before anything touches the input path.
