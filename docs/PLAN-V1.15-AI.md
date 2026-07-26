# v1.15 — AI in Nihongo Ride

Status: proposal. Written after measuring the on-device model rather than assuming it.

---

## 1. What I measured, before designing anything

Apple's `FoundationModels` (on-device, free, no network) is present in both SDKs under
Xcode 26.6, and `SystemLanguageModel.default.availability` is `.available` on this Mac.
So the capability is real. The question is what it is actually good at *here*.

Four probes, all on-device, verbatim results in `docs/ai-probes/`:

**Probe A — can it write Japanese example sentences?** Five target words, guided generation
with a `japanese` / `kana` / `english` schema.

| target | it produced | verdict |
|---|---|---|
| 勉強する | 「勉強する。」 | not a sentence, just the word |
| (garbage input) | an unrelated sentence, confidently | no refusal |
| 披露 | kana kept 出す in kanji, stray spaces | malformed |
| 落ち着く | 落ち着いて → **てきじゅうていて**, ゆっくり → **りょくりょく** | not Japanese |
| しかし | kana kept 面白かった in kanji | malformed |

**Five out of five had a defective kana field.** Kana is the typing target — it is the string
the learner is graded against. This single result disqualifies the obvious design.

**Probe B — can it analyse mistakes?** Given explicit data (`shi -> si (7), chi -> ti (5),
tsu -> tu (4), …`), the pattern is plainly kunrei-shiki romaji plus dropped sokuon.

- English: pattern = *"Consistent mistake pattern"*, advice = *"Keep practicing!"*
- Chinese: pattern = *"Vowel sound changes"* — wrong, these are consonants — and it
  **answered in English despite Chinese instructions**.

**Probe C — constrained classification** into six named patterns, four easy cases: **2 of 4
correct**. `kya -> kiya` was classified as a long-vowel problem. Even when the label was
right, the advice was nonsense: for a romaji-system issue it suggested *"practice writing
kanji characters in their traditional forms."*

**Probe D — grounded explanation** from the app's own dictionary row (word, authoritative
reading, glosses): the one task it did acceptably. Usable prose, nothing invented.

Latency: 1–2 s warm, 8–10 s cold. Requires Apple Intelligence enabled on an eligible device.

## 2. What that forces

The app's last two releases were entirely about not teaching wrong Japanese — v1.14 shipped
an apology in its release notes for 保育 being drilled as ほいって. A model that gets the
reading of 落ち着いて wrong would reintroduce exactly that failure, at scale, generated fresh
for every learner, with no reviewer in the loop.

So the rule this design is built on:

> **The app authors every Japanese character the learner reads or types.
> The model may explain, in the learner's own language, grounded in data the app supplies.
> It never authors Japanese, and it is never in the trust path.**

The corollary is the part worth saying out loud: for the diagnosis itself, *the app is better
than the model*. It owns the romaji NFA, the kana tables and every keystroke. It can say
"you are typing kunrei-shiki: si/ti/tu where this app teaches shi/chi/tsu" — correctly, every
time, in 0 ms. Asking a model to guess that from a summary is strictly worse. The model's
honest job is warmth, not truth.

## 3. The update

### §AI-1 — Coach (the headline feature)

A new screen, plus an entry point on the results screen when there is something to say.

**Diagnosis: deterministic.** A new `DiagnosticsKit` classifies recorded mistakes into named
patterns using the app's own romaji tables:

| pattern | signature | what the learner needs |
|---|---|---|
| **particle は/へ/を** | typed `wa`/`e`/`o`, got わ/え/お | the rule: these three are written `ha`/`he`/`wo` |
| **ん before a vowel or y** | `honya` → ほにゃ, wanted ほんや | the rule: `nn` (or `n'`) closes ん |
| dropped sokuon | expected っ, got the bare consonant | `tt`/`kk`/`ss` doubles the consonant |
| long vowel | missing/extra ー, おう vs おお | which words take う and which take お |
| small ya/yu/yo | `kiya` → きや, wanted きゃ | `kya` is one key sequence, not two |
| dakuten | が/か, だ/た, ば/ぱ | a reading problem, not an input one — drill the words |

The first two are the highest-value entries and neither was in the first draft of this plan.
**こんにちは is the very first passage in the corpus**, 152 of 233 passages contain particle は,
134 contain を, 33 contain へ — and a learner typing what they hear (`konnichiwa`) gets
こんにちわ every time. This is the most common romaji-input mistake there is, it is live in the
app's most-used practice content, and the app can detect it exactly.

**What the first draft got wrong, and it matters.** It led with a "kunrei-shiki" pattern —
flagging `si`/`ti`/`tu` as mistakes. The engine's own table accepts all of them
(`romaji-hiragana.tsv` lines 207, 257, 258, 278, 242), and onboarding advertises "し = shi / si"
as a feature. It is not a mistake in this app; I had invented the probe data and then designed a
diagnostic for the fiction. Caught by the Gemini review. The lesson generalises: a pattern only
belongs here if the ENGINE rejects it, so each one ships with a test that feeds the wrong input
through `KanaInputMatcher` and asserts it is actually rejected.

**Remedy: the rule, then the practice — in that order.** The review's sharpest point: if a
learner types `kiya` for きゃ, the cause is not that they don't know the word, it is that they
don't know the key sequence. Handing them a vocabulary deck drills the wrong thing. So each
pattern leads with a short, concrete rule and a **character-level replay of their own mistake**
— the romaji they typed against the romaji that would have worked, aligned at the point of
divergence — and only then offers a drill built from the app's own vocabulary by structural
query, for the patterns where repetition actually helps.

**Phrasing: optional, on-device.** When Apple Intelligence is available and the setting is on,
the model rewrites the app's own diagnosis into one warm, personal sentence — given the
pattern name, the fix, and the counts. The written fallback is always present and always
correct; the model's line replaces it only if it arrives, and is capped in length. Off, or
unavailable, or slow → the feature is complete without it.

### §AI-2 — Word insight

On the results screen's review list and in the word detail: "why this word trips people up",
generated on-device from the word's authoritative reading, glosses and level — the one task
Probe D showed it does acceptably. Opt-in, cached per word (so it costs one generation ever),
labeled as AI-written, never introduces Japanese beyond the word already on screen, and
silently absent when the model is not available.

### §AI-3 — Example sentences for the 4,952 words that have none

2,122 of 7,074 entries have an example sentence. This is the biggest content gap in the app,
and it is where a *large* model earns its place — offline, at build time, through the existing
committed pipeline (`scripts/gen_examples.py`), never at runtime:

1. generate candidates with a strong model (Gemini 3.x via `agy`, or Claude);
2. **validate against the app's own engines**, not against a reviewer's patience —
   the kana must be typeable by `RomajiKana`, the reading of the target word must match
   `VocabStore` exactly, any conjugated form must equal `Conjugator`'s output, the kana must
   be globally unique, the sentence must contain the target word;
3. sample-audit what survives, by hand;
4. ship the survivors as data, with provenance in the id, exactly like every previous batch.

**Those gates are necessary and nowhere near sufficient.** The Gemini review produced five
concrete sentences that pass every one of them and are still wrong:

- **transitivity** — 「彼がドアを開く」: 開く is intransitive, so を is ungrammatical. The
  reading matches, the kana is typeable, the word is present.
- **homograph** — target 角 (かど, "corner"), sentence 「牛の角が大きい」, which reads つの.
  The learner is graded on a reading the sentence does not have.
- **level overload** — an N5 target wrapped in N1 vocabulary: correct, useless.
- **register mixing** — 「わたくしは本日にラーメンを食べる」: humble nouns, plain verb.
- **semantic absurdity** — 「電気を勉強する」: parses, means nothing.

So the gate set grows: a morphological pass (Sudachi/MeCab) must agree that the target token
carries the target reading — that alone kills the homograph class, which is the dangerous one
because it teaches a false reading; every non-target token must be at or below the target's
JLPT level plus one, using the app's own 7,074-entry level data; transitivity is checked
against the JMdict POS the entries already carry; and register/naturalness stay a human
sample-audit, because nothing mechanical catches translation-ese. A batch that cannot clear
this ships as nothing — the app is better with 2,122 good sentences than 7,074 uneven ones.

The model proposes; the app's deterministic engines dispose. Nothing reaches a learner that
the app cannot itself verify.

### Privacy and review

Everything at runtime is on-device; §AI-3 happens on my machine before the build. **No network
calls, no accounts, no data leaves the device**, so App Privacy stays "Data Not Collected" and
the review notes stay true. Worth stating plainly in the notes, because "AI" in a release note
invites the question.

## 4. What I am NOT building, and why

- **Runtime generation of Japanese practice content.** Probe A. It would undo v1.14.
- **A chat tutor.** Latency 8–10 s cold, and every Japanese sentence it produced was suspect.
- **Model-authored mistake diagnosis.** Probe B and C: the app does it correctly and instantly.
- **A cloud model.** It would end "Data Not Collected", add a key, a cost and a failure mode,
  for a feature the device can do.

## 5. Risks

- **Apple Intelligence is not universal.** Eligible hardware, enabled by the user, model
  downloaded. Every AI surface must be additive and absent-by-default, never a hole in the UI.
- **The model ignored a Chinese instruction once.** Chinese output must be verified per surface
  or the AI phrasing must be English-only until it is.
- **Deployment target.** The app ships iOS 17 / macOS 14; `FoundationModels` needs 26. All AI
  code sits behind `if #available`, and the deployment target does not move.
- **Quality drift.** The model updates with the OS. Anything it writes must be labeled and
  non-load-bearing, which the design already requires.

## 6. Sequencing

§AI-1 is the release. §AI-2 is small once §AI-1's availability plumbing exists. §AI-3 runs in
parallel on my machine and lands as data whenever a batch passes its gates.

The v1.15 correctness work already committed (§A–§D) ships in the same release.

---

## 7. Review round 1 — Gemini 3.6 Flash (via `agy`, 2026-07-26)

It was given the plan as text with no repository access, and asked for disagreement. Four
things it said that changed the plan, and one it said that I am not taking.

**Taken — the kunrei-shiki pattern was fiction.** Covered in §AI-1 above. This is the review's
biggest single contribution: I had designed a diagnostic for input the engine accepts.

**Taken — the missing patterns are the important ones.** Particle は/へ/を and ん-before-vowel,
which it called the most common romaji-input mistake there is. Verified against the corpus:
こんにちは is passage #1, and 152 of 233 passages contain particle は.

**Taken — a word drill is the wrong remedy for an input-mechanics error.** "The root cause is
IME key-sequence ignorance, not unfamiliarity with vocabulary containing 拗音." §AI-1 now leads
with the rule and a character-level replay of the learner's own divergence.

**Taken — the pipeline gates are porous.** Five concrete counter-examples, now in §AI-3, plus
the morphological / level / transitivity gates they force.

**Noted, not taken — "the model selects from app-authored candidates".** It is genuinely safe
(no invalid Japanese is reachable) and I dismissed it too fast in the first draft. But the app
has 2,122 sentences across 7,074 words: there is almost never more than one candidate to choose
between. The architecture is right and the data does not exist yet. If §AI-3 lands and words
start carrying three or four validated sentences, selection becomes the obvious next use — and
it stays inside the constraint. Recorded here so it is not rediscovered from scratch.

Two more of its blind-spot points I am carrying but not building now: real-time character-level
feedback DURING typing (the diffing machinery §AI-1 needs is the same machinery, so this is a
natural v1.16), and pitch-accent metadata alongside TTS (a content problem, not a code one).
