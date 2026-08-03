# v1.16 — Live Coach, N3 content, and the debts v1.15 left

Status: proposal, for Codex and Gemini review before any code.

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
deterministic gates and the human read that shipped 779 sentences in v1.15 at a measured
3.6% pre-review defect rate.**

The v1.15 constraint therefore hardens: *the app authors every Japanese character; the model
never does, at runtime or otherwise, without a gate and a reader between it and a learner.*

## 2. The update

### §A — Live Coach (the headline; deterministic)

v1.15's Coach explains a mistake **after** the ride. Both reviewers named the same next
step, for the same reason: the diffing machinery already exists, and the moment a learner
can actually use the information is the moment the key is refused, not five minutes later.

At the instant of a refusal the app already knows the target kana, the romaji accepted so
far, the key pressed, the keys that would have worked, and which kana the learner is
standing on. Today it discards all of that into a red flash and a combo reset.

Live Coach spends that information, once, at the right time:

- the refused key is shown against a key that works, aligned at the divergence — the same
  `MistakeReplay` the Coach screen draws, inline and immediate;
- it appears only on the **second** refusal at the same kana, so a slipped finger is not
  lectured at;
- it never blocks input, never steals focus, and disappears the moment the correct key
  arrives;
- it is off during Time Attack (the mode is a sprint; an explanation mid-sprint is a
  penalty), and behind a setting, default on.

Everything it shows is derived, not authored. No model, no network, nothing new persisted.

### §B — N3 example sentences (the AI, where it is measured to work)

2,898 of 7,074 words have an example. N5 and N4 are covered. **N3 has 872 without one** and
is the level where learners live longest.

Same pipeline as v1.15 §I, with the gates it grew: shape, no-latin, no-duplicate,
morphological target presence, reading alignment via Sudachi, level ceiling. Then generation
in batches, then the two-lens agent review, then my adjudication, then merge with per-example
provenance (`exMeta`) so a batch stays rollback-able.

**N3 is harder than N5/N4 and the gates must be re-measured, not assumed.** A pilot of 60
N3 words runs first and reports its own numbers; the full batch only proceeds if they hold.
Specifically expected to be worse at N3: homographs (more kanji with several readings),
transitivity pairs (上がる/上げる, 変わる/変える), and register (N3 introduces keigo contexts).
If the pilot's post-review defect rate is materially worse than N5/N4's, the batch stops and
the release ships without it.

### §C — The two data-loss debts v1.15 found and did not fix

Both were confirmed still present in the code today.

**An unreadable word-list file gets overwritten.** `WordListStore.loadOrMigrate` carefully
returns `.unreadableDeferred` so a file it could not READ is left alone — and `AppModel`
discards the outcome (zero references). The session runs on an empty store and the next ★
tap saves it over the good file. The loader's whole reason for distinguishing "unreadable"
from "corrupt" is undone by the first write. Same fix as v1.15 §C did for the four other
stores: keep the outcome, gate the writes, tell the user.

**The v1.4 favorites migration silently drops everything past the 500th.**
`seedDefaultIDs` does `prefix(maxWordsPerList)`. v1.4 had no cap, so a user with 620 saved
words loses 120 — and then `enqueueAllLocal` pushes the truncated deck over the cloud copy.
Fix: spill into auto-created "★ 2", "★ 3" lists (the 50-list cap leaves room) and report the
spill so it can be surfaced once.

### §D — The accessibility debt, led by the worst case in the app

At AX5 in Practice, **the characters the learner has to type are behind an ellipsis**.
`PracticeView` has no `dynamicTypeSize` cap (GameView and ConjugationGameView both cap at
accessibility1) and the passage `Group` has no ScrollView, so the target text truncates.
A typing app that hides the typing target is broken, not merely inconvenient.

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

## 4. Open questions for the reviewers

1. Is Live Coach the right headline, or is it a distraction that clutters the one screen
   where the learner is concentrating? Is "second refusal at the same kana" the right
   trigger, or should it be time-based, or per-word?
2. What breaks at N3 that the N5/N4 gates cannot see, beyond homographs, transitivity and
   register? What extra gate would you add before the pilot rather than after?
3. Is there an AI-shaped feature I am dismissing too fast because the ON-DEVICE model is
   bad — something a large model could do offline, at build time, that would show up as a
   user-visible feature rather than as content? (Pre-computed per-word confusion notes?
   Pre-computed drill sets? Something else?)
4. §C's spill fix creates lists the user did not ask for. Is that better or worse than
   raising the per-list cap for the default list only?
