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

## Entries

*(none yet — the first is the N = 35 record)*
