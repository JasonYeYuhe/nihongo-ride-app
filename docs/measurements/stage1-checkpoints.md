# Stage 1 — checkpoint readings (`sales_report.py --checkpoint`)

Created 2026-09-24, **before the N = 35 row was read** (N = 34 through Pacific 2026-09-22 on that day),
so the shape of a record is fixed before its first entry. `PLAN-STAGE1` §K's schedule: N = 35 (record,
falsifies nothing) · N = 100 (the first checkpoint that can falsify §D's 8.2%) · 2026-12-08 (day-90
interim record, written regardless of N — also if the decision row has already fired) · N = 200 or
2027-03-08, whichever first (the go / iterate / stop decision) · 2027-03-08 (refunds).

## Rules for every entry

1. **Verbatim.** Paste the tool's own lines: the cohort window, `N = … (macOS … · iOS …)`, the territory
   split, the launch-spike / exposure-day lines, the purchase lines, the checkpoint table, the exit code,
   and **every `BOUND WITHHELD:` reason word for word**. Do not paraphrase a reason.
2. **Never compute a bound by hand.** While the tool withholds, no `3/N`, no percentage, no "for context".
   A bound printed with a caveat under it is quoted without the caveat — that is why the tool withholds.
3. **No branch is evaluated here.** GO / STOP / STOP BUILDING are read by a person against §K's text on
   the day the decision row fires, not in this file.
4. **Before running:** confirm with the owner that every walk install and every registered-session install
   whose Pacific report day falls inside the window is already in `stage1-known-positives.json`; an
   unregistered install is invisible to the tool. Record the answer ("owner confirmed: no walk installs
   yet" is an answer).
5. **Name what this reading shares data with.** Every entry lists the earlier readings and controls
   computed from the same cached report days (the first entry shares its cache with the 2026-09-16,
   2026-09-17 and 2026-09-24 runs) — a reading written down first is not thereby blind.
6. Append only; a correction is a dated line under the entry it corrects.
7. *(added 2026-09-25, v1.34 §C2, before the first entry)* Run `python3 scripts/review_watch.py` the same
   day and paste its full output into the entry verbatim — including its exit code and the "before day 0 /
   since day 0 / total" lines, so "none since day 0" can be told from "none read". A flagged review is
   read by a person against §K's "negatively"; the tool decides nothing.

## Entries

### N = 35 — the reading of 2026-09-25 (JST), recorded 2026-10-07

**When the row was reached, and why this is recorded late.**
* The N = 35 row first printed `REACHED` in a run started at 2026-09-24T15:27:08Z (2026-09-25 00:27
  JST). That run fetched Pacific 2026-09-23 into the cache, and its exit code was lost.
* The reading below is the re-run at 15:45:08Z (00:45 JST) on the same cache, made to capture the exit
  code. Its body is byte-identical.
* Rule 4 asks for the owner's confirmation **before** running. The question was first put to the owner at
  15:38:02Z, seven minutes before this re-run. It was asked eight times in all, from 2026-09-25 00:38 to
  2026-10-03 15:05 JST (transcript `49ea16ff-0f53-45e2-a780-3f7a052f9cb7.jsonl`, lines 196 to 5979),
  and never answered.
* On 2026-10-07 at 01:36 JST the owner replied to the message listing the three owner-only items: the §K
  purchase, §L's three checks, and this question. The reply was *"你想办法自己做掉 你全权负责
  没办法再找我"* ("find a way to do it yourself; you have full authority; come back to me only if there
  is no other way"). The agent takes it as delegating this question. The §K purchase and §L's checks
  stay owner-only: §K says *"An agent cannot do this step and must not try."*
* §K's DECIDED 2026-09-17 box also rests on a delegation, but that one covered choices. This one covers
  a fact only the owner knows. **So the answer below is the agent's finding, not the owner's
  confirmation.** It was made after the reading, so rule 4's "before running" was not met.

**The reading, verbatim.** `python3 scripts/sales_report.py --checkpoint`. Kept outside the repo at
`~/Library/Caches/NihongoRide-v134-work/checkpoint-2026-09-25.txt`, md5
`b077ce90a5a798632ac69bbd0ff99388`. The run printed that same md5 when it wrote the file
(`9980488b-03ea-4d2c-9560-4861dc8786d0.jsonl:382`). The last line is the shell's capture of the exit code.
The tool prints a territory line only for adjusted purchases; there were none, so the output has no
territory line and none is added by hand.

```
checkpoint — PLAN-STAGE1 §K, day 0 = 2026-09-09
  registry docs/measurements/stage1-known-positives.json · schema 1 · 0 entries
  decisions: exclude_walk_first_downloads_from_N=true · exclude_owner_refund_from_refund_ceiling=true
    (exclude_owner_refund_from_refund_ceiling is echoed, never applied: nothing here evaluates the day-180 refund ceiling)
window 2026-06-06 .. 2026-09-23  (110 days)
  report states: data=110
calibration (the full default window — every check --calibrate runs):
  positive control · updates  release-day 15.2/d vs other 8.8/d = 1.73x
  positive control · downloads release-day 2.8/d vs other 2.2/d = 1.27x
  OK — the instrument responds to known-positive events.
second release-day control (PLAN-STAGE1 §K "DECIDED 2026-09-17" item 11 — gates the bound only; --calibrate does not run it):
  exposure days (12): 2026-08-11, 2026-08-12, 2026-08-15, 2026-08-16, 2026-08-17, 2026-08-18, 2026-08-31, 2026-09-01, 2026-09-11, 2026-09-12, 2026-09-17, 2026-09-18
  other days (14): 2026-08-14, 2026-09-02, 2026-09-03, 2026-09-04, 2026-09-10, 2026-09-13, 2026-09-14, 2026-09-15, 2026-09-16, 2026-09-19, 2026-09-20, 2026-09-21, 2026-09-22, 2026-09-23
  updates (F7)                  exposure 15.67/d vs other 6.00/d = 2.61x
  first-time downloads (F1/1F)  exposure 3.17/d vs other 2.00/d = 1.58x
    other-day first-time downloads 2.00/d before 2026-09-09 over 4 day(s), 2.00/d from 2026-09-09 over 10 day(s)
  OK — check A: updates elevated on exposure days · check B: update ratio 2.61x > first-time download ratio 1.58x
cohort since day 0: 2026-09-09 .. 2026-09-23  (15 days · report states: data=15)
  2026-09-08 first-time downloads (F1/1F): 0 — N is the same whether day 0 is 09-08 or 09-09
  FIRST-TIME DOWNLOADS  raw 36 (macOS 23 · iOS 13)
    registered walk first_download: none in the cohort window
  N = 36 (macOS 23 · iOS 13)  first-time downloads F1+1F since 2026-09-09
  PURCHASES  raw gross 0 (macOS 0 · iOS 0) · refunded 0 · net 0
    registered, always subtracted (§K: "exclude it from the cohort"): purchase 0 · refund 0
  ADJUSTED PURCHASES  gross 0 (macOS 0 · iOS 0) · refunded 0 · net 0
  registry entries: none
pre-registered checkpoints (§K, quoted):
  REACHED      N = 35   record, falsifies nothing
  not reached  N = 100  first checkpoint that can falsify §D's 8.2%
  not reached  2026-12-08 (day 90)  interim record, no decision attached — a dated waypoint regardless of N
  not reached  N = 200, or 2027-03-08 (day 180), whichever comes first  the go / iterate / stop decision
  not reached  2027-03-08 (day 180)  refunds
  (read at N = 36, with 2026-09-23 the newest report day read)
BOUND WITHHELD:
  - no matched day-0 known-positive purchase: the registry holds no kind=purchase entry with status=matched in the cohort window — §K: "this project does not trust an instrument that has not fired"
exit=5
```

**Rule 4: any walk install or registered-session install in Pacific 2026-09-09 .. 2026-09-23? None
found.** The registry's 0 entries stand. The evidence is in
`docs/measurements/2026-10-07-n35-rule4-evidence/`.
* **No session install.** No session was registered: `docs/sessions/` holds only its README, and the
  registry has no "session participant" entry. No record, transcript or readable message shows
  recruiting. WeChat, LINE and in-person contact could not be read.
* **No walk install, as far as the walk's own steps can be seen.**
  * The cached Apple reports (Pacific 06-06 .. 10-01) hold no Nihongo Ride in-app purchase row. They
    do hold five of the vendor's other apps' rows, all iPhone, so an iOS purchase would have shown.
  * A Mac purchase row has never been observed, but a Mac purchase needs the App Store copy installed,
    and the next bullet finds none.
  * So the walk's purchase (step 3) had not happened, and only step 1's installs could have come before
    it.
  * Step 1 on this Mac:
    * `/Applications/Nihongo Ride.app` was absent in every surviving `stage1_walk.py` snapshot, from
      2026-09-15T16:52Z to 2026-10-03T04:15Z.
    * LaunchServices was rebuilt on 2026-09-15 at 12:22 JST and keeps records of deleted bundles. It
      holds 48 records for the bundle id, none under `/Applications` or the Trash, all developer builds.
    * The app container's launch counter (4 → 8) is accounted for by launches of developer archives.
  * Step 1 on the owner's iPhone "js": `com.jasonye.nihongoride is not installed` at
    2026-09-15T16:27:28Z.
  * This Mac's app-focus store holds the iPhone's synced stream. It shows no Nihongo Ride in the
    foreground on any Pacific day from 09-09 to 10-05, and it holds at least 467 records on each of
    those days.
    * This source is provisional. It is local to the Mac and touches no device, but the owner has not
      said which devices' data may be read.
    * Struck out, it leaves the iPhone evidence at the 09-15 check.
  * No agent installed the app from the App Store or TestFlight. The walk card's evidence folder does
    not exist.
* **What no source can see, so absence of evidence only:**
  * a download that was never opened (a first download counts in N even after deletion);
  * a copy on this Mac installed and deleted before 2026-09-15 12:22 JST without being opened;
  * devices on other Apple accounts, and the owner's iPad on most days;
  * a family member's devices;
  * recruiting outside the readable channels, and participants' devices.
* **The margin is one unit: N = 36 against 35.** Five first-download rows in the window fall where no
  source can see: iPad, CN on 09-11, 09-12, 09-15 and 09-21, and JP on 09-16. If any two of them are
  walk installs, this `REACHED` is wrong. The row falsifies nothing either way.

**Rule 5: what this reading shares data with.** None of these reads was blind to this cache, and the
rule-4 answer above was written after all of them.
* The 2026-09-16, 2026-09-17 and 2026-09-24 (JST) runs named in this file's header. The last of these
  is the N = 34 reading at 01:04 JST, cache through Pacific 09-22.
* The calibration and second release-day control runs of 2026-09-16 and 09-17 (`b3707d9`).
* The 15:27:08Z run of this same reading.
* The later agent readings of 2026-09-29 (N = 50) and 2026-10-03 (N = 59). Neither is an entry here.
* The cache-only re-runs and row scans the investigation made on 2026-10-07 JST, through 09-23, 09-27
  and 10-01. They are kept outside the repo in `~/Library/Caches/NihongoRide-v135-work/n35-1007/`.

**Rule 7: `review_watch.py` on the same JST day, verbatim.**
* It ran at 2026-09-24T15:54:48Z, nine minutes after the reading, in the worktree `wf_75d1c54a-5e9-1`.
* That work was committed as `3ac1ee0` nine minutes later and reached main through merge `8072a55` at
  2026-09-25 01:33 JST.
* That version prints no `API meta.paging.total` line; the line came in `08c3c39`. Later runs of the
  reviewed tool also read 0 since day 0 (2026-09-28 and 2026-10-03).
* No saved file holds this output. The first-hand copy is the tool result at
  `~/.claude/projects/-Users-jason-Documents-typing-app/9980488b-03ea-4d2c-9560-4861dc8786d0/subagents/workflows/wf_75d1c54a-5e9/agent-ab1390c5788464d83.jsonl`,
  lines 98–99; other transcripts quote it.
* The last line is the shell's capture of the exit code.

```
review_watch — App Store customer reviews for app 6777469778 (read-only GET via scripts/asc_api.sh)
read at 2026-09-24T15:54:48Z · /v1/apps/6777469778/customerReviews?limit=200&sort=createdDate · 1 page(s)
NOTE: this endpoint shows the reviews visible to the App Store Connect API. It may lag the storefronts; a review a storefront shows may not be here yet.
"since day 0" = the review's createdDate converted to its America/Los_Angeles calendar day (the Pacific report day sales_report.py uses) is on or after 2026-09-09.

total reviews (lifetime, as the API shows them): 1
before day 0 (2026-09-09): 1   (counted; not the guardrail's subject)
since day 0 (2026-09-09):  0   (0 with purchase vocabulary)

REVIEWS SINCE DAY 0 (2026-09-09) — every one, on every run; no high-water mark
  (none visible to the API)

BEFORE DAY 0 — counted above, not listed as since day 0; one line each
  2026-07-10 PT · rating 5/5 · CHN · id 00000193-f7fb-5203-538a-6cdb00000000 · purchase vocabulary: 付费

SUMMARY: since day 0: 0 review(s), 0 flagged · before day 0: 1 · total 1
exit 0 (the read succeeded)
live exit=0
```

**Rules 2 and 3.** No bound is computed, because the tool withholds for the one reason quoted above.
No branch is evaluated.
