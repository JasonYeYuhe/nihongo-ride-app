# Evidence for the N = 35 record's rule-4 answer (read 2026-10-07 JST)

`docs/measurements/stage1-checkpoints.md` rule 4 asks whether every walk install and every
registered-session install whose Pacific report day falls inside a reading's window is in
`stage1-known-positives.json`. For the N = 35 record the window is Pacific 2026-09-09 .. 2026-09-23.
The owner did not answer the question; on 2026-10-07 they delegated it to the agent. What the agent's
finding rests on is summarised here.

**This repository is public.** Two kinds of evidence are therefore kept on the build Mac only, in
`~/Library/Application Support/NihongoRide-Stats/evidence/n35-rule4-2026-10-07/`: the device-usage
evidence, and rows from the vendor's other apps. They were removed from this directory on 2026-10-07,
the day they were added. The local copies' SHA-256:

```
2d33abbed9824acf826933fc8505bd11c583553ad3566cb4e8b366daac61a074  app-focus-daily.txt
3cbb2005e96f21e38d97657d93efc8495a60ab33fe690fd95feb97863a5fdb18  sales-in-app-purchase-rows.txt
```

| file | where | what it shows | what it cannot see |
|---|---|---|---|
| `walk-snapshots.txt` | here | every surviving `stage1_walk.py` snapshot (2026-09-15T16:52Z .. 2026-10-03T04:15Z): `/Applications/Nihongo Ride.app` is absent in each | times between snapshots, and eight earlier snapshots from 09-15 that were deleted later |
| `launchservices-nihongoride.txt` | here | the 48 LaunchServices records for the bundle id: none under `/Applications` or the Trash, all developer builds and archives. The registry keeps records of deleted bundles | anything before its rebuild at 2026-09-15 12:22 JST |
| `sales-in-app-purchase-rows.txt` | local only | every in-app purchase row in the cached Apple daily reports (Pacific 06-06 .. 10-01): 0 for Nihongo Ride. The vendor's other apps have 5 rows, all iPhone, which is the control | who bought; days after 10-01; what a Mac purchase row looks like, since none has ever been observed |
| `app-focus-daily.txt` | local only | read from this Mac's own app-focus store, with no device touched: no Nihongo Ride records from the owner's iPhone or iPad in the window | installs never brought to the front; days with no records |

**Provisional.** The app-focus source touches no device. But the owner has not said which devices'
data may be read. If the owner strikes it, the iPhone evidence reduces to the 2026-09-15 check: an agent
ran `stage1_walk.py ios-state`, and the owner's iPhone reported `com.jasonye.nihongoride is not installed`.

**Searched, nothing found:**
* agent transcripts: no install of Nihongo Ride from the App Store or TestFlight by any agent, and no
  walk step that installs or purchases. Step 0's read-only preflight was run often;
* `docs/sessions/`: no session was ever registered;
* the walk card's evidence folder: it does not exist.

**Not usable as evidence.** The system install history and `install.log` have recorded no third-party
Mac App Store install for months, so their silence proves nothing.

**What no source can see:**
* a download that was never opened (a first download counts in N even after deletion);
* devices on other Apple accounts;
* a family member's devices;
* recruiting outside the readable channels, and participants' devices.
