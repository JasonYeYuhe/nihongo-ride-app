#!/usr/bin/env bash
set -euo pipefail
# Nihongo Ride — iOS (iPad) App Store build & upload.
# Usage: scripts/build-appstore-ios.sh [--upload]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

# --- Build from an xattr-free copy when the source tree carries provenance ----
# macOS Sequoia stamps com.apple.provenance on files under ~/Documents; it is
# STICKY (xattr -c / -d don't remove it) and makes codesign fail with "resource
# fork, Finder information, or similar detritus not allowed". When present, mirror
# the working tree (incl. uncommitted changes) into a temp dir with rsync (rsync
# WITHOUT -X drops xattrs) and re-exec there. See build-appstore.sh for details.
if [[ -z "${NR_BUILD_COPY:-}" ]] && xattr "$ROOT/project.yml" 2>/dev/null | grep -q com.apple.provenance; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/nrbuild.XXXXXX")"
    echo "==> Source carries provenance xattrs (codesign-hostile); building from a clean copy:"
    echo "    $WORK"
    rsync -a --exclude .git --exclude build --exclude .build --exclude .claude \
        --exclude '*.xcodeproj' --exclude .swiftpm \
        --exclude .venv-jp --exclude .dictation-wav "$ROOT/" "$WORK/"
    export NR_BUILD_COPY="$ROOT"
    exec "$WORK/scripts/build-appstore-ios.sh" "$@"
fi

TEAM_ID="KHMK6Q3L3K"
API_KEY_ID="${ASC_KEY_ID:-DMMFP6XTXX}"
API_ISSUER="${ASC_ISSUER_ID:-c5671c11-49ec-47d9-bd38-5e3c1a249416}"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
[[ -f "$API_KEY_PATH" ]] || API_KEY_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_${API_KEY_ID}.p8"

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# --- Prod schema gate (only when this build can actually reach users) ---------
# See build-appstore.sh for why this gate lives on the build path and not in a doc.
# Both platforms write the same records to the same container, so both are gated.
if $UPLOAD && [[ "${NR_SKIP_SCHEMA_CHECK:-0}" != "1" ]]; then
    echo "==> [0/2] CloudKit Production schema gate"
    if ! "$SCRIPT_DIR/check_prod_schema.sh"; then
        echo "❌ Refusing to build for upload: Production can't store what this build writes."
        echo "   Deploy the schema first, or NR_SKIP_SCHEMA_CHECK=1 to override."
        exit 1
    fi
fi

# Outside any iCloud-synced folder when the repo sits in one: codesign refuses bundles created
# under ~/Documents since macOS 27, and the export re-signs inside this directory. See
# scripts/build_root.sh (it prints where and why).
BUILD_DIR="$(bash "$SCRIPT_DIR/build_root.sh" "$ROOT")/appstore-ios"
ARCHIVE="$BUILD_DIR/NihongoRideiOS.xcarchive"
EXPORT="$BUILD_DIR/export"
PROJECT="$ROOT/NihongoRide.xcodeproj"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "==> [1/2] Archiving iOS (Release, generic/iOS, automatic signing)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme NihongoRideiOS \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -quiet
echo "    ✓ $ARCHIVE"

# --- Artifact gate, on the archive that was just built ------------------------
#
# Wired into the build path for the same reason `check_prod_schema.sh` above is: until v1.32 the
# iOS artifact was inspected by NOTHING. `launch_gate.sh` read `Contents/Info.plist` — the macOS
# bundle shape — so handed an iOS app it reported a harness error, and the thing that ships to the
# iOS App Store had never been looked at.
#
# What it catches here is not hypothetical. An iOS build without
# `com.apple.developer.icloud-services` traps in `CKContainer.init` on launch, for EVERY customer
# — measured on the simulator 2026-09-10, with a paired control and the log line quoted in
# launch_gate.sh's header. `AppModel.init` reaches that path on every un-isolated launch, so there
# is no version of this that only some users see.
#
# It cannot LAUNCH the app; that needs a device, and it says so rather than printing a pass.
APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/Nihongo Ride.app"
echo "==> [1b/2] iOS artifact gate"
# The two non-zero codes are NOT the same news, and launch_gate.sh's own header says the
# distinction is why it exists: 1 = the app is broken, 2 = the gate could not inspect it. A bare
# `if !` collapses them, so a missing Info.plist would have been reported as a shipping defect and
# a shipping defect as a possible harness fault. (v1.32 pre-submission review.)
"$SCRIPT_DIR/launch_gate.sh" "$APP_IN_ARCHIVE"; GATE=$?
if [ "$GATE" -eq 2 ]; then
    echo "❌ HARNESS ERROR: the gate could not inspect $APP_IN_ARCHIVE. Fix the harness, not the app."
    exit 1
fi
if [ "$GATE" -ne 0 ]; then
    echo "❌ The archived iOS app FAILED its artifact gate (exit $GATE). Do not ship it."
    exit 1
fi

if [[ "$UPLOAD" != true ]]; then
    echo "==> Skipping upload (pass --upload)"; exit 0
fi

echo "==> [2/2] Exporting + uploading to App Store Connect"
cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>KHMK6Q3L3K</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <!-- Absent, this defaults to TRUE on Xcode 15+, and Xcode then silently rewrites
         the build number on upload to dodge a collision. It really happened: a
         duplicate upload of macOS build 14 landed in App Store Connect as build 15,
         a number that appears nowhere in project.yml. The submit script looks builds
         up BY NUMBER, so a silently renumbered build is one it can't find -- or worse,
         one it mistakes for another. The build number must be what we wrote; a
         collision should fail loudly instead of being papered over. -->
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER"
echo "    ✓ Uploaded (Apple will process the build)."
