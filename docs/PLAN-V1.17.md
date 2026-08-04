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
found zero "wrong" items in pilot 2. Prompt engineering is not the answer either — pilot 2 was
the good version of that prompt and it plateaued.

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
vocabulary that will never produce this defect. Extrapolating 15% to the full pending set,
roughly **130 of the 872 words** are missing a sense a natural sentence would plausibly use.

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

## 3. Why completing the glosses is necessary but not sufficient

Because the app joins every gloss into one line, completing the data changes what the word
card renders. 通じる is already 26 characters at two glosses; at five it is roughly ninety,
on a phone, on the typing screen, under the word being typed.

So the data fix forces a display decision, and the display decision is what makes the
sentence–sense binding necessary rather than speculative:

- the entry carries the **full** sense set (so the data is true),
- the word card shows a **bounded** number of them (so the screen still works),
- and therefore the example must carry **its own** sense, or we are back to a card whose
  visible glosses may not include the one its example uses.

That is the argument for `exSense`. It is not a nice-to-have; it is what the display cap costs.

## 4. The design

### §A — complete the gloss layer

**A1. Audit all 872 pending N3 words** with the same six-agent pass used for the sample
(`/tmp/gloss-audit` chunks; the script is worth committing as `scripts/gloss_audit.py`).
Expected yield from the sample: ~130 words needing a sense added, ~80 needing en/zh
reconciliation.

**A2. Author the missing senses, review them, merge them.** Rules:
- **Additive only.** No gloss is ever removed or reworded in this pass — a reworded gloss
  changes what an already-shipped example appears to teach.
- Cap raised from 3 to **5**, and only for entries the audit flagged. Everything else is
  untouched, which is where the low regression risk comes from.
- Every added sense is verified against the Japanese, not transplanted from the other
  language (see 名人).
- Gates before merge: ids, `surface`, `kana`, `jlpt`, `vc` byte-identical; only `meanings`
  changes; no duplicate senses within a list; readings still globally unique (`swift test`
  already enforces that).

**A3. Bound the display and bind the example.**
- `gloss(for:)` gains a display cap (3), keeping the full list available for the data.
- `VocabEntry` gains `exSense: String?` — the gloss **this example teaches**, stored as the
  gloss text and not an index, so it cannot silently point at the wrong sense when a list
  changes. `VocabEntry` is bundled read-only data with no persistence or sync surface, so
  this field is contained; it needs a `CodingKeys` entry and nothing else.
- The word card's example row shows `exSense` when it is present and is not already the first
  displayed gloss. One extra line, only when it says something.

### §B — regenerate with the sense declared

**B1. The generator returns `sense` per sentence** — the English gloss the sentence teaches,
which must match one of the entry's glosses after normalisation.

**B2. The gate gains a routing rule, not just a rejection.** A sentence whose declared sense
is not in the entry's list is **not** a bad sentence. It goes to a **vocabulary-gap queue**:
the word needs that sense added (§A2 again), and the sentence is probably fine. This is the
mechanism the v1.16 stop rule said did not exist — it cannot prove the sentence is right, but
it makes the specific failure *legible* instead of silent.

Honest limit: the gate cannot check that the declaration is truthful. A model could declare
sense #1 and write sense #3. What it does buy is a much sharper review question — "this
sentence claims to teach X; does it?" instead of "is this right?" — and sharper questions get
better answers. Declaration honesty gets its own sampled number in B4.

**B3. Re-pilot the same 245 words.** Same seed, same strata, same gate, same two-lens review.
This is the third point in a controlled series and directly comparable to pilots 1 and 2.

**B4. Measure declaration honesty** on a 60-item sample: does the sentence teach the sense it
declares? Reported as its own number, not folded into the defect rate.

### §C — ship or defer, by the rule below

## 5. The stop rule, written before any results

The metric is unchanged: the **adjudicated defect rate among gate survivors, counted before
flagged items are removed**. v1.16's pilots ran 13–15%.

**N3 ships when all three hold:**
1. adjudicated defect rate **≤ 10%**;
2. **zero** false-reading defects;
3. **zero** gloss-versus-sense defects that the gate did **not** route to the vocabulary-gap
   queue.

The third is the real test and it is deliberately not "zero mismatches". The claim this plan
makes is that mismatches become *visible and routed*, not that they stop existing. If they are
still arriving silently, the mechanism failed and N3 waits again.

Additionally, §A ships **on its own merits even if §B stops again**: completing the glosses
makes the existing 2,898 example sentences and every word card more accurate for English
users today, independent of N3.

## 6. What I am not building, and why

- **Re-deriving all glosses from JMdict.** The measurement says 85% of entries are fine.
  Churning the displayed text of 7,000 entries to fix 15% of one level is the wrong trade, and
  the licensing and quality questions are unanswered.
- **One sentence per sense.** Multiplies the review burden by the polysemy factor for no
  measured learner benefit.
- **A machine sense-matcher** (decide from the sentence which gloss it uses). That is the same
  judgment the reviewers are already making, with less accuracy and no accountability.
- **Touching N2/N1.** Same audit, later, once the method has a passing pilot behind it.

## 7. Sequencing and what each step costs

| step | work | gate |
|---|---|---|
| A1 | 872-word audit, 6 agents × ~4 chunks | none — measurement |
| A2 | author ~130 sense additions + review | additive-only diff gate + `swift test` |
| A3 | `exSense` field, display cap, example row | render gate + device check at large type |
| B1–B2 | generator `sense` field, gate routing rule | calibrate against the 779 reviewed corpus first |
| B3 | re-pilot 245, eight review agents | the stop rule in §5 |
| B4 | 60-item declaration-honesty sample | reported separately |

**Calibrate before trusting, as always.** Every gate change in B2 runs through
`scripts/gate_calibration.py` against the 779 already-reviewed sentences before it is allowed
to judge new material. Five of eight candidate gates died there during v1.16; the odds that a
new one is right by intuition are not good.
