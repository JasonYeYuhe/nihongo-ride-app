#!/usr/bin/env bash
# Nihongo Ride — where build products may live on this machine.
#
# Prints one directory. Scripts that create and SIGN bundles put them under it:
#   BUILD_ROOT="$(bash "$SCRIPT_DIR/build_root.sh" "$ROOT")"
#
# WHY THIS EXISTS (measured 2026-09-16, macOS 27.0)
# ------------------------------------------------
# Since macOS 27 this repo's parent, ~/Documents, is an iCloud Drive File Provider domain. A bundle
# directory created anywhere under it is stamped with `com.apple.FinderInfo` and
# `com.apple.fileprovider.fpfs#P` within seconds, and codesign then refuses it: "resource fork,
# Finder information, or similar detritus not allowed". Measured three ways: `swift test` in-tree
# died on 23/23 test bundles; clearing the attributes did not hold (they came back on the next
# build); a hand-made Probe.app under build/ failed `codesign --sign -` while the identical bundle
# under ~/Library/Caches signed. So every signed product has to be built outside the synced folder.
#
# WHO USES IT: scripts/run_all_gates.sh, for `swift test --scratch-path`. The App Store build
# scripts do NOT need it and do not call it: since macOS Sequoia they already re-exec from an
# rsync'd copy under $TMPDIR whenever the tree carries com.apple.provenance (build-appstore.sh
# ~lines 14-31), and inside that copy this helper would answer "<copy>/build" anyway. (The first
# version of this change wired them in too and claimed it fixed the release export; review on
# 2026-09-17 showed it changed nothing on that path, so it was taken out again.)
#
# RULE
# ----
# * NIHONGO_BUILD_ROOT set → that, verbatim (an explicit choice wins).
# * The repo root, or any ancestor, carries the `com.apple.file-provider-domain-id` attribute →
#   "${NIHONGO_BUILD_CACHE:-$HOME/Library/Caches}/NihongoRide-build/<checkout name>-<8 hex of its path>"
#   — one directory PER CHECKOUT, so the live tree and an agent worktree never share a SwiftPM
#   build lock or evict each other's products.
# * Otherwise → "<repo>/build", exactly as before (CI, and any checkout outside a synced folder).
#
# The reason is printed on stderr so a build log says where its products went and why.
# scripts/test_build_root.py plants the attribute on temp directories to prove each branch.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
# -P: a symlink to a checkout inside ~/Documents must resolve to the synced path it really is.
ROOT="$(cd "$ROOT" && pwd -P)"

if [[ -n "${NIHONGO_BUILD_ROOT:-}" ]]; then
  echo "build root: $NIHONGO_BUILD_ROOT (NIHONGO_BUILD_ROOT)" >&2
  echo "$NIHONGO_BUILD_ROOT"
  exit 0
fi

dir="$ROOT"
while :; do
  if domain="$(xattr -p com.apple.file-provider-domain-id "$dir" 2>/dev/null)"; then
    tag="$(printf '%s' "$ROOT" | shasum | cut -c1-8)"
    out="${NIHONGO_BUILD_CACHE:-$HOME/Library/Caches}/NihongoRide-build/$(basename "$ROOT")-$tag"
    echo "build root: $out ($dir is a File Provider domain: ${domain%%/*} — signed bundles built" \
         "under it are refused by codesign)" >&2
    echo "$out"
    exit 0
  fi
  [[ "$dir" == "/" ]] && break
  dir="$(dirname "$dir")"
done

echo "build root: $ROOT/build (no File Provider domain above the repo)" >&2
echo "$ROOT/build"
