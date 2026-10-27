# Evidence from the v1.35 release work directory

`~/Library/Caches/NihongoRide-v135-work/` was retired on 2026-10-27, after 1.36 went live on both
platforms (Pacific 2026-10-26). This follows the release work-directory rule: a work directory is kept
until a newer version is live. The files the docs cite from it were kept first:

| cited as | kept at |
|---|---|
| `NihongoRide-v135-work/checkpoint-2026-10-03.txt` (STATE-2026-10-03:41; md5 `86d6ba2aec36e06b70630f93d4524ec0`) | `docs/evidence/v135/checkpoint-2026-10-03.txt` |
| `NihongoRide-v135-work/checkpoint-2026-10-07.txt` (STATE-2026-10-07:77; md5 `35d24a37468ac2d3028cdc0d824aafce`) | `docs/evidence/v135/checkpoint-2026-10-07.txt` |
| the review-watch readings beside them (STATE-2026-10-03:94) | `docs/evidence/v135/review-watch-2026-10-03.txt`, `review-watch-2026-10-07.txt` |
| `NihongoRide-v135-work/review-1003/result.json` and `fix-result.json` (STATE-2026-10-03:83) | `docs/evidence/v135/review-1003/` |
| `NihongoRide-v135-work/corpus-round2.json` (`docs/measurements/v135-residue-inspection.json`, `n5-g022`'s votes) | `docs/evidence/v135/corpus-round2.json` |
| `NihongoRide-v135-work/n35-1007/` (STATE-2026-10-07:50, `stage1-checkpoints.md` N = 35 rule 5) | `~/Library/Application Support/NihongoRide-Stats/evidence/v135-n35-1007/` on the build Mac: `workflow-result.json` and the three cache-only re-runs (through 09-23, 09-27, 10-01), with `SHA256SUMS.txt` |
| `NihongoRide-v135-work/r3-wav` (`docs/measurements/v135-dictation-remeasure.json`) | `~/Library/Application Support/NihongoRide-Stats/evidence/v135-r3-wav/` on the build Mac: all 962 files, compared identical before the retirement |

What was left out, and why:
* **n35-1007 stays off this public repository.** `workflow-result.json` names paired devices, and the
  rest of that directory is the rule-4 investigation's working material (install records, log scans,
  skeptic outputs). The curated rule-4 evidence was already in
  `NihongoRide-Stats/evidence/n35-rule4-2026-10-07/`. Only the files the docs cite were kept.
* **r3-wav** is 143 MB, too large for this repository.
* The visual-pass harness (`run_visual_pass.sh`, `harness/`, `proj/`) moved to
  `~/Library/Caches/NihongoRide-v137-work/visualpass/`, with its `VP=` path updated. Its DerivedData,
  SourcePackages and the 1.35 screenshot sets (`v135a`, `v135b`) were not kept; nothing cites them.
* 1.35's renders, probes, gate and build logs, design outputs and the submit drafts: nothing cites them.
