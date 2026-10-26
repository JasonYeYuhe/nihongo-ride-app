# Second-opinion brief — Nihongo Ride, 2026-09-28 (JST)

You are one of two independent reviewers (the other is a different model; you will not see each other's
answers). The owner will choose between options after reading both of you. **You are read-only: do not
modify, create or delete any file, do not run builds, and do not contact any network service.** This
directory is a throwaway copy of the repository at `8108fc7`; the unmerged branch named below is at
`origin/claude/dazzling-elion-131e9a`. `_consult/` holds screenshots, the agent's memory notes and two
verbatim tool outputs.

Everything in §1 is measured or read back unless marked otherwise. Check it against the repo where it
matters to your answer; if you find a claim here that the repo contradicts, say so first.

## 1. Where things stand

**The app.** Nihongo Ride, a Japanese typing-practice app, one SwiftUI codebase, macOS + iOS, free with
one non-consumable in-app purchase (`com.jasonye.nihongoride.scenery.lifetime`, extends the ride's road
west of Kyoto). One owner, who delegates whole releases to an agent (implementation, review, build,
upload, submission) and keeps a few actions for themselves.

**The observation window** (`docs/PLAN-STAGE1.md` §K/§L, `docs/PLAN-WINDOW.md`). Pre-registered, day 0 =
2026-09-09. Frozen for the window: the offer, its price, its placements and presentation, en-US/zh-Hans/ja
store metadata (description, keywords, screenshots). Anything that could change how far people ride is
registered in §K, not avoided. Release days are a registered covariate (the second control measured
first-time downloads 1.58x higher on release/exposure days; `_consult/checkpoint-2026-09-25.txt`).
Checkpoint read on 2026-09-25: **N = 36 first-time downloads since day 0 (macOS 23, iOS 13), 0
purchases**; the N = 35 row printed REACHED; the next checkpoint that can falsify anything is N = 100.
The bound is withheld until the owner makes a day-0 known-positive purchase — owner-only, not done. The
N = 35 record waits on the owner confirming no unregistered walk install fell in 09-09..09-23.
`review_watch.py` (09-28): 0 reviews since day 0, 1 lifetime.

**Releases.** v1.33 on sale since 2026-09-17 PT (macOS build 57 / iOS 58). **v1.34 submitted
2026-09-28 ~15:00 JST, both platforms WAITING_FOR_REVIEW** (macOS build 59 / iOS 60),
`releaseType = AFTER_APPROVAL` — it goes live automatically when Apple approves, as 1.33 did. 1.33 was
approved within two hours; 1.34 has now waited about seven. Builds 58/59 of 1.34 were uploaded earlier
and superseded (never attached) because the simulator pass found four layout defects after they were
built.

**What v1.34 contains** (`docs/PLAN-V1.34.md` §B, each item with dated addenda; What's New and review
notes in `scripts/submit_1_34.py`):
* B1 — the results screen gains one text line: streak (from 2 days) and words/forms due tomorrow, only
  after a ride that was recorded (`TomorrowLine.swift`, `AppModel.tomorrowLine`, `ResultsView`).
* B2 — pasting over 200 sentences / 20,000 characters shows a one-line notice of what was kept and
  dropped (was a silent cut); pasted texts get a context-menu Delete on every platform (on macOS there was
  no way to delete one) (`CustomTextsView.swift`).
* B3 — VoiceOver reads the values of HUD pills that 1.33 hides at accessibility sizes.
* B4 — About's small grey text raised to ≥ 4.5:1 contrast (colour only; the counter text is frozen).
* B5 — Sentence-mode romaji hint wraps to two lines instead of truncating; the typed-romaji row
  truncates at the head so the newest characters stay visible; the ★ keeps clear of a keyboard-up
  sentence card.

**Verification done** (§G of the plan; records in §G.3 and §F): headless pixel comparison against the
1.33 tree (only intended screens differ; the offer's screens identical); per-branch review lenses with
independent refuters, three fix rounds, then an eight-lens whole-release review (0 SERIOUS, 14 MINOR, all
closed or recorded); an AX5 simulator pass on a 402pt iPhone and an iPad mini (found four defects, fixed,
re-run clean on 09-28); `run_all_gates.sh` 14 run / 0 failed; iOS placement tests 9 + 3 / 0 failed; the
macOS launch gate PASS; ASC read-back byte-exact; 1.34's listing metadata and screenshots compared equal
to 1.33's by checksum; the IAP untouched (APPROVED, familySharable false).

**The one cost the re-run made concrete** (`_consult/screens/`). The paste notice now sits under the
"Japanese text" label, directly above the editor. At the default size it is whole in both languages
(`iphone-paste-en-default.png`), and on the iPad it is whole at AX5 (`ipad-paste-zh-AX5.png`). **At AX5 on
a phone with the keyboard up, only its first two lines clear the keyboard**: "Only the first / 200"
(`iphone-paste-en-AX5-keyboard-up.png`) and "只保留前 200 / 句,已去掉 30" (`iphone-paste-zh-AX5-keyboard-up.png`).
The rest is under the keyboard's blurred glass until the rider dismisses the keyboard or scrolls. This was
predicted and accepted before submission (§B2's "Verifier follow-up"); what the re-run added is that the
English visible half names the cap but not the loss. 1.33 showed no notice at all in this case. How many
riders paste text, and how many use AX5 on a phone, is unknown — the app has no telemetry by design.

## 2. Decisions the agent already took under delegation — flag any you would reverse

Each has its reasoning in `docs/PLAN-V1.34.md`; read the section before disagreeing.
1. B1 "due tomorrow" counts today's unreviewed cards plus tomorrow's (§B1), because unreviewed cards are
   still due tomorrow.
2. B1's line appears only after a journalled ride, not after a cram run that records nothing (§B1 (c)).
3. B1's text uses U+00A0 / U+2060 so a count never parts from its noun. Cost: the widest English rows
   (999 words and 999 forms) need the whole 0.7 minimum scale at AX5 (§B1 addendum).
4. B5's hint wraps to two lines; costs measured and accepted (the kana row drops to one line for the
   longest hints; §B5).
5. B5's ★ fix reserves the corner columns on keyboard-up sentence cards; long sentences draw 16–18%
   smaller (§B5 addendum (2)).
6. B2's notice is one line, in the unit that was actually cut, in the editor Section's header; the AX5
   keyboard-up cost above was accepted for this release (§B2).
7. Deferred, not fixed: the results screen's stage line at 4.41:1 contrast (under 4.5:1); About's licence
   badges at 4.28:1; a pre-existing iPad default-size wrap of the ride's accuracy pill ("100 / %").
8. The unmerged apostrophe fix (below) was kept out of 1.34, because it arrived after verification began.

## 3. Open decisions — recommend one option for each

**D1. The paste notice at AX5, now that it has been seen.**
* A. Leave 1.34 in review; make a notice that fits at AX5 the first UI item of v1.35 (~2 weeks later,
  plan target ~10-22).
* B. Withdraw 1.34 from review now (developer reject), shorten the notice (for example "200 of 230
  sentences kept" / 「保留 200/230 句」) or move the counts into the header label, re-run the affected
  simulator cells and a review round, rebuild as macOS 60 / iOS 61, resubmit. Estimated 0.5–1 agent-day;
  the review queue restarts; the release day moves.
* C. Leave 1.34 in review; after approval ship a small 1.34.1 with the notice fix (and possibly D2's
  content fix) — an extra release day inside the window.

**D2. The apostrophe content fix** — branch `origin/claude/dazzling-elion-131e9a`, commit `0205e50`
(written by a separate agent session). 18 English translations in Practice passages have shown "I'''m"
since June (shipped in every release through 1.33, also in 1.34); the branch fixes `passages.json`, adds a
corpus-wide quoting-residue test, makes both generators refuse residue, and raises the gate floor 14 → 15.
Not yet independently reviewed.
* A. Review it independently, merge to main now, ship it with v1.35.
* B. Fold it into a resubmitted 1.34 (only meaningful if D1 = B).
* C. Ship it alone as a content-only 1.34.1 soon after approval.

**D3. Release type while 1.34 waits.**
* A. Keep `AFTER_APPROVAL` (as 1.33; the release day is whatever day Apple approves, and it is recorded).
* B. Switch to `MANUAL` and release on a chosen day.

**D4. v1.35's scope and order.** Planned (§F): B6 search the corpus from Word Lists (2 days, with a cut
rule); B2's two improvements only if there is evidence anyone pastes; the N = 100 checkpoint record; the
112-sentence headword residue and a flagged counter item, corrected by ear; "two populations, not one
gate" (1 day); §E if the owner has walked. Candidates 1.34 surfaced: the AX5 paste notice (D1); the 4.41
stage line and 4.28 badges; the iPad accuracy-pill wrap; a 0.1-day deep-link device check (§I). §I lists
what is deliberately not in this phase — do not propose those. What should v1.35 be, in what order, and
what would you cut?

**D5. The simulator clone `NihongoRide-VisualPass`** (created for 1.34's AX5 pass; a few GB). A. Keep
until v1.35's AX5 pass, then remove. B. Remove now and recreate when needed.

## 4. Hard limits (the owner's red lines — options that cross them are not options)

No purchase of any kind in any environment (production, sandbox, TestFlight, local StoreKit config); no
Apple Account sign-in/out; nothing written into §L's walked column or §K as "done"; the protected §L
sentence is not reworded; no change to the offer, price, placements, the Settings road card, the menu route
strip, `RoadView`, About's counter text, or store metadata during the window; §I items stay out.

## 5. What to return

Plain text, under about 900 words, in this shape:

```
D1: <A|B|C> — confidence <low|medium|high>
  why: <2–4 sentences, citing files/sections where it matters>
  would change my mind: <one line>
D2: ...
D3: ...
D4: <ordered list for v1.35, what to cut, and why>
D5: ...
REVERSALS (from §2): <item number — what you would do instead and why>, or "none"
MISSED: <anything risky or wrong in the state above that no question asks about>, or "none"
CORRECTIONS: <any claim in this brief the repo contradicts>, or "none"
```
