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

| pattern | signature | remediation drill |
|---|---|---|
| kunrei-shiki | `si/ti/tu/hu/zi` accepted where `shi/chi/tsu/fu/ji` is taught | words rich in し・ち・つ |
| dropped sokuon | expected っ, got the bare consonant | words containing っ |
| long vowel | missing/extra ー or doubled vowel | words containing ー and おう/えい |
| small ya/yu/yo | きゃ typed きや | words with拗音 |
| dakuten | が/か, だ/た, ば/ぱ | minimal pairs from the deck |
| ん before vowel | んあ vs な | words with ん before a vowel |

Each pattern carries a written explanation and a **drill built from the app's own vocabulary
by structural query** — so the practice content is as correct as the dictionary is. This is
the actual new capability: the app notices what you keep getting wrong, names it, and hands
you a targeted set. None of it needs a model.

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
