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

---

# The N5+N4 batch (2026-07-27)

939 words with no example sentence — every one at N5 or N4. Generated in 16 calls, about
eight minutes of wall clock.

| stage | in | out | |
|---|---|---|---|
| generation | 939 | 939 | Gemini 3.6 Flash via `agy` |
| deterministic gates | 939 | **838 (89%)** | 84 level, 17 reading, 2 duplicate, 2 target absent |
| two-lens review | 838 | **779 (93%)** | 59 flagged; 20 by both lenses |
| merged | | **779** | each with model / prompt version / batch / reviewer |

The pilot predicted 89–92% through the gates and it held.

## What the review caught that no gate could

24 agents, two lenses over twelve chunks — one asking "is this correct, natural Japanese",
the other "does this sentence do its job and is it safe to ship". 59 of 838, and I read a
random eight to check the reviewers were not simply over-flagging. They were not:

- 「毎晩、暖かいお風呂に入ります。」 — bath water is 温かい; 暖 is air temperature. The same
  homophone error the pilot found in 暖かい心, and worse here because the app teaches 暖かい
  correctly on its own card, so the two would have contradicted each other.
- 「この服は高いですが、しかしとても綺麗です。」 — が and しかし both carry the contrast, and
  しかし cannot follow a が-clause. The card being taught IS しかし.
- 「朝起きて、そして顔を洗いました。」 — same doubling, on the そして card.
- 「おばあさんは今も元気です。」 glossed "my grandmother" — おばあさん is for someone else's.
  The ご両親 class again.
- 「姉は将来有名な学者になりたいです。」 — plain ～たい cannot take a third-person subject.
- 「次の角を右に曲ります。」 — non-standard okurigana; the app's own other card writes 曲がって.
- Translation defects: 手紙 glossed 短信 (an SMS in modern Chinese), みかん as 香橙 (a different
  citrus), 「我从早上就做了洗衣服」 (ungrammatical), and several tense mismatches.

**Policy: everything a reviewer flagged was dropped, all 59.** Some are salvageable with a
one-character fix, but a fixed sentence is an unreviewed sentence again, and the word simply
keeps no example — which is where it started. They can go into a later batch.

## And a defect in the app's OWN data, found by review rather than by any rule

「公園で優しそうなおじいさんに会いました。」 was flagged as not matching its headword. It did
not: entry `n5-b233` was **伯父** (おじ, uncle) with the reading おじいさん and the gloss
"grandfather" — three fields disagreeing with each other, teaching that 伯父 reads おじいさん
and means grandfather. `n5-b037` was 伯父 with the reading おじさん. Both fixed to match their
readings, the way 勉強 became 勉強する and ジェット became ジェット機.

I then checked whether "one surface with several readings" is a rule worth testing: 116
surfaces have more than one, and almost all are legitimate (依存 いそん/いぞん, 潜る
くぐる/もぐる, 怒る いかる/おこる). So there is no rule here — this one needed a reader, which
is what the review was for.

## Where the corpus stands

2,119 → **2,898 example sentences**. N5 and N4 are now essentially covered; N3–N1 still have
4,016 words without one, and nothing from them ships until a batch of their own is generated,
gated and read, with its own measured rate.
