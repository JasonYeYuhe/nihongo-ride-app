# v1.27 — scope in progress

Opened 2026-08-25, while v1.26 sat in review. The first item is a research item and is written
out in full because it is the one whose method is not obvious; the rest are the open items v1.26
recorded, carried here so this file is a usable starting point rather than a stub.

---

## §R Build the macOS App Store package with the screen locked

**Goal:** remove the human step from the release. Everything else in this pipeline runs
unattended — `swift test`, `xcodebuild test`, both archives, the iOS upload, the launch gate,
the submit script. The macOS App Store export is the only thing that needs somebody physically
at the machine, and it needs them for a reason nobody has yet measured.

### What is MEASURED

These were established on 2026-08-25, around the v1.26 release, and each one is a fact rather
than a recollection:

| | |
|---|---|
| `codesign` (the archive step) with the console **locked** | **succeeds** — v1.26's smoke archive was built and signed while `IOConsoleLocked` was `<true/>` |
| `productbuild` (the App Store `.pkg`) with the console locked | **fails** `-60008` "Unable to obtain authorization for this operation" — v1.25, recorded in STATE |
| `login.keychain-db` lock state | **unlocked, `no-timeout`** — measured immediately before a locked-console failure and again before a successful export |
| a persistent `3rd Party Mac Developer Installer` identity | **does not exist**, before OR after a successful App Store export. `security find-identity -v` lists four identities and that is not one of them |
| the keychain search list | `login.keychain-db` only — the `roastmate-signing.keychain-db` trap is fixed and stayed fixed |

**The second and third rows together are the finding.** The keychain is not locked, so "unlock
the keychain" is not the fix and never was. What the console lock blocks is the **authorization
prompt** for a private key's ACL. `codesign` survives because its key is already authorised for
it; `productbuild` does not because its key is not.

**The fourth row kills the obvious fix.** The standard CI remedy is to pre-authorise the key:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <keychain-password> ~/Library/Keychains/login.keychain-db
```

That operates on a **persistent** private key, and there isn't one. Under
`signingStyle: automatic` with `-allowProvisioningUpdates`, Xcode provisions an installer
identity for the duration of the export and removes it afterwards — measured by checking
`find-identity` before and after an export that succeeded. Each export authorises a key that
did not exist a minute earlier, which is precisely the thing a prompt exists to gate.

### What is NOT measured, and must not be asserted

* That the transient key's ACL is what fails. It is the only explanation consistent with all
  five rows above, and it is still an inference.
* That a **persistent, pre-authorised** installer identity would survive the lock. This is the
  proposed fix and it is untested.
* Whether `productbuild` under `signingStyle: manual` would use that identity rather than
  fetching its own.

### ⚠️ The diagnostic STATE tells you to run does not exist on this path

STATE says: *"read the distribution log's 'Signing product with identity … from keychain
<path>' line FIRST. It names which keychain was used, which is the one fact the error code does
not give you."*

**That log is not produced by the export this project actually runs.** With
`destination: upload`, `xcodebuild -exportArchive` uploads directly: no export directory is
created despite `-exportPath` being passed, no `IDEDistribution*.log` is written anywhere under
the build tree or `~/Library/Logs`, and the signing lines appear in neither the captured stdout
nor stderr of the whole run. Checked after v1.26's successful export, which is the best possible
case for finding them.

So **step one is to restore the instrument**, before any hypothesis is tested against it. Two
candidates:

1. Export with `destination: export` into a local directory (which does produce the log and a
   local signed `.pkg`), then upload that `.pkg` separately. Costs one extra step and changes
   the upload path — which is a release-critical path, so it is a change to prove out, not to
   make casually.
2. Run the export under `xcodebuild -verbose`, or set `IDEDistributionLogLevel`, and check
   whether the signing line reappears on the `upload` destination.

Prefer 2 first: it does not change what the release does.

### The experiment, which must be falsifiable

The whole point is that the current answer — "unlock the screen" — works, so any proposed fix
can be adopted for a bad reason. The test is therefore not "does an export succeed" but
**"does an export succeed with the console genuinely locked"**, verified rather than assumed:

```bash
ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked    # must print <true/> DURING the export
```

Assert the lock state **inside** the run, not before it, and record it in the log. v1.26's §E
notes the shape of the mistake to avoid here: three screenshot runs "passed" against
SpringBoard because nothing asserted the app was frontmost. A locked-screen build test that
does not prove the screen was locked is the same error.

Sequence:

1. **Restore the diagnostic** (above). Capture a successful UNLOCKED export's signing line.
   Without this, a failure later cannot be attributed.
2. **Reproduce the failure** with the console locked, on the current configuration. STATE has
   it from v1.25, but it has not been reproduced since, and the toolchain has moved (Xcode
   26.6). A trap that no longer reproduces is a trap that has been fixed by somebody else.
3. **Obtain a persistent `3rd Party Mac Developer Installer`** identity in `login.keychain-db`
   (downloaded from the developer portal, not generated by an export), and pre-authorise it
   with `set-key-partition-list`. **This step needs the keychain password and is therefore
   owner-only** — an agent can prepare everything around it and cannot do it.
4. **Switch the export to `signingStyle: manual`** for macOS only, naming that identity, and
   confirm it still produces a byte-equivalent upload when unlocked.
5. **Then lock the console and run it.** Success here, with the lock asserted during the run,
   is the only result that closes this.

### Cost, and the honest alternative

Roughly one build cycle per step, and step 5 needs the machine idle. If step 3 or 4 proves
awkward, the fallback is not "keep unlocking": it is to note that **the archive step already
runs locked**, so a release could be split — archive unattended, export attended — which is
what v1.26 did by accident and which cost one round trip rather than a day.

This is a convenience item, not a correctness one. It should not be allowed to consume a
release, and it must not be half-adopted: an export path changed to `manual` signing and never
tested locked would leave the project with a new signing configuration and the same manual step.

---

## Carried in from v1.26

* **Instance twenty-one, latent.** `conjugationDueCount` and `conjugationReviewQueue` count a
  due card without validating its `formToken`; `makeReview` parses that token and drops what it
  cannot read. Demonstrated accidentally by a v1.26 fixture using `"masu"` — thirty due
  reported, zero prompts built. Unreachable until a `ConjugationForm` case is renamed or
  removed. Close it the way `resolves:` closed its sibling: one predicate the count and the run
  share.
* **§C + B4, the pause-aware timing release.** The conjugation drill grades every clean answer
  5 because no per-prompt timing is supplied, and practice mode's live WPM is wall clock while
  the WPM it records is ridden time. Needs a baseline chosen against data, which is the part
  v1.26 declined to guess at. The test must drive the SESSION — `NoPromptTimingTests` is the
  shape, and it will go red when this lands, which is its job.
* **The 913 `nearest` dictation exclusions.** v1.26 measured the doubt rather than restating
  it: instrument 2 agrees with adjudication **42/63 = 67%** on the instrument-1-silent
  population, and its margin is LARGER when it is wrong (0.0240) than when it is right
  (0.0177). Re-deciding them needs an instrument this repo does not have.
* **The 15 `propagated` exclusions.** They rest on a comment — "a voice does not change its
  mind between sentences" — that nothing enforces and that a context-sensitive speech front-end
  makes doubtful. Instrument 1 can decide each directly. Small, decidable, and it RELEASES
  content rather than removing it, which makes it the cheapest content win available.
* **112 sentences no reading gate inspects.** N1 29, N2 34, N3 13, N4 17, N5 19; ids in
  `docs/measurements/v126-uninspected-residue.json`. 55 kana-only stems, 22 whose stem appears
  nowhere, 14 deliberately tokenless, 11 named irregulars, 10 outside the selector. v1.26's
  audit of the PREVIOUS residue found two real defects, so auditing this one is not obviously
  finished work.
* **§E accessibility** — waived, not closed. v1.26 added nothing here. The static scan
  (37 fixed frames, 15 `.font(.system(size:))`, 25 `.lineLimit(1)`) is still the cheap first
  answer, and the comparator problem is still unsolved.
