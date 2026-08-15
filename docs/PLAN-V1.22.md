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

**DONE — 1 rescued, 1 false rescue, 4 still blocked.**
`docs/measurements/v122-blocked-entry-rescue.json`, tool `scripts/check_forces_reading.py`.

- **未だ/いまだ RESCUED.** 「その古代文字は未だに解読されていない。」 Both parsers agree, and the
  reason is stronger than either: まだ cannot take に (*まだに is not a word), so 未だに admits
  only いまだに. Three lenses accepted it against three defective controls they rejected 9/9.
- **違える was a FALSE rescue.** The audio proved ちがえ by byte-identity, but Sudachi tokenises
  寝違え as one word: the sentence uses a different verb that merely contains the headword.
  That is the substring trap `ExampleSentenceTests` exists for, arriving from the other
  direction, and no check that reasons about READINGS can see it.
- **博士 and 明後日 stay blocked, now on two parsers disagreeing** rather than one tool's
  verdict — Sudachi takes the taught reading, the voice takes the rival, by wide margins.
- **そこで was never a reading problem**: Sudachi still parses 「そこで、」 as そこ+で, the
  locative, in Codex's frame as in the original. The conjunction is homographic and no
  context disambiguates it for a parser.
- **釣 stays as §C decided it.**

The rule survives, narrowed: it is a shipping gate, not a claim about the language, and an
entry can now be appealed with evidence from a parser the pipeline does not share. The other
216 were NOT retried — their blocking reason is structural, and the one rescue worked because
未だに is a fixed form that excludes the rival grammatically, not because the old verdict was
careless.

And the review caught, twice, what no reading oracle could: the first accepted candidate was
a near-duplicate of shipped n1-b1136 down to subject and predicate, and its Chinese used 查明,
importing an investigating agent that the stative 分かっていない does not have.

## §C 釣 → 釣り, decided rather than deferred

Left alone in §C on the rule that a frozen field moves only when the current value is wrong,
and 釣 CAN be read つり. That rule stands. But the entry is also the only one of the nine
whose defect would be fully resolved by the same surface correction two of its neighbours
already got, and a corrected 釣り would unblock an example sentence. Decide it with the §B
batch, on evidence, and record the answer either way — a candidate that is neither taken nor
refused just gets rediscovered.

## §E What the pre-submission review caught

Sixteen findings, ten survived a skeptic. The three that mattered were all the same defect
wearing different words, and all three were mine:

**The reading notes were corroborated circularly.** The rule was "name the sibling that
carries a reviewed sentence, and check it against how often the corpus reads that spelling
each way". Both halves are Sudachi output, and the corpus only contains sentences for the
entry the pipeline happened to serve — so 日本 reading にっぽん 52 times out of 52 says
nothing about Japanese. Three notes shipped backwards: the にほん card was told にっぽん is
the everyday reading, 辛い/からい (N5, "spicy") was pointed at つらい ("painful"), and 下/げ at
しも while した ships at N5. The non-circular signal is the JLPT level, which comes from the
JLPT lists and not from this pipeline. A note now ships only when the sibling it names is
STRICTLY EASIER than the card and is the easiest reading of that spelling; same level means
no signal and no note. 87 notes became 64, and a data test now fails on any note naming a
reading that is not taught earlier — the check that would have caught all three.

**The orphan fix was half a fix.** The conjugation side of every due count was still
unfiltered, and the app badge is `vocab + conjugation` — while 言う/ゆう, one of the two
entries v1.18 retired, is a verb. `ConjugationReviewStore` now takes the same injected
check on `dueCards`/`dueCount`/`dueByDay`/`dueForecast`, all four call sites pass it, and a
test asserts the filter is asked about the VERB and not the prompt key (passing the whole
`sourceID#form` would match nothing, drop every card, and look like a fix).

**And the weak-words cram** was the one counting path outside that sweep with the same
shape: the menu gated on how many words had been reviewed while the cram itself dropped
unresolvable ids, so a learner was offered a cram of N and handed N-1.

Smaller, all fixed: the due-dictation launcher wore the sentence launcher's English label;
a saved word whose entry is gone printed its raw internal id ("n2-b984") where a learner
expects a word — newly reachable because this release withdraws an entry; the note
generator took the first recorded sibling rather than the easiest; and a retirement's
`replacedBy` was never checked to name an entry that exists, which this release's own
manifest relies on. The guard now checks it across the whole corpus, because the correct
case (ぺん in n2 pointing at ペン in n5) crosses files and a per-file check would have
rejected it.

One finding was resolved by reading rather than by running, and it is worth saying which:
whether the reading note fits the compact (keyboard-up) card. Reaching a noted card on a
device needs two full runs — the earliest one sits at rank 15 of its level pool, and N5/N4
have none at all by construction — and the simulator here has its software keyboard off. It
does not need a device: the compact layout DROPS the whole example block (two lines plus
furigana, ~50pt) and the note is one caption line (~14pt), so compact-with-a-note is
strictly shorter than the full layout with a note, which was verified on an iPhone 17.

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
