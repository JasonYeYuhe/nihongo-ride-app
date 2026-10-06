# Evidence for the N = 35 record's rule-4 answer (read 2026-10-07 JST)

`docs/measurements/stage1-checkpoints.md` rule 4 asks whether every walk install and every
registered-session install whose Pacific report day falls inside a reading's window is in
`stage1-known-positives.json`. For the N = 35 record the window is Pacific 2026-09-09 .. 2026-09-23.
The owner did not answer the question. On 2026-10-07 they delegated it to the agent. These files are
what the agent's finding rests on. Every read was read-only. No device was queried: the iPhone line
below dates from 2026-09-15T16:27:28Z, and the app-focus file was read from this Mac's own store.

| file | what it is | what it cannot see |
|---|---|---|
| `sales-in-app-purchase-rows.txt` | every in-app purchase row in the cached Apple daily reports (Pacific 06-06 .. 10-01): 0 for Nihongo Ride, 5 for the vendor's other apps (the control, all iPhone) | who bought; days after 10-01; whether a Mac purchase row looks the same, since none has ever been observed |
| `walk-snapshots.txt` | every surviving `stage1_walk.py` snapshot (2026-09-15T16:52Z .. 2026-10-03T04:15Z): `/Applications/Nihongo Ride.app` is absent in each | times between snapshots; the eight earlier 09-15 snapshots, deleted later |
| `launchservices-nihongoride.txt` | the 48 LaunchServices records for the bundle id: none under `/Applications` or the Trash, all developer builds and archives. The registry keeps records of deleted bundles | anything before its rebuild at 2026-09-15 12:22 JST |
| `app-focus-daily.txt` | from this Mac's app-focus store (Biome `App.InFocus`): 0 Nihongo Ride records in the streams synced from the owner's iPhone "js" and iPad; the Mac's own 4 records fall inside agent gate runs | installs never brought to the front; the iPad on its many empty days; retention is about 28 days |

**The app-focus source is provisional.** It is local to this Mac and touches no device. But the owner
has not said which devices' data may be read, and one reviewer in the investigation declined to use it
under the device-query rule. If the owner strikes it, the iPhone evidence reduces to the 2026-09-15
check below.

**The iPhone "js", 2026-09-15T16:27:28Z (2026-09-16 01:27 JST).** Source: `stage1_walk.py ios-state`, run
by an agent. Transcript:
`~/.claude/projects/-Users-jason-Documents-typing-app/52871ea6-6982-46e9-8247-9671d4e7c338/subagents/workflows/wf_1eb0d8c6-92e/agent-a1844fd410592dd57.jsonl`,
line 276. The snapshot directory it names was deleted later. The js line is quoted verbatim, with the
device identifier elided here:

```
WARN  js · iPhone 15 Pro Max (iPhone16,2) · iOS 27.0 · ‹device id elided› · paired: com.jasonye.nihongoride is not installed — walk step 1 installs it from the App Store
```

The same run also listed the apps on a second paired iPhone that is not the owner's, without that
person's consent. That is the incident behind the rule that device queries are opt-in per named
device. The rule-4 answer does not use that device's line.

**Searched, nothing found:**
* the Claude Code, Codex and Gemini transcripts on this Mac since 2026-09-08: no install of Nihongo
  Ride from the App Store or TestFlight by any agent, and no walk step that installs or purchases.
  Step 0's read-only preflight was run often;
* `docs/sessions/`, which holds only its README, so no session was ever registered. Whether an
  unregistered session was run is not visible here;
* the walk card's evidence folder, `~/Documents/NihongoRide-Evidence`, which does not exist.

**Not usable as evidence:**
* `/Library/Receipts/InstallHistory.plist` has recorded no third-party Mac App Store install since
  2025-08-05.
* `/var/log/install.log` starts on 2026-06-07 and has recorded none at all.
* The 1Blocker (09-28), Goodnotes (09-29) and WhatsApp (10-02 JST) updates are missing from both, so
  their silence proves nothing.

**What no source can see:**
* a download that was never opened (a first download counts in N even after the app is deleted);
* devices on other Apple accounts;
* a family member's devices;
* recruiting outside the readable channels (WeChat, LINE, in person) and participants' devices.
