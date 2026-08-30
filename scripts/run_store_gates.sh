#!/usr/bin/env bash
#
# Run the StoreKit purchase gates (Tests/NihongoRideMacTests) on macOS.
#
# WHY THIS COPIES THE TREE FIRST
# -------------------------------
# Two reasons, and the second one is a trap this project has now paid for twice in different
# costumes.
#
# 1. The same reason `build-appstore.sh` does it: files under `~/Documents` carry
#    `com.apple.provenance`, and codesign refuses to sign them.
#
# 2. **`xcodebuild` hangs in the working tree when an agent worktree is left under `.claude/`.**
#    Measured 2026-08-30: `xcodebuild -list -project NihongoRide.xcodeproj` timed out at 0% CPU
#    with SwiftPM.framework loaded and no package cache written, in-place; the identical project
#    generated in an rsync'd copy listed in seconds. The difference was
#    `.claude/worktrees/wf_e2240193-634-5` — a leftover full checkout from a v1.24 review fan-out,
#    **containing its own `Package.swift`**. A second Swift package nested inside the root
#    package's directory is what SwiftPM's xcodebuild integration stalls on.
#
#    STATE already warned that agent worktrees live inside the repo and the release build copies
#    them; the new half is that they also break `xcodebuild` outright, and that
#    `git worktree remove --force` and `git worktree prune` both HANG on such a worktree, so the
#    documented cleanup does not work. `rm -rf` does, slowly.
#
#    Copying is therefore not a workaround for one stale directory — it is how this gate stays
#    runnable no matter what an agent leaves behind.
#
# Exit codes: 0 all gates passed · 65 a gate failed · anything else, the harness broke.
# NEVER pipe this: a pipe replaces the exit code of the command before it, and this project has
# already shipped a release on an `xcodebuild … | tail` that reported 0 for a failed suite.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/nihongo-store-gates"

rm -rf "$WORK"
mkdir -p "$WORK"
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.claude' \
  --exclude '/*.xcodeproj' \
  --exclude '/NihongoRide-*' \
  "$REPO/" "$WORK/"

cd "$WORK"
xcodegen generate >/dev/null

# The scheme reference is written ONLY when `storeKitConfiguration` sits under the scheme's `run:`
# block. Under `test:` or at the scheme's top level xcodegen ignores it silently, with no
# diagnostic at all — so the check is a grep, not somebody's memory.
if ! grep -q "StoreKitConfigurationFileReference" \
     "NihongoRide.xcodeproj/xcshareddata/xcschemes/NihongoRide.xcscheme"; then
  echo "HARNESS ERROR: the generated scheme carries no StoreKitConfigurationFileReference." >&2
  echo "  xcodegen honours storeKitConfiguration only under a scheme's run: block." >&2
  exit 3
fi

xcodebuild test \
  -project NihongoRide.xcodeproj \
  -scheme NihongoRide \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:NihongoRideMacTests \
  -derivedDataPath "$WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$WORK/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO
