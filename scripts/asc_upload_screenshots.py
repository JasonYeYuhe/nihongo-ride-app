#!/usr/bin/env python3
"""
Upload macOS App Store screenshots to a given appStoreVersionLocalization.

Usage:
  python3 scripts/asc_upload_screenshots.py <versionLocalizationId> <file1.png> [file2.png ...]

Reserves an APP_DESKTOP screenshot set, uploads each file via the returned
upload operations, and commits with an MD5 checksum. Order is preserved.
"""
import hashlib
import json
import sys
import time
import requests
import jwt  # PyJWT

KEY_ID = "DMMFP6XTXX"
ISSUER_ID = "c5671c11-49ec-47d9-bd38-5e3c1a249416"
KEY_PATH = f"/Users/jason/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com"


def token():
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 18 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID})


def hdr():
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def create_set(loc_id):
    body = {"data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}
    r = requests.post(f"{BASE}/v1/appScreenshotSets", headers=hdr(), json=body)
    r.raise_for_status()
    return r.json()["data"]["id"]


def upload_one(set_id, path, idx):
    data = open(path, "rb").read()
    fname = path.split("/")[-1]
    # 1. reserve
    body = {"data": {"type": "appScreenshots",
                     "attributes": {"fileName": fname, "fileSize": len(data)},
                     "relationships": {"appScreenshotSet": {
                         "data": {"type": "appScreenshotSets", "id": set_id}}}}}
    r = requests.post(f"{BASE}/v1/appScreenshots", headers=hdr(), json=body)
    r.raise_for_status()
    d = r.json()["data"]
    sid = d["id"]
    ops = d["attributes"]["uploadOperations"]
    # 2. upload bytes per operation
    for op in ops:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        h = {x["name"]: x["value"] for x in op["requestHeaders"]}
        resp = requests.request(op["method"], op["url"], headers=h, data=chunk)
        resp.raise_for_status()
    # 3. commit
    md5 = hashlib.md5(data).hexdigest()
    patch = {"data": {"type": "appScreenshots", "id": sid,
                      "attributes": {"uploaded": True, "sourceFileChecksum": md5}}}
    r = requests.patch(f"{BASE}/v1/appScreenshots/{sid}", headers=hdr(), json=patch)
    r.raise_for_status()
    print(f"  [{idx}] uploaded {fname} ({len(data)} bytes) -> {sid}")
    return sid


def main():
    loc_id = sys.argv[1]
    files = sys.argv[2:]
    print(f"creating APP_DESKTOP screenshot set on loc {loc_id}")
    set_id = create_set(loc_id)
    print(f"  set id = {set_id}")
    for i, f in enumerate(files, 1):
        upload_one(set_id, f, i)
    print(f"done: {len(files)} screenshots uploaded")


if __name__ == "__main__":
    main()
