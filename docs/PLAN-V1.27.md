# v1.27 — the first product-stage release

Opened 2026-08-25 while v1.26 sat in review; scoped 2026-08-26 once v1.26 went live on both
platforms and the Stage 0 baseline was measured.

**Shipped: §A only.** Everything below §A was already open when this file was written and stays
open. §R (the locked-screen macOS export) was not attempted — the screen was unlocked for this
release, so the question never became load-bearing.

---

## §A Ask for a review, and count every time we decided not to — SHIPPED

`PLAN-V2-PRODUCT.md` §C names review-prompting "the single biggest lever on downloads". This is
that, and it is the first monetization-adjacent code this repo has ever carried.

**The API the plan names is deprecated.** `SKStoreReviewController` carries
`API_DEPRECATED(ios(10.3, 18.0), macos(10.14, 15.0))` in the shipping SDK. Verified there rather
than recalled — the same way the product plan verified `AppTransaction`. What replaced it,
`@Environment(\.requestReview)`, is **iOS 16 / macOS 13**, below this app's 17.0 / 14.0 targets,
is not deprecated, and is one call on both platforms with no window-scene plumbing.

**The rejections are the feature.** `requestReview` reports nothing back: Apple decides whether
to show anything, never says which way it went, and silently discards calls past its own
three-per-365-days limit. So a release that produces no new reviews would be indistinguishable
from one whose gates never let a single moment through — this project's oldest rule in new
clothes. `ReviewPromptLedger` counts **every** outcome by reason, on-device and never
transmitted, so the thresholds can be revised against data instead of defended. All five
thresholds are judgements and say so in the source; the annual limit is not, and mirrors
Apple's.

**The ask and the record are one branch.** `requestDates.append` and `ask()` sit on the same
line of control flow, so the ledger cannot record a request that was never made or miss one that
was — the fix twenty-one count-vs-run defects arrived at, applied before the defect rather than
after. The moment is built from the appended `RideRecord`, not from the session, so the accuracy
gating the prompt is the accuracy the Ride Log shows; and it is consumed on the way through, so
"ride again" bouncing back through results cannot spend two of Apple's three slots on one ride.

**Eleven mutations, all red**, including deleting the `ResultsView` call site — the v1.26
scenario where 527 tests stayed green while the view was severed from the model.

### Why the ASO half of Stage 0 is NOT in this release

Stage 0 also calls for `ja` / `zh-Hant` storefront locales, and the pre-submission review was
right that locales, description and binary all attach to one App Store version record. That
makes them shippable together; it does not make them **readable** together. New locales move
downloads and the review prompt moves reviews, and both feed the one number Stage 0 is trying to
read against a baseline recorded three days earlier. **One change at a time**, which is this
project's own rule about instruments pointed at its own release process. The ASO payload is
v1.28, by which time the acquisition-source report may exist to say whether a `ja` listing can
replicate anything.

---

## Open items, carried from v1.26 and still open

The first item is a research item and is written out in full because it is the one whose method
is not obvious; the rest are the open items v1.26 recorded, carried here so this file is a
usable starting point rather than a stub.

---

## §R Build the macOS App Store package with the screen locked

> **⚠️ MEASURED 2026-08-28: the failure does not reproduce.** A full macOS App Store
> export + upload succeeded with **82 of 82 one-second samples of `IOConsoleLocked` reading
> `<true/>`** — asserted DURING the run, which is what this section demands and what an earlier
> bracketed observation the same day could not give. Two exports that day, both with the console
> locked, both succeeded.
>
> This section's own rule applies to this section: *"A trap that no longer reproduces is a trap
> that has been fixed by somebody else."* STATE's `productbuild` row was measured on v1.25 and
> the toolchain has moved to Xcode 26.6.
>
> **What this does NOT establish**: that it can never fail. Two successes are not a proof of
> absence, and the mechanism was never understood — §R's own "what is NOT measured" list still
> stands, including that the transient key's ACL was only ever an inference. So the sampler is
> now permanent in `build-appstore.sh` and every release prints its ratio. If the trap returns,
> the log says so instead of a person guessing.
>
> **Consequence: steps 3, 4 and 5 below are moot unless it returns**, and with them the
> owner-only step (obtaining and pre-authorising a persistent installer identity). The macOS
> release no longer needs a human at the machine, which was the entire goal.

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
* ~~**The 15 `propagated` exclusions.**~~ **DONE in v1.28 §A**, and the rule behind them is
  retired: 11 released, 2 kept on direct proof, 2 undecided.
  **And it unblocks the item above.** That entry says re-deciding the 913 `nearest` exclusions
  "needs an instrument this repo does not have". It does now — instrument 1b, proof by byte
  identity under a whole-span kana substitution, calibrated at 0 spurious matches against 69 real
  alternative readings. Running it over the 910 is the largest content win available.
* ~~The 15 `propagated` exclusions (original entry).~~ They rest on a comment — "a voice does not change its
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

---

# Shipped

**Submitted 2026-08-26, macOS build 50 / iOS build 51, marketing 1.27 — both platforms
WAITING_FOR_REVIEW, verified by querying ASC directly rather than by reading the submit script's
own output.** `launch_gate` passed on the archive that was actually uploaded, with the Mac
signed into iCloud. `swift test` **570 green** (545 → 570); iOS XCUITest exit 0, 4 passed and
1 skipped by design; macOS Xcode build succeeded. Metadata written and **read back identical**
on both platforms. No corpus file was touched.

| | v1.26 | v1.27 |
|---|---|---|
| tests (`swift test`) | 541 | **570** |
| mutations proven red on new code | — | **13** |
| corpus files changed | 5 entries | **0** |
| App Store locales | 2 | 2 (`ja` / `zh-Hant` deferred to v1.28, deliberately) |

## What actually happened

**Two builds were uploaded and abandoned.** macOS 49 and iOS 50 went to Apple before the
pre-submission review ran; the review produced changes to `AppModel`, so both were rebuilt as
50 / 51. Uploading a build costs nothing but the wait — abandoning one is cheaper than shipping
around it.

**The iOS build was interrupted mid-archive and reported nothing useful.** The wrapper died with
signal 137 and the log ended at `** BUILD INTERRUPTED **`. Neither "it uploaded" nor "it did not"
could be read off that, so it was read off **ASC**, per platform: `filter[preReleaseVersion.platform]`
distinguishes the two build 50s, which a bare build listing does not. The iOS archive had never
uploaded. Re-run in the background, it took 140 seconds.

**The pre-submission review claimed two BLOCKERs and one was real** — recorded in the commit
`review(v1.27)`. The unreal one is the more useful entry: it described a UI-test launch
corrupting the owner's ledger, which cannot happen because `settingsStore` already routes an
isolated launch into a throwaway suite. The gates were unified onto one predicate anyway, and
**reverting that unification leaves the suite green** — so it is recorded as defence in depth
rather than as a fix, because claiming a test proves it would be the exact failure this project
keeps finding.

**Three instruments were wrong, and each was caught by using it** — the pattern v1.26 recorded,
repeating:

* `check_versions.py` defaulted `--submit-script` to `submit_1_26.py` while the project was on
  1.27. It now resolves the newest on disk and prints which file it read.
* STATE said releases are archived under `NihongoRide-Archives/`. Nothing does that; the path to
  gate had to be read out of the upload run's own log.
* A journal seed written with a bare `JSONEncoder()` loaded as an empty journal, because
  `RideJournal` uses `.iso8601`. Caught only because the helper asserted its own seed had loaded.

## Open, and carried forward

* **The Analytics reports still do not exist** — all 156, on both requests, zero instances as of
  2026-08-26. Re-check after 2026-08-28. Until then §G's guardrail layer has nothing behind it
  and the acquisition-source question that gates the `ja` listing is unanswerable.
* **The ASO payload** — `ja` / `zh-Hant` locales, keyword tuning. v1.28.
* **The "no network" description** — still true today and must be reworded **before** any IAP
  ships, not with it.
* Everything under "Open items, carried from v1.26" above, untouched: §R, instance twenty-one,
  §C + B4 timing, the 913 `nearest` and 15 `propagated` dictation exclusions, the 112
  uninspected sentences, §E accessibility.

---

# v1.28 — shipped

**Submitted 2026-08-28, macOS build 52 / iOS build 53, marketing 1.28 — both platforms
WAITING_FOR_REVIEW, verified by querying ASC directly.** `swift test` **571 green**; launch gate
passed on the uploaded archive with the Mac signed into iCloud; What's New read back from ASC in
all **three** locales, and read back for its *numbers* rather than its length — 11 → 10 and
5,771 → 5,770 are the same number of characters, so a length check could not have seen the
correction.

| | v1.27 | v1.28 |
|---|---|---|
| tests | 570 | **571** |
| dictation pool | 5,760 | **5,770** |
| App Store locales | 2 | **3** (`ja` added) |
| builds abandoned to a review finding | 2 | **2** |

## The pre-submission review found a real defect, in builds that were already uploaded

`verdict()` returned RELEASE as soon as **any** span agreed with its corpus reading, without
checking it was the span the sentence had been withheld for. It released `n2-g210`
(彼が殺人を犯した動機は何だ) on 彼 = かれ while 何 — the whole reason it was withheld — was never
confirmed. **The evidence that released the sentence and the reason it was withheld were
different predicates, agreeing only by inspection**: this project's oldest defect shape, arriving
in the release whose subject is an assumption that looked like a measurement.

Ten of eleven were right. Checking is what found the one, and the fix was made at the predicate
and then **re-measured from the restored pre-change state**, so the shipped result comes from the
corrected instrument rather than from a hand-patched list.

## And §R closed itself

Two macOS exports that day succeeded with the console locked, the second with **82/82 one-second
samples of `IOConsoleLocked` reading `<true/>` taken during the export**. §R's own rule decides
it: a trap that no longer reproduces has been fixed by somebody else. The sampler is now
permanent, so a return is recorded rather than rediscovered.

## Open, and carried forward

* **The 910 `nearest` exclusions.** PLAN-V1.27 said re-deciding them "needs an instrument this
  repo does not have". Instrument 1b is that instrument — 0 spurious matches against 69 real
  alternative readings — and running it over the 910 is now the largest content win available.
* **`n5-kazoku` reads 四人 as よんにん**, where standard Japanese lexicalises よにん. Not applied:
  correcting it would not release the sentence (Kyoko says ひと either way), so it belongs to a
  reading-gate release, not this one.
* **The CN search-result row**, which the acquisition funnel identified and this release does not
  touch. `en-US` and `zh-Hans` keywords were deliberately left alone so v1.28's per-territory
  reading stays attributable to the one locale that changed.
* The three sentences no instrument has decided, now labelled `undecided` rather than
  `propagated`.
