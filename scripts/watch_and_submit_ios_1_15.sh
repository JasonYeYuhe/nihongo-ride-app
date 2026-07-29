#!/usr/bin/env bash
# Watches iOS 1.14's review state; the moment it is APPROVED, creates the iOS 1.15
# version (metadata) and submits build 27, then independently re-queries ASC.
#
# Fires ONLY on approval states. A rejection also unblocks version creation, but
# submitting 1.15 on top of a rejected 1.14 would be wrong twice over — the rejection
# reason may need fixing IN 1.15, and the Resolution Center thread needs an answer.
# So on any rejection-shaped state this stops loudly and does nothing.
set -u
cd "$(dirname "$0")/.."

APP="6777469778"
POLL_SECONDS=900          # 15 min — review state changes on the scale of hours
MAX_POLLS=96              # give up after ~24h; the session it runs in won't outlive that

state() {
    bash scripts/asc_api.sh GET \
        "/v1/apps/$APP/appStoreVersions?filter[platform]=IOS&filter[versionString]=1.14&limit=1" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['attributes']['appStoreState'] if d.get('data') else 'UNKNOWN')"
}

for i in $(seq 1 "$MAX_POLLS"); do
    S=$(state)
    echo "[$i] iOS 1.14: $S"
    case "$S" in
        READY_FOR_SALE|PENDING_DEVELOPER_RELEASE|PROCESSING_FOR_APP_STORE|ACCEPTED)
            echo "== approved — creating iOS 1.15 metadata =="
            scripts/submit_1_15.py --metadata || { echo "METADATA FAILED"; exit 1; }
            echo "== submitting iOS 1.15 (build 27) =="
            scripts/submit_1_15.py --submit || { echo "SUBMIT FAILED"; exit 1; }
            echo "== independent re-query =="
            bash scripts/asc_api.sh GET \
                "/v1/apps/$APP/appStoreVersions?filter[platform]=IOS&limit=2" \
                | python3 -c "
import sys, json
for v in json.load(sys.stdin).get('data', []):
    a = v['attributes']
    print(f\"  IOS {a['versionString']}: {a['appStoreState']}\")"
            exit 0
            ;;
        REJECTED|METADATA_REJECTED|DEVELOPER_REJECTED|INVALID_BINARY|DEVELOPER_ACTION_NEEDED)
            echo "!! iOS 1.14 was REJECTED ($S) — NOT submitting 1.15. Read the Resolution Center."
            exit 1
            ;;
        WAITING_FOR_REVIEW|IN_REVIEW|UNKNOWN)
            ;;
        *)
            echo "?? unrecognised state '$S' — continuing to watch, will not act on it"
            ;;
    esac
    sleep "$POLL_SECONDS"
done
echo "gave up after $MAX_POLLS polls — run scripts/submit_1_15.py --metadata && --submit by hand after approval"
exit 2
