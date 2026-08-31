# Fast iteration — the backlog, and what actually makes it fast

Written 2026-08-31, after the owner chose speed: *"快速迭代,把功能做得更多更好."*

`PLAN-WINDOW.md` holds the constraints and why they are so few. **This file is the work.** One
rule lives in one place: constraints there, backlog here.

---

## §A The bottleneck is the release, not the ideas — and it is measurable

Every release in this repo currently hand-copies a submit script. Measured on the newest one:

```
scripts/submit_1_30.py     792 lines
  per-release config       162   VERSION, TARGETS, What's New, review notes, description edits
  copied machinery         630   identical every release, retyped or copy-pasted by hand
```

There are **28 such scripts on disk.** The duplication is deliberate in origin — each file is that
release's record, and its docstring carries defects that are *properties of the template* — but the
consequence is that shipping costs an hour of careful, error-prone work before a single line of the
new feature is involved. **v1.30 proved the risk is not theoretical:** its `do_submit` carried the
ordering rule in a comment and not in the code, both platforms went to Apple without the purchase,
and both submissions had to be cancelled and rebuilt.

**Nothing else on this list changes the iteration rate as much as fixing that.** It is also the
safest item here: it touches no app code, so it cannot affect the measurement or a user.

### The gates, and which are load-bearing every time

| gate | cost | every release? |
|---|---|---|
| `swift test` | ~45 s | **yes** |
| `launch_gate.sh` on the uploaded archive | ~20 s | **yes** — it exists because v1.4 shipped a launch crash that only a signed build on an iCloud-signed Mac reproduces |
| build + upload ×2 | ~8 min | **yes** |
| `run_ios_placement_tests.sh` | ~4 min | **only when UI or placement changed** |
| `run_store_gates.sh` | ~1 min | **exits 3 with zero coverage today.** Run it, but it is not evidence — see `PLAN-STAGE1` §L |
| byte-exact read-back of every ASC PATCH | seconds | **yes, always** — it is what caught the star-glyph rejection before review |

---

## §B What still binds (short — the argument is in `PLAN-WINDOW.md`)

1. **Do not touch the offer, the price, or the placement.** Voids the pre-registration.
2. **Do not change store metadata for `en-US` / `zh-Hans` / `ja`.**
3. **A feature that substantially changes how far people ride** moves exposure-per-install.
   Register it; do not avoid it.
4. **Anything shipped free can still be sold later** — `PLAN-V2-PRODUCT` §E's red line is
   *grandfather on `originalAppVersion`*, not *freeze forever*. This is the correction that
   unblocked this whole plan; two external reviews found it independently.

> **And shipping frequently is itself a mild acquisition intervention, so register the cadence.**
> `PLAN-V2-PRODUCT` §L already recorded that **seven releases in fourteen days** coincided with the
> traffic tripling, and deliberately filed it as *one candidate among four* rather than a lever —
> *"it is also the one with a perverse incentive attached."* Fast iteration is now that perverse
> incentive arriving on purpose. **Write the release dates down** so day 90 can see them; do not
> claim the cadence caused anything.

---

## §C The backlog, tier 1 — each of these is days, not weeks

Ranked by visible improvement per day of work, with the risk named.

### 1. Extract the release template (§A) — **DONE 2026-09-01, `scripts/asc_release.py`**

Leave each `submit_<version>.py` as its 162 lines of config, importing the 630 lines of machinery
from one module. **Do not delete the old files** — they are the record of what was sent for each
release. Zero app-code risk. Pays back on every item below.

> **How it was held to the script it was ported from, because a plausible port is the whole
> risk here.** `scripts/test_asc_release.py` drives BOTH `submit_1_30.py` and the extracted
> module against one stateful fake App Store Connect, configured from v1.30's own constants, and
> requires the same calls with the same bodies in the same order, the same failure ledger and the
> same end state — across **eleven scenarios**, not one, because a differential over the happy
> path is a differential over the branch nobody doubted. The matrix deliberately includes the
> branches that have cost something: the purchase that cannot be staged, a description whose
> sentence is no longer there, a store locale the release writes no copy for, one platform
> already in review, an orphan submission container.
>
> **Both comparisons are controlled.** Dropping the byte-exact read-back from the port must make
> the call-log comparison go red; making `fail()` swallow its argument must make the ledger
> comparison go red. Both fire. The end-state comparison is *not* independently controlled and is
> kept as a cheap redundancy rather than as evidence — said out loud because an uncontrolled
> check that passes looks exactly like a controlled one.
>
> **And then against the real thing.** `--dry-run` issues GETs only, so both implementations were
> run against live App Store Connect and their output diffed: **73 lines, identical**, one
> deliberately generalised header aside. That is the half the fake cannot give — that the port's
> endpoint strings are the ones Apple answers.
>
> **One ledger message differs on purpose** (v1.30's text names v1.30) and is *enumerated* in the
> test rather than normalised away by a regex, because a regex tolerant of "any version-shaped
> difference" would also tolerate the next difference, which nobody has read.

**It also closed a rule that had been a comment since v1.5.** `# What's New — MUST NOT contain
the literal star glyph (ASC rejects it)` has ridden along in twenty-plus submit scripts and
`docs/ASC_METADATA.md` records the rejection twice; **nothing had ever checked it.** `preflight`
now does, along with four other contracts that were also only comments — What's New and review
notes against ASC's 4000-character limit (the description was the only field checked), and, new,
**a description edit whose OLD sentence is a substring of its NEW one**, which would re-apply on
every run and grow the paragraph without bound. v1.30's pair happens not to trip that; nothing
stopped the next one from doing so.

*What the star-glyph check does NOT cover, stated because this repo pays for unstated scopes:*
U+2605 is the only glyph this project has **measured** a rejection for, so it is the only one
asserted. Other glyphs ASC may dislike are unmeasured, and this check says nothing about them.

**`iap=` is a required argument with no default.** The gate cannot tell "this release sells
nothing" from "somebody forgot to wire the purchase up", and those must not be the same
keystroke — v1.24 §C's move, applied to the release path.

### 2. The conjugation prompt clock — a live defect, and a visible feature

`ConjugationSRSCard.quality(from:)` grades **every clean answer 5**, because `ConjugationSession`
never supplies a `durationRatio` and the default 1.0 makes `<= 1.5` always true. Measured with an
injected clock advancing 30 s per keystroke — 240 s to type たべます, reported ratio 1.0 — against
a negative control where the identical typing through `GameSession` graded 4. `NoPromptTimingTests`
holds the finding.

**Why it is a feature and not a chore:** the learner's hardest conjugations are being scheduled as
instant recall and leaving the rotation faster than a vocabulary card, and that wrong schedule is
durable and syncs to every device they own. The code already scopes the fix — *a paused prompt
clock, a baseline chosen against data, and the live-WPM readout routed through `RunClock`* — and
the last of those is user-visible.

*Risk:* it rewrites SM-2 schedules. Choose the baseline against data, not intuition; the existing
`secondsPerKanaBaseline` (0.8 s/kana) was calibrated for copying a word the learner can SEE, and a
conjugation prompt is recall plus production.

### 3. "Type your own text" in Practice — the bounded half of F1

The flagship's promise, at a fraction of its cost, because two blockers turned out to be softer
than the plan recorded:

* **There IS an on-device tokenizer.** `PLAN-STAGE1` §N said *"there is no tokenizer on the device
  at all"*; that is false and is now corrected there. `CFStringTokenizer` with a `ja` locale and
  `kCFStringTokenizerAttributeLatinTranscription` returns readings offline, on both platforms,
  with no dependency. Verified by running it.
* **Its quality problem does not bind here.** The same run splits 日本語 into 日本[nippon] +
  語[go] — exactly the compound-splitting this project measured in Sudachi. **But a wrong reading
  in the curated corpus is a *taught error*, while a wrong reading in text the learner pasted is
  visible to them and theirs to correct.** Different standard. Show the reading, let them edit it.

**Scope it so it does not touch SRS.** `SRSCard(id: entryID)` keys review cards on corpus ids, and
`SyncMerge` merges them across devices through CloudKit; giving pasted words card identities is the
expensive, dangerous half of F1 and it is what makes the full feature weeks rather than days. Ship
practice-only first. It already answers the question that matters — *will anyone paste their own
material* — and that answer is what decides whether the SRS half is worth building.

### 4. Whatever a pass over the app finds

Tier 1 above is everything I can defend from the repo's own records. **The rest of the backlog
should come from using the app, not from reading it**, and that pass is itself the next work item.
`DiagnosticsKit`/`StumbledWords` is already built and wired to `ResultsView`; there is a widget, a
reminder scheduler, a share card, a coach view, six modes, and 21 kits. The question worth an
afternoon is which of those is underexposed rather than missing.

---

## §D Carried, and not tier 1

* **iOS StoreKit has no automated coverage at all** (`PLAN-STAGE1` §J/§L). The code now carrying
  money is the least-tested in the repo. Not tier 1 only because `SKTestSession` is measurably
  inert here — re-check on every toolchain bump, and it becomes tier 1 the day it works.
* **Accessibility (§E, carried since v1.26).**
* **Corpus:** `n5-kazoku` reads 四人 as よんにん (standard is よにん); the 112 uninspected residue.
* **NOT the 522 undecided dictation sentences.** `PLAN-V1.29` closed that with a measurement.
* **`ta_score`'s `totalPlayerCount`** — never read since v1.3; one physical-device errand closes a
  class of future proposals.

---

## §E Owner-only, and expiring

Unchanged and repeated because a fast cadence is exactly when these get skipped:

* **`PLAN-STAGE1` §L's three manual purchase gates**, still unwalked. While v1.30 is in review a
  failed gate costs a cancel and a resubmit — minutes, measured. After `READY_FOR_SALE` it costs a
  whole new version with live customers meeting a broken purchase.
* **§K's day-0 known-positive purchase.**
* **Whether to denominate §K's checkpoints by installs rather than dates** — free to decide only
  before day 0.

---

## §F What would make this plan wrong

* **If the release-template extraction turns out to be more than a day.** It is proposed as the
  first item *because* it is cheap; if it is not, it loses its place rather than growing.
* **If practice-only custom text turns out to need SRS to be worth anything.** Then item 3 is not
  the bounded half of F1, it is a stub, and the honest move is to build F1 properly after the
  window rather than ship something nobody returns to.
* **If the cadence itself moves installs.** That would be good news and a confound at once —
  which is why §B says to write the dates down now.
