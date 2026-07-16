#!/bin/bash
# Pre-submit CloudKit Production schema guardrail (PLAN-V1.9 §7, field-level since v1.10 §0).
#
# CloudKit's Development environment JITs unknown record types AND unknown fields;
# Production does neither — it REJECTS a write naming anything it doesn't have. So any
# gap between what the app writes and what Prod holds is invisible in every simulator,
# every debug build, and every run against Development, and shows up only as a silent
# save failure in the field.
#
# This has bitten twice, and the second one is why this script now checks FIELDS:
#
#   v1.5–v1.8  The WordList record TYPE was never promoted to Production. Named
#              word-list sync failed for 3 versions. The type-level check was written
#              in response, and would have caught it.
#   v1.5–v1.9  WordList.deletedAt was missing from Production — and the type-level
#              check passed the whole time, because the TYPE was there. `deletedAt` is
#              a Date? and `record["deletedAt"] = nil` REMOVES the key, so ordinary
#              list sync never named the field and never failed. Only SOFT-DELETING a
#              list wrote it, so only deletions were rejected: whole-list deletion had
#              never once worked, in any environment, since v1.5.
#
# The moral, and the reason for the parsing below: an OPTIONAL field is written only on
# the rarer path, so a type-level check certifies precisely the paths that were never
# broken. A field the app can write must exist in Prod BEFORE the build that writes it.
#
# The field list is PARSED from CloudKitSyncController's `fill(_:from:)` overloads rather
# than hand-maintained here. A hand-written copy is a promise to keep two files in sync,
# and an unkept version of that promise is how the bug above survived three releases —
# so add a field to `fill` and this guardrail demands it in Prod on its own.
#
# Needs the cktool management token in the keychain (name: nihongo-cktool-schema):
#   xcrun cktool save-token "<token>" --type management --method keychain
# Get a token at CloudKit Console → account Settings → Tokens → Create Management Token.
#
# Usage:  scripts/check_prod_schema.sh        # exit 0 = all present, 1 = missing / error
set -o pipefail
TEAM=KHMK6Q3L3K
CONTAINER=iCloud.com.jasonye.nihongoride
SRC="$(dirname "$0")/../Sources/NihongoRideApp/CloudKitSyncController.swift"

[ -f "$SRC" ] || { echo "❌ can't find $SRC"; exit 1; }

# Parse "<RecordType> <field>" pairs out of the fill overloads. The signature → record
# type map mirrors the RT enum; a fill whose signature isn't recognised is a hard error
# rather than a silent skip (a skipped type is exactly the failure this script exists
# to prevent).
WRITES=$(awk '
    /static func fill\(_ record: CKRecord/ {
        if ($0 ~ /from card: ConjugationSRSCard/)   rt = "ConjugationSRSCard"
        else if ($0 ~ /from card: SRSCard/)         rt = "SRSCard"
        else if ($0 ~ /from ride: RideRecord/)      rt = "RideRecord"
        else if ($0 ~ /from slot: OdometerLog/)     rt = "Odometer"
        else if ($0 ~ /savedIDs:/)                  rt = "SavedWords"
        else if ($0 ~ /from list: WordList/)        rt = "WordList"
        else { print "UNMAPPED " $0 > "/dev/stderr"; exit 3 }
        next
    }
    rt && /^[[:space:]]*}/ { rt = "" }
    rt && match($0, /record\["[A-Za-z0-9_]+"\][[:space:]]*=/) {
        f = substr($0, RSTART + 8)
        sub(/".*/, "", f)
        print rt, f
    }
' "$SRC") || { echo "❌ failed to parse fill() overloads in $SRC — fix the parser before trusting this check."; exit 1; }

[ -n "$WRITES" ] || { echo "❌ parsed ZERO fields from $SRC — the parser is broken, not the schema."; exit 1; }

SCHEMA=$(mktemp)
if ! xcrun cktool export-schema --team-id "$TEAM" --container-id "$CONTAINER" \
        --environment production --output-file "$SCHEMA" 2>/tmp/cktool_err; then
    echo "❌ cktool export-schema failed:"; cat /tmp/cktool_err
    echo "   (need a management token: xcrun cktool save-token … --type management)"
    exit 1
fi

missing=0
for rt in $(echo "$WRITES" | awk '{print $1}' | sort -u); do
    block=$(awk -v rt="$rt" '
        $0 ~ "RECORD TYPE " rt " \\(" { inblock = 1 }
        inblock { print }
        inblock && /^[[:space:]]*\)/ { exit }
    ' "$SCHEMA")

    if [ -z "$block" ]; then
        echo "  ❌ MISSING record type: $rt"
        missing=1
        continue
    fi

    fields=$(echo "$WRITES" | awk -v rt="$rt" '$1 == rt {print $2}')
    gaps=""
    for f in $fields; do
        if ! echo "$block" | grep -qE "^[[:space:]]+\"?$f\"?[[:space:]]+[A-Z]"; then
            gaps="$gaps $f"
            missing=1
        fi
    done

    if [ -z "$gaps" ]; then
        echo "  ✅ $rt ($(echo $fields | wc -w | tr -d ' ') fields)"
    else
        echo "  ❌ $rt is missing field(s):$gaps"
    fi
done

rm -f "$SCHEMA"
if [ "$missing" = "1" ]; then
    echo "❌ Production schema does not cover what the app writes — DEPLOY before submitting."
    echo "   A missing FIELD fails only the path that writes it, so this can look fine in"
    echo "   testing and break exactly one feature in the field (see the header)."
    echo "   Fix: xcrun cktool import-schema … --environment development, then CloudKit"
    echo "   Console → Deploy Schema Changes (Dev→Prod). Prod rejects import/validate."
    exit 1
fi
echo "✅ Production schema covers every record type AND field the app writes."
