# The release-day control in `--calibrate`: what it can see, what it cannot, and what was left alone

Measured 2026-09-16, around 00:30 JST (= 2026-09-15 08:30 PDT). Read-only throughout: App Store
Connect GETs, the public iTunes lookup, git history, and the local sales cache
(`~/Library/Application Support/NihongoRide-Stats/sales/`, 101 daily files, 2026-06-06 … 2026-09-14,
no gaps). **Nothing in `scripts/sales_report.py` was changed by this work**, and §5 says why.

The mutation runs in §3 were made against the real cache with no network, earlier in the same
2026-09-16 preparation session that wrote this file; the throwaway harness that swapped the sets is
not committed, and this file's author did not re-run it. The numbers are quoted
exactly as that run printed them.

## 1. What the control is

`calibrate()` compares mean `F7` (update) units per day on `RELEASE_DAYS` against every other data
day on or after 2026-08-01 (`scripts/sales_report.py:372-389`). It fails only if updates are **not**
elevated on release days. The same comparison for downloads is **printed and never checked**
(`:384-385`), although the module docstring states both halves: *"updates must be release-locked
and downloads must not be"* (`:29`).

`RELEASE_DAYS = {"2026-08-11", "2026-08-16", "2026-08-18", "2026-08-20", "2026-08-22", "2026-08-24"}`
(`:106-107`), added in `91171a3` (2026-08-26 01:02 +0900) with the comment *"Days a version reached
users."* Neither the commit message nor the diff says how the dates were chosen.

As shipped, today:

| command | exit | key lines |
|---|---|---|
| `python3 scripts/sales_report.py --calibrate` (default window 2026-06-06 … 09-14) | **0** | updates release-day 15.2/d vs other 9.2/d = **1.65x**; downloads 2.8/d vs 2.3/d = **1.24x**; OK |
| `python3 scripts/sales_report.py --since 2026-09-09 --calibrate` | **4** | `CALIBRATION-FAIL: no release days in window — cannot run the positive control` |

The second is by design, not a defect: the control needs at least one `RELEASE_DAYS` date and one
other day in the window, and no `RELEASE_DAYS` date is later than 2026-08-24. This is why §K's
"`--calibrate` still passes" has to mean the full default window.

## 2. Release-day evidence, per version and platform

Time conversion: commits are `+0900` (JST); ASC and sales days are Pacific; in Aug–Sep 2026
PDT = JST − 16 h. Sources: ASC `appStoreVersions` (`createdDate`, PDT; no approval or release
timestamp is exposed, and every version shows `READY_FOR_SALE` / `AFTER_APPROVAL` / null
`earliestReleaseDate`, so state cannot date anything), ASC `reviewSubmissions` (`submittedDate`;
only the 10 most recent, 1.29 onward), phased release (null for every version 1.19–1.32, so each was
a full release), commit timestamps and messages, docs, and the public iTunes lookup (release time of
the current version only).

All times PDT.

| version / platform | earliest possible | latest possible | Pacific release date |
|---|---|---|---|
| 1.20 both | record created 08-09 21:01 | seen live 08-11 04:22 (`88c042b`); 1.21 record created 08-11 02:02 \* | **08-10 or 08-11**, unresolved |
| 1.21 both | created 08-11 02:02; "in review" 04:22 (`88c042b`) | "live (2026-08-11)" (`336ed4c`, written 08-12 07:25) | **08-11**; conflict: no macOS 1.21 units until 08-12 |
| 1.22 both | 08-15 02:03 (`de05411`) | 08-15 22:10 (`5d4c48e`) | **08-15**, firm |
| 1.23 both | 08-17 04:10 | 08-17 16:15 (`098668e` message) | **08-17**, firm |
| 1.24 macOS | 08-19 08:07 (`bf43237`) | "live on macOS 2026-08-20" at 08-21 01:33 (`76238ba`) | **08-20**, possibly 08-19 |
| 1.24 iOS | "in review" 08-21 01:33 (`76238ba`) | iOS download 08-21; 1.25 record 08-22 23:10 \* | **08-21**; conflict: one iPad update on 08-20 |
| 1.25 both | created 08-22 23:10 | 08-24 03:17 (`c50b983`) | macOS **08-23** (single update unit only); iOS **08-23 or 08-24** |
| 1.26 both | 08-24 19:14 (`b9dd532`); macOS IN_REVIEW / iOS WAITING by 08-25 07:33 (`docs/HANDOFF-V2-PRODUCT-PROMPT.md:94`) | 1.27 record 08-26 03:18 \*; macOS download 08-26 | **08-25**, possibly 08-26 |
| 1.27 both | 08-26 03:22 (`14f5214`) | "live on both" 08-27 05:06 (`59cb62d`) | **08-26 or 08-27**, unresolved |
| 1.28 both | 08-27 09:51 (`3a0d37d`); "in review" 12:03 (`44821f0`) | 1.29 record 08-29 23:27 \*; iOS download 08-29 | **08-27 to 08-29**, unresolved |
| 1.29 both | submitted 08-29 23:28 | 1.30 records 08-31 01:18 \*; "READY_FOR_SALE, queried directly" 08-31 01:43 (`eb28e02`) | **08-30 or 08-31**, unresolved |
| 1.30 iOS | WAITING 08-31 08:45 (`1ebce98`) | "went READY_FOR_SALE" 08-31 21:08 (`51139e4`); iOS download 08-31 | **08-31**, firm |
| 1.30 macOS | — | — | never released (withdrawn 09-07) |
| 1.31 iOS | submitted 09-04 22:00; WAITING 22:02 (`2c59373`) | "live 09-06" written 09-07 05:39 (`f258801`) | **09-05 or 09-06** |
| 1.31 macOS | submitted 09-07 05:37; IN_REVIEW at an undated "09-08 observation" | seen live 09-08 19:02 (`e8a6ade`) | **09-08**, possibly 09-07 |
| 1.32 both | submitted 09-10 17:24; WAITING 17:37 (`8c7defe`) | READY_FOR_SALE by 09-11 20:09 (`43d0da7`); iTunes lookup iOS 2026-09-11 09:35, macOS 12:34 | **09-11**, firm |

\* relies on the docs' stated rule that ASC will not create a new version while the previous one is
in review (`docs/STATE-2026-08-18.md:21`, `docs/PLAN-ITERATION.md:629-631`).

**What that says about the existing six dates.** They are **Japan-time observation dates**, which
land on (roughly) the Pacific day *after* a release — the day the update wave arrives. `5d4c48e`
wrote "1.22 live (2026-08-16)" at 08-15 22:10 PDT, so 08-16 cannot be a Pacific date; `098668e`,
committed 08-17 16:15 PDT, says "macOS 1.23 approved and on sale 2026-08-17, iOS 2026-08-18", and
the iOS date cannot be Pacific. The actual release days 08-15 and 08-17 are counted as "other".
**08-22 has no source anywhere in the repo**, is not the first appearance of any version, and has
3 update units. For 1.32, the one version with an exact release time, the release day carried
**2** update units and the next Pacific day **29**.

| | Pacific days |
|---|---|
| firm release dates | 08-11, 08-15, 08-17, 08-31, 09-11 |
| uncertain (possible release days) | 08-12, 08-19, 08-20, 08-21, 08-23, 08-24, 08-25, 08-26, 08-27, 08-28, 08-29, 08-30, 09-05, 09-06, 09-07, 09-08 |
| certainly not a release date | 08-13, 08-14, 08-16, 08-18, 08-22, 09-01, 09-02, 09-03, 09-04, 09-09, 09-10, 09-12, 09-13, 09-14 |
| release days currently counted as "other" | 08-10 (1.20 or 1.19); 08-03 … 08-09 (1.15–1.18) |

**The handoff's September dates** (`docs/HANDOFF-STAGE1-GATES-PROMPT.md:148`): 09-04 is the iOS 1.31
submission day; 09-07 the macOS 1.31 submission day (a release that day is not ruled out); 09-09 is
the Japan date of the 09-08 19:02 PDT live observation, and the macOS update-surge day; 09-10 had 1.32
submitted at 17:24 and every row still 1.31. **None of the four is a Pacific release day. 09-11 is
the only firm September release day.** The same uncertainty reaches Stage 1's day 0: in Pacific
terms it is 09-07 or 09-08, and `--since 2026-09-09` leaves out Pacific 09-08.

## 3. Mutations of the control on the real cache (quoted verbatim)

M0 as shipped PASS (1.65x / 1.24x); M1 RELEASE_DAYS := quiet days {08-13,08-14,09-02,09-03,09-13,09-14} FAIL
(0.57x); M2 firm Pacific release dates {08-11,08-15,08-17,08-31,09-11} PASS (updates 1.14x, downloads 1.75x);
M3 firm Pacific date +1 {08-12,08-16,08-18,09-01,09-12} PASS (2.43x / 1.22x); M4 swap classification
(UPDATE:=F1/1F, DOWNLOAD:=F7) PASS (1.24x / 1.65x) — BLIND SPOT: the docstring's "downloads must not be
release-locked" is printed, never enforced; M5 UPDATE:=redownload codes FAIL (and F7 unclassified);
M6 handoff's four September days added PASS (1.41x / 1.08x).

What each one shows:

* **M1 and M5 are the control firing.** Put quiet days in `RELEASE_DAYS`, or point `UPDATE` at the
  redownload codes, and it goes red. It is not vacuous.
* **M4 is a blind spot, not a failure.** With updates and downloads swapped, the run still passes,
  because the only enforced comparison is "the `UPDATE` set is higher on release days", and first-time
  downloads are also somewhat higher then. The check that would catch it — updates elevated **more**
  than downloads — is the docstring's second half, and nothing evaluates it.
* **M2 and M3 bracket the definition question.** On firm Pacific release dates the update margin is
  thin (1.14x) and downloads are the more elevated series (1.75x) — consistent with the update wave
  arriving the next day. On the day after, updates dominate (2.43x / 1.22x). The shipped set — two
  next-day dates (08-16, 08-18), one release date (08-11), one unsourced day (08-22) and two uncertain
  ones (08-20, 08-24) — sits between (1.65x / 1.24x). **"Release date and the next day" as one set
  was not measured.**
* **M6 passes on days that are not release days.** A control that passes with non-events added is
  telling you how forgiving it is, not that those days were events.

## 4. Why nobody may pick release days from the update rows

The control asks whether `F7` units are higher on release days. If release days were chosen as "the
first day `F7` rows show the new version", every chosen day would have at least one `F7` unit **by
construction**, and wherever two days are possible that rule picks the one where the wave starts.
The control would then pass because of how the days were chosen, and could no longer fail. So §2
dates nothing from an `F7` count. One cell leans on an update row — 1.25 macOS, 08-23, a single
unit — and it is marked as such and kept out of the firm list. Download dates carry the same effect
more weakly; that line only prints.

A second-order form of the same problem now exists and is stated rather than hidden: **M0–M6 have
been seen.** Any definition chosen from here on is chosen by someone who knows which ones pass. The
least-bad response is to choose from release-timing evidence alone (§2) and to write down that the
ratios were already known — which this paragraph does.

## 5. What was deliberately NOT changed, and why

* **`RELEASE_DAYS`, the `DOWNLOAD` / `UPDATE` / `REDOWNLOAD` / `PURCHASE` sets, and every calibration
  criterion are unchanged.** PLAN-STAGE1 §K's day-0 instruction is to "confirm the row appears and
  `--calibrate` still passes". "Still" only means something if the instrument before and after the
  owner's known-positive purchase is the same instrument. Changing it now would make that comparison
  one between two different instruments.
* **No "updates must beat downloads" check was added**, although M4 shows the gap. Same reason; and
  M2 shows such a check would go red under a release-date-only definition, so it cannot be adopted
  independently of the definition question.
* **08-22 was not removed**, although it has no source. Same reason.
* **The handoff's four September dates were not added.** None is a Pacific release day (§2), and M6
  shows adding them would pass on non-events.
* **No threshold, cohort definition, checkpoint or decision rule moved.**

The definition question, the M4 blind spot, and an explicitly-labelled agent recommendation (to be
adopted, if at all, only after the known-positive is confirmed) are in
`docs/DRAFTS-STAGE1-RECORDS.md` §6, items 12 and 13, as questions for the owner.
