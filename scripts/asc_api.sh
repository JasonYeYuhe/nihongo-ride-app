#!/usr/bin/env bash
# Nihongo Ride — App Store Connect API helper.
#
# Generates a short-lived ES256 JWT from Jason's .p8 key and makes an
# authenticated request to the App Store Connect REST API.
#
# Usage:
#   scripts/asc_api.sh GET  "/v1/apps?limit=200"
#   scripts/asc_api.sh POST "/v1/bundleIds" '{"data": {...}}'
#
# Credentials default to the shared team key (same one CLI Pulse / Kinen /
# Stride use). Override via env if needed.

set -euo pipefail

KEY_ID="${ASC_KEY_ID:-DMMFP6XTXX}"
ISSUER_ID="${ASC_ISSUER_ID:-c5671c11-49ec-47d9-bd38-5e3c1a249416}"
# Prefer the canonical location; fall back to the iCloud copy.
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
if [[ ! -f "$KEY_PATH" ]]; then
    KEY_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_${KEY_ID}.p8"
fi

METHOD="${1:-GET}"
ENDPOINT="${2:-/v1/apps}"
BODY="${3:-}"

[[ -f "$KEY_PATH" ]] || { echo "error: key not found at $KEY_PATH" >&2; exit 2; }

JWT="$(swift - "$KEY_PATH" "$KEY_ID" "$ISSUER_ID" <<'SWIFT'
import Foundation
import CryptoKit
let args = CommandLine.arguments
let pem = try String(contentsOfFile: args[1], encoding: .utf8)
let kid = args[2]; let iss = args[3]
func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
let header = #"{"alg":"ES256","kid":"\#(kid)","typ":"JWT"}"#
let now = Int(Date().timeIntervalSince1970); let exp = now + 18 * 60
let payload = #"{"iss":"\#(iss)","iat":\#(now),"exp":\#(exp),"aud":"appstoreconnect-v1"}"#
let signingInput = b64url(Data(header.utf8)) + "." + b64url(Data(payload.utf8))
let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
let sig = try key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + b64url(sig.rawRepresentation))
SWIFT
)"

BASE="https://api.appstoreconnect.apple.com"
if [[ "$METHOD" == "GET" ]]; then
    curl -sS -g -H "Authorization: Bearer $JWT" "${BASE}${ENDPOINT}"
elif [[ -n "$BODY" ]]; then
    curl -sS -g -X "$METHOD" -H "Authorization: Bearer $JWT" \
        -H "Content-Type: application/json" -d "$BODY" "${BASE}${ENDPOINT}"
else
    curl -sS -g -X "$METHOD" -H "Authorization: Bearer $JWT" "${BASE}${ENDPOINT}"
fi
