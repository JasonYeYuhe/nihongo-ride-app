# v1.22 — finish what v1.21 started, and pay a debt that is live

v1.21 shipped dictation, gave Sentence mode a pool that follows the learner, and settled
§C. Three things it left behind are already on `main` and one of them is a bug that is
affecting users right now.

## §0 Already on main (the reason to ship at all)

- **The due-count orphan fix.** `resolves:` — the filter that stops a retired entry counting
  toward work that no longer exists — was wired into one of the five places that count due
  cards. The badge, the widget, the reminder body and the Ride Log forecast all counted every
  stored card, so the two entries v1.18 retired have been inflating them ever since for every
  learner who studied them, permanently. Fixed, five call sites, a test each.
- 87 reading notes; three headwords resolved (ぺん retired toward the N5 ペン it duplicated,
  擽ぐったい and 引受る corrected in `surface` only).

That fix alone justifies a release. Everything below is what makes it worth a version number.

## §A Dictation should follow the learner too

§B gave Sentence mode `makeSentence(ids:)` and `makeSentence(due:)`. Dictation got neither,
so the app is now asymmetric in a way nothing justifies: you can read the sentences for your
saved list, but you cannot hear them. The builders exist; dictation needs the same two entry
points, minus the sentences `DictationSafety` withholds.

The honest-count rule from §B carries over and gets sharper here, because two filters stack:
a list's word has to have a typeable sentence AND that sentence has to have survived the
reading measurement. "20 words, 14 sentences, 11 you can hear" is three numbers, and the
learner should be told the last one, not the first.

## §B The six that were called blocked and may not be

STATE's rule — "an entry failing two independent generation rounds with the same defect is
blocked, not unlucky" — was challenged during §C by Codex, and the challenge is fair:

> Two failed generation rounds are strong evidence of a systematic generator failure. They
> are not proof that an honest example is impossible.

Six entries sit in that bucket for content reasons rather than orthography: そこで, 未だ,
博士, 明後日, 違える, 釣. Codex proposed concrete rescues for four of them — a two-sentence
frame for そこで (「雨が降り始めた。そこで、試合を中止することにした。」), 未だに for いまだ, a
物知り博士 sense for はかせ, an overt announcement register for みょうごにち.

The reason not to have done it already is real and has to be respected: the pipeline that
failed twice and the gate that judged it share the assumption these entries violate, so
"generate again and check" cannot decide this. These six need authored Japanese reviewed by
the three-lens shape, not another generation round — and the review has to answer a
narrower question than usual: **does this sentence force the taught reading**, not merely
"is it correct Japanese".

Six sentences is a small batch. It is also the first content work in this project aimed at
the class of entries the pipeline is structurally unable to serve, so the write-up matters
more than the yield.

## §C 釣 → 釣り, decided rather than deferred

Left alone in §C on the rule that a frozen field moves only when the current value is wrong,
and 釣 CAN be read つり. That rule stands. But the entry is also the only one of the nine
whose defect would be fully resolved by the same surface correction two of its neighbours
already got, and a corrected 釣り would unblock an example sentence. Decide it with the §B
batch, on evidence, and record the answer either way — a candidate that is neither taken nor
refused just gets rediscovered.

## §D What v1.21 measured and could not finish

- The dictation exclusion list is calibrated to one voice — the one
  `AVSpeechSynthesisVoice(language: "ja-JP")` returns. Measured: 16 of the 27 proven
  mismatches reproduce on a completely different synthesis engine, so the readings are
  substantially a shared-front-end property and only partly per-voice. Recorded in
  `DictationSafety`. Nothing to fix; something to not forget.
- 14 sentences still have no `exKana` and never will (12 digits, 2 middle dot). Pinned by id.
- `exTokens` still feeds only furigana. Nothing analyses which token a learner stumbles on,
  though DiagnosticsKit exists and dictation now produces exactly the signal that would make
  it interesting — a learner who mistypes a specific word in a sentence they could not hear.
  Not this release; noted so it stops being invisible.

## Stop rule

Ships when: `swift test` is green; `check_vocab_diff` clean (with a manifest if the §B batch
touches reviewed content) and its self-check passes all probes; any new content batch has
been through the three-lens review with a negative control that shows the panel fires; the
Release launch crash gate passes; and the honest-count rule holds for every new pool —
no run is ever padded to look fuller than the learner's own material.
