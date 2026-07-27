# §AI-3 pilot — 60 words, measured (2026-07-27)

Run before deciding whether to generate the 4,953 missing example sentences, because the
question is not "can a model write Japanese" but "what fraction of what survives our gates is
still wrong", and that is a number, not an opinion.

## Setup

60 words with no example sentence — 30 N5, 30 N4, sampled with a fixed seed
(`pilot-60-words.json`). Generated in one call with Gemini 3.6 Flash via `agy`, raw output
in `pilot-60-raw-output.txt`. Then every deterministic gate: shape, latin characters,
duplicate-of-shipped, target presence, reading alignment (Sudachi), and level.

## What the gates caught — and what they got wrong about themselves

**First run: 32 of 60 survived (53%).** Reading the rejections, 23 of the 28 were the GATE
being wrong, not the sentences:

- the level gate compared every token against the vocabulary, so the past-tense auxiliary た
  (which collides with an N2 entry) and the particle で (N3) failed sentences like
  「りんごを三つ買いました。」;
- the target-presence gate is the generator's substring rule, which refuses single-character
  stems — so 「私は大きな鞄を持っています。」 was rejected for not containing 持つ.

Both were rebuilt morphologically: level checks content words only (名詞/動詞/形容詞/副詞/連体詞)
and exempts the target itself; presence asks Sudachi whether a token's dictionary form IS the
target. **Second run: 55 of 60 (92%)**, and all five remaining rejections are correct —
散歩 (N3) inside an N5 sentence twice, 言う tokenised as いい, and 聴く where the entry is 聞く.

The lesson is the same one this project keeps relearning: a gate written from intuition
measures itself. The pilot's first useful output was a bug list for the pilot.

## The number that matters: reading all 55 survivors

**2 real defects (3.6%)**, plus 2 that are odd rather than wrong.

| | sentence | what is wrong |
|---|---|---|
| 見せる | 旅の写真を**ご両親**に見せました。 | ご両親 is honorific — someone ELSE's parents — while the sentence means the speaker's own. Register error. |
| 心 | 彼の**暖かい**心に深く感謝しています。 | warmth of feeling is 温かい; 暖 is temperature. Wrong kanji. |
| 晩 | 今日の晩はカレーを食べます。 | understandable, but 今晩 is what people say |
| 入院 | 風邪をひいて三日間入院しました。 | three days in hospital for a cold |

The register error is precisely the class the Codex review predicted no mechanical gate can
reach, and it survived every one of ours. Nothing here is going to change that: it needs a
reader.

## What that implies for the full 4,953

At this rate an unreviewed full batch ships **roughly 180 defective sentences**, in an app
whose last two releases were about removing wrong Japanese and which shipped an apology for
it. That is not a rate to accept silently.

Reading 55 sentences carefully is maybe twenty minutes. The full corpus is ~90 such passes.

**Recommendation: N5 + N4 only** — 939 words, the levels where the gap hurts most and where
the sentences are simplest and least likely to go wrong, reviewable in a bounded ~17 passes.
Ship nothing from N3–N1 until that is done and its real defect rate is known too. Anything
that does ship carries per-example provenance (model, prompt version, batch, reviewer) so a
batch can be rolled back, which the current data does not have.

## Reproducing

    .venv-jp/bin/python scripts/pilot_gate.py docs/ai-probes/pilot-60-words.json \
        docs/ai-probes/pilot-60-raw-output.txt
