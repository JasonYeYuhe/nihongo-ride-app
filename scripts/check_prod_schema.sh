#!/bin/bash
# Pre-submit CloudKit Production schema guardrail (PLAN-V1.9 §7).
#
# The WordList record type was JIT'd in Development back in v1.5 but never promoted to
# Production, so named word-list iCloud sync silently failed in the field for 3 versions
# (v1.5–v1.8) — nothing surfaced it. This checks that EVERY record type the app writes
# (CloudKitSyncController's RT enum) actually exists in the CloudKit PRODUCTION schema,
# so a missing/undeployed type is caught before a release, not by users.
#
# Needs the cktool management token in the keychain (name: nihongo-cktool-schema):
#   xcrun cktool save-token "<token>" --type management --method keychain
# Get a token at CloudKit Console → account Settings → Tokens → Create Management Token.
#
# Usage:  scripts/check_prod_schema.sh        # exit 0 = all present, 1 = missing / error
set -o pipefail
TEAM=KHMK6Q3L3K
CONTAINER=iCloud.com.jasonye.nihongoride
# Record types the app writes — keep in sync with CloudKitSyncController RT enum.
REQUIRED=(SRSCard RideRecord Odometer SavedWords WordList ConjugationSRSCard)

SCHEMA=$(mktemp)
if ! xcrun cktool export-schema --team-id "$TEAM" --container-id "$CONTAINER" \
        --environment production --output-file "$SCHEMA" 2>/tmp/cktool_err; then
    echo "❌ cktool export-schema failed:"; cat /tmp/cktool_err
    echo "   (need a management token: xcrun cktool save-token … --type management)"
    exit 1
fi

missing=0
for rt in "${REQUIRED[@]}"; do
    if grep -qE "RECORD TYPE $rt \(" "$SCHEMA"; then
        echo "  ✅ $rt"
    else
        echo "  ❌ MISSING in Production: $rt"
        missing=1
    fi
done

rm -f "$SCHEMA"
if [ "$missing" = "1" ]; then
    echo "❌ Production schema is missing record type(s) the app writes — DEPLOY before submitting."
    echo "   (cktool import-schema to Development, then CloudKit Console → Deploy Schema Changes Dev→Prod.)"
    exit 1
fi
echo "✅ All app record types are present in the CloudKit Production schema."
