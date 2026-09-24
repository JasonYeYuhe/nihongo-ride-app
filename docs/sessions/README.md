# docs/sessions — the moderated-session tally (aggregates only)

Created 2026-09-25 (JST) with `docs/SESSIONS-STAGE1.md`, before any participant was recruited. **This
directory holds counts, never people.** The kit's §6 is the rule; the short form:

* No per-participant file, ever. No names, initials, P-numbers beside quotes, device names, Apple IDs,
  order numbers, screenshots of a participant's screen, or dates of individual sessions.
* Per-participant notes live outside the repository (the kit, §6). The registry entry for each install
  lives in `docs/measurements/stage1-known-positives.json` and is the owner's to write, the same day.
* A cell below 3 is written `< 3`, not as its number.
* Quotes appear only in the quote section, only with per-quote consent given at the time, and without
  anything beside them that says who, where or when.
* The prices used on the four cards are **not** recorded here. They are in the owner's private notes with
  the date they were fixed.
* Append a completed batch as a dated block using the template below. Never edit an earlier block; a
  correction is a dated line under it.

## Template — copy below the rule, one block per batch

```markdown
### Batch <k> — appended <YYYY-MM-DD> (JST) · sessions ran <YYYY-MM-DD> to <YYYY-MM-DD> · build(s) on sale: <macOS x.y (b) / iOS x.y (b)>

Kit version: `docs/SESSIONS-STAGE1.md` at <commit>; Appendix A re-pinned: <yes/no, commit>.
Card wording: unchanged from the kit / Card <S|B|C|L> reworded on <date> (wording in private notes).
Prices: fixed before the first session of this batch (yes/no); the same for every participant in a
territory (yes/no).

#### Participants
| territory | macOS | iOS | total | recruited outside the App Store |
|---|---|---|---|---|
| <CC> | <n or < 3> | <n or < 3> | <n> | <n> |
| **all** | | | | |

Registered in `stage1-known-positives.json` as `first_download` the same day: <n of n>. Late by one or
more days: <n> (which checkpoint window, if any, they fell inside). Already had the app (not a first
ride, not a first_download): <n>. Day-2 return did not happen: <n>.
Proficiency as stated (never tested): beginner <n> · intermediate <n> · advanced <n> · native <n>.
Interface language used: English <n> · 中文 <n> · switched during the study <n>.

#### Q1 — own text (kit §4.2)
| code | count |
|---|---|
| pasted | |
| opened-not-pasted | |
| looked-not-found | |
| declined | |
| not-asked | |

Of `pasted`: own material <n> · found on the spot <n> · corrected a reading <n> · rode it <n> ·
hit "no sentences" <n>. Found 〔My text〕 unprompted before the question: <n>.

#### Q2 — the exhausted queue (kit §4.2) — observed and stated are never merged
| behaviour | observed (notice appeared) | stated (asked at the end) |
|---|---|---|
| changed-level | | |
| changed-mode | | |
| own-text | | |
| ride-log-or-other-screen | | |
| closed-app | | |
| asked-me | | |
| other | | |
| **notice never appeared** | <n> | — |

#### Forced choice (kit §4.4) — by package and by the position it was shown in
| package | shown 1st | shown 2nd | shown 3rd | shown 4th | chosen total | "never" total |
|---|---|---|---|---|---|---|
| S supporter | | | | | | |
| B bring your own material | | | | | | |
| C structured course | | | | | | |
| L listening | | | | | | |

Asked for a fifth option: <n> (what, in category terms). Choice taken from a participant who did not
return on day 2 (kept apart): <n>, choices: <S/B/C/L counts>.

#### Road entrances — observed only, never pointed at
Reached the Settings road row unprompted: <n>. Said anything there: <n>. Purchased during the study
(registered as `kind = purchase`, GO never fires): <n>.

#### Quotes — per-quote consent recorded at the time; nothing beside a quote says who
* "<quote>"
* "<quote>"

#### What went wrong in this batch (kit §8, honestly)
* <e.g. two sessions where the moderator answered a question before the "what do you think?" step>
```
