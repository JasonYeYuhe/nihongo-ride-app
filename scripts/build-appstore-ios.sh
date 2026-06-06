#!/usr/bin/env bash
set -euo pipefail
# Nihongo Ride — iOS (iPad) App Store build & upload.
# Usage: scripts/build-appstore-ios.sh [--upload]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

TEAM_ID="KHMK6Q3L3K"
API_KEY_ID="${ASC_KEY_ID:-DMMFP6XTXX}"
API_ISSUER="${ASC_ISSUER_ID:-c5671c11-49ec-47d9-bd38-5e3c1a249416}"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
[[ -f "$API_KEY_PATH" ]] || API_KEY_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_${API_KEY_ID}.p8"

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

BUILD_DIR="$ROOT/build/appstore-ios"
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
