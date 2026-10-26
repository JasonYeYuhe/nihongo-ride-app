# Evidence from the v1.34 release work directory

`~/Library/Caches/NihongoRide-v134-work/` was retired on 2026-10-27, after 1.35 went live. This
follows the release work-directory rule: a work directory is kept until a newer version is live. The
files the docs cite from it were kept first:

| cited as | kept at |
|---|---|
| `NihongoRide-v134-work/checkpoint-2026-09-25.txt` (the N = 35 record's reading, md5 `b077ce90a5a798632ac69bbd0ff99388`) | `docs/evidence/v134/checkpoint-2026-09-25.txt` |
| `NihongoRide-v134-work/checkpoint-2026-09-29.txt` | `docs/evidence/v134/checkpoint-2026-09-29.txt` |
| `NihongoRide-v134-work/consult-2026-09-28/` (STATE-2026-09-29) | `docs/evidence/v134/consult-2026-09-28/`: the brief and both answers |
| `NihongoRide-v134-work/visualpass/after2/` (PLAN-V1.34 §G) | `~/Library/Application Support/NihongoRide-Stats/evidence/v134-visualpass-after2/` on the build Mac |

What was left out of each:
* **consult:** the read-only repository copy the models read (75 MB, a copy of this repository at
  `8108fc7`) and the models' raw logs.
* **visualpass:** only the manifest and the 96 screenshots were kept. At 61 MB the screenshots are too
  large for this public repository. The 270 MB `.xcresult` bundle they were exported from was not kept.
