# v1.17 — the gloss layer, and the N3 sentences it unblocks

v1.16 shipped without N3 example sentences. The pre-committed stop rule fired on both pilots,
and the second one located the blocker precisely: **the app shows a gloss that does not
include the sense the sentence uses.** This plan fixes that, and it starts where the last one
ended — with a measurement, not a design.

## 1. What the v1.16 pilots proved, and what they did not

Two pilots, 245 stratified N3 words each, 208 gate survivors each, eight review agents each.

|  | pilot 1 | pilot 2 |
|---|---|---|
| flagged | 55 (26.4%) | 53 (25.5%) |
| severity "wrong" | 13 | 8 |
| false readings among "wrong" | 2 | 0 |
| gloss-mismatch among "wrong" | 6 | 0 |

Pilot 2's prompt change — pin the sense to the displayed gloss, forbid burying the word in a
compound, allow the model to decline — moved the severe end a long way and got the model to
refuse 6 words rather than write something wrong. It did **not** remove the gloss-mismatch
class; it demoted it. 通す was still threading a needle against "to let pass"; 見舞い was still
an ordinary sick-visit against "enquiry"; the English for 場 still said "opportunity".

**What that rules out.** The Japanese is not the problem: three of four correctness reviewers
found zero "wrong" items in pilot 2.

What it does **not** rule out — and the first draft of this plan wrongly claimed it did — is
prompt engineering. Pilot 2's prompt told the model to pin the sense to the displayed gloss
while feeding it an incomplete gloss list, i.e. it asked for natural Japanese for a word whose
natural usage had been excluded from the input. That is a contradiction, not a ceiling. The
prompt that has never been tried is the opposite one: let the model use the sense it wants and
**say which sense it used**. §A is that experiment.

## 2. The measurement (2026-08-04)

Two facts about the app that reframe the whole thing.

**Fact one: the app already displays every gloss it has.** `VocabEntry.gloss(for:)` is
`meanings(for:).joined(separator: ", ")`. There is no selection step and never was. So a
"mismatched gloss" never means the app picked the wrong one — it means **the sense is not in
the list at all.**

**Fact two, measured on a 240-word random sample of the 872 pending N3 words**
(`Sources/VocabKit/Resources/n3.json`, audited by six agents):

| verdict | count | share |
|---|---|---|
| en and zh cover the same senses | 199 | 83% |
| zh carries a sense en does not | 16 | 7% |
| en carries a sense zh does not | 5 | 2% |
| both lists incomplete | 20 | 8% |
| **a common sense NEITHER list carries** | **36** | **15%** |

| polysemy risk | count | share |
|---|---|---|
| low — the word means essentially one thing | 203 | 85% |
| medium | 26 | 11% |
| high — several common unrelated senses | 11 | 5% |

**The problem is concentrated, not systemic.** 85% of N3 words are single-sense concrete
vocabulary that will never produce this defect.

**How much to trust these numbers.** Each word was judged once, by one agent — there is no
second opinion and therefore no inter-rater number, and the judge is an LLM assessing glosses
another LLM wrote, with no lexicographic authority behind it. The sample is also unstratified,
while Japanese polysemy skews hard by word class. So 15% is an *estimate of where to look*,
not a count to plan headcount against — which is why §A measures the gap on real generated
output instead of scaling this audit to all 872.

**And the missing senses are not obscure — they are the dominant ones:**

| word | app shows | missing |
|---|---|---|
| 通り | avenue, street | as / in accordance with (言った通りに, 予想通り); その通り; 人通り |
| 次第 | order, depending on | as soon as ~ (決まり次第); 次第に; こういう次第です |
| 元 | origin, original | former / ex- (元社長); the source of something (火の元) |
| 通じる | to lead to, to communicate | to get through (電話が通じない); to be well-versed in; 一年を通じて |
| 生 | (raw) | live, not recorded (生放送); in person (生で見る) |
| 相当 | suitable, fair | considerably (相当疲れた); to be equivalent to |

For a word like 通り, the *most likely* sentence a fluent writer produces uses a sense the app
does not list. That is why the pipeline keeps failing on it, and why no prompt can fix it: the
model would have to write a sentence it knows is unnatural in order to match an impoverished
gloss.

**One caveat the measurement produced, which matters for the implementation.** The Chinese
glosses cannot be trusted as a source to copy from: for 名人 the audit found the zh gloss is
the ordinary *Chinese* reading of those characters and not a live sense of the Japanese word —
a false friend sitting in the data. Any reconciliation pass must verify a sense, not transplant
it.

## 3. What the review broke — and what is left standing

The first draft of this section argued: completing the glosses forces a display cap, and the
cap is what makes a per-example `exSense` field necessary. **Gemini 3.6 rejected that
argument and the measurements agree with Gemini.**

- **The cap barely binds.** Of the 36 sampled entries needing a sense added, only **6** are
  already at three English glosses. The other 28 have two, so the addition fits inside a cap
  of three and is displayed anyway. A cap justified by 6 entries in 240 does not force a
  schema change.
- **A count cap is the wrong shape regardless.** Three long glosses wrap; five short ones fit
  on one line. If the display needs bounding it should be bounded by width, in the view, not
  by count, in the data.
- **The three cards do not behave the same way, and the first draft treated them as if they
  did** (Codex). There are **five** consumers of the gloss, not three:

  | site | behaviour with a longer gloss |
  |---|---|
  | `GameView.swift:413` | no `lineLimit` → **wraps**, card grows. Measured at 14.4 pt/char: 通じる is 1.3 lines today, 4.3 at five senses, on a ~380 pt card with the keyboard up. |
  | `ConjugationGameView.swift:266` | `.lineLimit(1).minimumScaleFactor(0.5)` → **shrinks to half size, then truncates**. This is the one that actually breaks. |
  | `ListsView.swift:343`, `ResultsView.swift:327` | one-line glosses in lists and result chips — also affected, and unnamed in the first draft. |
  | `PracticeView.swift:293` | **not evidence.** Practice builds synthetic passage entries whose only "meaning" is the passage translation; N3 gloss growth cannot lengthen it. |

- **Six shipped entries already exceed three glosses** — 宜しく (4), 割り込む (5), 様 (4), 汚す (4),
  苦心 (4), 隙間 (4). A global `prefix(3)` is therefore already a change to shipped N1/N2 cards,
  which contradicts the first draft's "everything else is untouched".

So `exSense` is **not** adopted as a committed design. If a display bound turns out to be
needed, the cheap options come first: truncate in the view, or order the entry's glosses so
the one its example uses leads.

### The hazard the review surfaced that nearly shipped

Gemini objected that a flat gloss list hides grammar and phonology, and gave 通り as the
example. Checked against the data and Sudachi, it is worse than a style objection:

- the entry is 通り / **とおり**, glossed "avenue, street";
- the sense the audit says is missing is 「言ったとおり」/「予想どおり」;
- 予想どおり is **どおり** — Sudachi reads it `ドオリ` against the entry's `トオリ`.

So adding that sense invites sentences whose reading is not the reading the app teaches —
manufacturing exactly the false-reading defect the stop rule bans. **My audit's
`missingFromBoth` list contains reading changes disguised as sense additions**, and a
gloss-completion pass that trusted it would have imported them.

(One case I initially added to this list was my own error, not the audit's: 生放送 is
なまほうそう, so the "live" sense of 生 really is at the entry's reading.)

The fix is not a new gate — it is the gate that already exists. A proposed sense is only
legitimate if a sentence using it tokenizes to the entry's kana, and `pilot_gate.py` already
performs exactly that reading-alignment check. **Which means the sense and the sentence must
be authored and validated together**, because the sentence is the evidence that the sense is
realised at the taught reading. That collapses the two-phase design below into one loop.

## 4. The design — one loop, not two phases

### §A — pilot 3: let the model name the sense, and measure the real gap

Same 245 words, same seed, same strata: the third point in a controlled series.

The generator returns, per word, `jp` / `en` / `zh` **and `sense`** — a short English gloss
naming the sense the sentence teaches, written **freely**, not constrained to the entry's
list. Pilot 2 constrained it to the list and that is precisely what plateaued: it asked for
natural Japanese for a word whose natural usage the prompt had excluded. (Gemini called the
first draft's "prompt engineering is not the answer" circular, and it was right — the
untested prompt is this one.)

The gate runs unchanged, then classifies each survivor by its declared sense:

- **sense already in the entry's list** → the normal path;
- **sense not in the list** → a *proposed gloss addition, backed by a sentence whose reading
  the gate has already verified*.

That second bucket is the measurement the whole plan exists for. It reports, on real generated
material, how many N3 words actually need a sense — replacing the audit's hypothetical "a
natural sentence could plausibly use this".

### §B — adjudicate the pair, not the sentence

The two review lenses judge (sentence, sense) **together**:

1. does the sentence teach the sense it declares?
2. is that sense a real sense of this word **at this entry's reading**?

Question 2 has teeth only because the reading gate has already run. Measured on the audit's
own proposals: of 49 that were machine-checkable, **3 carry a different reading** — 注ぐ is
つぐ but 力を注ぐ reads そそぐ; 下す is おろす but 判断を下す and 命令を下す read くだす — plus the
通り/予想どおり case, which surface matching cannot even see. A gloss-completion pass that
trusted the audit would have imported all four as "new senses".

### §C — merge additively, with the evidence attached

Accepted additions go into `meanings`, **appended**, never reordered or reworded: a reworded
gloss changes what an already-shipped example appears to teach. Each carries `exMeta`
provenance, as sentences already do, so a batch stays rollback-able.

Gates before merge: `id`, `surface`, `kana`, `jlpt`, `vc` byte-identical; only `meanings`
grows; no duplicate sense within a list; `swift test` still green (it already enforces
globally unique readings).

This is also the answer to the "vocabulary gap queue" Gemini called a deadlock: there is no
queue beside the pipeline. The gap is resolved in the same loop that found it.

### §D — display, decided after §C and not before

Only after §C is the real distribution of gloss-line lengths known. Then:

- if the 95th-percentile line still fits two lines on a phone with the keyboard up, **do
  nothing**;
- if not, bound it **in the view, by width** — a count cap is the wrong shape, since three
  long glosses wrap and five short ones do not — or order an entry's glosses so the one its
  example uses leads;
- a stored `exSense` field is the last resort, adopted only if the display work proves it
  necessary. It is **not** in scope by default.

## 5. The stop rule — falsifiable this time

The first draft's third condition was "zero gloss-versus-sense defects that the gate did not
route". **Gemini showed that is unfalsifiable, and it is right.** The gate can only check
`declaredSense ∈ glosses`; a model that declares sense A and writes sense B passes it. A stop
condition must not depend on a check that the failure it targets can defeat.

So condition 3 moves to the review, which actually reads the sentence.

**N3 ships when all three hold:**

1. adjudicated defect rate **≤ 10%** among gate survivors, counted before flagged items are
   removed (v1.16's pilots ran 13–15%);
2. **zero** false-reading defects;
3. **declaration honesty ≥ 95%** on a 60-item hand-read sample — for each, does the sentence
   teach the sense it declares? Below that threshold the declaration is noise and every
   routing decision built on it is worthless.

Condition 3 fails loudly and specifically if the model games the declaration, which is exactly
what the previous wording assumed away.

**And "routed" is not a shipping state** (Codex). Three things have to be true or "zero
unrouted defects" measures process visibility instead of what a user sees:

- the gate returns one of three dispositions — `reject`, `vocabularyGap`, `survive` — with the
  routing decision logged, not a flat list of rejection strings as today
  (`pilot_gate.py` currently treats any reason as rejection);
- **a routed item may not ship as-is.** Once its sense is added in §C it re-enters generation
  and gating and gets fresh adjudication, in the same pilot;
- the final merged data must show **zero adjudicated sentence-versus-visible-sense defects**,
  however the item was routed on the way there.

Below the 95% honesty threshold the pilot stops and the declaration mechanism itself is the
thing under review, not the sentences.

## 6. What I am not building, and why

- **A standalone 872-word gloss audit.** The 240-word sample earned its keep — it produced §2
  and found the hazard in §3 — but scaling it is speculative work about words that may never
  need a sentence. §A measures the gap on material that actually gets generated.

  **Correction to the first draft:** it claimed §A "ships on its own merits — completing the
  glosses improves every word card for English users today, independent of N3". That is false,
  and Codex caught it. §A is scoped to the 872 N3 entries that have **no** example; the 2,898
  entries that DO have one are a disjoint set, overlap zero by definition. The independent
  benefit is real but much narrower: better word cards for those 872 pending words.
- **`exSense` as a committed field.** §3 and §D: the display argument for it did not survive
  measurement.
- **A vocabulary-gap queue.** A queue with no resolution path is a bottleneck with a nicer
  name; §C resolves gaps inside the loop.
- **Re-deriving all glosses from JMdict.** 85% of entries are fine. Churning 7,000 entries'
  displayed text to fix 15% of one level is the wrong trade, and the licensing and quality
  questions are unanswered.
- **One example sentence per sense.** Multiplies review burden by the polysemy factor for no
  measured learner benefit.
- **Touching N2/N1.** Same method, later, once it has a passing pilot behind it.

## 7. Sequencing

| step | work | gate |
|---|---|---|
| A | pilot 3: regenerate 245 with a free `sense` declaration | existing gates unchanged |
| B | eight review agents on (sentence, sense) pairs, then adjudication | — |
| C | merge accepted sense additions | additive-only diff gate + `swift test` |
| D | measure gloss-line lengths, then decide the display | render gate + device check at large type |
| — | apply §5 | ship or defer |

Roughly half the first draft's cost: no 872-word audit, no schema change, no display work
before it is shown to be needed.

**The calibration claim in the first draft does not hold, and this is the correction that
matters most.** It said any gate change calibrates against the 779 reviewed sentences first.
It cannot: `gate_calibration.py` builds its corpus from `id / jp / en / zh` only — those
sentences carry **no declared sense**, so the corpus cannot test declaration matching,
normalisation, routing, or honesty. Either the 779 get adjudicated sense labels, or a separate
labelled calibration set is built, **before** the routing rule is allowed to judge anything.
The five-of-eight lesson from v1.16 still stands; what changed is that this particular safety
net does not currently reach this particular gate.

### The change surface, named

The first draft said `exSense` needs "a `CodingKeys` entry and nothing else". Codex verified
that is false. Even the reduced design touches:

| file | change |
|---|---|
| `scripts/gen_batch.py` | prompt input semantics + the fixed `id/jp/en/zh` output contract |
| `scripts/pilot_gate.py` | a three-way result model instead of a flat reason list |
| `scripts/apply_batch.py` | currently writes only `exJP/exEN/exZH` + `exMeta` — a declared sense is silently discarded today |
| `scripts/gate_calibration.py` | a sense-labelled corpus |
| — | an additive ordered-diff validator for `meanings`; none exists (`swift test` only enforces globally unique readings) |
| `Tests/ConjugationDataTests/ExampleSentenceTests.swift` | no sense-binding coverage; its header still says "2,121 shipped example sentences" against 2,898 in the data |

And **if** §D concludes a stored field is needed after all: `VocabEntry`'s stored properties,
`CodingKeys` **and** its custom initialiser, plus `GameSession`/`ConjugationSession` exposure
and the UI — and it must be **localised** (`exSenseEN`/`exSenseZH` or a dictionary), because an
English-only field would render English text in Chinese mode, a new user-visible mismatch.

## 8. Implementation status

| step | state |
|---|---|
| A1 `gen_batch.py` declares the sense; the pin-to-gloss constraint is gone; the reading rule for sense choice is in | **done** |
| A2 `pilot_gate.py` three dispositions + loose sense matcher (8 cases pinned); rejection path unchanged, verified at 1.2% against the 779 | **done** |
| A3 `apply_batch.py` carries the sense into `exMeta` | **done** |
| B pilot 3 on the same 245 words, same seed | running |
| review + adjudication of (sentence, sense) pairs | next |
| §C merge, §D display, stop rule | after the pilot reports |

## 9. What the reviews changed

| raised by | claim | disposition |
|---|---|---|
| Gemini 3.6 | "completing the glosses forces a display cap, which forces `exSense`" is invalid | **Accepted.** Measured: only 6 of 36 affected entries are at the cap; the line wraps rather than clips. `exSense` dropped from the committed design. |
| Gemini 3.6 | "prompt engineering plateaued" is circular — pilot 2 pinned the sense to an incomplete list | **Accepted.** §A is now exactly the untested prompt: declare the sense freely. |
| Gemini 3.6 | the stop rule's routing condition is unfalsifiable | **Accepted.** Condition 3 rewritten as a hand-read declaration-honesty threshold. |
| Gemini 3.6 | a flat gloss list hides grammar and phonology (通り / -どおり) | **Accepted, and it is worse than stylistic.** Verified with Sudachi; drove the reading-gate requirement in §B. |
| Gemini 3.6 | exact string matching will flood the queue on `"as soon as"` vs `"as soon as; immediately"` | **Accepted.** No string match is a pass/fail gate any more: an unmatched sense is a routing signal, and review judges it. |
| Gemini 3.6 | the audit is LLM-judging-LLM with no lexicographic authority and no agreement threshold | **Accepted as a limit on §2.** Each word was judged once, not voted on. §A replaces the estimate with a measurement on real output rather than scaling the audit. |
| Gemini 3.6 | net-zero viewport saving: the cap saves a line, `exSense` adds one back | **Accepted**; part of why §D is deferred and `exSense` is not default. |
| Gemini 3.6 | en/zh top-N may cover different sense sets, so a cap breaks one language | **Accepted**; recorded as a constraint on any §D display bound. |
| Codex | the three cited cards do not behave alike, and there are five gloss consumers not three | **Accepted.** §3 rewritten per site. The conjugation card is the one that truncates; Practice is not evidence at all. |
| Codex | "§A improves every word card / the 2,898 existing examples" is false | **Accepted — a flat error.** The 872 pending and the 2,898 with examples are disjoint. Corrected in §6. |
| Codex | six shipped N1/N2 entries already exceed three glosses, so a global `prefix(3)` is not "untouched" | **Accepted**; listed in §3 as a constraint on any display bound. |
| Codex | "`CodingKeys` and nothing else" is false; and an English-only `exSense` breaks Chinese mode | **Accepted.** §7 now names the change surface, including localisation. |
| Codex | the 779-sentence corpus cannot calibrate a declaration-driven route — it has no sense labels | **Accepted, and it is the most important correction.** §7 rewritten: a labelled set has to exist first. |
| Codex | `apply_batch.py` would silently discard a declared sense | **Accepted**; in the change-surface table. |
| Codex | "zero unrouted" measures process visibility; routed items need a lifecycle | **Accepted.** §5 now requires three explicit dispositions, forbids shipping a routed item as-is, and adds a final zero-defect condition on the merged data. |
| Codex | the audit percentages are not reproducible from the repo | **Accepted.** The 240 judgments and their limits are committed at `docs/measurements/n3-gloss-audit-2026-08-04.json`. |
| Codex | "full sense set" contradicts a hard cap of five | **Accepted**; the cap is gone with `exSense`. §C appends what review accepts and §D decides display separately. |
| Codex | verdict: **rework** | **Taken.** This revision is the rework; the design is smaller than the draft it replaces. |
