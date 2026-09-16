# Why `SKTestSession` is inert for Nihongo Ride — a purchase-free probe, 2026-09-17

Xcode 27.0 (27A266a) · macOS 27.0 (26A428). Run by an agent session under the owner's 2026-09-17
delegation, as the "one bounded timebox" `docs/PLAN-V1.32.md` asked for. **No purchase-capable call was
built or run**: the probe code was grepped before every build for `purchase(`, `buyProduct`,
`AppStore.sync`, `Transaction.` iteration, `refundTransaction`, `approveAskToBuy` (no matches). It only
constructed a session, reset it, set and cleared a simulated `.loadProducts` error, and loaded products.
Scratch sources and logs stayed outside the repo; nothing in the app, its tests or
`run_store_gates.sh` was changed by the probe.

## Result

A minimal macOS SwiftUI app with a hosted XCTest bundle, the repo's `.storekit` copied in, and the same
`sessionIsInert` logic as `StoreGateTests`. Every run: `xcodebuild test … -only-testing:SKProbeTests`,
exit 0.

| variant | signing | runs → result (products before the simulated error) |
|---|---|---|
| V1 `com.example.skprobe`, no extension | ad hoc, no entitlements | INERT(1) ×4, incl. two control runs last |
| V2 `com.jasonye.nihongoride`, no extension | ad hoc, no entitlements | INERT(1) ×2 |
| V3 `com.example.skprobe` + widget extension | ad hoc, no entitlements | INERT(1) ×2 |
| V4 `com.jasonye.nihongoride` + widget extension | ad hoc, no entitlements | INERT(1) ×2 |
| V1n | `CODE_SIGNING_ALLOWED=NO` — the mode `run_store_gates.sh` builds in | INERT(1) ×2 |
| V1 (first two runs, Xcode's default entitlement injection) | ad hoc + injected | LIVE(1) ×2 |
| V1g | base entitlements injected | LIVE(1) ×3 |
| V3g, with the widget extension | base entitlements injected | LIVE(1) ×2 |
| V1t | `com.apple.security.get-task-allow` **true** (+ testmanagerd exceptions) | LIVE(1) ×2 |
| V1x | the same keys, `get-task-allow` **false** | INERT(1) ×2 |
| V1f `com.example.skprobefresh` | ad hoc, no entitlements | "LIVE"(0) ×2 — a false LIVE, see below |

**Conclusion, at the strength the data supports.** On this toolchain the session is inert whenever the
test host lacks `com.apple.security.get-task-allow`, for ANY bundle id, with or without an extension;
with that one entitlement it is live, extension included. `storekitagent` says so on every refused
call: `<bundle id> is not installed for development`; the test process logs `SKServiceErrorDomain Code=2
{SKInternalErrorDomain Code=4}` (§J recorded Code=3 on Xcode 26.6). `run_store_gates.sh` builds with
`CODE_SIGNING_ALLOWED=NO`, and its own run at 02:14 JST today — this session's `run_all_gates.sh`, not
another session — logged `com.jasonye.nihongoride is not installed for development` after each of its
nine configuration saves. So **§J/§L's "a minimal non-App-Store app drives the same session fine, so the
difference is this app, not the tooling" no longer holds**: the minimal app is equally inert when signed
the way the harness signs. Not shown: the real app going live with `get-task-allow` (deliberately not
run, next section).

## Deliberately not run, and why

* **The real bundle id with `get-task-allow`.** A LIVE session saves
  `~/Library/Group Containers/group.com.apple.storekit/Documents/Persistence/Octane/<bundle id>/Configuration.storekit`.
  Measured: once that file exists, later runs of that id WITHOUT `get-task-allow` take products from the
  LOCAL test store, while a fresh id and the real id take them from Apple's sandbox. Whether that file can
  also reroute the App Store build is unmeasured — and the owner is about to make the §K purchase on this
  Mac, which must reach `salesReports`. So no such file was created for `com.jasonye.nihongoride`. Verified
  after the probe: none exists (`scripts/stage1_walk.py preflight` now checks this and FAILs if one does).
* **Turning the gates on.** Signing the harness with `get-task-allow` would very likely bring the nine
  `StoreGateTests` back — and they perform simulated purchases against the local `.storekit`, which the
  owner's instruction for this round forbids. The change is small and is the owner's call after the walk.

## Two further findings

1. **The scheme's `storeKitConfiguration` does not arm the local store on its own on this toolchain.**
   V1f (fresh id, inert session) resolved 0 products, and V2/V4 resolved the real product from Apple's
   sandbox. The comments in `project.yml` and `StoreGateTests.swift` that say the scheme "arms the app's
   store environment independently of the session" describe Xcode 26.6, not 27.0.
2. **`sessionIsInert` has no products-resolved precondition**: with 0 products it reads "not inert"
   (V1f). Not changed: in that state the gates would run and fail loudly (`test00_theStoreIsReachable`
   asserts one product, exit 65) and no purchase could complete without a product — so it is a misleading
   red, not a false green, and turning it into a skip would make a broken harness read as the documented
   no-coverage state.

## Environment, before and after (the owner's walk Mac)

`stage1_walk.py mac-state` identical; the sandboxed container plist byte-identical (sha256 `6ec1abf0…`);
`NihongoRide.entitlement.v1` absent; `mdfind` for the bundle id lists the same 7 paths, no probe path; all
13 probe `.app` bundles unregistered from LaunchServices and deleted; the probe's own `Octane/com.example.*`
configs and preference files removed. One key a probe window added to the UNsandboxed
`~/Library/Preferences/com.jasonye.nihongoride.plist` was removed again (content byte-identical to before,
mtime changed).

## Next step, after the walk (owner's decision)

On this Mac after the §K/§L walk, or on another account or CI runner: run V2/V4 with `get-task-allow` to
confirm the real id goes live, then decide whether the gates' simulated purchases should run; delete or
check any `Octane/com.jasonye.nihongoride` config afterwards.
