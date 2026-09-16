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
# under ~/Library/Caches signed. So every signed product — SwiftPM test bundles, the App Store
# archive and its export — has to be built outside the synced folder, or not at all.
#
# RULE
# ----
# * NIHONGO_BUILD_ROOT set → that, verbatim (an explicit choice wins).
# * The repo root, or any ancestor, carries the `com.apple.file-provider-domain-id` attribute →
#   "${NIHONGO_BUILD_CACHE:-$HOME/Library/Caches}/NihongoRide-build".
# * Otherwise → "<repo>/build", exactly as before (CI, and any checkout outside a synced folder).
#
# The reason is printed on stderr so a build log says where its products went and why.
# scripts/test_build_root.py plants the attribute on temp directories to prove each branch.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(cd "$ROOT" && pwd)"

if [[ -n "${NIHONGO_BUILD_ROOT:-}" ]]; then
  echo "build root: $NIHONGO_BUILD_ROOT (NIHONGO_BUILD_ROOT)" >&2
  echo "$NIHONGO_BUILD_ROOT"
  exit 0
fi

dir="$ROOT"
while :; do
  if domain="$(xattr -p com.apple.file-provider-domain-id "$dir" 2>/dev/null)"; then
    out="${NIHONGO_BUILD_CACHE:-$HOME/Library/Caches}/NihongoRide-build"
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
